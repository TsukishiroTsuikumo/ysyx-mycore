`timescale 1ns/1ps
`include "axi_defs.vh"

module dcache_axi_adapter #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2,
    parameter integer LINE_BYTES = 16,
    parameter [ID_WIDTH-1:0] AXI_ID = {{(ID_WIDTH-1){1'b0}}, 1'b1}
)(
    input                               clk,
    input                               reset,

    // Cache-line read request/response interface.
    input                               line_rreq_valid,
    output                              line_rreq_ready,
    input      [ADDR_WIDTH-1:0]         line_rreq_addr,
    output reg                          line_rresp_valid,
    output     [LINE_BYTES*8-1:0]       line_rresp_data,
    output reg [1:0]                    line_rresp_resp,

    // Cache-line writeback request/response interface.
    input                               line_wreq_valid,
    output                              line_wreq_ready,
    input      [ADDR_WIDTH-1:0]         line_wreq_addr,
    input      [LINE_BYTES*8-1:0]       line_wreq_data,
    output reg                          line_wresp_valid,
    output reg [1:0]                    line_wresp_resp,

    // AXI4 write-address channel.
    output     [ID_WIDTH-1:0]           m_axi_awid,
    output     [ADDR_WIDTH-1:0]         m_axi_awaddr,
    output     [7:0]                    m_axi_awlen,
    output     [2:0]                    m_axi_awsize,
    output     [1:0]                    m_axi_awburst,
    output                              m_axi_awlock,
    output     [3:0]                    m_axi_awcache,
    output     [2:0]                    m_axi_awprot,
    output     [3:0]                    m_axi_awqos,
    output                              m_axi_awvalid,
    input                               m_axi_awready,

    // AXI4 write-data channel.
    output     [DATA_WIDTH-1:0]         m_axi_wdata,
    output     [DATA_WIDTH/8-1:0]       m_axi_wstrb,
    output                              m_axi_wlast,
    output                              m_axi_wvalid,
    input                               m_axi_wready,

    // AXI4 write-response channel.
    input      [ID_WIDTH-1:0]           m_axi_bid,
    input      [1:0]                    m_axi_bresp,
    input                               m_axi_bvalid,
    output                              m_axi_bready,

    // AXI4 read-address channel.
    output     [ID_WIDTH-1:0]           m_axi_arid,
    output     [ADDR_WIDTH-1:0]         m_axi_araddr,
    output     [7:0]                    m_axi_arlen,
    output     [2:0]                    m_axi_arsize,
    output     [1:0]                    m_axi_arburst,
    output                              m_axi_arlock,
    output     [3:0]                    m_axi_arcache,
    output     [2:0]                    m_axi_arprot,
    output     [3:0]                    m_axi_arqos,
    output                              m_axi_arvalid,
    input                               m_axi_arready,

    // AXI4 read-data channel.
    input      [ID_WIDTH-1:0]           m_axi_rid,
    input      [DATA_WIDTH-1:0]         m_axi_rdata,
    input      [1:0]                    m_axi_rresp,
    input                               m_axi_rlast,
    input                               m_axi_rvalid,
    output                              m_axi_rready
);

    localparam integer LINE_WIDTH = LINE_BYTES * 8;
    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam integer LINE_BEATS = LINE_BYTES / DATA_BYTES;
    localparam [2:0] AXI_SIZE = $clog2(DATA_BYTES);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_AW   = 3'd1;
    localparam [2:0] ST_W    = 3'd2;
    localparam [2:0] ST_B    = 3'd3;
    localparam [2:0] ST_AR   = 3'd4;
    localparam [2:0] ST_R    = 3'd5;

    reg [2:0] state_q;
    reg [ADDR_WIDTH-1:0] addr_q;
    reg [LINE_WIDTH-1:0] write_buf_q;
    reg [LINE_WIDTH-1:0] read_buf_q;
    reg [7:0] beat_q;
    reg [1:0] read_resp_q;

    function [1:0] merge_resp;
        input [1:0] accumulated;
        input [1:0] incoming;
        begin
            if ((accumulated == `AXI_RESP_DECERR) ||
                (incoming == `AXI_RESP_DECERR)) begin
                merge_resp = `AXI_RESP_DECERR;
            end
            else if ((accumulated == `AXI_RESP_SLVERR) ||
                     (incoming == `AXI_RESP_SLVERR)) begin
                merge_resp = `AXI_RESP_SLVERR;
            end
            else if ((accumulated != `AXI_RESP_OKAY) ||
                     (incoming != `AXI_RESP_OKAY)) begin
                merge_resp = `AXI_RESP_SLVERR;
            end
            else begin
                merge_resp = `AXI_RESP_OKAY;
            end
        end
    endfunction

    wire [1:0] rid_checked_resp =
        (m_axi_rid == AXI_ID) ? m_axi_rresp : `AXI_RESP_SLVERR;
    wire [1:0] merged_rresp = merge_resp(read_resp_q, rid_checked_resp);
    wire expected_read_last = (beat_q == LINE_BEATS - 1);

    assign line_wreq_ready = (state_q == ST_IDLE);
    assign line_rreq_ready = (state_q == ST_IDLE) && !line_wreq_valid;
    assign line_rresp_data = read_buf_q;

    assign m_axi_awid    = AXI_ID;
    assign m_axi_awaddr  = addr_q;
    assign m_axi_awlen   = LINE_BEATS - 1;
    assign m_axi_awsize  = AXI_SIZE;
    assign m_axi_awburst = `AXI_BURST_INCR;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awvalid = (state_q == ST_AW);

    assign m_axi_wdata  = write_buf_q[beat_q*DATA_WIDTH +: DATA_WIDTH];
    assign m_axi_wstrb  = {DATA_BYTES{1'b1}};
    assign m_axi_wlast  = (beat_q == LINE_BEATS - 1);
    assign m_axi_wvalid = (state_q == ST_W);
    assign m_axi_bready = (state_q == ST_B);

    assign m_axi_arid    = AXI_ID;
    assign m_axi_araddr  = addr_q;
    assign m_axi_arlen   = LINE_BEATS - 1;
    assign m_axi_arsize  = AXI_SIZE;
    assign m_axi_arburst = `AXI_BURST_INCR;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arvalid = (state_q == ST_AR);
    assign m_axi_rready  = (state_q == ST_R);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_q          <= ST_IDLE;
            addr_q           <= {ADDR_WIDTH{1'b0}};
            write_buf_q      <= {LINE_WIDTH{1'b0}};
            read_buf_q       <= {LINE_WIDTH{1'b0}};
            beat_q           <= 8'b0;
            read_resp_q      <= `AXI_RESP_OKAY;
            line_rresp_valid <= 1'b0;
            line_rresp_resp  <= `AXI_RESP_OKAY;
            line_wresp_valid <= 1'b0;
            line_wresp_resp  <= `AXI_RESP_OKAY;
        end
        else begin
            line_rresp_valid <= 1'b0;
            line_wresp_valid <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    // A writeback is selected if both line interfaces are
                    // asserted. A conforming D-cache does not issue both.
                    if (line_wreq_valid && line_wreq_ready) begin
                        addr_q      <= line_wreq_addr;
                        write_buf_q <= line_wreq_data;
                        beat_q      <= 8'b0;
                        state_q     <= ST_AW;
                    end
                    else if (line_rreq_valid && line_rreq_ready) begin
                        addr_q      <= line_rreq_addr;
                        read_buf_q  <= {LINE_WIDTH{1'b0}};
                        beat_q      <= 8'b0;
                        read_resp_q <= `AXI_RESP_OKAY;
                        state_q     <= ST_AR;
                    end
                end

                ST_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        beat_q  <= 8'b0;
                        state_q <= ST_W;
                    end
                end

                ST_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast) begin
                            beat_q  <= 8'b0;
                            state_q <= ST_B;
                        end
                        else begin
                            beat_q <= beat_q + 1'b1;
                        end
                    end
                end

                ST_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        line_wresp_valid <= 1'b1;
                        line_wresp_resp  <= (m_axi_bid == AXI_ID)
                                            ? merge_resp(`AXI_RESP_OKAY,
                                                         m_axi_bresp)
                                            : `AXI_RESP_SLVERR;
                        state_q <= ST_IDLE;
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        beat_q      <= 8'b0;
                        read_resp_q <= `AXI_RESP_OKAY;
                        state_q     <= ST_R;
                    end
                end

                ST_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (beat_q < LINE_BEATS) begin
                            read_buf_q[beat_q*DATA_WIDTH +: DATA_WIDTH]
                                <= m_axi_rdata;
                        end

                        if (m_axi_rlast) begin
                            line_rresp_valid <= 1'b1;
                            line_rresp_resp  <= expected_read_last
                                                ? merged_rresp
                                                : `AXI_RESP_SLVERR;
                            beat_q      <= 8'b0;
                            read_resp_q <= `AXI_RESP_OKAY;
                            state_q     <= ST_IDLE;
                        end
                        else begin
                            beat_q <= beat_q + 1'b1;
                            read_resp_q <= expected_read_last
                                           ? `AXI_RESP_SLVERR
                                           : merged_rresp;
                        end
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $error("dcache_axi_adapter: DATA_WIDTH must be byte aligned");
        end
        if ((LINE_BYTES % DATA_BYTES) != 0) begin
            $error("dcache_axi_adapter: line width must contain whole AXI beats");
        end
        if ((LINE_BEATS < 1) || (LINE_BEATS > 256)) begin
            $error("dcache_axi_adapter: AXI burst must contain 1..256 beats");
        end
    end

    always @(posedge clk) begin
        if (!reset && line_rreq_valid && line_wreq_valid &&
            (state_q == ST_IDLE)) begin
            $error("dcache_axi_adapter: simultaneous line read and writeback requests");
        end
        if (!reset && line_rreq_valid && line_rreq_ready &&
            ((line_rreq_addr % LINE_BYTES) != 0)) begin
            $error("dcache_axi_adapter: unaligned read line address 0x%08x",
                   line_rreq_addr);
        end
        if (!reset && line_wreq_valid && line_wreq_ready &&
            ((line_wreq_addr % LINE_BYTES) != 0)) begin
            $error("dcache_axi_adapter: unaligned write line address 0x%08x",
                   line_wreq_addr);
        end
        if (!reset && state_q == ST_R && m_axi_rvalid && m_axi_rready &&
            (m_axi_rid != AXI_ID)) begin
            $error("dcache_axi_adapter: read response ID mismatch expected=%0d got=%0d",
                   AXI_ID, m_axi_rid);
        end
        if (!reset && state_q == ST_B && m_axi_bvalid && m_axi_bready &&
            (m_axi_bid != AXI_ID)) begin
            $error("dcache_axi_adapter: write response ID mismatch expected=%0d got=%0d",
                   AXI_ID, m_axi_bid);
        end
    end
`endif

endmodule
