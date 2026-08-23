`timescale 1ns/1ps
`include "axi_defs.vh"

module icache_axi_adapter #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2,
    parameter integer LINE_BYTES = 16,
    parameter [ID_WIDTH-1:0] AXI_ID = {ID_WIDTH{1'b0}}
)(
    input                               clk,
    input                               reset,

    // Cache-line request interface. One request may be outstanding.
    input                               line_req_valid,
    output                              line_req_ready,
    input      [ADDR_WIDTH-1:0]         line_req_addr,

    output reg                          line_resp_valid,
    output     [LINE_BYTES*8-1:0]       line_resp_data,
    output reg [1:0]                    line_resp_resp,

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

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_AR   = 2'd1;
    localparam [1:0] ST_R    = 2'd2;

    reg [1:0] state_q;
    reg [ADDR_WIDTH-1:0] addr_q;
    reg [LINE_WIDTH-1:0] line_buf_q;
    reg [7:0] beat_q;
    reg [1:0] resp_q;

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
                // EXOKAY is not expected because this adapter never issues
                // exclusive accesses. Treat it as a protocol/slave error.
                merge_resp = `AXI_RESP_SLVERR;
            end
            else begin
                merge_resp = `AXI_RESP_OKAY;
            end
        end
    endfunction

    wire [1:0] rid_checked_resp =
        (m_axi_rid == AXI_ID) ? m_axi_rresp : `AXI_RESP_SLVERR;
    wire [1:0] merged_rresp = merge_resp(resp_q, rid_checked_resp);
    wire expected_last = (beat_q == LINE_BEATS - 1);

    assign line_req_ready = (state_q == ST_IDLE);
    assign line_resp_data = line_buf_q;

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
            state_q         <= ST_IDLE;
            addr_q          <= {ADDR_WIDTH{1'b0}};
            line_buf_q      <= {LINE_WIDTH{1'b0}};
            beat_q          <= 8'b0;
            resp_q          <= `AXI_RESP_OKAY;
            line_resp_valid <= 1'b0;
            line_resp_resp  <= `AXI_RESP_OKAY;
        end
        else begin
            line_resp_valid <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    if (line_req_valid && line_req_ready) begin
                        addr_q     <= line_req_addr;
                        line_buf_q <= {LINE_WIDTH{1'b0}};
                        beat_q     <= 8'b0;
                        resp_q     <= `AXI_RESP_OKAY;
                        state_q    <= ST_AR;
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        beat_q  <= 8'b0;
                        resp_q  <= `AXI_RESP_OKAY;
                        state_q <= ST_R;
                    end
                end

                ST_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (beat_q < LINE_BEATS) begin
                            line_buf_q[beat_q*DATA_WIDTH +: DATA_WIDTH]
                                <= m_axi_rdata;
                        end

                        if (m_axi_rlast) begin
                            line_resp_valid <= 1'b1;
                            line_resp_resp  <= expected_last
                                               ? merged_rresp
                                               : `AXI_RESP_SLVERR;
                            state_q <= ST_IDLE;
                            beat_q  <= 8'b0;
                            resp_q  <= `AXI_RESP_OKAY;
                        end
                        else begin
                            beat_q <= beat_q + 1'b1;
                            resp_q <= expected_last
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
            $error("icache_axi_adapter: DATA_WIDTH must be byte aligned");
        end
        if ((LINE_BYTES % DATA_BYTES) != 0) begin
            $error("icache_axi_adapter: line width must contain whole AXI beats");
        end
        if ((LINE_BEATS < 1) || (LINE_BEATS > 256)) begin
            $error("icache_axi_adapter: AXI burst must contain 1..256 beats");
        end
    end

    always @(posedge clk) begin
        if (!reset && line_req_valid && line_req_ready &&
            ((line_req_addr % LINE_BYTES) != 0)) begin
            $error("icache_axi_adapter: unaligned cache-line request 0x%08x",
                   line_req_addr);
        end
        if (!reset && state_q == ST_R && m_axi_rvalid && m_axi_rready &&
            (m_axi_rid != AXI_ID)) begin
            $error("icache_axi_adapter: response ID mismatch expected=%0d got=%0d",
                   AXI_ID, m_axi_rid);
        end
    end
`endif

endmodule
