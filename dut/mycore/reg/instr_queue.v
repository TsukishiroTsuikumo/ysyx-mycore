`timescale 1ns/1ps

module instr_queue #(
    parameter QUEUE_DEPTH = 8,
    parameter [31:0] RESET_PC = 32'h0000_0000
)(
    input               clk,
    input               reset,
    output              pm_req_valid,
    output      [31:0]  pm_req_addr,
    input               pm_req_ready,
    input               pm_resp_valid,
    input       [127:0] pm_resp_data,
    input               redirect_valid,
    input       [31:0]  redirect_target,
    input        [1:0]  consume_count,
    output reg    [1:0] instr_valid,
    output reg   [31:0] instr0,
    output reg   [31:0] instr1,
    output reg   [31:0] pc0,
    output reg   [31:0] pc1,
    output              queue_full,
    output              queue_empty,
    output      [31:0]  stale_response_count
);

    function integer clog2;
        input integer value;
        integer value_work;
        begin
            clog2 = 0;
            value_work = value - 1;
            while (value_work > 0) begin
                clog2 = clog2 + 1;
                value_work = value_work >> 1;
            end
        end
    endfunction

    localparam PTR_WIDTH = clog2(QUEUE_DEPTH);

    reg [127:0] line_fifo [0:QUEUE_DEPTH-1];
    reg  [31:0] base_pc_fifo [0:QUEUE_DEPTH-1];
    reg   [1:0] word_idx_fifo [0:QUEUE_DEPTH-1];
    reg         response_valid_fifo [0:QUEUE_DEPTH-1];

    reg [PTR_WIDTH:0] read_ptr;
    reg [PTR_WIDTH:0] alloc_ptr;
    reg [PTR_WIDTH:0] response_ptr;
    reg [31:0] fetch_pc_q;
    reg [31:0] stale_response_count_q;

    wire [PTR_WIDTH-1:0] read_index;
    wire [PTR_WIDTH-1:0] alloc_index;
    wire [PTR_WIDTH-1:0] response_index;
    wire [PTR_WIDTH:0] outstanding_count;
    wire request_fire;
    wire head_ready;
    reg [1:0] consume_actual;
    wire consume_finishes_line;
    reg [32:0] stale_total_on_redirect;

    assign read_index = read_ptr[PTR_WIDTH-1:0];
    assign alloc_index = alloc_ptr[PTR_WIDTH-1:0];
    assign response_index = response_ptr[PTR_WIDTH-1:0];
    assign outstanding_count = alloc_ptr - response_ptr;

    assign queue_empty = (alloc_ptr == read_ptr);
    assign queue_full = (alloc_ptr[PTR_WIDTH-1:0] ==
                         read_ptr[PTR_WIDTH-1:0]) &&
                        (alloc_ptr[PTR_WIDTH] != read_ptr[PTR_WIDTH]);
    assign pm_req_valid = !reset && !redirect_valid && !queue_full;
    assign pm_req_addr = {fetch_pc_q[31:4], 4'b0000};
    assign request_fire = pm_req_valid && pm_req_ready;
    assign head_ready = !queue_empty && response_valid_fifo[read_index];
    assign consume_finishes_line = (consume_actual != 2'd0) &&
        (({1'b0, word_idx_fifo[read_index]} + consume_actual) >= 3'd4);
    assign stale_response_count = stale_response_count_q;

    always @(*) begin
        instr_valid = 2'b00;
        instr0 = 32'h0000_0013;
        instr1 = 32'h0000_0013;
        pc0 = 32'b0;
        pc1 = 32'b0;

        if (head_ready) begin
            instr_valid[0] = 1'b1;
            case (word_idx_fifo[read_index])
                2'd0: begin
                    instr0 = line_fifo[read_index][31:0];
                    instr1 = line_fifo[read_index][63:32];
                    instr_valid[1] = 1'b1;
                end
                2'd1: begin
                    instr0 = line_fifo[read_index][63:32];
                    instr1 = line_fifo[read_index][95:64];
                    instr_valid[1] = 1'b1;
                end
                2'd2: begin
                    instr0 = line_fifo[read_index][95:64];
                    instr1 = line_fifo[read_index][127:96];
                    instr_valid[1] = 1'b1;
                end
                default: begin
                    instr0 = line_fifo[read_index][127:96];
                    instr1 = 32'h0000_0013;
                    instr_valid[1] = 1'b0;
                end
            endcase
            pc0 = base_pc_fifo[read_index] +
                  {28'b0, word_idx_fifo[read_index], 2'b00};
            pc1 = pc0 + 32'd4;
        end
    end

    always @(*) begin
        consume_actual = 2'd0;
        if (instr_valid[0] && (consume_count != 2'd0)) begin
            if (instr_valid[1] && (consume_count >= 2'd2))
                consume_actual = 2'd2;
            else
                consume_actual = 2'd1;
        end
    end

    always @(*) begin
        stale_total_on_redirect = {1'b0, stale_response_count_q} +
                                  {{(32-PTR_WIDTH){1'b0}},
                                   outstanding_count};
        if (pm_resp_valid && (stale_total_on_redirect != 33'd0))
            stale_total_on_redirect = stale_total_on_redirect - 1'b1;
    end

    integer entry;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_ptr <= {(PTR_WIDTH+1){1'b0}};
            alloc_ptr <= {(PTR_WIDTH+1){1'b0}};
            response_ptr <= {(PTR_WIDTH+1){1'b0}};
            fetch_pc_q <= RESET_PC;
            stale_response_count_q <= 32'b0;
            for (entry = 0; entry < QUEUE_DEPTH; entry = entry + 1) begin
                line_fifo[entry] <= {4{32'h0000_0013}};
                base_pc_fifo[entry] <= 32'b0;
                word_idx_fifo[entry] <= 2'b00;
                response_valid_fifo[entry] <= 1'b0;
            end
        end
        else if (redirect_valid) begin
            read_ptr <= {(PTR_WIDTH+1){1'b0}};
            alloc_ptr <= {(PTR_WIDTH+1){1'b0}};
            response_ptr <= {(PTR_WIDTH+1){1'b0}};
            fetch_pc_q <= redirect_target;
            stale_response_count_q <= stale_total_on_redirect[31:0];
            for (entry = 0; entry < QUEUE_DEPTH; entry = entry + 1) begin
                word_idx_fifo[entry] <= 2'b00;
                response_valid_fifo[entry] <= 1'b0;
            end
        end
        else begin
            if (request_fire) begin
                base_pc_fifo[alloc_index] <= pm_req_addr;
                word_idx_fifo[alloc_index] <= fetch_pc_q[3:2];
                response_valid_fifo[alloc_index] <= 1'b0;
                alloc_ptr <= alloc_ptr + 1'b1;
                fetch_pc_q <= {fetch_pc_q[31:4], 4'b0000} + 32'd16;
            end

            if (consume_actual != 2'd0) begin
                if (consume_finishes_line) begin
                    response_valid_fifo[read_index] <= 1'b0;
                    word_idx_fifo[read_index] <= 2'b00;
                    read_ptr <= read_ptr + 1'b1;
                end
                else begin
                    word_idx_fifo[read_index] <=
                        word_idx_fifo[read_index] + consume_actual;
                end
            end

            if (pm_resp_valid) begin
                if (stale_response_count_q != 32'd0) begin
                    stale_response_count_q <=
                        stale_response_count_q - 1'b1;
                end
                else if ((response_ptr != alloc_ptr) || request_fire) begin
                    line_fifo[response_index] <= pm_resp_data;
                    response_valid_fifo[response_index] <= 1'b1;
                    response_ptr <= response_ptr + 1'b1;
                end
            end
        end
    end

endmodule
