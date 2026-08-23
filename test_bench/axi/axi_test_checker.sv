`timescale 1ns/1ps
`include "axi_defs.vh"

// Passive checker for the four-beat, 32-bit AXI4 cache-line traffic used by
// this test.  It intentionally has no outputs: counters are public so the
// top-level test can prove that each requested backpressure case occurred.
module axi_test_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 2,
    parameter bit CHECK_READ = 1'b1,
    parameter bit CHECK_WRITE = 1'b1,
    parameter bit CHECK_FIXED_ID = 1'b0,
    parameter logic [ID_WIDTH-1:0] EXPECTED_ID = '0
)(
    input logic                         clk,
    input logic                         reset,

    input logic [ID_WIDTH-1:0]          awid,
    input logic [ADDR_WIDTH-1:0]        awaddr,
    input logic [7:0]                   awlen,
    input logic [2:0]                   awsize,
    input logic [1:0]                   awburst,
    input logic                         awlock,
    input logic [3:0]                   awcache,
    input logic [2:0]                   awprot,
    input logic [3:0]                   awqos,
    input logic                         awvalid,
    input logic                         awready,

    input logic [DATA_WIDTH-1:0]        wdata,
    input logic [DATA_WIDTH/8-1:0]      wstrb,
    input logic                         wlast,
    input logic                         wvalid,
    input logic                         wready,

    input logic [ID_WIDTH-1:0]          bid,
    input logic [1:0]                   bresp,
    input logic                         bvalid,
    input logic                         bready,

    input logic [ID_WIDTH-1:0]          arid,
    input logic [ADDR_WIDTH-1:0]        araddr,
    input logic [7:0]                   arlen,
    input logic [2:0]                   arsize,
    input logic [1:0]                   arburst,
    input logic                         arlock,
    input logic [3:0]                   arcache,
    input logic [2:0]                   arprot,
    input logic [3:0]                   arqos,
    input logic                         arvalid,
    input logic                         arready,

    input logic [ID_WIDTH-1:0]          rid,
    input logic [DATA_WIDTH-1:0]        rdata,
    input logic [1:0]                   rresp,
    input logic                         rlast,
    input logic                         rvalid,
    input logic                         rready
);

    localparam logic [2:0] EXPECTED_SIZE = $clog2(DATA_WIDTH / 8);

    integer aw_stall_count;
    integer w_stall_count;
    integer b_stall_count;
    integer ar_stall_count;
    integer r_stall_count;
    integer read_burst_count;
    integer write_burst_count;

    logic aw_stalled_q;
    logic w_stalled_q;
    logic b_stalled_q;
    logic ar_stalled_q;
    logic r_stalled_q;

    logic [ID_WIDTH+ADDR_WIDTH+24:0] aw_payload_q;
    logic [DATA_WIDTH+DATA_WIDTH/8:0] w_payload_q;
    logic [ID_WIDTH+1:0] b_payload_q;
    logic [ID_WIDTH+ADDR_WIDTH+24:0] ar_payload_q;
    logic [ID_WIDTH+DATA_WIDTH+2:0] r_payload_q;

    wire [ID_WIDTH+ADDR_WIDTH+24:0] aw_payload =
        {awid, awaddr, awlen, awsize, awburst, awlock,
         awcache, awprot, awqos};
    wire [DATA_WIDTH+DATA_WIDTH/8:0] w_payload =
        {wdata, wstrb, wlast};
    wire [ID_WIDTH+1:0] b_payload = {bid, bresp};
    wire [ID_WIDTH+ADDR_WIDTH+24:0] ar_payload =
        {arid, araddr, arlen, arsize, arburst, arlock,
         arcache, arprot, arqos};
    wire [ID_WIDTH+DATA_WIDTH+2:0] r_payload =
        {rid, rdata, rresp, rlast};

    logic read_outstanding_q;
    logic [ID_WIDTH-1:0] read_id_q;
    logic [2:0] read_beat_q;
    logic write_outstanding_q;
    logic write_data_done_q;
    logic [ID_WIDTH-1:0] write_id_q;
    logic [2:0] write_beat_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            aw_stall_count     <= 0;
            w_stall_count      <= 0;
            b_stall_count      <= 0;
            ar_stall_count     <= 0;
            r_stall_count      <= 0;
            read_burst_count   <= 0;
            write_burst_count  <= 0;
            aw_stalled_q       <= 1'b0;
            w_stalled_q        <= 1'b0;
            b_stalled_q        <= 1'b0;
            ar_stalled_q       <= 1'b0;
            r_stalled_q        <= 1'b0;
            aw_payload_q       <= '0;
            w_payload_q        <= '0;
            b_payload_q        <= '0;
            ar_payload_q       <= '0;
            r_payload_q        <= '0;
            read_outstanding_q <= 1'b0;
            read_id_q          <= '0;
            read_beat_q        <= '0;
            write_outstanding_q <= 1'b0;
            write_data_done_q  <= 1'b0;
            write_id_q         <= '0;
            write_beat_q       <= '0;
        end
        else begin
            if (CHECK_WRITE) begin
                if (aw_stalled_q &&
                    (!awvalid || (aw_payload !== aw_payload_q))) begin
                    $fatal(1, "AXI AWVALID/payload changed while stalled");
                end
                if (w_stalled_q &&
                    (!wvalid || (w_payload !== w_payload_q))) begin
                    $fatal(1, "AXI WVALID/payload changed while stalled");
                end
                if (b_stalled_q &&
                    (!bvalid || (b_payload !== b_payload_q))) begin
                    $fatal(1, "AXI BVALID/payload changed while stalled");
                end

                aw_stalled_q <= awvalid && !awready;
                w_stalled_q  <= wvalid && !wready;
                b_stalled_q  <= bvalid && !bready;
                if (awvalid && !awready) begin
                    aw_payload_q   <= aw_payload;
                    aw_stall_count <= aw_stall_count + 1;
                end
                if (wvalid && !wready) begin
                    w_payload_q   <= w_payload;
                    w_stall_count <= w_stall_count + 1;
                end
                if (bvalid && !bready) begin
                    b_payload_q   <= b_payload;
                    b_stall_count <= b_stall_count + 1;
                end

                if (awvalid && awready) begin
                    if (write_outstanding_q) begin
                        $fatal(1, "AXI checker saw overlapping write bursts");
                    end
                    if ((awlen != 8'd3) || (awsize != EXPECTED_SIZE) ||
                        (awburst != `AXI_BURST_INCR) || awlock ||
                        ((awaddr & ((DATA_WIDTH/8)-1)) != 0) ||
                        ((awaddr & 32'h0000_000f) != 0)) begin
                        $fatal(1, "AXI checker saw illegal cache-line AW");
                    end
                    if (CHECK_FIXED_ID && (awid != EXPECTED_ID)) begin
                        $fatal(1, "AXI AWID mismatch: expected %0d got %0d",
                               EXPECTED_ID, awid);
                    end
                    write_outstanding_q <= 1'b1;
                    write_data_done_q   <= 1'b0;
                    write_id_q          <= awid;
                    write_beat_q        <= 3'd0;
                end

                if (wvalid && wready) begin
                    if (!write_outstanding_q) begin
                        $fatal(1, "AXI W beat arrived without accepted AW");
                    end
                    if (wstrb != {DATA_WIDTH/8{1'b1}}) begin
                        $fatal(1, "AXI cache-line write used partial WSTRB");
                    end
                    if (wlast !== (write_beat_q == 3'd3)) begin
                        $fatal(1, "AXI WLAST mismatch at beat %0d",
                               write_beat_q);
                    end
                    if (wlast) begin
                        write_data_done_q <= 1'b1;
                    end
                    else begin
                        write_beat_q <= write_beat_q + 1'b1;
                    end
                end

                if (bvalid && bready) begin
                    if (!write_outstanding_q || !write_data_done_q) begin
                        $fatal(1, "AXI B response arrived before write data");
                    end
                    if ((bid != write_id_q) || (bresp != `AXI_RESP_OKAY)) begin
                        $fatal(1, "AXI write response mismatch id=%0d resp=%0d",
                               bid, bresp);
                    end
                    write_outstanding_q <= 1'b0;
                    write_data_done_q   <= 1'b0;
                    write_burst_count   <= write_burst_count + 1;
                end
            end

            if (CHECK_READ) begin
                if (ar_stalled_q &&
                    (!arvalid || (ar_payload !== ar_payload_q))) begin
                    $fatal(1, "AXI ARVALID/payload changed while stalled");
                end
                if (r_stalled_q &&
                    (!rvalid || (r_payload !== r_payload_q))) begin
                    $fatal(1, "AXI RVALID/payload changed while stalled");
                end

                ar_stalled_q <= arvalid && !arready;
                r_stalled_q  <= rvalid && !rready;
                if (arvalid && !arready) begin
                    ar_payload_q   <= ar_payload;
                    ar_stall_count <= ar_stall_count + 1;
                end
                if (rvalid && !rready) begin
                    r_payload_q   <= r_payload;
                    r_stall_count <= r_stall_count + 1;
                end

                if (arvalid && arready) begin
                    if (read_outstanding_q) begin
                        $fatal(1, "AXI checker saw overlapping read bursts");
                    end
                    if ((arlen != 8'd3) || (arsize != EXPECTED_SIZE) ||
                        (arburst != `AXI_BURST_INCR) || arlock ||
                        ((araddr & ((DATA_WIDTH/8)-1)) != 0) ||
                        ((araddr & 32'h0000_000f) != 0)) begin
                        $fatal(1, "AXI checker saw illegal cache-line AR");
                    end
                    if (CHECK_FIXED_ID && (arid != EXPECTED_ID)) begin
                        $fatal(1, "AXI ARID mismatch: expected %0d got %0d",
                               EXPECTED_ID, arid);
                    end
                    read_outstanding_q <= 1'b1;
                    read_id_q          <= arid;
                    read_beat_q        <= 3'd0;
                end

                if (rvalid && rready) begin
                    if (!read_outstanding_q) begin
                        $fatal(1, "AXI R beat arrived without accepted AR");
                    end
                    if ((rid != read_id_q) || (rresp != `AXI_RESP_OKAY)) begin
                        $fatal(1, "AXI read response mismatch id=%0d resp=%0d",
                               rid, rresp);
                    end
                    if (rlast !== (read_beat_q == 3'd3)) begin
                        $fatal(1, "AXI RLAST mismatch at beat %0d",
                               read_beat_q);
                    end
                    if (rlast) begin
                        read_outstanding_q <= 1'b0;
                        read_burst_count   <= read_burst_count + 1;
                    end
                    else begin
                        read_beat_q <= read_beat_q + 1'b1;
                    end
                end
            end
        end
    end

endmodule
