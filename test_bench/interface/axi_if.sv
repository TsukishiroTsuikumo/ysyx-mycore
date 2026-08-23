`ifndef YSYX_AXI_IF_SV
`define YSYX_AXI_IF_SV

`timescale 1ns/1ps

// AXI4 interface used by the cache/interconnect verification environment.
//
// aw_owner/ar_owner are verification sidebands, not AXI4 signals.  A future
// I/D arbiter or standalone test top should drive 0 for the instruction owner
// and 1 for the data owner.  They let passive components retain ownership
// information after the request has entered the shared AXI fabric.
interface axi_if #(
    parameter int unsigned ADDR_WIDTH  = 32,
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned ID_WIDTH    = 2,
    parameter int unsigned USER_WIDTH  = 1,
    parameter int unsigned OWNER_WIDTH = 1
) (
    input logic aclk,
    input logic aresetn
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam logic [OWNER_WIDTH-1:0] OWNER_INSTR = '0;
    localparam logic [OWNER_WIDTH-1:0] OWNER_DATA  = {{(OWNER_WIDTH-1){1'b0}}, 1'b1};

    initial begin
        if (ADDR_WIDTH == 0 || DATA_WIDTH == 0 || ID_WIDTH == 0 ||
            USER_WIDTH == 0 || OWNER_WIDTH == 0) begin
            $fatal(1, "AXI interface widths must all be greater than zero");
        end
        if ((DATA_WIDTH % 8) != 0 || ((STRB_WIDTH & (STRB_WIDTH - 1)) != 0)) begin
            $fatal(1, "AXI DATA_WIDTH must contain a power-of-two number of bytes");
        end
    end

    // Write address channel.
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic [3:0]             awqos;
    logic [3:0]             awregion;
    logic [USER_WIDTH-1:0]  awuser;
    logic [OWNER_WIDTH-1:0] aw_owner;
    logic                   awvalid;
    logic                   awready;

    // Write data channel.
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic [USER_WIDTH-1:0] wuser;
    logic                  wvalid;
    logic                  wready;

    // Write response channel.
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic [USER_WIDTH-1:0] buser;
    logic                  bvalid;
    logic                  bready;

    // Read address channel.
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [7:0]             arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic [3:0]             arqos;
    logic [3:0]             arregion;
    logic [USER_WIDTH-1:0]  aruser;
    logic [OWNER_WIDTH-1:0] ar_owner;
    logic                   arvalid;
    logic                   arready;

    // Read data channel.
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic [USER_WIDTH-1:0] ruser;
    logic                  rvalid;
    logic                  rready;

    modport master (
        input  aclk, aresetn,
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache,
               awprot, awqos, awregion, awuser, aw_owner, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wuser, wvalid,
        input  wready,
        input  bid, bresp, buser, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arlock, arcache,
               arprot, arqos, arregion, aruser, ar_owner, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, ruser, rvalid,
        output rready
    );

    modport slave (
        input  aclk, aresetn,
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache,
               awprot, awqos, awregion, awuser, aw_owner, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wuser, wvalid,
        output wready,
        output bid, bresp, buser, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache,
               arprot, arqos, arregion, aruser, ar_owner, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, ruser, rvalid,
        input  rready
    );

    modport monitor (
        input aclk, aresetn,
              awid, awaddr, awlen, awsize, awburst, awlock, awcache,
              awprot, awqos, awregion, awuser, aw_owner, awvalid, awready,
              wdata, wstrb, wlast, wuser, wvalid, wready,
              bid, bresp, buser, bvalid, bready,
              arid, araddr, arlen, arsize, arburst, arlock, arcache,
              arprot, arqos, arregion, aruser, ar_owner, arvalid, arready,
              rid, rdata, rresp, rlast, ruser, rvalid, rready
    );

endinterface

`endif
