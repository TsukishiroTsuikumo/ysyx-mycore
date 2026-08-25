`timescale 1ns/1ps

// Cache-line to AXI4 memory subsystem.
//
// This wrapper preserves the line-oriented interfaces currently used by the
// instruction and data caches while implementing the shared memory path with
// 32-bit AXI4 bursts. It intentionally keeps the legacy memory image tasks at
// this hierarchy level so a wrapper instance named u_mem remains compatible
// with existing test code that calls u_mem.write_word(...).
module cache_axi_memory_system #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2,
    parameter integer LINE_BYTES = 16,
    parameter integer MEM_WIDTH  = 24,
    parameter integer MEM_BYTES  = (1 << MEM_WIDTH),
    parameter [ADDR_WIDTH-1:0] RAM_BASE  = 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] RAM_MASK  = 32'hff00_0000,
    parameter [ADDR_WIDTH-1:0] MMIO_BASE = 32'h1000_0000,
    parameter [ADDR_WIDTH-1:0] MMIO_MASK = 32'hffff_0000
)(
    input                               clk,
    input                               reset,

    // ICache line-read interface.
    input                               ic_req_rvalid,
    output                              ic_req_rready,
    input      [ADDR_WIDTH-1:0]         ic_req_raddr,
    output                              ic_resp_rvalid,
    output     [LINE_BYTES*8-1:0]       ic_resp_rdata,
    output     [1:0]                    ic_resp_rresp,

    // DCache line-read interface.
    input                               dc_req_rvalid,
    output                              dc_req_rready,
    input      [ADDR_WIDTH-1:0]         dc_req_raddr,
    output                              dc_resp_rvalid,
    output     [LINE_BYTES*8-1:0]       dc_resp_rdata,
    output     [1:0]                    dc_resp_rresp,

    // DCache line-writeback interface.
    input                               dc_req_wvalid,
    output                              dc_req_wready,
    input      [ADDR_WIDTH-1:0]         dc_req_waddr,
    input      [LINE_BYTES*8-1:0]       dc_req_wdata,
    output                              dc_resp_wvalid,
    output     [1:0]                    dc_resp_wresp,

    // Passive observation of the shared AXI boundary.  These ports do not
    // participate in the handshake; they expose the D-cache write channels
    // and the post-arbitration I/D read channels to the verification layer.
    output     [ID_WIDTH-1:0]           mon_axi_awid,
    output     [ADDR_WIDTH-1:0]         mon_axi_awaddr,
    output     [7:0]                    mon_axi_awlen,
    output     [2:0]                    mon_axi_awsize,
    output     [1:0]                    mon_axi_awburst,
    output                              mon_axi_awlock,
    output     [3:0]                    mon_axi_awcache,
    output     [2:0]                    mon_axi_awprot,
    output     [3:0]                    mon_axi_awqos,
    output                              mon_axi_awvalid,
    output                              mon_axi_awready,
    output     [DATA_WIDTH-1:0]         mon_axi_wdata,
    output     [DATA_WIDTH/8-1:0]       mon_axi_wstrb,
    output                              mon_axi_wlast,
    output                              mon_axi_wvalid,
    output                              mon_axi_wready,
    output     [ID_WIDTH-1:0]           mon_axi_bid,
    output     [1:0]                    mon_axi_bresp,
    output                              mon_axi_bvalid,
    output                              mon_axi_bready,
    output     [ID_WIDTH-1:0]           mon_axi_arid,
    output     [ADDR_WIDTH-1:0]         mon_axi_araddr,
    output     [7:0]                    mon_axi_arlen,
    output     [2:0]                    mon_axi_arsize,
    output     [1:0]                    mon_axi_arburst,
    output                              mon_axi_arlock,
    output     [3:0]                    mon_axi_arcache,
    output     [2:0]                    mon_axi_arprot,
    output     [3:0]                    mon_axi_arqos,
    output                              mon_axi_arvalid,
    output                              mon_axi_arready,
    output     [ID_WIDTH-1:0]           mon_axi_rid,
    output     [DATA_WIDTH-1:0]         mon_axi_rdata,
    output     [1:0]                    mon_axi_rresp,
    output                              mon_axi_rlast,
    output                              mon_axi_rvalid,
    output                              mon_axi_rready
);

    localparam [ID_WIDTH-1:0] ICACHE_AXI_ID = {ID_WIDTH{1'b0}};
    localparam [ID_WIDTH-1:0] DCACHE_AXI_ID =
        {{(ID_WIDTH-1){1'b0}}, 1'b1};

    // ICache adapter read channels.
    wire [ID_WIDTH-1:0]   ic_axi_arid;
    wire [ADDR_WIDTH-1:0] ic_axi_araddr;
    wire [7:0]            ic_axi_arlen;
    wire [2:0]            ic_axi_arsize;
    wire [1:0]            ic_axi_arburst;
    wire                  ic_axi_arlock;
    wire [3:0]            ic_axi_arcache;
    wire [2:0]            ic_axi_arprot;
    wire [3:0]            ic_axi_arqos;
    wire                  ic_axi_arvalid;
    wire                  ic_axi_arready;
    wire [ID_WIDTH-1:0]   ic_axi_rid;
    wire [DATA_WIDTH-1:0] ic_axi_rdata;
    wire [1:0]            ic_axi_rresp;
    wire                  ic_axi_rlast;
    wire                  ic_axi_rvalid;
    wire                  ic_axi_rready;

    // DCache adapter channels.
    wire [ID_WIDTH-1:0]   dc_axi_awid;
    wire [ADDR_WIDTH-1:0] dc_axi_awaddr;
    wire [7:0]            dc_axi_awlen;
    wire [2:0]            dc_axi_awsize;
    wire [1:0]            dc_axi_awburst;
    wire                  dc_axi_awlock;
    wire [3:0]            dc_axi_awcache;
    wire [2:0]            dc_axi_awprot;
    wire [3:0]            dc_axi_awqos;
    wire                  dc_axi_awvalid;
    wire                  dc_axi_awready;
    wire [DATA_WIDTH-1:0] dc_axi_wdata;
    wire [DATA_WIDTH/8-1:0] dc_axi_wstrb;
    wire                  dc_axi_wlast;
    wire                  dc_axi_wvalid;
    wire                  dc_axi_wready;
    wire [ID_WIDTH-1:0]   dc_axi_bid;
    wire [1:0]            dc_axi_bresp;
    wire                  dc_axi_bvalid;
    wire                  dc_axi_bready;
    wire [ID_WIDTH-1:0]   dc_axi_arid;
    wire [ADDR_WIDTH-1:0] dc_axi_araddr;
    wire [7:0]            dc_axi_arlen;
    wire [2:0]            dc_axi_arsize;
    wire [1:0]            dc_axi_arburst;
    wire                  dc_axi_arlock;
    wire [3:0]            dc_axi_arcache;
    wire [2:0]            dc_axi_arprot;
    wire [3:0]            dc_axi_arqos;
    wire                  dc_axi_arvalid;
    wire                  dc_axi_arready;
    wire [ID_WIDTH-1:0]   dc_axi_rid;
    wire [DATA_WIDTH-1:0] dc_axi_rdata;
    wire [1:0]            dc_axi_rresp;
    wire                  dc_axi_rlast;
    wire                  dc_axi_rvalid;
    wire                  dc_axi_rready;

    // Shared read channel after I/D arbitration.
    wire [ID_WIDTH-1:0]   arb_axi_arid;
    wire [ADDR_WIDTH-1:0] arb_axi_araddr;
    wire [7:0]            arb_axi_arlen;
    wire [2:0]            arb_axi_arsize;
    wire [1:0]            arb_axi_arburst;
    wire                  arb_axi_arlock;
    wire [3:0]            arb_axi_arcache;
    wire [2:0]            arb_axi_arprot;
    wire [3:0]            arb_axi_arqos;
    wire                  arb_axi_arvalid;
    wire                  arb_axi_arready;
    wire [ID_WIDTH-1:0]   arb_axi_rid;
    wire [DATA_WIDTH-1:0] arb_axi_rdata;
    wire [1:0]            arb_axi_rresp;
    wire                  arb_axi_rlast;
    wire                  arb_axi_rvalid;
    wire                  arb_axi_rready;

    assign mon_axi_awid    = dc_axi_awid;
    assign mon_axi_awaddr  = dc_axi_awaddr;
    assign mon_axi_awlen   = dc_axi_awlen;
    assign mon_axi_awsize  = dc_axi_awsize;
    assign mon_axi_awburst = dc_axi_awburst;
    assign mon_axi_awlock  = dc_axi_awlock;
    assign mon_axi_awcache = dc_axi_awcache;
    assign mon_axi_awprot  = dc_axi_awprot;
    assign mon_axi_awqos   = dc_axi_awqos;
    assign mon_axi_awvalid = dc_axi_awvalid;
    assign mon_axi_awready = dc_axi_awready;
    assign mon_axi_wdata   = dc_axi_wdata;
    assign mon_axi_wstrb   = dc_axi_wstrb;
    assign mon_axi_wlast   = dc_axi_wlast;
    assign mon_axi_wvalid  = dc_axi_wvalid;
    assign mon_axi_wready  = dc_axi_wready;
    assign mon_axi_bid     = dc_axi_bid;
    assign mon_axi_bresp   = dc_axi_bresp;
    assign mon_axi_bvalid  = dc_axi_bvalid;
    assign mon_axi_bready  = dc_axi_bready;

    assign mon_axi_arid    = arb_axi_arid;
    assign mon_axi_araddr  = arb_axi_araddr;
    assign mon_axi_arlen   = arb_axi_arlen;
    assign mon_axi_arsize  = arb_axi_arsize;
    assign mon_axi_arburst = arb_axi_arburst;
    assign mon_axi_arlock  = arb_axi_arlock;
    assign mon_axi_arcache = arb_axi_arcache;
    assign mon_axi_arprot  = arb_axi_arprot;
    assign mon_axi_arqos   = arb_axi_arqos;
    assign mon_axi_arvalid = arb_axi_arvalid;
    assign mon_axi_arready = arb_axi_arready;
    assign mon_axi_rid     = arb_axi_rid;
    assign mon_axi_rdata   = arb_axi_rdata;
    assign mon_axi_rresp   = arb_axi_rresp;
    assign mon_axi_rlast   = arb_axi_rlast;
    assign mon_axi_rvalid  = arb_axi_rvalid;
    assign mon_axi_rready  = arb_axi_rready;

    // Decoder-to-RAM channels.
    wire [ID_WIDTH-1:0]   ram_axi_awid;
    wire [ADDR_WIDTH-1:0] ram_axi_awaddr;
    wire [7:0]            ram_axi_awlen;
    wire [2:0]            ram_axi_awsize;
    wire [1:0]            ram_axi_awburst;
    wire                  ram_axi_awlock;
    wire [3:0]            ram_axi_awcache;
    wire [2:0]            ram_axi_awprot;
    wire [3:0]            ram_axi_awqos;
    wire                  ram_axi_awvalid;
    wire                  ram_axi_awready;
    wire [DATA_WIDTH-1:0] ram_axi_wdata;
    wire [DATA_WIDTH/8-1:0] ram_axi_wstrb;
    wire                  ram_axi_wlast;
    wire                  ram_axi_wvalid;
    wire                  ram_axi_wready;
    wire [ID_WIDTH-1:0]   ram_axi_bid;
    wire [1:0]            ram_axi_bresp;
    wire                  ram_axi_bvalid;
    wire                  ram_axi_bready;
    wire [ID_WIDTH-1:0]   ram_axi_arid;
    wire [ADDR_WIDTH-1:0] ram_axi_araddr;
    wire [7:0]            ram_axi_arlen;
    wire [2:0]            ram_axi_arsize;
    wire [1:0]            ram_axi_arburst;
    wire                  ram_axi_arlock;
    wire [3:0]            ram_axi_arcache;
    wire [2:0]            ram_axi_arprot;
    wire [3:0]            ram_axi_arqos;
    wire                  ram_axi_arvalid;
    wire                  ram_axi_arready;
    wire [ID_WIDTH-1:0]   ram_axi_rid;
    wire [DATA_WIDTH-1:0] ram_axi_rdata;
    wire [1:0]            ram_axi_rresp;
    wire                  ram_axi_rlast;
    wire                  ram_axi_rvalid;
    wire                  ram_axi_rready;

    // Decoder-to-MMIO error terminator channels.
    wire [ID_WIDTH-1:0]   mmio_axi_awid;
    wire [ADDR_WIDTH-1:0] mmio_axi_awaddr;
    wire [7:0]            mmio_axi_awlen;
    wire [2:0]            mmio_axi_awsize;
    wire [1:0]            mmio_axi_awburst;
    wire                  mmio_axi_awlock;
    wire [3:0]            mmio_axi_awcache;
    wire [2:0]            mmio_axi_awprot;
    wire [3:0]            mmio_axi_awqos;
    wire                  mmio_axi_awvalid;
    wire                  mmio_axi_awready;
    wire [DATA_WIDTH-1:0] mmio_axi_wdata;
    wire [DATA_WIDTH/8-1:0] mmio_axi_wstrb;
    wire                  mmio_axi_wlast;
    wire                  mmio_axi_wvalid;
    wire                  mmio_axi_wready;
    wire [ID_WIDTH-1:0]   mmio_axi_bid;
    wire [1:0]            mmio_axi_bresp;
    wire                  mmio_axi_bvalid;
    wire                  mmio_axi_bready;
    wire [ID_WIDTH-1:0]   mmio_axi_arid;
    wire [ADDR_WIDTH-1:0] mmio_axi_araddr;
    wire [7:0]            mmio_axi_arlen;
    wire [2:0]            mmio_axi_arsize;
    wire [1:0]            mmio_axi_arburst;
    wire                  mmio_axi_arlock;
    wire [3:0]            mmio_axi_arcache;
    wire [2:0]            mmio_axi_arprot;
    wire [3:0]            mmio_axi_arqos;
    wire                  mmio_axi_arvalid;
    wire                  mmio_axi_arready;
    wire [ID_WIDTH-1:0]   mmio_axi_rid;
    wire [DATA_WIDTH-1:0] mmio_axi_rdata;
    wire [1:0]            mmio_axi_rresp;
    wire                  mmio_axi_rlast;
    wire                  mmio_axi_rvalid;
    wire                  mmio_axi_rready;

    icache_axi_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .AXI_ID     (ICACHE_AXI_ID)
    ) u_icache_adapter (
        .clk             (clk),
        .reset           (reset),
        .line_req_valid  (ic_req_rvalid),
        .line_req_ready  (ic_req_rready),
        .line_req_addr   (ic_req_raddr),
        .line_resp_valid (ic_resp_rvalid),
        .line_resp_data  (ic_resp_rdata),
        .line_resp_resp  (ic_resp_rresp),
        .m_axi_arid      (ic_axi_arid),
        .m_axi_araddr    (ic_axi_araddr),
        .m_axi_arlen     (ic_axi_arlen),
        .m_axi_arsize    (ic_axi_arsize),
        .m_axi_arburst   (ic_axi_arburst),
        .m_axi_arlock    (ic_axi_arlock),
        .m_axi_arcache   (ic_axi_arcache),
        .m_axi_arprot    (ic_axi_arprot),
        .m_axi_arqos     (ic_axi_arqos),
        .m_axi_arvalid   (ic_axi_arvalid),
        .m_axi_arready   (ic_axi_arready),
        .m_axi_rid       (ic_axi_rid),
        .m_axi_rdata     (ic_axi_rdata),
        .m_axi_rresp     (ic_axi_rresp),
        .m_axi_rlast     (ic_axi_rlast),
        .m_axi_rvalid    (ic_axi_rvalid),
        .m_axi_rready    (ic_axi_rready)
    );

    dcache_axi_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .AXI_ID     (DCACHE_AXI_ID)
    ) u_dcache_adapter (
        .clk              (clk),
        .reset            (reset),
        .line_rreq_valid  (dc_req_rvalid),
        .line_rreq_ready  (dc_req_rready),
        .line_rreq_addr   (dc_req_raddr),
        .line_rresp_valid (dc_resp_rvalid),
        .line_rresp_data  (dc_resp_rdata),
        .line_rresp_resp  (dc_resp_rresp),
        .line_wreq_valid  (dc_req_wvalid),
        .line_wreq_ready  (dc_req_wready),
        .line_wreq_addr   (dc_req_waddr),
        .line_wreq_data   (dc_req_wdata),
        .line_wresp_valid (dc_resp_wvalid),
        .line_wresp_resp  (dc_resp_wresp),
        .m_axi_awid       (dc_axi_awid),
        .m_axi_awaddr     (dc_axi_awaddr),
        .m_axi_awlen      (dc_axi_awlen),
        .m_axi_awsize     (dc_axi_awsize),
        .m_axi_awburst    (dc_axi_awburst),
        .m_axi_awlock     (dc_axi_awlock),
        .m_axi_awcache    (dc_axi_awcache),
        .m_axi_awprot     (dc_axi_awprot),
        .m_axi_awqos      (dc_axi_awqos),
        .m_axi_awvalid    (dc_axi_awvalid),
        .m_axi_awready    (dc_axi_awready),
        .m_axi_wdata      (dc_axi_wdata),
        .m_axi_wstrb      (dc_axi_wstrb),
        .m_axi_wlast      (dc_axi_wlast),
        .m_axi_wvalid     (dc_axi_wvalid),
        .m_axi_wready     (dc_axi_wready),
        .m_axi_bid        (dc_axi_bid),
        .m_axi_bresp      (dc_axi_bresp),
        .m_axi_bvalid     (dc_axi_bvalid),
        .m_axi_bready     (dc_axi_bready),
        .m_axi_arid       (dc_axi_arid),
        .m_axi_araddr     (dc_axi_araddr),
        .m_axi_arlen      (dc_axi_arlen),
        .m_axi_arsize     (dc_axi_arsize),
        .m_axi_arburst    (dc_axi_arburst),
        .m_axi_arlock     (dc_axi_arlock),
        .m_axi_arcache    (dc_axi_arcache),
        .m_axi_arprot     (dc_axi_arprot),
        .m_axi_arqos      (dc_axi_arqos),
        .m_axi_arvalid    (dc_axi_arvalid),
        .m_axi_arready    (dc_axi_arready),
        .m_axi_rid        (dc_axi_rid),
        .m_axi_rdata      (dc_axi_rdata),
        .m_axi_rresp      (dc_axi_rresp),
        .m_axi_rlast      (dc_axi_rlast),
        .m_axi_rvalid     (dc_axi_rvalid),
        .m_axi_rready     (dc_axi_rready)
    );

    axi_read_arbiter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_read_arbiter (
        .clk            (clk),
        .reset          (reset),
        .s0_axi_arid    (ic_axi_arid),
        .s0_axi_araddr  (ic_axi_araddr),
        .s0_axi_arlen   (ic_axi_arlen),
        .s0_axi_arsize  (ic_axi_arsize),
        .s0_axi_arburst (ic_axi_arburst),
        .s0_axi_arlock  (ic_axi_arlock),
        .s0_axi_arcache (ic_axi_arcache),
        .s0_axi_arprot  (ic_axi_arprot),
        .s0_axi_arqos   (ic_axi_arqos),
        .s0_axi_arvalid (ic_axi_arvalid),
        .s0_axi_arready (ic_axi_arready),
        .s0_axi_rid     (ic_axi_rid),
        .s0_axi_rdata   (ic_axi_rdata),
        .s0_axi_rresp   (ic_axi_rresp),
        .s0_axi_rlast   (ic_axi_rlast),
        .s0_axi_rvalid  (ic_axi_rvalid),
        .s0_axi_rready  (ic_axi_rready),
        .s1_axi_arid    (dc_axi_arid),
        .s1_axi_araddr  (dc_axi_araddr),
        .s1_axi_arlen   (dc_axi_arlen),
        .s1_axi_arsize  (dc_axi_arsize),
        .s1_axi_arburst (dc_axi_arburst),
        .s1_axi_arlock  (dc_axi_arlock),
        .s1_axi_arcache (dc_axi_arcache),
        .s1_axi_arprot  (dc_axi_arprot),
        .s1_axi_arqos   (dc_axi_arqos),
        .s1_axi_arvalid (dc_axi_arvalid),
        .s1_axi_arready (dc_axi_arready),
        .s1_axi_rid     (dc_axi_rid),
        .s1_axi_rdata   (dc_axi_rdata),
        .s1_axi_rresp   (dc_axi_rresp),
        .s1_axi_rlast   (dc_axi_rlast),
        .s1_axi_rvalid  (dc_axi_rvalid),
        .s1_axi_rready  (dc_axi_rready),
        .m_axi_arid     (arb_axi_arid),
        .m_axi_araddr   (arb_axi_araddr),
        .m_axi_arlen    (arb_axi_arlen),
        .m_axi_arsize   (arb_axi_arsize),
        .m_axi_arburst  (arb_axi_arburst),
        .m_axi_arlock   (arb_axi_arlock),
        .m_axi_arcache  (arb_axi_arcache),
        .m_axi_arprot   (arb_axi_arprot),
        .m_axi_arqos    (arb_axi_arqos),
        .m_axi_arvalid  (arb_axi_arvalid),
        .m_axi_arready  (arb_axi_arready),
        .m_axi_rid      (arb_axi_rid),
        .m_axi_rdata    (arb_axi_rdata),
        .m_axi_rresp    (arb_axi_rresp),
        .m_axi_rlast    (arb_axi_rlast),
        .m_axi_rvalid   (arb_axi_rvalid),
        .m_axi_rready   (arb_axi_rready)
    );

    axi_addr_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .RAM_BASE   (RAM_BASE),
        .RAM_MASK   (RAM_MASK),
        .MMIO_BASE  (MMIO_BASE),
        .MMIO_MASK  (MMIO_MASK)
    ) u_addr_decoder (
        .clk               (clk),
        .reset             (reset),
        .s_axi_awid        (dc_axi_awid),
        .s_axi_awaddr      (dc_axi_awaddr),
        .s_axi_awlen       (dc_axi_awlen),
        .s_axi_awsize      (dc_axi_awsize),
        .s_axi_awburst     (dc_axi_awburst),
        .s_axi_awlock      (dc_axi_awlock),
        .s_axi_awcache     (dc_axi_awcache),
        .s_axi_awprot      (dc_axi_awprot),
        .s_axi_awqos       (dc_axi_awqos),
        .s_axi_awvalid     (dc_axi_awvalid),
        .s_axi_awready     (dc_axi_awready),
        .s_axi_wdata       (dc_axi_wdata),
        .s_axi_wstrb       (dc_axi_wstrb),
        .s_axi_wlast       (dc_axi_wlast),
        .s_axi_wvalid      (dc_axi_wvalid),
        .s_axi_wready      (dc_axi_wready),
        .s_axi_bid         (dc_axi_bid),
        .s_axi_bresp       (dc_axi_bresp),
        .s_axi_bvalid      (dc_axi_bvalid),
        .s_axi_bready      (dc_axi_bready),
        .s_axi_arid        (arb_axi_arid),
        .s_axi_araddr      (arb_axi_araddr),
        .s_axi_arlen       (arb_axi_arlen),
        .s_axi_arsize      (arb_axi_arsize),
        .s_axi_arburst     (arb_axi_arburst),
        .s_axi_arlock      (arb_axi_arlock),
        .s_axi_arcache     (arb_axi_arcache),
        .s_axi_arprot      (arb_axi_arprot),
        .s_axi_arqos       (arb_axi_arqos),
        .s_axi_arvalid     (arb_axi_arvalid),
        .s_axi_arready     (arb_axi_arready),
        .s_axi_rid         (arb_axi_rid),
        .s_axi_rdata       (arb_axi_rdata),
        .s_axi_rresp       (arb_axi_rresp),
        .s_axi_rlast       (arb_axi_rlast),
        .s_axi_rvalid      (arb_axi_rvalid),
        .s_axi_rready      (arb_axi_rready),
        .ram_axi_awid      (ram_axi_awid),
        .ram_axi_awaddr    (ram_axi_awaddr),
        .ram_axi_awlen     (ram_axi_awlen),
        .ram_axi_awsize    (ram_axi_awsize),
        .ram_axi_awburst   (ram_axi_awburst),
        .ram_axi_awlock    (ram_axi_awlock),
        .ram_axi_awcache   (ram_axi_awcache),
        .ram_axi_awprot    (ram_axi_awprot),
        .ram_axi_awqos     (ram_axi_awqos),
        .ram_axi_awvalid   (ram_axi_awvalid),
        .ram_axi_awready   (ram_axi_awready),
        .ram_axi_wdata     (ram_axi_wdata),
        .ram_axi_wstrb     (ram_axi_wstrb),
        .ram_axi_wlast     (ram_axi_wlast),
        .ram_axi_wvalid    (ram_axi_wvalid),
        .ram_axi_wready    (ram_axi_wready),
        .ram_axi_bid       (ram_axi_bid),
        .ram_axi_bresp     (ram_axi_bresp),
        .ram_axi_bvalid    (ram_axi_bvalid),
        .ram_axi_bready    (ram_axi_bready),
        .ram_axi_arid      (ram_axi_arid),
        .ram_axi_araddr    (ram_axi_araddr),
        .ram_axi_arlen     (ram_axi_arlen),
        .ram_axi_arsize    (ram_axi_arsize),
        .ram_axi_arburst   (ram_axi_arburst),
        .ram_axi_arlock    (ram_axi_arlock),
        .ram_axi_arcache   (ram_axi_arcache),
        .ram_axi_arprot    (ram_axi_arprot),
        .ram_axi_arqos     (ram_axi_arqos),
        .ram_axi_arvalid   (ram_axi_arvalid),
        .ram_axi_arready   (ram_axi_arready),
        .ram_axi_rid       (ram_axi_rid),
        .ram_axi_rdata     (ram_axi_rdata),
        .ram_axi_rresp     (ram_axi_rresp),
        .ram_axi_rlast     (ram_axi_rlast),
        .ram_axi_rvalid    (ram_axi_rvalid),
        .ram_axi_rready    (ram_axi_rready),
        .mmio_axi_awid     (mmio_axi_awid),
        .mmio_axi_awaddr   (mmio_axi_awaddr),
        .mmio_axi_awlen    (mmio_axi_awlen),
        .mmio_axi_awsize   (mmio_axi_awsize),
        .mmio_axi_awburst  (mmio_axi_awburst),
        .mmio_axi_awlock   (mmio_axi_awlock),
        .mmio_axi_awcache  (mmio_axi_awcache),
        .mmio_axi_awprot   (mmio_axi_awprot),
        .mmio_axi_awqos    (mmio_axi_awqos),
        .mmio_axi_awvalid  (mmio_axi_awvalid),
        .mmio_axi_awready  (mmio_axi_awready),
        .mmio_axi_wdata    (mmio_axi_wdata),
        .mmio_axi_wstrb    (mmio_axi_wstrb),
        .mmio_axi_wlast    (mmio_axi_wlast),
        .mmio_axi_wvalid   (mmio_axi_wvalid),
        .mmio_axi_wready   (mmio_axi_wready),
        .mmio_axi_bid      (mmio_axi_bid),
        .mmio_axi_bresp    (mmio_axi_bresp),
        .mmio_axi_bvalid   (mmio_axi_bvalid),
        .mmio_axi_bready   (mmio_axi_bready),
        .mmio_axi_arid     (mmio_axi_arid),
        .mmio_axi_araddr   (mmio_axi_araddr),
        .mmio_axi_arlen    (mmio_axi_arlen),
        .mmio_axi_arsize   (mmio_axi_arsize),
        .mmio_axi_arburst  (mmio_axi_arburst),
        .mmio_axi_arlock   (mmio_axi_arlock),
        .mmio_axi_arcache  (mmio_axi_arcache),
        .mmio_axi_arprot   (mmio_axi_arprot),
        .mmio_axi_arqos    (mmio_axi_arqos),
        .mmio_axi_arvalid  (mmio_axi_arvalid),
        .mmio_axi_arready  (mmio_axi_arready),
        .mmio_axi_rid      (mmio_axi_rid),
        .mmio_axi_rdata    (mmio_axi_rdata),
        .mmio_axi_rresp    (mmio_axi_rresp),
        .mmio_axi_rlast    (mmio_axi_rlast),
        .mmio_axi_rvalid   (mmio_axi_rvalid),
        .mmio_axi_rready   (mmio_axi_rready)
    );

    axi_ram_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .MEM_WIDTH  (MEM_WIDTH),
        .MEM_BYTES  (MEM_BYTES),
        .BASE_ADDR  (RAM_BASE)
    ) u_ram (
        .clk           (clk),
        .reset         (reset),
        .s_axi_awid    (ram_axi_awid),
        .s_axi_awaddr  (ram_axi_awaddr),
        .s_axi_awlen   (ram_axi_awlen),
        .s_axi_awsize  (ram_axi_awsize),
        .s_axi_awburst (ram_axi_awburst),
        .s_axi_awlock  (ram_axi_awlock),
        .s_axi_awcache (ram_axi_awcache),
        .s_axi_awprot  (ram_axi_awprot),
        .s_axi_awqos   (ram_axi_awqos),
        .s_axi_awvalid (ram_axi_awvalid),
        .s_axi_awready (ram_axi_awready),
        .s_axi_wdata   (ram_axi_wdata),
        .s_axi_wstrb   (ram_axi_wstrb),
        .s_axi_wlast   (ram_axi_wlast),
        .s_axi_wvalid  (ram_axi_wvalid),
        .s_axi_wready  (ram_axi_wready),
        .s_axi_bid     (ram_axi_bid),
        .s_axi_bresp   (ram_axi_bresp),
        .s_axi_bvalid  (ram_axi_bvalid),
        .s_axi_bready  (ram_axi_bready),
        .s_axi_arid    (ram_axi_arid),
        .s_axi_araddr  (ram_axi_araddr),
        .s_axi_arlen   (ram_axi_arlen),
        .s_axi_arsize  (ram_axi_arsize),
        .s_axi_arburst (ram_axi_arburst),
        .s_axi_arlock  (ram_axi_arlock),
        .s_axi_arcache (ram_axi_arcache),
        .s_axi_arprot  (ram_axi_arprot),
        .s_axi_arqos   (ram_axi_arqos),
        .s_axi_arvalid (ram_axi_arvalid),
        .s_axi_arready (ram_axi_arready),
        .s_axi_rid     (ram_axi_rid),
        .s_axi_rdata   (ram_axi_rdata),
        .s_axi_rresp   (ram_axi_rresp),
        .s_axi_rlast   (ram_axi_rlast),
        .s_axi_rvalid  (ram_axi_rvalid),
        .s_axi_rready  (ram_axi_rready)
    );

    axi_error_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_mmio_error (
        .clk           (clk),
        .reset         (reset),
        .s_axi_awid    (mmio_axi_awid),
        .s_axi_awaddr  (mmio_axi_awaddr),
        .s_axi_awlen   (mmio_axi_awlen),
        .s_axi_awsize  (mmio_axi_awsize),
        .s_axi_awburst (mmio_axi_awburst),
        .s_axi_awlock  (mmio_axi_awlock),
        .s_axi_awcache (mmio_axi_awcache),
        .s_axi_awprot  (mmio_axi_awprot),
        .s_axi_awqos   (mmio_axi_awqos),
        .s_axi_awvalid (mmio_axi_awvalid),
        .s_axi_awready (mmio_axi_awready),
        .s_axi_wdata   (mmio_axi_wdata),
        .s_axi_wstrb   (mmio_axi_wstrb),
        .s_axi_wlast   (mmio_axi_wlast),
        .s_axi_wvalid  (mmio_axi_wvalid),
        .s_axi_wready  (mmio_axi_wready),
        .s_axi_bid     (mmio_axi_bid),
        .s_axi_bresp   (mmio_axi_bresp),
        .s_axi_bvalid  (mmio_axi_bvalid),
        .s_axi_bready  (mmio_axi_bready),
        .s_axi_arid    (mmio_axi_arid),
        .s_axi_araddr  (mmio_axi_araddr),
        .s_axi_arlen   (mmio_axi_arlen),
        .s_axi_arsize  (mmio_axi_arsize),
        .s_axi_arburst (mmio_axi_arburst),
        .s_axi_arlock  (mmio_axi_arlock),
        .s_axi_arcache (mmio_axi_arcache),
        .s_axi_arprot  (mmio_axi_arprot),
        .s_axi_arqos   (mmio_axi_arqos),
        .s_axi_arvalid (mmio_axi_arvalid),
        .s_axi_arready (mmio_axi_arready),
        .s_axi_rid     (mmio_axi_rid),
        .s_axi_rdata   (mmio_axi_rdata),
        .s_axi_rresp   (mmio_axi_rresp),
        .s_axi_rlast   (mmio_axi_rlast),
        .s_axi_rvalid  (mmio_axi_rvalid),
        .s_axi_rready  (mmio_axi_rready)
    );

`ifndef SYNTHESIS
    task write_byte;
        input [31:0] address;
        input [7:0] data;
        begin
            u_ram.write_byte(address, data);
        end
    endtask

    task write_word;
        input [31:0] address;
        input [31:0] data;
        begin
            u_ram.write_word(address, data);
        end
    endtask

    task load_word_image;
        input [255*8:1] file_name;
        begin
            u_ram.load_word_image(file_name);
        end
    endtask

`endif

endmodule
