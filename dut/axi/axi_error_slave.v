`timescale 1ns/1ps
`include "axi_defs.vh"

// AXI4 error terminator. It drains complete requests and returns DECERR while
// honoring response backpressure. Read and write channels operate independently.
module axi_error_slave #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2
)(
    input                               clk,
    input                               reset,

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
    input                               s_axi_rready
);

    reg read_active_q;
    reg [ID_WIDTH-1:0] read_id_q;
    reg [7:0] read_len_q;
    reg [7:0] read_beat_q;

    reg write_active_q;
    reg write_resp_q;
    reg [ID_WIDTH-1:0] write_id_q;
    reg [7:0] write_len_q;
    reg [8:0] write_beat_q;

    assign s_axi_arready = !read_active_q;
    assign s_axi_rid     = read_id_q;
    assign s_axi_rdata   = {DATA_WIDTH{1'b0}};
    assign s_axi_rresp   = `AXI_RESP_DECERR;
    assign s_axi_rlast   = read_active_q && (read_beat_q == read_len_q);
    assign s_axi_rvalid  = read_active_q;

    assign s_axi_awready = !write_active_q && !write_resp_q;
    assign s_axi_wready  = write_active_q;
    assign s_axi_bid     = write_id_q;
    assign s_axi_bresp   = `AXI_RESP_DECERR;
    assign s_axi_bvalid  = write_resp_q;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_active_q <= 1'b0;
            read_id_q     <= {ID_WIDTH{1'b0}};
            read_len_q    <= 8'b0;
            read_beat_q   <= 8'b0;
        end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_active_q <= 1'b1;
                read_id_q     <= s_axi_arid;
                read_len_q    <= s_axi_arlen;
                read_beat_q   <= 8'b0;
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    read_active_q <= 1'b0;
                    read_beat_q   <= 8'b0;
                end
                else begin
                    read_beat_q <= read_beat_q + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_active_q <= 1'b0;
            write_resp_q   <= 1'b0;
            write_id_q     <= {ID_WIDTH{1'b0}};
            write_len_q    <= 8'b0;
            write_beat_q   <= 9'b0;
        end
        else begin
            if (s_axi_bvalid && s_axi_bready) begin
                write_resp_q <= 1'b0;
            end

            if (s_axi_awvalid && s_axi_awready) begin
                write_active_q <= 1'b1;
                write_id_q     <= s_axi_awid;
                write_len_q    <= s_axi_awlen;
                write_beat_q   <= 9'b0;
            end
            else if (s_axi_wvalid && s_axi_wready) begin
                if (s_axi_wlast) begin
                    write_active_q <= 1'b0;
                    write_resp_q   <= 1'b1;
                    write_beat_q   <= 9'b0;
                end
                else if (write_beat_q < 9'd256) begin
                    write_beat_q <= write_beat_q + 1'b1;
                end
            end
        end
    end

    // The address/control/data inputs are intentionally consumed but ignored.
    wire unused_inputs = ^{s_axi_awaddr, s_axi_awsize, s_axi_awburst,
                           s_axi_awlock, s_axi_awcache, s_axi_awprot,
                           s_axi_awqos, s_axi_wdata, s_axi_wstrb,
                           s_axi_araddr, s_axi_arsize, s_axi_arburst,
                           s_axi_arlock, s_axi_arcache, s_axi_arprot,
                           s_axi_arqos};

endmodule
