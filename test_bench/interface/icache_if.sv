interface icache_if (
  input bit clk
);
  logic         rst;
  logic         req_valid;
  logic         req_ready;
  logic [31:0]  req_addr;

  logic         resp_valid;
  logic [31:0]  resp_data;

  modport dut (
    output req_valid,
    output req_addr,
    input  req_ready,
    input  resp_valid,
    input  resp_data
  );

  modport icache (
    input  req_valid,
    input  req_addr,
    output req_ready,
    output resp_valid,
    output resp_data
  );

endinterface
