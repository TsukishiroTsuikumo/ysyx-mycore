interface icache_if (
  input bit clk
);
  logic         reset;
  logic         req_valid;
  logic         req_ready;
  logic [31:0]  req_addr;

  logic         resp_valid;
  // Complete 16-byte instruction line.  Word address line_base + 4*n maps
  // to resp_data[n*32 +: 32].
  logic [127:0] resp_data;

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
