`timescale 1ns/1ps

// Integrated processor/cache/AXI/RAM system.
//
// use_cache selects the response path presented to the single processor
// instance.  Core requests are always mirrored on the direct PM/DM ports so
// verification agents can observe them.  In direct mode (use_cache == 0), the
// external PM/DM inputs provide the responses and cache requests are gated.
// In system mode (use_cache == 1), the same core communicates through the
// instruction/data caches and the AXI-backed RAM.
module mycore_system #(
    parameter integer LINE_BYTES       = 16,
    parameter integer ICACHE_WAY_NUM   = 4,
    parameter integer ICACHE_SET_NUM   = 16,
    parameter integer DCACHE_WAY_NUM   = 4,
    parameter integer DCACHE_SET_NUM   = 16,
    parameter integer AXI_ADDR_WIDTH   = 32,
    parameter integer AXI_DATA_WIDTH   = 32,
    parameter integer AXI_ID_WIDTH     = 2,
    parameter integer MEM_WIDTH        = 24,
    parameter integer MEM_BYTES        = (1 << MEM_WIDTH),
    parameter [AXI_ADDR_WIDTH-1:0] RAM_BASE  = 32'h0000_0000,
    parameter [AXI_ADDR_WIDTH-1:0] RAM_MASK  = 32'hff00_0000,
    parameter [AXI_ADDR_WIDTH-1:0] MMIO_BASE = 32'h1000_0000,
    parameter [AXI_ADDR_WIDTH-1:0] MMIO_MASK = 32'hffff_0000
)(
    input                               clk,
    input                               reset,
    input                               use_cache,

    // Direct instruction-memory test interface.  Request outputs always
    // mirror the processor; response inputs are selected when use_cache=0.
    output                              pm_req_valid_out,
    output     [31:0]                   pm_req_addr_out,
    input                               pm_req_ready_in,
    input                               pm_resp_valid_in,
    input      [127:0]                  pm_resp_data_in,

    // Direct data-memory test interface, with the same selection convention.
    output     [31:0]                   dm_req_addr_out,
    output                              dm_req_rvalid_out,
    input                               dm_req_rready_in,
    input                               dm_resp_rvalid_in,
    input      [31:0]                   dm_resp_rdata_in,
    output                              dm_req_wvalid_out,
    input                               dm_req_wready_in,
    output     [3:0]                    dm_req_wstrb_out,
    output     [31:0]                   dm_req_wdata_out,
    input                               dm_resp_wvalid_in,

    // Stable, flat two-slot retirement interface.  The single-issue core
    // drives slot 0 and keeps slot 1 clear.
    output     [1:0]                    retire_valid_out,
    output     [63:0]                   retire_pc_out,
    output     [63:0]                   retire_instr_out,
    output     [1:0]                    retire_rd_write_out,
    output     [9:0]                    retire_rd_addr_out,
    output     [63:0]                   retire_rd_data_out,

    // First cache/AXI error is retained until reset.
    output reg                          bus_fault_valid_out,
    output reg                          bus_fault_is_write_out,
    output reg [31:0]                   bus_fault_addr_out,
    output reg [1:0]                    bus_fault_resp_out,

    // Processor-side response observation after the direct/cache mux.  Core
    // requests already appear on the direct PM/DM outputs above.
    output                              mon_core_pm_req_ready,
    output                              mon_core_pm_resp_valid,
    output     [127:0]                  mon_core_pm_resp_data,
    output                              mon_core_dm_req_rready,
    output                              mon_core_dm_resp_rvalid,
    output     [31:0]                   mon_core_dm_resp_rdata,
    output                              mon_core_dm_req_wready,
    output                              mon_core_dm_resp_wvalid,

    // Passive shared-AXI observation ports for the SV verification layer.
    output     [AXI_ID_WIDTH-1:0]       mon_axi_awid,
    output     [AXI_ADDR_WIDTH-1:0]     mon_axi_awaddr,
    output     [7:0]                    mon_axi_awlen,
    output     [2:0]                    mon_axi_awsize,
    output     [1:0]                    mon_axi_awburst,
    output                              mon_axi_awlock,
    output     [3:0]                    mon_axi_awcache,
    output     [2:0]                    mon_axi_awprot,
    output     [3:0]                    mon_axi_awqos,
    output                              mon_axi_awvalid,
    output                              mon_axi_awready,
    output     [AXI_DATA_WIDTH-1:0]     mon_axi_wdata,
    output     [AXI_DATA_WIDTH/8-1:0]   mon_axi_wstrb,
    output                              mon_axi_wlast,
    output                              mon_axi_wvalid,
    output                              mon_axi_wready,
    output     [AXI_ID_WIDTH-1:0]       mon_axi_bid,
    output     [1:0]                    mon_axi_bresp,
    output                              mon_axi_bvalid,
    output                              mon_axi_bready,
    output     [AXI_ID_WIDTH-1:0]       mon_axi_arid,
    output     [AXI_ADDR_WIDTH-1:0]     mon_axi_araddr,
    output     [7:0]                    mon_axi_arlen,
    output     [2:0]                    mon_axi_arsize,
    output     [1:0]                    mon_axi_arburst,
    output                              mon_axi_arlock,
    output     [3:0]                    mon_axi_arcache,
    output     [2:0]                    mon_axi_arprot,
    output     [3:0]                    mon_axi_arqos,
    output                              mon_axi_arvalid,
    output                              mon_axi_arready,
    output     [AXI_ID_WIDTH-1:0]       mon_axi_rid,
    output     [AXI_DATA_WIDTH-1:0]     mon_axi_rdata,
    output     [1:0]                    mon_axi_rresp,
    output                              mon_axi_rlast,
    output                              mon_axi_rvalid,
    output                              mon_axi_rready
);

    localparam integer LINE_WIDTH = LINE_BYTES * 8;

    wire          core_pm_req_valid;
    wire [31:0]   core_pm_req_addr;
    wire          core_pm_req_ready;
    wire          core_pm_resp_valid;
    wire [127:0]  core_pm_resp_data;

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

    wire          cache_pm_req_ready;
    wire          cache_pm_resp_valid;
    wire [127:0]  cache_pm_resp_data;
    wire          cache_dm_req_rready;
    wire          cache_dm_resp_rvalid;
    wire [31:0]   cache_dm_resp_rdata;
    wire          cache_dm_req_wready;
    wire          cache_dm_resp_wvalid;

    wire                  ic_req_rvalid;
    wire                  ic_req_rready;
    wire [31:0]           ic_req_raddr;
    wire                  ic_resp_rvalid;
    wire [LINE_WIDTH-1:0] ic_resp_rdata;
    wire [1:0]            ic_resp_rresp;
    wire                  ic_fault_valid;
    wire [31:0]           ic_fault_addr;
    wire [1:0]            ic_fault_resp;

    wire                  dc_req_rvalid;
    wire                  dc_req_rready;
    wire [31:0]           dc_req_raddr;
    wire                  dc_resp_rvalid;
    wire [LINE_WIDTH-1:0] dc_resp_rdata;
    wire [1:0]            dc_resp_rresp;
    wire                  dc_req_wvalid;
    wire                  dc_req_wready;
    wire [31:0]           dc_req_waddr;
    wire [LINE_WIDTH-1:0] dc_req_wdata;
    wire                  dc_resp_wvalid;
    wire [1:0]            dc_resp_wresp;
    wire                  dc_fault_valid;
    wire                  dc_fault_is_write;
    wire [31:0]           dc_fault_addr;
    wire [1:0]            dc_fault_resp;

    assign pm_req_valid_out  = core_pm_req_valid;
    assign pm_req_addr_out   = core_pm_req_addr;
    assign dm_req_addr_out   = core_dm_req_addr;
    assign dm_req_rvalid_out = core_dm_req_rvalid;
    assign dm_req_wvalid_out = core_dm_req_wvalid;
    assign dm_req_wstrb_out  = core_dm_req_wstrb;
    assign dm_req_wdata_out  = core_dm_req_wdata;

    assign mon_core_pm_req_ready   = core_pm_req_ready;
    assign mon_core_pm_resp_valid  = core_pm_resp_valid;
    assign mon_core_pm_resp_data   = core_pm_resp_data;
    assign mon_core_dm_req_rready  = core_dm_req_rready;
    assign mon_core_dm_resp_rvalid = core_dm_resp_rvalid;
    assign mon_core_dm_resp_rdata  = core_dm_resp_rdata;
    assign mon_core_dm_req_wready  = core_dm_req_wready;
    assign mon_core_dm_resp_wvalid = core_dm_resp_wvalid;

    assign core_pm_req_ready   = use_cache
                                 ? cache_pm_req_ready : pm_req_ready_in;
    assign core_pm_resp_valid  = use_cache
                                 ? cache_pm_resp_valid : pm_resp_valid_in;
    assign core_pm_resp_data   = use_cache
                                 ? cache_pm_resp_data : pm_resp_data_in;
    assign core_dm_req_rready  = use_cache
                                 ? cache_dm_req_rready : dm_req_rready_in;
    assign core_dm_resp_rvalid = use_cache
                                 ? cache_dm_resp_rvalid : dm_resp_rvalid_in;
    assign core_dm_resp_rdata  = use_cache
                                 ? cache_dm_resp_rdata : dm_resp_rdata_in;
    assign core_dm_req_wready  = use_cache
                                 ? cache_dm_req_wready : dm_req_wready_in;
    assign core_dm_resp_wvalid = use_cache
                                 ? cache_dm_resp_wvalid : dm_resp_wvalid_in;

    mycore u_core (
        .clk                  (clk),
        .reset                (reset),
        .pm_req_valid_out     (core_pm_req_valid),
        .pm_req_addr_out      (core_pm_req_addr),
        .pm_req_ready_in      (core_pm_req_ready),
        .pm_resp_valid_in     (core_pm_resp_valid),
        .pm_resp_data_in      (core_pm_resp_data),
        .dm_req_addr_out      (core_dm_req_addr),
        .dm_req_rvalid_out    (core_dm_req_rvalid),
        .dm_req_rready_in     (core_dm_req_rready),
        .dm_resp_rvalid_in    (core_dm_resp_rvalid),
        .dm_resp_rdata_in     (core_dm_resp_rdata),
        .dm_req_wvalid_out    (core_dm_req_wvalid),
        .dm_req_wready_in     (core_dm_req_wready),
        .dm_req_wstrb_out     (core_dm_req_wstrb),
        .dm_req_wdata_out     (core_dm_req_wdata),
        .dm_resp_wvalid_in    (core_dm_resp_wvalid),
        .retire_valid_out     (retire_valid_out),
        .retire_pc_out        (retire_pc_out),
        .retire_instr_out     (retire_instr_out),
        .retire_rd_write_out  (retire_rd_write_out),
        .retire_rd_addr_out   (retire_rd_addr_out),
        .retire_rd_data_out   (retire_rd_data_out)
    );

    Icache #(
        .PM_LINE_BYTES (LINE_BYTES),
        .PM_WAY_NUM    (ICACHE_WAY_NUM),
        .PM_SET_NUM    (ICACHE_SET_NUM),
        .PM_LINE_WIDTH (LINE_WIDTH)
    ) u_icache (
        .clk               (clk),
        .reset             (reset),
        .flush             (1'b0),
        .pm_req_valid_in   (core_pm_req_valid && use_cache),
        .pm_req_addr_in    (core_pm_req_addr),
        .pm_req_ready_out  (cache_pm_req_ready),
        .pm_resp_valid_out (cache_pm_resp_valid),
        .pm_resp_data_out  (cache_pm_resp_data),
        .ic_req_rvalid     (ic_req_rvalid),
        .ic_req_rready     (ic_req_rready),
        .ic_req_raddr      (ic_req_raddr),
        .ic_resp_rvalid    (ic_resp_rvalid),
        .ic_resp_rdata     (ic_resp_rdata),
        .ic_resp_rresp     (ic_resp_rresp),
        .ic_fault_valid    (ic_fault_valid),
        .ic_fault_addr     (ic_fault_addr),
        .ic_fault_resp     (ic_fault_resp)
    );

    Dcache #(
        .DM_LINE_BYTES (LINE_BYTES),
        .DM_WAY_NUM    (DCACHE_WAY_NUM),
        .DM_SET_NUM    (DCACHE_SET_NUM),
        .DM_LINE_WIDTH (LINE_WIDTH)
    ) u_dcache (
        .clk                (clk),
        .reset              (reset),
        .dm_req_addr_in     (core_dm_req_addr),
        .dm_req_rvalid_in   (core_dm_req_rvalid && use_cache),
        .dm_req_rready_in   (cache_dm_req_rready),
        .dm_resp_rvalid_out (cache_dm_resp_rvalid),
        .dm_resp_rdata_out  (cache_dm_resp_rdata),
        .dm_req_wvalid_in   (core_dm_req_wvalid && use_cache),
        .dm_req_wready_out  (cache_dm_req_wready),
        .dm_req_wstrb_in    (core_dm_req_wstrb),
        .dm_req_wdata_in    (core_dm_req_wdata),
        .dm_resp_wready_out (cache_dm_resp_wvalid),
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
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .MEM_WIDTH  (MEM_WIDTH),
        .MEM_BYTES  (MEM_BYTES),
        .RAM_BASE   (RAM_BASE),
        .RAM_MASK   (RAM_MASK),
        .MMIO_BASE  (MMIO_BASE),
        .MMIO_MASK  (MMIO_MASK)
    ) u_mem (
        .clk             (clk),
        .reset           (reset),
        .ic_req_rvalid   (ic_req_rvalid),
        .ic_req_rready   (ic_req_rready),
        .ic_req_raddr    (ic_req_raddr),
        .ic_resp_rvalid  (ic_resp_rvalid),
        .ic_resp_rdata   (ic_resp_rdata),
        .ic_resp_rresp   (ic_resp_rresp),
        .dc_req_rvalid   (dc_req_rvalid),
        .dc_req_rready   (dc_req_rready),
        .dc_req_raddr    (dc_req_raddr),
        .dc_resp_rvalid  (dc_resp_rvalid),
        .dc_resp_rdata   (dc_resp_rdata),
        .dc_resp_rresp   (dc_resp_rresp),
        .dc_req_wvalid   (dc_req_wvalid),
        .dc_req_wready   (dc_req_wready),
        .dc_req_waddr    (dc_req_waddr),
        .dc_req_wdata    (dc_req_wdata),
        .dc_resp_wvalid  (dc_resp_wvalid),
        .dc_resp_wresp   (dc_resp_wresp),
        .mon_axi_awid    (mon_axi_awid),
        .mon_axi_awaddr  (mon_axi_awaddr),
        .mon_axi_awlen   (mon_axi_awlen),
        .mon_axi_awsize  (mon_axi_awsize),
        .mon_axi_awburst (mon_axi_awburst),
        .mon_axi_awlock  (mon_axi_awlock),
        .mon_axi_awcache (mon_axi_awcache),
        .mon_axi_awprot  (mon_axi_awprot),
        .mon_axi_awqos   (mon_axi_awqos),
        .mon_axi_awvalid (mon_axi_awvalid),
        .mon_axi_awready (mon_axi_awready),
        .mon_axi_wdata   (mon_axi_wdata),
        .mon_axi_wstrb   (mon_axi_wstrb),
        .mon_axi_wlast   (mon_axi_wlast),
        .mon_axi_wvalid  (mon_axi_wvalid),
        .mon_axi_wready  (mon_axi_wready),
        .mon_axi_bid     (mon_axi_bid),
        .mon_axi_bresp   (mon_axi_bresp),
        .mon_axi_bvalid  (mon_axi_bvalid),
        .mon_axi_bready  (mon_axi_bready),
        .mon_axi_arid    (mon_axi_arid),
        .mon_axi_araddr  (mon_axi_araddr),
        .mon_axi_arlen   (mon_axi_arlen),
        .mon_axi_arsize  (mon_axi_arsize),
        .mon_axi_arburst (mon_axi_arburst),
        .mon_axi_arlock  (mon_axi_arlock),
        .mon_axi_arcache (mon_axi_arcache),
        .mon_axi_arprot  (mon_axi_arprot),
        .mon_axi_arqos   (mon_axi_arqos),
        .mon_axi_arvalid (mon_axi_arvalid),
        .mon_axi_arready (mon_axi_arready),
        .mon_axi_rid     (mon_axi_rid),
        .mon_axi_rdata   (mon_axi_rdata),
        .mon_axi_rresp   (mon_axi_rresp),
        .mon_axi_rlast   (mon_axi_rlast),
        .mon_axi_rvalid  (mon_axi_rvalid),
        .mon_axi_rready  (mon_axi_rready)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bus_fault_valid_out    <= 1'b0;
            bus_fault_is_write_out <= 1'b0;
            bus_fault_addr_out     <= 32'b0;
            bus_fault_resp_out     <= 2'b00;
        end
        else if (!bus_fault_valid_out && use_cache &&
                 (dc_fault_valid || ic_fault_valid)) begin
            bus_fault_valid_out    <= 1'b1;
            bus_fault_is_write_out <= dc_fault_valid
                                      ? dc_fault_is_write : 1'b0;
            bus_fault_addr_out     <= dc_fault_valid
                                      ? dc_fault_addr : ic_fault_addr;
            bus_fault_resp_out     <= dc_fault_valid
                                      ? dc_fault_resp : ic_fault_resp;
        end
    end

`ifndef SYNTHESIS
    task write_arch_reg;
        input [4:0] address;
        input [31:0] data;
        begin
            u_core.write_arch_reg(address, data);
        end
    endtask

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

    task load_word_image;
        input [255*8:1] file_name;
        begin
            u_mem.load_word_image(file_name);
        end
    endtask
`endif

endmodule
