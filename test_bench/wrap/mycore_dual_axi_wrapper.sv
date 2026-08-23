`timescale 1ns/1ps

// Phase-4 integration top for the two-wide in-order core.  The instruction
// frontend already speaks in complete 16-byte lines, so it connects directly
// to the instruction-side AXI adapter.  The scalar data port keeps the
// existing D-cache in front of the data-side adapter and both masters share
// the internal AXI RAM.
//
// This is deliberately a separate top from mycore_wrapper.  The legacy UVM
// hierarchy and single-issue core remain unchanged while the wider core has a
// realistic cache/AXI acceptance path.
module mycore_dual_axi_wrapper #(
    parameter integer ISSUE_WIDTH   = 2,
    parameter integer FETCH_DEPTH   = 8,
    parameter integer COUNTER_WIDTH = 64,
    parameter [31:0]  RESET_PC      = 32'h0000_0000,
    parameter integer MEM_WIDTH     = 16,
    parameter integer MEM_BYTES     = (1 << MEM_WIDTH)
)(
    input  wire                         clk,
    input  wire                         reset,

    output wire [1:0]                   retire_valid,
    output wire [1:0]                   commit_valid,
    output wire [1:0][31:0]             retire_pc,
    output wire [1:0][31:0]             retire_instr,
    output wire [1:0][4:0]              commit_rd_addr,
    output wire [1:0][31:0]             commit_rd_data,
    output wire [31:0]                  arch_regfile [0:31],

    output wire [COUNTER_WIDTH-1:0]     perf_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_issued_instr_count,
    output wire [COUNTER_WIDTH-1:0]     perf_retired_instr_count,
    output wire [COUNTER_WIDTH-1:0]     perf_dual_issue_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_dual_retire_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_frontend_empty_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_data_hazard_stall_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_memory_stall_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_pair_serialize_cycle_count,

    output wire                         sticky_bus_fault_valid,
    output wire                         sticky_bus_fault_is_write,
    output wire [31:0]                  sticky_bus_fault_addr,
    output wire [1:0]                   sticky_bus_fault_resp
);

    wire          core_pm_req_valid;
    wire [31:0]   core_pm_req_addr;
    wire          core_pm_req_ready;
    wire          core_pm_resp_valid;
    wire [127:0]  core_pm_resp_data;
    wire [1:0]    core_pm_resp_code;

    wire [31:0]   core_dm_req_addr;
    wire          core_dm_req_rvalid;
    wire          core_dm_req_rready;
    wire          core_dm_resp_rvalid;
    wire [31:0]   core_dm_resp_rdata;
    wire          core_dm_req_wvalid;
    wire          core_dm_req_wready;
    wire [3:0]    core_dm_req_wstrb;
    wire [31:0]   core_dm_req_wdata;
    wire          core_dm_resp_wvalid;

    mycore_dual #(
        .ISSUE_WIDTH   (ISSUE_WIDTH),
        .FETCH_DEPTH   (FETCH_DEPTH),
        .COUNTER_WIDTH (COUNTER_WIDTH),
        .RESET_PC      (RESET_PC)
    ) u_core (
        .clk                                 (clk),
        .reset                               (reset),
        .pm_req_valid_out                    (core_pm_req_valid),
        .pm_req_addr_out                     (core_pm_req_addr),
        .pm_req_ready_in                     (core_pm_req_ready),
        .pm_resp_valid_in                    (core_pm_resp_valid),
        .pm_resp_data_in                     (core_pm_resp_data),
        .pm_resp_code_in                     (core_pm_resp_code),
        .dm_req_addr_out                     (core_dm_req_addr),
        .dm_req_rvalid_out                   (core_dm_req_rvalid),
        .dm_req_rready_in                    (core_dm_req_rready),
        .dm_resp_rvalid_in                   (core_dm_resp_rvalid),
        .dm_resp_rdata_in                    (core_dm_resp_rdata),
        .dm_req_wvalid_out                   (core_dm_req_wvalid),
        .dm_req_wready_in                    (core_dm_req_wready),
        .dm_req_wstrb_out                    (core_dm_req_wstrb),
        .dm_req_wdata_out                    (core_dm_req_wdata),
        .dm_resp_wvalid_in                   (core_dm_resp_wvalid),
        .retire_valid_out                    (retire_valid),
        .commit_valid_out                    (commit_valid),
        .retire_pc_out                       (retire_pc),
        .retire_instr_out                    (retire_instr),
        .commit_rd_addr_out                  (commit_rd_addr),
        .commit_rd_data_out                  (commit_rd_data),
        .arch_regfile_out                    (arch_regfile),
        .perf_cycle_count                    (perf_cycle_count),
        .perf_issued_instr_count             (perf_issued_instr_count),
        .perf_retired_instr_count            (perf_retired_instr_count),
        .perf_dual_issue_cycle_count          (perf_dual_issue_cycle_count),
        .perf_dual_retire_cycle_count         (perf_dual_retire_cycle_count),
        .perf_frontend_empty_cycle_count      (perf_frontend_empty_cycle_count),
        .perf_data_hazard_stall_cycle_count   (perf_data_hazard_stall_cycle_count),
        .perf_memory_stall_cycle_count        (perf_memory_stall_cycle_count),
        .perf_pair_serialize_cycle_count      (perf_pair_serialize_cycle_count)
    );

    wire          dc_req_rvalid;
    wire          dc_req_rready;
    wire [31:0]   dc_req_raddr;
    wire          dc_resp_rvalid;
    wire [127:0]  dc_resp_rdata;
    wire [1:0]    dc_resp_rresp;
    wire          dc_req_wvalid;
    wire          dc_req_wready;
    wire [31:0]   dc_req_waddr;
    wire [127:0]  dc_req_wdata;
    wire          dc_resp_wvalid;
    wire [1:0]    dc_resp_wresp;

    wire          dc_fault_valid;
    wire          dc_fault_is_write;
    wire [31:0]   dc_fault_addr;
    wire [1:0]    dc_fault_resp;

    Dcache u_dcache (
        .clk                (clk),
        .reset              (reset),
        .dm_req_addr_in     (core_dm_req_addr),
        .dm_req_rvalid_in   (core_dm_req_rvalid),
        .dm_req_rready_in   (core_dm_req_rready),
        .dm_resp_rvalid_out (core_dm_resp_rvalid),
        .dm_resp_rdata_out  (core_dm_resp_rdata),
        .dm_req_wvalid_in   (core_dm_req_wvalid),
        .dm_req_wready_out  (core_dm_req_wready),
        .dm_req_wstrb_in    (core_dm_req_wstrb),
        .dm_req_wdata_in    (core_dm_req_wdata),
        .dm_resp_wready_out (core_dm_resp_wvalid),
        .dc_req_rvalid      (dc_req_rvalid),
        .dc_req_rready      (dc_req_rready),
        .dc_req_raddr       (dc_req_raddr),
        .dc_resp_rvalid     (dc_resp_rvalid),
        .dc_resp_rdata      (dc_resp_rdata),
        .dc_resp_rresp      (dc_resp_rresp),
        .dc_req_wvalid      (dc_req_wvalid),
        .dc_req_wready      (dc_req_wready),
        .dc_req_waddr       (dc_req_waddr),
        .dc_req_wdata       (dc_req_wdata),
        .dc_resp_wvalid     (dc_resp_wvalid),
        .dc_resp_wresp      (dc_resp_wresp),
        .dc_fault_valid     (dc_fault_valid),
        .dc_fault_is_write  (dc_fault_is_write),
        .dc_fault_addr      (dc_fault_addr),
        .dc_fault_resp      (dc_fault_resp)
    );

    cache_axi_memory_system #(
        .MEM_WIDTH (MEM_WIDTH),
        .MEM_BYTES (MEM_BYTES)
    ) u_mem (
        .clk            (clk),
        .reset          (reset),
        .ic_req_rvalid  (core_pm_req_valid),
        .ic_req_rready  (core_pm_req_ready),
        .ic_req_raddr   (core_pm_req_addr),
        .ic_resp_rvalid (core_pm_resp_valid),
        .ic_resp_rdata  (core_pm_resp_data),
        .ic_resp_rresp  (core_pm_resp_code),
        .dc_req_rvalid  (dc_req_rvalid),
        .dc_req_rready  (dc_req_rready),
        .dc_req_raddr   (dc_req_raddr),
        .dc_resp_rvalid (dc_resp_rvalid),
        .dc_resp_rdata  (dc_resp_rdata),
        .dc_resp_rresp  (dc_resp_rresp),
        .dc_req_wvalid  (dc_req_wvalid),
        .dc_req_wready  (dc_req_wready),
        .dc_req_waddr   (dc_req_waddr),
        .dc_req_wdata   (dc_req_wdata),
        .dc_resp_wvalid (dc_resp_wvalid),
        .dc_resp_wresp  (dc_resp_wresp)
    );

    // The line adapter permits a single instruction request at a time.  Hold
    // its accepted address so an error response can be reported precisely.
    reg [31:0] ic_pending_addr_q;
    reg        sticky_fault_valid_q;
    reg        sticky_fault_is_write_q;
    reg [31:0] sticky_fault_addr_q;
    reg [1:0]  sticky_fault_resp_q;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ic_pending_addr_q       <= RESET_PC;
            sticky_fault_valid_q    <= 1'b0;
            sticky_fault_is_write_q <= 1'b0;
            sticky_fault_addr_q     <= 32'b0;
            sticky_fault_resp_q     <= 2'b00;
        end
        else begin
            if (core_pm_req_valid && core_pm_req_ready)
                ic_pending_addr_q <= core_pm_req_addr;

            if (!sticky_fault_valid_q) begin
                if (dc_fault_valid) begin
                    sticky_fault_valid_q    <= 1'b1;
                    sticky_fault_is_write_q <= dc_fault_is_write;
                    sticky_fault_addr_q     <= dc_fault_addr;
                    sticky_fault_resp_q     <= dc_fault_resp;
                end
                else if (core_pm_resp_valid &&
                         (core_pm_resp_code != 2'b00)) begin
                    sticky_fault_valid_q    <= 1'b1;
                    sticky_fault_is_write_q <= 1'b0;
                    sticky_fault_addr_q     <= ic_pending_addr_q;
                    sticky_fault_resp_q     <= core_pm_resp_code;
                end
            end
        end
    end

    assign sticky_bus_fault_valid    = sticky_fault_valid_q;
    assign sticky_bus_fault_is_write = sticky_fault_is_write_q;
    assign sticky_bus_fault_addr     = sticky_fault_addr_q;
    assign sticky_bus_fault_resp     = sticky_fault_resp_q;

`ifndef SYNTHESIS
    // Simulation image access is intentionally forwarded at this wrapper
    // level so tests do not depend on the AXI RAM's internal hierarchy.
    task write_byte;
        input [31:0] address;
        input [7:0] data;
        begin
            u_mem.write_byte(address, data);
        end
    endtask

    task write_word;
        input [31:0] address;
        input [31:0] data;
        begin
            u_mem.write_word(address, data);
        end
    endtask

    task read_word;
        input [31:0] address;
        output [31:0] data;
        begin
            data = u_mem.u_ram.read_data(address);
        end
    endtask

    task load_word_image;
        input [255*8:1] file_name;
        begin
            u_mem.load_word_image(file_name);
        end
    endtask
`endif

endmodule
