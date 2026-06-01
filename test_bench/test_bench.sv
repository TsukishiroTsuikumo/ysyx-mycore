`timescale 1ns/1ps

module test_bench;

    import uvm_pkg::*;
    import mycore_uvm_pkg::*;

    bit clk;
    int unsigned reg_init_seed;
    int unsigned sim_timeout_cycles;

    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end

    initial begin
        sim_timeout_cycles = 200000;
        void'($value$plusargs("SIM_TIMEOUT=%d", sim_timeout_cycles));
        repeat (sim_timeout_cycles) @(posedge clk);
        $fatal(1, "SIM_TIMEOUT: simulation exceeded %0d cycles", sim_timeout_cycles);
    end

    icache_if icache_if_inst(.clk(clk));
    dcache_if dcache_if_inst(.clk(clk));
    probe_if  probe_if_inst (.clk(clk));

    mycore_wrapper dut (
        .clk            (clk),
        .reset          (icache_if_inst.rst),

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
        .probe_commit   (probe_if_inst.commit),
        .probe_rd_addr  (probe_if_inst.rd_addr),
        .probe_rd_data  (probe_if_inst.rd_data)
    );

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
        icache_if_inst.rst = 1'b1;
        dcache_if_inst.rst = 1'b1;
        probe_if_inst.reset = 1'b1;

        uvm_config_db#(virtual icache_if)::set(null, "*", "vif", icache_if_inst);
        uvm_config_db#(virtual dcache_if)::set(null, "*", "vif", dcache_if_inst);
        uvm_config_db#(virtual probe_if) ::set(null, "*", "probe", probe_if_inst);

        if (!$value$plusargs("UVM_TESTNAME=%s", testname)) begin
            testname = "instr_base_test";
        end
        run_test(testname);
    end

endmodule
