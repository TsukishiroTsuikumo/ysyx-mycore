`timescale 1ns/1ps
`include "axi_defs.vh"

// One-master/two-slave AXI4 address decoder with an internal DECERR target.
// Read and write channels are independently locked to the selected slave for
// the lifetime of each burst. Only aligned INCR address decoding is required by
// the cache adapters; unsupported or cross-region requests use the error path.
module axi_addr_decoder #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2,
    parameter [ADDR_WIDTH-1:0] RAM_BASE   = 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] RAM_MASK   = 32'hff00_0000,
    parameter [ADDR_WIDTH-1:0] MMIO_BASE  = 32'h1000_0000,
    parameter [ADDR_WIDTH-1:0] MMIO_MASK  = 32'hffff_0000
)(
    input                               clk,
    input                               reset,

    // Upstream AXI4 slave-facing port.
    input      [ID_WIDTH-1:0]           s_axi_awid,
    input      [ADDR_WIDTH-1:0]         s_axi_awaddr,
    input      [7:0]                    s_axi_awlen,
    input      [2:0]                    s_axi_awsize,
    input      [1:0]                    s_axi_awburst,
    input                               s_axi_awlock,
    input      [3:0]                    s_axi_awcache,
    input      [2:0]                    s_axi_awprot,
    input      [3:0]                    s_axi_awqos,
    input                               s_axi_awvalid,
    output                              s_axi_awready,

    input      [DATA_WIDTH-1:0]         s_axi_wdata,
    input      [DATA_WIDTH/8-1:0]       s_axi_wstrb,
    input                               s_axi_wlast,
    input                               s_axi_wvalid,
    output                              s_axi_wready,

    output     [ID_WIDTH-1:0]           s_axi_bid,
    output     [1:0]                    s_axi_bresp,
    output                              s_axi_bvalid,
    input                               s_axi_bready,

    input      [ID_WIDTH-1:0]           s_axi_arid,
    input      [ADDR_WIDTH-1:0]         s_axi_araddr,
    input      [7:0]                    s_axi_arlen,
    input      [2:0]                    s_axi_arsize,
    input      [1:0]                    s_axi_arburst,
    input                               s_axi_arlock,
    input      [3:0]                    s_axi_arcache,
    input      [2:0]                    s_axi_arprot,
    input      [3:0]                    s_axi_arqos,
    input                               s_axi_arvalid,
    output                              s_axi_arready,

    output     [ID_WIDTH-1:0]           s_axi_rid,
    output     [DATA_WIDTH-1:0]         s_axi_rdata,
    output     [1:0]                    s_axi_rresp,
    output                              s_axi_rlast,
    output                              s_axi_rvalid,
    input                               s_axi_rready,

    // RAM downstream AXI4 master-facing port.
    output     [ID_WIDTH-1:0]           ram_axi_awid,
    output     [ADDR_WIDTH-1:0]         ram_axi_awaddr,
    output     [7:0]                    ram_axi_awlen,
    output     [2:0]                    ram_axi_awsize,
    output     [1:0]                    ram_axi_awburst,
    output                              ram_axi_awlock,
    output     [3:0]                    ram_axi_awcache,
    output     [2:0]                    ram_axi_awprot,
    output     [3:0]                    ram_axi_awqos,
    output                              ram_axi_awvalid,
    input                               ram_axi_awready,

    output     [DATA_WIDTH-1:0]         ram_axi_wdata,
    output     [DATA_WIDTH/8-1:0]       ram_axi_wstrb,
    output                              ram_axi_wlast,
    output                              ram_axi_wvalid,
    input                               ram_axi_wready,

    input      [ID_WIDTH-1:0]           ram_axi_bid,
    input      [1:0]                    ram_axi_bresp,
    input                               ram_axi_bvalid,
    output                              ram_axi_bready,

    output     [ID_WIDTH-1:0]           ram_axi_arid,
    output     [ADDR_WIDTH-1:0]         ram_axi_araddr,
    output     [7:0]                    ram_axi_arlen,
    output     [2:0]                    ram_axi_arsize,
    output     [1:0]                    ram_axi_arburst,
    output                              ram_axi_arlock,
    output     [3:0]                    ram_axi_arcache,
    output     [2:0]                    ram_axi_arprot,
    output     [3:0]                    ram_axi_arqos,
    output                              ram_axi_arvalid,
    input                               ram_axi_arready,

    input      [ID_WIDTH-1:0]           ram_axi_rid,
    input      [DATA_WIDTH-1:0]         ram_axi_rdata,
    input      [1:0]                    ram_axi_rresp,
    input                               ram_axi_rlast,
    input                               ram_axi_rvalid,
    output                              ram_axi_rready,

    // Reserved MMIO downstream AXI4 master-facing port.
    output     [ID_WIDTH-1:0]           mmio_axi_awid,
    output     [ADDR_WIDTH-1:0]         mmio_axi_awaddr,
    output     [7:0]                    mmio_axi_awlen,
    output     [2:0]                    mmio_axi_awsize,
    output     [1:0]                    mmio_axi_awburst,
    output                              mmio_axi_awlock,
    output     [3:0]                    mmio_axi_awcache,
    output     [2:0]                    mmio_axi_awprot,
    output     [3:0]                    mmio_axi_awqos,
    output                              mmio_axi_awvalid,
    input                               mmio_axi_awready,

    output     [DATA_WIDTH-1:0]         mmio_axi_wdata,
    output     [DATA_WIDTH/8-1:0]       mmio_axi_wstrb,
    output                              mmio_axi_wlast,
    output                              mmio_axi_wvalid,
    input                               mmio_axi_wready,

    input      [ID_WIDTH-1:0]           mmio_axi_bid,
    input      [1:0]                    mmio_axi_bresp,
    input                               mmio_axi_bvalid,
    output                              mmio_axi_bready,

    output     [ID_WIDTH-1:0]           mmio_axi_arid,
    output     [ADDR_WIDTH-1:0]         mmio_axi_araddr,
    output     [7:0]                    mmio_axi_arlen,
    output     [2:0]                    mmio_axi_arsize,
    output     [1:0]                    mmio_axi_arburst,
    output                              mmio_axi_arlock,
    output     [3:0]                    mmio_axi_arcache,
    output     [2:0]                    mmio_axi_arprot,
    output     [3:0]                    mmio_axi_arqos,
    output                              mmio_axi_arvalid,
    input                               mmio_axi_arready,

    input      [ID_WIDTH-1:0]           mmio_axi_rid,
    input      [DATA_WIDTH-1:0]         mmio_axi_rdata,
    input      [1:0]                    mmio_axi_rresp,
    input                               mmio_axi_rlast,
    input                               mmio_axi_rvalid,
    output                              mmio_axi_rready
);

    localparam [1:0] TARGET_RAM  = 2'd0;
    localparam [1:0] TARGET_MMIO = 2'd1;
    localparam [1:0] TARGET_ERR  = 2'd2;

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE = $clog2(DATA_BYTES);

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_RESP = 2'd1;
    localparam [1:0] RD_ERR  = 2'd2;

    localparam [2:0] WR_IDLE     = 3'd0;
    localparam [2:0] WR_DATA     = 3'd1;
    localparam [2:0] WR_RESP     = 3'd2;
    localparam [2:0] WR_ERR_DATA = 3'd3;
    localparam [2:0] WR_ERR_RESP = 3'd4;

    wire [63:0] ar_byte_count = ({56'b0, s_axi_arlen} + 64'd1)
                                  << s_axi_arsize;
    wire [63:0] ar_last_address = {32'b0, s_axi_araddr} +
                                  ar_byte_count - 64'd1;
    wire ar_decode_valid = (s_axi_arsize == AXI_SIZE) &&
                           (s_axi_arburst == `AXI_BURST_INCR) &&
                           !s_axi_arlock &&
                           ((s_axi_araddr & (DATA_BYTES - 1)) == 0) &&
                           (ar_last_address[63:ADDR_WIDTH] == 0) &&
                           (({52'b0, s_axi_araddr[11:0]} +
                             ar_byte_count) <= 64'd4096);
    wire ar_in_ram = ar_decode_valid &&
                     ((s_axi_araddr & RAM_MASK) == (RAM_BASE & RAM_MASK)) &&
                     ((ar_last_address[ADDR_WIDTH-1:0] & RAM_MASK) ==
                      (RAM_BASE & RAM_MASK));
    wire ar_in_mmio = ar_decode_valid &&
                      ((s_axi_araddr & MMIO_MASK) ==
                       (MMIO_BASE & MMIO_MASK)) &&
                      ((ar_last_address[ADDR_WIDTH-1:0] & MMIO_MASK) ==
                       (MMIO_BASE & MMIO_MASK));
    wire [1:0] ar_target_now = ar_in_ram  ? TARGET_RAM  :
                               ar_in_mmio ? TARGET_MMIO : TARGET_ERR;

    wire [63:0] aw_byte_count = ({56'b0, s_axi_awlen} + 64'd1)
                                  << s_axi_awsize;
    wire [63:0] aw_last_address = {32'b0, s_axi_awaddr} +
                                  aw_byte_count - 64'd1;
    wire aw_decode_valid = (s_axi_awsize == AXI_SIZE) &&
                           (s_axi_awburst == `AXI_BURST_INCR) &&
                           !s_axi_awlock &&
                           ((s_axi_awaddr & (DATA_BYTES - 1)) == 0) &&
                           (aw_last_address[63:ADDR_WIDTH] == 0) &&
                           (({52'b0, s_axi_awaddr[11:0]} +
                             aw_byte_count) <= 64'd4096);
    wire aw_in_ram = aw_decode_valid &&
                     ((s_axi_awaddr & RAM_MASK) == (RAM_BASE & RAM_MASK)) &&
                     ((aw_last_address[ADDR_WIDTH-1:0] & RAM_MASK) ==
                      (RAM_BASE & RAM_MASK));
    wire aw_in_mmio = aw_decode_valid &&
                      ((s_axi_awaddr & MMIO_MASK) ==
                       (MMIO_BASE & MMIO_MASK)) &&
                      ((aw_last_address[ADDR_WIDTH-1:0] & MMIO_MASK) ==
                       (MMIO_BASE & MMIO_MASK));
    wire [1:0] aw_target_now = aw_in_ram  ? TARGET_RAM  :
                               aw_in_mmio ? TARGET_MMIO : TARGET_ERR;

    reg [1:0] read_state_q;
    reg [1:0] read_target_q;
    reg [ID_WIDTH-1:0] error_read_id_q;
    reg [7:0] error_read_len_q;
    reg [7:0] error_read_beat_q;

    reg [2:0] write_state_q;
    reg [1:0] write_target_q;
    reg [ID_WIDTH-1:0] error_write_id_q;
    reg [7:0] error_write_len_q;
    // One extra bit prevents a malformed 256-beat burst without WLAST from
    // wrapping beat 255 back to zero while the request is being drained.
    reg [8:0] error_write_beat_q;

    // Address payloads are passed through unchanged. Valid/ready gating below
    // ensures that only the selected target observes a handshake.
    assign ram_axi_arid    = s_axi_arid;
    assign ram_axi_araddr  = s_axi_araddr;
    assign ram_axi_arlen   = s_axi_arlen;
    assign ram_axi_arsize  = s_axi_arsize;
    assign ram_axi_arburst = s_axi_arburst;
    assign ram_axi_arlock  = s_axi_arlock;
    assign ram_axi_arcache = s_axi_arcache;
    assign ram_axi_arprot  = s_axi_arprot;
    assign ram_axi_arqos   = s_axi_arqos;
    assign ram_axi_arvalid = (read_state_q == RD_IDLE) &&
                             (ar_target_now == TARGET_RAM) && s_axi_arvalid;

    assign mmio_axi_arid    = s_axi_arid;
    assign mmio_axi_araddr  = s_axi_araddr;
    assign mmio_axi_arlen   = s_axi_arlen;
    assign mmio_axi_arsize  = s_axi_arsize;
    assign mmio_axi_arburst = s_axi_arburst;
    assign mmio_axi_arlock  = s_axi_arlock;
    assign mmio_axi_arcache = s_axi_arcache;
    assign mmio_axi_arprot  = s_axi_arprot;
    assign mmio_axi_arqos   = s_axi_arqos;
    assign mmio_axi_arvalid = (read_state_q == RD_IDLE) &&
                              (ar_target_now == TARGET_MMIO) && s_axi_arvalid;

    assign s_axi_arready = (read_state_q == RD_IDLE) &&
                           ((ar_target_now == TARGET_RAM)  ? ram_axi_arready  :
                            (ar_target_now == TARGET_MMIO) ? mmio_axi_arready :
                                                            1'b1);

    wire selected_ram_read = (read_state_q == RD_RESP) &&
                             (read_target_q == TARGET_RAM);
    wire selected_mmio_read = (read_state_q == RD_RESP) &&
                              (read_target_q == TARGET_MMIO);
    wire selected_error_read = (read_state_q == RD_ERR);

    assign s_axi_rid = selected_ram_read  ? ram_axi_rid  :
                       selected_mmio_read ? mmio_axi_rid : error_read_id_q;
    assign s_axi_rdata = selected_ram_read  ? ram_axi_rdata  :
                         selected_mmio_read ? mmio_axi_rdata :
                                              {DATA_WIDTH{1'b0}};
    assign s_axi_rresp = selected_ram_read  ? ram_axi_rresp  :
                         selected_mmio_read ? mmio_axi_rresp :
                                              `AXI_RESP_DECERR;
    assign s_axi_rlast = selected_ram_read  ? ram_axi_rlast  :
                         selected_mmio_read ? mmio_axi_rlast :
                         (selected_error_read &&
                          (error_read_beat_q == error_read_len_q));
    assign s_axi_rvalid = selected_ram_read  ? ram_axi_rvalid  :
                          selected_mmio_read ? mmio_axi_rvalid :
                                               selected_error_read;
    assign ram_axi_rready = selected_ram_read && s_axi_rready;
    assign mmio_axi_rready = selected_mmio_read && s_axi_rready;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_state_q      <= RD_IDLE;
            read_target_q     <= TARGET_ERR;
            error_read_id_q   <= {ID_WIDTH{1'b0}};
            error_read_len_q  <= 8'b0;
            error_read_beat_q <= 8'b0;
        end
        else begin
            case (read_state_q)
                RD_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        if (ar_target_now == TARGET_ERR) begin
                            error_read_id_q   <= s_axi_arid;
                            error_read_len_q  <= s_axi_arlen;
                            error_read_beat_q <= 8'b0;
                            read_state_q      <= RD_ERR;
                        end
                        else begin
                            read_target_q <= ar_target_now;
                            read_state_q  <= RD_RESP;
                        end
                    end
                end

                RD_RESP: begin
                    if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
                        read_state_q <= RD_IDLE;
                    end
                end

                RD_ERR: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            error_read_beat_q <= 8'b0;
                            read_state_q      <= RD_IDLE;
                        end
                        else begin
                            error_read_beat_q <= error_read_beat_q + 1'b1;
                        end
                    end
                end

                default: read_state_q <= RD_IDLE;
            endcase
        end
    end

    assign ram_axi_awid    = s_axi_awid;
    assign ram_axi_awaddr  = s_axi_awaddr;
    assign ram_axi_awlen   = s_axi_awlen;
    assign ram_axi_awsize  = s_axi_awsize;
    assign ram_axi_awburst = s_axi_awburst;
    assign ram_axi_awlock  = s_axi_awlock;
    assign ram_axi_awcache = s_axi_awcache;
    assign ram_axi_awprot  = s_axi_awprot;
    assign ram_axi_awqos   = s_axi_awqos;
    assign ram_axi_awvalid = (write_state_q == WR_IDLE) &&
                             (aw_target_now == TARGET_RAM) && s_axi_awvalid;

    assign mmio_axi_awid    = s_axi_awid;
    assign mmio_axi_awaddr  = s_axi_awaddr;
    assign mmio_axi_awlen   = s_axi_awlen;
    assign mmio_axi_awsize  = s_axi_awsize;
    assign mmio_axi_awburst = s_axi_awburst;
    assign mmio_axi_awlock  = s_axi_awlock;
    assign mmio_axi_awcache = s_axi_awcache;
    assign mmio_axi_awprot  = s_axi_awprot;
    assign mmio_axi_awqos   = s_axi_awqos;
    assign mmio_axi_awvalid = (write_state_q == WR_IDLE) &&
                              (aw_target_now == TARGET_MMIO) && s_axi_awvalid;

    assign s_axi_awready = (write_state_q == WR_IDLE) &&
                           ((aw_target_now == TARGET_RAM)  ? ram_axi_awready  :
                            (aw_target_now == TARGET_MMIO) ? mmio_axi_awready :
                                                            1'b1);

    assign ram_axi_wdata  = s_axi_wdata;
    assign ram_axi_wstrb  = s_axi_wstrb;
    assign ram_axi_wlast  = s_axi_wlast;
    assign ram_axi_wvalid = (write_state_q == WR_DATA) &&
                            (write_target_q == TARGET_RAM) && s_axi_wvalid;
    assign mmio_axi_wdata  = s_axi_wdata;
    assign mmio_axi_wstrb  = s_axi_wstrb;
    assign mmio_axi_wlast  = s_axi_wlast;
    assign mmio_axi_wvalid = (write_state_q == WR_DATA) &&
                             (write_target_q == TARGET_MMIO) && s_axi_wvalid;

    assign s_axi_wready = (write_state_q == WR_ERR_DATA) ? 1'b1 :
                          ((write_state_q == WR_DATA) &&
                           ((write_target_q == TARGET_RAM)
                              ? ram_axi_wready : mmio_axi_wready));

    assign s_axi_bid = (write_state_q == WR_ERR_RESP)
                       ? error_write_id_q
                       : ((write_target_q == TARGET_RAM)
                            ? ram_axi_bid : mmio_axi_bid);
    assign s_axi_bresp = (write_state_q == WR_ERR_RESP)
                         ? `AXI_RESP_DECERR
                         : ((write_target_q == TARGET_RAM)
                              ? ram_axi_bresp : mmio_axi_bresp);
    assign s_axi_bvalid = (write_state_q == WR_ERR_RESP) ? 1'b1 :
                          ((write_state_q == WR_RESP) &&
                           ((write_target_q == TARGET_RAM)
                              ? ram_axi_bvalid : mmio_axi_bvalid));
    assign ram_axi_bready = (write_state_q == WR_RESP) &&
                            (write_target_q == TARGET_RAM) && s_axi_bready;
    assign mmio_axi_bready = (write_state_q == WR_RESP) &&
                             (write_target_q == TARGET_MMIO) && s_axi_bready;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_state_q       <= WR_IDLE;
            write_target_q      <= TARGET_ERR;
            error_write_id_q    <= {ID_WIDTH{1'b0}};
            error_write_len_q   <= 8'b0;
            error_write_beat_q  <= 9'b0;
        end
        else begin
            case (write_state_q)
                WR_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        if (aw_target_now == TARGET_ERR) begin
                            error_write_id_q   <= s_axi_awid;
                            error_write_len_q  <= s_axi_awlen;
                            error_write_beat_q <= 9'b0;
                            write_state_q      <= WR_ERR_DATA;
                        end
                        else begin
                            write_target_q <= aw_target_now;
                            write_state_q  <= WR_DATA;
                        end
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                        write_state_q <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        write_state_q <= WR_IDLE;
                    end
                end

                WR_ERR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (s_axi_wlast) begin
                            error_write_beat_q <= 9'b0;
                            write_state_q      <= WR_ERR_RESP;
                        end
                        else begin
                            if (error_write_beat_q < 9'd256) begin
                                error_write_beat_q <= error_write_beat_q + 1'b1;
                            end
                        end
                    end
                end

                WR_ERR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        write_state_q <= WR_IDLE;
                    end
                end

                default: write_state_q <= WR_IDLE;
            endcase
        end
    end

endmodule
