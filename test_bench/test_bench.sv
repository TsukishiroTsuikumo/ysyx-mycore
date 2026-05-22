`timescale 1ns/1ps

module test_bench;

  import uvm_pkg::*;
  import mycore_pkg::*;

  bit clk;
  int unsigned reg_init_seed;
  int unsigned sim_timeout_cycles;

  function automatic logic [31:0] make_init_reg_value(
    input int unsigned index,
    input int unsigned seed
  );
    logic [31:0] value;
    begin
      value = seed ^ (32'h9e37_79b9 * index);
      value = value ^ (value << 13);
      value = value ^ (value >> 17);
      value = value ^ (value << 5);
      make_init_reg_value = value;
    end
  endfunction

  task automatic initialize_register_file();
    integer idx;
    logic [31:0] value;
    begin
      reg_init_seed = 32'h1bad_f00d;
      void'($value$plusargs("REG_INIT_SEED=%d", reg_init_seed));
      state_probe_if_inst.reg_init_done = 1'b0;
      for (idx = 0; idx < 32; idx++) begin
        value = (idx == 0) ? 32'b0 : make_init_reg_value(idx, reg_init_seed);
        dut.regfile.reg_val[idx] = value;
        state_probe_if_inst.init_reg_val[idx] = value;
      end
      state_probe_if_inst.reg_init_done = 1'b1;
      $display("REGINIT: initialized DUT regfile with REG_INIT_SEED=%0d", reg_init_seed);
    end
  endtask

  initial begin
    clk = 0;
    forever #1 clk = ~clk;
  end

  initial begin
    sim_timeout_cycles = 200000;
    void'($value$plusargs("SIM_TIMEOUT=%d", sim_timeout_cycles));
    repeat (sim_timeout_cycles) @(posedge clk);
    $fatal(1, "SIM_TIMEOUT: simulation exceeded %0d cycles", sim_timeout_cycles);
  end

  mycore_if mycore_if_inst(clk);
  mycore dut(
    .clk(clk),
    .reset(mycore_if_inst.dut_port.reset),

    .pm_req_valid_out(mycore_if_inst.dut_port.pm_req_valid),
    .pm_req_addr_out(mycore_if_inst.dut_port.pm_req_addr),
    .pm_req_ready_in(mycore_if_inst.dut_port.pm_req_ready),
    .pm_resp_valid_in(mycore_if_inst.dut_port.pm_resp_valid),
    .pm_resp_data_in(mycore_if_inst.dut_port.pm_resp_data),
    .dm_req_addr_out(mycore_if_inst.dut_port.dm_req_addr),

    .dm_req_rvalid_out(mycore_if_inst.dut_port.dm_req_rvalid),
    .dm_req_rready_in(mycore_if_inst.dut_port.dm_req_rready),
    .dm_resp_rvalid_in(mycore_if_inst.dut_port.dm_resp_rvalid),
    .dm_resp_rdata_in(mycore_if_inst.dut_port.dm_resp_rdata),

    .dm_req_wvalid_out(mycore_if_inst.dut_port.dm_req_wvalid),
    .dm_req_wready_in(mycore_if_inst.dut_port.dm_req_wready),
    .dm_req_wstrb_out(mycore_if_inst.dut_port.dm_req_wstrb),
    .dm_req_wdata_out(mycore_if_inst.dut_port.dm_req_wdata),
    .dm_resp_wvalid_in(mycore_if_inst.dut_port.dm_resp_wvalid)
  );

  state_probe_if state_probe_if_inst(clk, mycore_if_inst.reset);
  genvar i;
  generate
    for (i = 0; i < 32; i++) begin: gen_regfile_probe
      assign state_probe_if_inst.reg_val[i] = dut.regfile.reg_val[i];
    end
    assign state_probe_if_inst.instr_val = dut.instr_id;
    assign state_probe_if_inst.pc_val = dut.current_pc_if;
    assign state_probe_if_inst.instr_accept = mycore_if_inst.pm_req_valid && mycore_if_inst.pm_resp_valid && !dut.if_stall;
  endgenerate

  always @(posedge clk or posedge mycore_if_inst.reset) begin
    if (mycore_if_inst.reset) begin
      state_probe_if_inst.commit  <= 1'b0;
      state_probe_if_inst.wb_addr <= 5'b0;
      state_probe_if_inst.wb_data <= 32'b0;
    end
    else begin
      state_probe_if_inst.commit  <= dut.regfile.w1_en;
      state_probe_if_inst.wb_addr <= dut.regfile.w1_addr;
      state_probe_if_inst.wb_data <= dut.regfile.w1_in;
    end
  end

  initial begin
    $dumpfile("test.vcd");
    $dumpvars(0, test_bench);
  end

  initial begin
    forever begin
      @state_probe_if_inst.reg_init_request;
      initialize_register_file();
    end
  end

  string testname;

  initial begin
    mycore_if_inst.reset = 1'b1;
    uvm_config_db#(virtual mycore_if)::set(null, "*", "vif", mycore_if_inst);
    uvm_config_db#(virtual state_probe_if)::set(null, "*", "vif", state_probe_if_inst);
    if (!$value$plusargs("UVM_TESTNAME=%s", testname)) begin
      testname = "mycore_test";
    end
    run_test(testname);
  end

endmodule
