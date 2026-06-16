interface dcache_if (
  input bit clk
);
    logic           reset;
    logic   [31:0]  req_addr;

    logic           req_rvalid;
    logic           req_rready;
    logic           resp_rvalid;
    logic   [31:0]  resp_rdata;

    logic           req_wvalid;
    logic           req_wready;
    logic    [3:0]  req_wstrb;
    logic   [31:0]  req_wdata;
    logic           resp_wvalid;

    modport dut (
        output req_addr,

        output req_rvalid,
        input  req_rready,
        input  resp_rvalid,
        input  resp_rdata,

        output req_wvalid,
        input  req_wready,
        output req_wstrb,
        output req_wdata,
        input  resp_wvalid
    );

    modport dcache (
        input  req_addr,

        input  req_rvalid,
        output req_rready,
        output resp_rvalid,
        output resp_rdata,

        input  req_wvalid,
        output req_wready,
        input  req_wstrb,
        input  req_wdata,
        output resp_wvalid
    );

endinterface
