`timescale 1ns/1ps
`define SIM_TIMEOUT_CYCLES 20000000

module test_bench;

    import uvm_pkg::*;
    import mycore_pkg::*;

    localparam int unsigned AXI_ADDR_WIDTH  = 32;
    localparam int unsigned AXI_DATA_WIDTH  = 32;
    localparam int unsigned AXI_ID_WIDTH    = 2;
    localparam int unsigned AXI_USER_WIDTH  = 1;
    localparam int unsigned AXI_OWNER_WIDTH = 1;

    typedef virtual axi_if #(
        AXI_ADDR_WIDTH,
        AXI_DATA_WIDTH,
        AXI_ID_WIDTH,
        AXI_USER_WIDTH,
        AXI_OWNER_WIDTH
    ) shared_axi_vif_t;

    bit clk;
    int unsigned reg_init_seed;
    int unsigned sim_timeout_cycles;

    initial begin
        clk = 1'b1;
        forever #1 clk = ~clk;
    end

    initial begin
        sim_timeout_cycles = `SIM_TIMEOUT_CYCLES;
        void'($value$plusargs("SIM_TIMEOUT=%d", sim_timeout_cycles));
        repeat (sim_timeout_cycles) @(posedge clk);
        $fatal(1, "SIM_TIMEOUT: simulation exceeded %0d cycles", sim_timeout_cycles);
    end

    icache_if icache_if_inst(.clk(clk));
    dcache_if dcache_if_inst(.clk(clk));
    probe_if  probe_if_inst (.clk(clk));
    axi_if #(
        AXI_ADDR_WIDTH,
        AXI_DATA_WIDTH,
        AXI_ID_WIDTH,
        AXI_USER_WIDTH,
        AXI_OWNER_WIDTH
    ) shared_axi_if_inst (
        .aclk    (clk),
        .aresetn (~icache_if_inst.reset)
    );

    mycore_wrapper dut (
        .clk            (clk),
        .reset          (icache_if_inst.reset),

        .pm_req_ready   (icache_if_inst.req_ready),
        .pm_resp_valid  (icache_if_inst.resp_valid),
        .pm_resp_data   (icache_if_inst.resp_data),
        .pm_req_valid   (icache_if_inst.req_valid),
        .pm_req_addr    (icache_if_inst.req_addr),

        .dm_req_addr    (dcache_if_inst.req_addr),
        .dm_req_rvalid  (dcache_if_inst.req_rvalid),
        .dm_req_rready  (dcache_if_inst.req_rready),
        .dm_resp_rvalid (dcache_if_inst.resp_rvalid),
        .dm_resp_rdata  (dcache_if_inst.resp_rdata),
        .dm_req_wvalid  (dcache_if_inst.req_wvalid),
        .dm_req_wready  (dcache_if_inst.req_wready),
        .dm_req_wstrb   (dcache_if_inst.req_wstrb),
        .dm_req_wdata   (dcache_if_inst.req_wdata),
        .dm_resp_wvalid (dcache_if_inst.resp_wvalid),

        .probe_pc       (probe_if_inst.pc),
        .probe_regfile  (probe_if_inst.regfile_value),
        .probe_retire    (probe_if_inst.retire),
        .probe_commit   (probe_if_inst.commit),
        .probe_rd_addr  (probe_if_inst.rd_addr),
        .probe_rd_data  (probe_if_inst.rd_data),
        .probe_instr    (probe_if_inst.instr),
        .probe_bus_fault_valid    (probe_if_inst.bus_fault_valid),
        .probe_bus_fault_is_write (probe_if_inst.bus_fault_is_write),
        .probe_bus_fault_addr     (probe_if_inst.bus_fault_addr),
        .probe_bus_fault_resp     (probe_if_inst.bus_fault_resp)
    );

    // Passive verification tap at the shared AXI boundary: DCache owns the
    // write channels, while the read channels are observed after I/D
    // arbitration and before address decoding. No synthesizable RTL is altered
    // by this tap.
    assign shared_axi_if_inst.awid     = dut.u_mem.dc_axi_awid;
    assign shared_axi_if_inst.awaddr   = dut.u_mem.dc_axi_awaddr;
    assign shared_axi_if_inst.awlen    = dut.u_mem.dc_axi_awlen;
    assign shared_axi_if_inst.awsize   = dut.u_mem.dc_axi_awsize;
    assign shared_axi_if_inst.awburst  = dut.u_mem.dc_axi_awburst;
    assign shared_axi_if_inst.awlock   = dut.u_mem.dc_axi_awlock;
    assign shared_axi_if_inst.awcache  = dut.u_mem.dc_axi_awcache;
    assign shared_axi_if_inst.awprot   = dut.u_mem.dc_axi_awprot;
    assign shared_axi_if_inst.awqos    = dut.u_mem.dc_axi_awqos;
    assign shared_axi_if_inst.awregion = 4'b0;
    assign shared_axi_if_inst.awuser   = '0;
    assign shared_axi_if_inst.aw_owner = 1'b1;
    assign shared_axi_if_inst.awvalid  = dut.u_mem.dc_axi_awvalid;
    assign shared_axi_if_inst.awready  = dut.u_mem.dc_axi_awready;

    assign shared_axi_if_inst.wdata  = dut.u_mem.dc_axi_wdata;
    assign shared_axi_if_inst.wstrb  = dut.u_mem.dc_axi_wstrb;
    assign shared_axi_if_inst.wlast  = dut.u_mem.dc_axi_wlast;
    assign shared_axi_if_inst.wuser  = '0;
    assign shared_axi_if_inst.wvalid = dut.u_mem.dc_axi_wvalid;
    assign shared_axi_if_inst.wready = dut.u_mem.dc_axi_wready;

    assign shared_axi_if_inst.bid    = dut.u_mem.dc_axi_bid;
    assign shared_axi_if_inst.bresp  = dut.u_mem.dc_axi_bresp;
    assign shared_axi_if_inst.buser  = '0;
    assign shared_axi_if_inst.bvalid = dut.u_mem.dc_axi_bvalid;
    assign shared_axi_if_inst.bready = dut.u_mem.dc_axi_bready;

    assign shared_axi_if_inst.arid     = dut.u_mem.arb_axi_arid;
    assign shared_axi_if_inst.araddr   = dut.u_mem.arb_axi_araddr;
    assign shared_axi_if_inst.arlen    = dut.u_mem.arb_axi_arlen;
    assign shared_axi_if_inst.arsize   = dut.u_mem.arb_axi_arsize;
    assign shared_axi_if_inst.arburst  = dut.u_mem.arb_axi_arburst;
    assign shared_axi_if_inst.arlock   = dut.u_mem.arb_axi_arlock;
    assign shared_axi_if_inst.arcache  = dut.u_mem.arb_axi_arcache;
    assign shared_axi_if_inst.arprot   = dut.u_mem.arb_axi_arprot;
    assign shared_axi_if_inst.arqos    = dut.u_mem.arb_axi_arqos;
    assign shared_axi_if_inst.arregion = 4'b0;
    assign shared_axi_if_inst.aruser   = '0;
    assign shared_axi_if_inst.ar_owner =
        (dut.u_mem.arb_axi_arid == 2'd1) ? 1'b1 : 1'b0;
    assign shared_axi_if_inst.arvalid = dut.u_mem.arb_axi_arvalid;
    assign shared_axi_if_inst.arready = dut.u_mem.arb_axi_arready;

    assign shared_axi_if_inst.rid    = dut.u_mem.arb_axi_rid;
    assign shared_axi_if_inst.rdata  = dut.u_mem.arb_axi_rdata;
    assign shared_axi_if_inst.rresp  = dut.u_mem.arb_axi_rresp;
    assign shared_axi_if_inst.rlast  = dut.u_mem.arb_axi_rlast;
    assign shared_axi_if_inst.ruser  = '0;
    assign shared_axi_if_inst.rvalid = dut.u_mem.arb_axi_rvalid;
    assign shared_axi_if_inst.rready = dut.u_mem.arb_axi_rready;

    axi_protocol_checker #(
        .CHECK_FINAL_QUIESCENCE (1'b0)
    ) shared_axi_protocol_checker (
        .axi (shared_axi_if_inst)
    );

    always @(posedge clk) begin
        if (!probe_if_inst.reset && probe_if_inst.bus_fault_valid) begin
            $fatal(1,
                   "BUS_FAULT: %s address=0x%08x AXI_RESP=0x%0x",
                   probe_if_inst.bus_fault_is_write ? "write" : "read",
                   probe_if_inst.bus_fault_addr,
                   probe_if_inst.bus_fault_resp);
        end
    end

    function automatic logic [31:0] make_init_reg_value(
        input int unsigned index,
        input int unsigned seed
    );
        logic [31:0] value;
        value = seed ^ (32'h9e37_79b9 * index);
        value = value ^ (value << 13);
        value = value ^ (value >> 17);
        value = value ^ (value << 5);
        return value;
    endfunction

    task automatic initialize_register_file();
        integer idx;
        logic [31:0] value;
        begin
            reg_init_seed = 32'h1bad_f00d;
            void'($value$plusargs("REG_INIT_SEED=%d", reg_init_seed));
            probe_if_inst.reg_init_done = 1'b0;
            for (idx = 0; idx < 32; idx = idx + 1) begin
                value = (idx == 0) ? 32'b0 : make_init_reg_value(idx, reg_init_seed);
                dut.u_core.regfile.reg_val[idx] = value;
                probe_if_inst.init_reg_value[idx] = value;
            end
            probe_if_inst.reg_init_done = 1'b1;
            $display("REGINIT: initialized DUT regfile with REG_INIT_SEED=%0d", reg_init_seed);
        end
    endtask

    initial begin
        forever begin
            @probe_if_inst.reg_init_request;
            initialize_register_file();
        end
    end

    initial begin
        $dumpfile("test.vcd");
        $dumpvars(0, test_bench);
    end

    string testname;
    initial begin
        icache_if_inst.reset = 1'b1;
        dcache_if_inst.reset = 1'b1;
        probe_if_inst.reset = 1'b1;

        uvm_config_db#(virtual icache_if)::set(null, "*", "vif", icache_if_inst);
        uvm_config_db#(virtual dcache_if)::set(null, "*", "vif", dcache_if_inst);
        uvm_config_db#(virtual probe_if) ::set(null, "*", "probe", probe_if_inst);
        uvm_config_db#(shared_axi_vif_t)::set(
            null, "*", "vif", shared_axi_if_inst);

        if (!$value$plusargs("UVM_TESTNAME=%s", testname)) begin
            testname = "program_test";
        end
        run_test(testname);
    end

endmodule
