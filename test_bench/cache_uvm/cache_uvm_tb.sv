`timescale 1ns/1ps

module cache_uvm_tb;
    import uvm_pkg::*;
    import cache_uvm_pkg::*;

    logic clk;
    logic initial_reset;
    string testname;

    initial clk = 1'b0;
    always #1 clk = ~clk;

    cache_uvm_if bus(clk);
    assign bus.reset = initial_reset | bus.reset_request;

    initial begin
        initial_reset = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        initial_reset = 1'b0;
    end

    initial begin : watchdog
        repeat (200000) @(posedge clk);
        $fatal(1, "Cache UVM regression timed out");
    end

    Icache u_icache (
        .clk               (clk),
        .reset             (bus.reset),
        .flush             (bus.flush_request),
        .pm_req_valid_in   (bus.ic_cpu_req_valid),
        .pm_req_addr_in    (bus.ic_cpu_req_addr),
        .pm_req_ready_out  (bus.ic_cpu_req_ready),
        .pm_resp_valid_out (bus.ic_cpu_resp_valid),
        .pm_resp_data_out  (bus.ic_cpu_resp_data),
        .ic_req_rvalid     (bus.ic_mem_req_valid),
        .ic_req_rready     (bus.ic_mem_req_ready),
        .ic_req_raddr      (bus.ic_mem_req_addr),
        .ic_resp_rvalid    (bus.ic_mem_resp_valid),
        .ic_resp_rdata     (bus.ic_mem_resp_data),
        .ic_resp_rresp     (bus.ic_mem_resp_code),
        .ic_fault_valid    (bus.ic_fault_valid),
        .ic_fault_addr     (bus.ic_fault_addr),
        .ic_fault_resp     (bus.ic_fault_resp)
    );

    Dcache u_dcache (
        .clk                (clk),
        .reset              (bus.reset),
        .dm_req_addr_in     (bus.dc_cpu_req_addr),
        .dm_req_rvalid_in   (bus.dc_cpu_read_valid),
        .dm_req_rready_in   (bus.dc_cpu_read_ready),
        .dm_resp_rvalid_out (bus.dc_cpu_read_resp_valid),
        .dm_resp_rdata_out  (bus.dc_cpu_read_data),
        .dm_req_wvalid_in   (bus.dc_cpu_write_valid),
        .dm_req_wready_out  (bus.dc_cpu_write_ready),
        .dm_req_wstrb_in    (bus.dc_cpu_write_strb),
        .dm_req_wdata_in    (bus.dc_cpu_write_data),
        .dm_resp_wready_out (bus.dc_cpu_write_resp_valid),
        .dc_req_rvalid      (bus.dc_mem_read_valid),
        .dc_req_rready      (bus.dc_mem_read_ready),
        .dc_req_raddr       (bus.dc_mem_read_addr),
        .dc_resp_rvalid     (bus.dc_mem_read_resp_valid),
        .dc_resp_rdata      (bus.dc_mem_read_resp_data),
        .dc_resp_rresp      (bus.dc_mem_read_resp_code),
        .dc_req_wvalid      (bus.dc_mem_write_valid),
        .dc_req_wready      (bus.dc_mem_write_ready),
        .dc_req_waddr       (bus.dc_mem_write_addr),
        .dc_req_wdata       (bus.dc_mem_write_data),
        .dc_resp_wvalid     (bus.dc_mem_write_resp_valid),
        .dc_resp_wresp      (bus.dc_mem_write_resp_code),
        .dc_fault_valid     (bus.dc_fault_valid),
        .dc_fault_is_write  (bus.dc_fault_is_write),
        .dc_fault_addr      (bus.dc_fault_addr),
        .dc_fault_resp      (bus.dc_fault_resp)
    );

    initial begin
        uvm_config_db#(virtual cache_uvm_if)::set(null, "*", "vif", bus);
        if (!$value$plusargs("UVM_TESTNAME=%s", testname))
            testname = "cache_uvm_test";
        run_test(testname);
    end
endmodule
