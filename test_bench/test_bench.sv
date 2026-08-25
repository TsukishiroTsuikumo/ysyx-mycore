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

        .probe_retire_valid       (probe_if_inst.retire_valid),
        .probe_retire_pc          (probe_if_inst.retire_pc),
        .probe_retire_instr       (probe_if_inst.retire_instr),
        .probe_retire_rd_write    (probe_if_inst.retire_rd_write),
        .probe_retire_rd_addr     (probe_if_inst.retire_rd_addr),
        .probe_retire_rd_data     (probe_if_inst.retire_rd_data),
        .probe_bus_fault_valid    (probe_if_inst.bus_fault_valid),
        .probe_bus_fault_is_write (probe_if_inst.bus_fault_is_write),
        .probe_bus_fault_addr     (probe_if_inst.bus_fault_addr),
        .probe_bus_fault_resp     (probe_if_inst.bus_fault_resp),
        .mon_axi                  (shared_axi_if_inst)
    );

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
                dut.write_arch_reg(idx[4:0], value);
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
