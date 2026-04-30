module test_bench;

  import uvm_pkg::*;
  import mycore_pkg::*;

  bit clk;
  bit reset;
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
    reset = 1;
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
    .dm_st_out(mycore_if_inst.dm_st_out),
    .dm_ld_out(mycore_if_inst.dm_ld_out),
    .ld_valid(mycore_if_inst.ld_valid)
  );

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
    $fsdbDumpfile("test.wave");
    $fsdbDumpvars(0, test_bench);
  end

  initial begin
    uvm_config_db#(virtual mycore_if)::set(null, "*", "vif", mycore_if_inst);
    run_test("mycore_test");
  end

endmodule
