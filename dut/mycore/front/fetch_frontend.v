`timescale 1ns/1ps

// In-order instruction frontend with cache-line requests and two decode slots.
//
// The request/response interface is ordered and has no response backpressure.
// Each accepted request returns exactly one complete cache line.  Redirects
// invalidate all locally queued lines; responses for requests accepted before
// the redirect are counted and discarded before new-path responses are used.
module fetch_frontend #(
    parameter integer LINE_BYTES  = 16,
    parameter integer QUEUE_DEPTH = 8,
    parameter [31:0]  RESET_PC    = 32'h0000_0000
)(
    input  wire                         clk,
    input  wire                         reset,

    output wire                         pm_req_valid,
    output wire [31:0]                  pm_req_addr,
    input  wire                         pm_req_ready,

    input  wire                         pm_resp_valid,
    input  wire [(LINE_BYTES*8)-1:0]    pm_resp_data,

    input  wire                         redirect_valid,
    input  wire [31:0]                  redirect_target,

    // Number of oldest instructions accepted by the issue stage this cycle.
    // Legal values are 0, 1 and 2.  The frontend defensively saturates an
    // invalid request to the number of instructions actually available.
    input  wire [1:0]                   consume_count,

    output reg  [1:0]                   instr_valid,
    output reg  [31:0]                  instr0,
    output reg  [31:0]                  instr1,
    output reg  [31:0]                  pc0,
    output reg  [31:0]                  pc1,

    output wire                         queue_full,
    output wire                         queue_empty,
    output wire [31:0]                  stale_response_count
);

    function integer clog2(input integer value);
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer LINE_WIDTH     = LINE_BYTES * 8;
    localparam integer WORDS_PER_LINE = LINE_BYTES / 4;
    localparam integer PTR_WIDTH      = clog2(QUEUE_DEPTH);
    localparam integer WORD_IDX_WIDTH = clog2(WORDS_PER_LINE);
    localparam [31:0]  LINE_MASK      = LINE_BYTES - 1;

    reg [LINE_WIDTH-1:0] line_fifo [0:QUEUE_DEPTH-1];
    reg [31:0]           base_pc_fifo [0:QUEUE_DEPTH-1];
    reg [WORD_IDX_WIDTH-1:0] word_idx_fifo [0:QUEUE_DEPTH-1];
    reg                  response_valid_fifo [0:QUEUE_DEPTH-1];

    // Extended ring pointers retain a wrap bit.  Allocation order is also
    // response order, because the external interface is explicitly ordered.
    reg [PTR_WIDTH:0] read_ptr;
    reg [PTR_WIDTH:0] alloc_ptr;
    reg [PTR_WIDTH:0] response_ptr;

    reg [31:0] fetch_pc_q;
    reg [31:0] stale_response_count_q;

    wire [PTR_WIDTH-1:0] read_index     = read_ptr[PTR_WIDTH-1:0];
    wire [PTR_WIDTH-1:0] alloc_index    = alloc_ptr[PTR_WIDTH-1:0];
    wire [PTR_WIDTH-1:0] response_index = response_ptr[PTR_WIDTH-1:0];

    wire [PTR_WIDTH:0] allocated_count   = alloc_ptr - read_ptr;
    wire [PTR_WIDTH:0] outstanding_count = alloc_ptr - response_ptr;

    assign queue_empty = (alloc_ptr == read_ptr);
    assign queue_full  = (alloc_ptr[PTR_WIDTH-1:0] == read_ptr[PTR_WIDTH-1:0]) &&
                         (alloc_ptr[PTR_WIDTH] != read_ptr[PTR_WIDTH]);

    // Do not accept an old-path request in the redirect cycle.  The target
    // request is presented on the following cycle after fetch_pc_q is updated.
    assign pm_req_valid = !reset && !redirect_valid && !queue_full;
    assign pm_req_addr  = fetch_pc_q & ~LINE_MASK;

    wire request_fire = pm_req_valid && pm_req_ready;

    wire head_ready = !queue_empty && response_valid_fifo[read_index];
    wire [WORD_IDX_WIDTH-1:0] head_word_idx = word_idx_fifo[read_index];
    wire head_has_second = head_ready &&
                           (head_word_idx < (WORDS_PER_LINE - 1));

    integer head_bit_offset;
    always @(*) begin
        instr_valid = 2'b00;
        instr0 = 32'h0000_0013;
        instr1 = 32'h0000_0013;
        pc0 = 32'b0;
        pc1 = 32'b0;
        head_bit_offset = 0;

        if (head_ready) begin
            head_bit_offset = head_word_idx * 32;
            instr_valid[0] = 1'b1;
            instr0 = line_fifo[read_index][head_bit_offset +: 32];
            pc0 = base_pc_fifo[read_index] + (head_word_idx * 4);

            if (head_has_second) begin
                instr_valid[1] = 1'b1;
                instr1 = line_fifo[read_index][head_bit_offset + 32 +: 32];
                pc1 = base_pc_fifo[read_index] + ((head_word_idx + 1'b1) * 4);
            end
        end
    end

    // Saturating consumption protects the queue in synthesis.  Assertions
    // below still flag every violation of the consume_count contract.
    reg [1:0] consume_actual;
    always @(*) begin
        consume_actual = 2'd0;
        if (instr_valid[0] && (consume_count != 2'd0)) begin
            if (instr_valid[1] && (consume_count >= 2'd2))
                consume_actual = 2'd2;
            else
                consume_actual = 2'd1;
        end
    end

    wire [WORD_IDX_WIDTH:0] consumed_word_end =
        {1'b0, head_word_idx} + consume_actual;
    wire consume_finishes_line = (consume_actual != 2'd0) &&
                                 (consumed_word_end >= WORDS_PER_LINE);

    integer entry;
    reg [32:0] stale_total_on_redirect;
    always @(*) begin
        stale_total_on_redirect = {1'b0, stale_response_count_q} +
                                  outstanding_count;
        if (redirect_valid && pm_resp_valid &&
            (stale_total_on_redirect != 33'd0)) begin
            stale_total_on_redirect = stale_total_on_redirect - 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_ptr <= {(PTR_WIDTH+1){1'b0}};
            alloc_ptr <= {(PTR_WIDTH+1){1'b0}};
            response_ptr <= {(PTR_WIDTH+1){1'b0}};
            fetch_pc_q <= RESET_PC;
            stale_response_count_q <= 32'b0;
            for (entry = 0; entry < QUEUE_DEPTH; entry = entry + 1) begin
                line_fifo[entry] <= {WORDS_PER_LINE{32'h0000_0013}};
                base_pc_fifo[entry] <= 32'b0;
                word_idx_fifo[entry] <= {WORD_IDX_WIDTH{1'b0}};
                response_valid_fifo[entry] <= 1'b0;
            end
        end
        else if (redirect_valid) begin
            // All current entries are wrong-path.  Outstanding responses are
            // retained only as a count so they can be discarded in order.
            read_ptr <= {(PTR_WIDTH+1){1'b0}};
            alloc_ptr <= {(PTR_WIDTH+1){1'b0}};
            response_ptr <= {(PTR_WIDTH+1){1'b0}};
            fetch_pc_q <= redirect_target;
            stale_response_count_q <= stale_total_on_redirect[31:0];
            for (entry = 0; entry < QUEUE_DEPTH; entry = entry + 1) begin
                response_valid_fifo[entry] <= 1'b0;
                word_idx_fifo[entry] <= {WORD_IDX_WIDTH{1'b0}};
            end
        end
        else begin
            if (request_fire) begin
                base_pc_fifo[alloc_index] <= pm_req_addr;
                word_idx_fifo[alloc_index] <=
                    fetch_pc_q[clog2(LINE_BYTES)-1:2];
                response_valid_fifo[alloc_index] <= 1'b0;
                alloc_ptr <= alloc_ptr + 1'b1;
                fetch_pc_q <= (fetch_pc_q & ~LINE_MASK) + LINE_BYTES;
            end

            if (consume_actual != 2'd0) begin
                if (consume_finishes_line) begin
                    response_valid_fifo[read_index] <= 1'b0;
                    word_idx_fifo[read_index] <= {WORD_IDX_WIDTH{1'b0}};
                    read_ptr <= read_ptr + 1'b1;
                end
                else begin
                    word_idx_fifo[read_index] <=
                        consumed_word_end[WORD_IDX_WIDTH-1:0];
                end
            end

            if (pm_resp_valid) begin
                if (stale_response_count_q != 32'd0) begin
                    stale_response_count_q <= stale_response_count_q - 1'b1;
                end
                else if ((response_ptr != alloc_ptr) || request_fire) begin
                    line_fifo[response_index] <= pm_resp_data;
                    response_valid_fifo[response_index] <= 1'b1;
                    response_ptr <= response_ptr + 1'b1;
                end
            end
        end
    end

    assign stale_response_count = stale_response_count_q;

    // Parameter checks and protocol assertions are intentionally excluded
    // from synthesis, but active in Verilator and event-driven simulation.
    // synthesis translate_off
    initial begin
        if (LINE_BYTES != 16)
            $fatal(1, "fetch_frontend requires a 128-bit (16-byte) line");
        if (QUEUE_DEPTH < 2 || ((QUEUE_DEPTH & (QUEUE_DEPTH - 1)) != 0))
            $fatal(1, "fetch_frontend QUEUE_DEPTH must be a power of two >= 2");
        if (RESET_PC[1:0] != 2'b00)
            $fatal(1, "fetch_frontend RESET_PC must be 4-byte aligned");
    end

    always @(posedge clk) begin
        if (!reset) begin
            if (redirect_valid && (redirect_target[1:0] != 2'b00))
                $error("fetch_frontend redirect target is not RV32I aligned: 0x%08x",
                       redirect_target);
            if (redirect_valid && stale_total_on_redirect[32])
                $error("fetch_frontend stale-response counter overflow");
            if (consume_count == 2'd3)
                $error("fetch_frontend consume_count=3 is illegal");
            if ((consume_count >= 2'd1) && !instr_valid[0])
                $error("fetch_frontend consumed an unavailable slot0");
            if ((consume_count >= 2'd2) && !instr_valid[1])
                $error("fetch_frontend consumed an unavailable slot1");
            if (instr_valid[1] && (!instr_valid[0] || (pc1 != (pc0 + 4))))
                $error("fetch_frontend produced a non-contiguous instruction pair");
            if (allocated_count > QUEUE_DEPTH)
                $error("fetch_frontend allocation pointer exceeded queue capacity");
            if (outstanding_count > QUEUE_DEPTH)
                $error("fetch_frontend response pointer exceeded queue capacity");
            if (pm_resp_valid && !redirect_valid &&
                (stale_response_count_q == 0) &&
                (response_ptr == alloc_ptr) && !request_fire)
                $error("fetch_frontend received a response without an accepted request");
            if (pm_resp_valid && !redirect_valid &&
                (stale_response_count_q == 0) &&
                (response_ptr != alloc_ptr) &&
                response_valid_fifo[response_index])
                $error("fetch_frontend response overwrote a completed entry");
            if (redirect_valid && pm_resp_valid &&
                (stale_total_on_redirect == 33'd0) &&
                (stale_response_count_q == 0) &&
                (outstanding_count == 0))
                $error("fetch_frontend received an unsolicited response during redirect");
        end
    end
    // synthesis translate_on

endmodule
