module mycore_wrapper (
    input           clk,
    input           reset,

    input           pm_req_ready,
    input           pm_resp_valid,
    input   [31:0]  pm_resp_data,
    output          pm_req_valid,
    output  [31:0]  pm_req_addr,

    output  [31:0]  dm_req_addr,
    output          dm_req_rvalid,
    input           dm_req_rready,
    input           dm_resp_rvalid,
    input   [31:0]  dm_resp_rdata,
    output          dm_req_wvalid,
    input           dm_req_wready,
    output  [3:0]   dm_req_wstrb,
    output  [31:0]  dm_req_wdata,
    input           dm_resp_wvalid,

    output   [1:0]  probe_retire_valid,
    output  [63:0]  probe_retire_pc,
    output  [63:0]  probe_retire_instr,
    output   [1:0]  probe_retire_rd_write,
    output   [9:0]  probe_retire_rd_addr,
    output  [63:0]  probe_retire_rd_data,
    output          probe_bus_fault_valid,
    output          probe_bus_fault_is_write,
    output  [31:0]  probe_bus_fault_addr,
    output   [1:0]  probe_bus_fault_resp,

    axi_if           mon_axi
);

    reg use_cache;

    // These names intentionally remain stable for the existing passive
    // core-interface monitors.  They are all explicit mycore_system ports;
    // no pipeline or cache implementation hierarchy is sampled here.
    wire          core_pm_req_valid;
    wire [31:0]   core_pm_req_addr;
    wire          core_pm_req_ready;
    wire          core_pm_resp_valid;
    wire [31:0]   core_pm_resp_data;
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

    initial begin
        string uvm_testname;
        use_cache = 1'b0;
        if (!$value$plusargs("UVM_TESTNAME=%s", uvm_testname)) begin
            uvm_testname = "";
        end
        use_cache = (uvm_testname == "program_test") ||
                    (uvm_testname == "mem_image_test");
    end

    assign pm_req_valid = core_pm_req_valid;
    assign pm_req_addr = core_pm_req_addr;
    assign dm_req_addr = core_dm_req_addr;
    assign dm_req_rvalid = core_dm_req_rvalid;
    assign dm_req_wvalid = core_dm_req_wvalid;
    assign dm_req_wstrb = core_dm_req_wstrb;
    assign dm_req_wdata = core_dm_req_wdata;

    mycore_system u_system (
        .clk                    (clk),
        .reset                  (reset),
        .use_cache              (use_cache),
        .pm_req_valid_out       (core_pm_req_valid),
        .pm_req_addr_out        (core_pm_req_addr),
        .pm_req_ready_in        (pm_req_ready),
        .pm_resp_valid_in       (pm_resp_valid),
        .pm_resp_data_in        (pm_resp_data),
        .dm_req_addr_out        (core_dm_req_addr),
        .dm_req_rvalid_out      (core_dm_req_rvalid),
        .dm_req_rready_in       (dm_req_rready),
        .dm_resp_rvalid_in      (dm_resp_rvalid),
        .dm_resp_rdata_in       (dm_resp_rdata),
        .dm_req_wvalid_out      (core_dm_req_wvalid),
        .dm_req_wready_in       (dm_req_wready),
        .dm_req_wstrb_out       (core_dm_req_wstrb),
        .dm_req_wdata_out       (core_dm_req_wdata),
        .dm_resp_wvalid_in      (dm_resp_wvalid),
        .retire_valid_out       (probe_retire_valid),
        .retire_pc_out          (probe_retire_pc),
        .retire_instr_out       (probe_retire_instr),
        .retire_rd_write_out    (probe_retire_rd_write),
        .retire_rd_addr_out     (probe_retire_rd_addr),
        .retire_rd_data_out     (probe_retire_rd_data),
        .bus_fault_valid_out    (probe_bus_fault_valid),
        .bus_fault_is_write_out (probe_bus_fault_is_write),
        .bus_fault_addr_out     (probe_bus_fault_addr),
        .bus_fault_resp_out     (probe_bus_fault_resp),
        .mon_core_pm_req_ready  (core_pm_req_ready),
        .mon_core_pm_resp_valid (core_pm_resp_valid),
        .mon_core_pm_resp_data  (core_pm_resp_data),
        .mon_core_dm_req_rready (core_dm_req_rready),
        .mon_core_dm_resp_rvalid(core_dm_resp_rvalid),
        .mon_core_dm_resp_rdata (core_dm_resp_rdata),
        .mon_core_dm_req_wready (core_dm_req_wready),
        .mon_core_dm_resp_wvalid(core_dm_resp_wvalid),
        .mon_axi_awid           (mon_axi.awid),
        .mon_axi_awaddr         (mon_axi.awaddr),
        .mon_axi_awlen          (mon_axi.awlen),
        .mon_axi_awsize         (mon_axi.awsize),
        .mon_axi_awburst        (mon_axi.awburst),
        .mon_axi_awlock         (mon_axi.awlock),
        .mon_axi_awcache        (mon_axi.awcache),
        .mon_axi_awprot         (mon_axi.awprot),
        .mon_axi_awqos          (mon_axi.awqos),
        .mon_axi_awvalid        (mon_axi.awvalid),
        .mon_axi_awready        (mon_axi.awready),
        .mon_axi_wdata          (mon_axi.wdata),
        .mon_axi_wstrb          (mon_axi.wstrb),
        .mon_axi_wlast          (mon_axi.wlast),
        .mon_axi_wvalid         (mon_axi.wvalid),
        .mon_axi_wready         (mon_axi.wready),
        .mon_axi_bid            (mon_axi.bid),
        .mon_axi_bresp          (mon_axi.bresp),
        .mon_axi_bvalid         (mon_axi.bvalid),
        .mon_axi_bready         (mon_axi.bready),
        .mon_axi_arid           (mon_axi.arid),
        .mon_axi_araddr         (mon_axi.araddr),
        .mon_axi_arlen          (mon_axi.arlen),
        .mon_axi_arsize         (mon_axi.arsize),
        .mon_axi_arburst        (mon_axi.arburst),
        .mon_axi_arlock         (mon_axi.arlock),
        .mon_axi_arcache        (mon_axi.arcache),
        .mon_axi_arprot         (mon_axi.arprot),
        .mon_axi_arqos          (mon_axi.arqos),
        .mon_axi_arvalid        (mon_axi.arvalid),
        .mon_axi_arready        (mon_axi.arready),
        .mon_axi_rid            (mon_axi.rid),
        .mon_axi_rdata          (mon_axi.rdata),
        .mon_axi_rresp          (mon_axi.rresp),
        .mon_axi_rlast          (mon_axi.rlast),
        .mon_axi_rvalid         (mon_axi.rvalid),
        .mon_axi_rready         (mon_axi.rready)
    );

    // AXI fields unused by the current DUT subset are completed in the
    // verification adapter so monitors always see a fully-defined interface.
    assign mon_axi.awregion = 4'b0;
    assign mon_axi.awuser = '0;
    assign mon_axi.aw_owner = 1'b1;
    assign mon_axi.wuser = '0;
    assign mon_axi.buser = '0;
    assign mon_axi.arregion = 4'b0;
    assign mon_axi.aruser = '0;
    assign mon_axi.ar_owner = (mon_axi.arid == 2'd1) ? 1'b1 : 1'b0;
    assign mon_axi.ruser = '0;

    task automatic write_word(
        input logic [31:0] address,
        input logic [31:0] data
    );
        u_system.write_word(address, data);
    endtask

    task automatic write_arch_reg(
        input logic [4:0] address,
        input logic [31:0] data
    );
        u_system.write_arch_reg(address, data);
    endtask

endmodule
