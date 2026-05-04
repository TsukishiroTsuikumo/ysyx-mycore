`timescale 1ns/1ps

module test_bench;

  import uvm_pkg::*;
  import mycore_pkg::*;

  bit clk;
  bit reset;
  initial begin
    clk = 0;
    reset = 0;
    forever #1 clk = ~clk;
  end
  
  mycore_if mycore_if_inst(clk, reset);
  mycore dut(
    .clk(clk),
    .reset(reset),
    .pm_rd_in(mycore_if_inst.pm_rd_in),
    .pm_addr_out(mycore_if_inst.pm_addr_out),
    .ifetch(mycore_if_inst.ifetch),
    .dm_rd_in(mycore_if_inst.dm_rd_in),
    .dm_wr_out(mycore_if_inst.dm_wr_out),
    .dm_addr_out(mycore_if_inst.dm_addr_out),
    .dm_st(mycore_if_inst.dm_st_out),
    .dm_ld(mycore_if_inst.dm_ld_out),
    .ld_valid(mycore_if_inst.ld_valid)
  );

  state_probe_if state_probe_if_inst(clk, reset);
  genvar i;
  generate
    for (i = 0; i < 32; i++) begin: gen_regfile_probe
      assign state_probe_if_inst.reg_val[i] = dut.regfile.reg_val[i];
    end
    assign state_probe_if_inst.pm_rd_in = dut.pm_rd_in;
    assign state_probe_if_inst.pc_val = dut.current_pc_if;
    assign state_probe_if_inst.w1_en = dut.regfile.w1_en;
  endgenerate

  initial begin
    mycore_if_inst.pm_rd_in = 0;
    mycore_if_inst.pm_addr_out = 0;
    mycore_if_inst.ifetch = 0;
    mycore_if_inst.dm_rd_in = 0;
    mycore_if_inst.dm_wr_out = 0;
    mycore_if_inst.dm_addr_out = 0;
    mycore_if_inst.dm_st_out = 0;
    mycore_if_inst.dm_ld_out = 0;
    mycore_if_inst.ld_valid = 0;
  end

  initial begin
    $dumpfile("test.vcd");
    $dumpvars(0, test_bench);
  end

  string testname;

  initial begin
    uvm_config_db#(virtual mycore_if)::set(null, "*", "vif", mycore_if_inst);
    uvm_config_db#(virtual state_probe_if)::set(null, "*", "vif", state_probe_if_inst);
    if (!$value$plusargs("UVM_TESTNAME=%s", testname)) begin
      testname = "mycore_test";
    end
    run_test(testname);
  end

endmodule
