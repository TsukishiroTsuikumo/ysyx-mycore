`timescale 1ns/1ps

/*
 * Eight-entry reorder buffer for the fixed two-wide out-of-order core.
 *
 * Allocation, completion, and retirement are all prefix ordered.  Results
 * may complete through either CDB in any order, while retirement remains
 * strictly in program order.  A mispredicted control instruction recovers
 * only when it reaches the head: that instruction retires in the recovery
 * cycle and every younger entry is discarded.  Control, FENCE, and store
 * instructions always retire alone.
 */
module rob (
    input             clk,
    input             reset,

    input       [1:0] dispatch_count_in,

    input             alloc0_supported_in,
    input      [31:0] alloc0_pc_in,
    input      [31:0] alloc0_instr_in,
    input             alloc0_reports_rd_in,
    input             alloc0_writes_rd_in,
    input       [4:0] alloc0_arch_rd_in,
    input       [5:0] alloc0_pdst_in,
    input       [5:0] alloc0_old_pdst_in,
    input             alloc0_is_control_in,
    input             alloc0_is_fence_in,
    input             alloc0_is_store_in,

    input             alloc1_supported_in,
    input      [31:0] alloc1_pc_in,
    input      [31:0] alloc1_instr_in,
    input             alloc1_reports_rd_in,
    input             alloc1_writes_rd_in,
    input       [4:0] alloc1_arch_rd_in,
    input       [5:0] alloc1_pdst_in,
    input       [5:0] alloc1_old_pdst_in,
    input             alloc1_is_control_in,
    input             alloc1_is_fence_in,
    input             alloc1_is_store_in,

    output      [2:0] alloc_tag0_out,
    output      [2:0] alloc_tag1_out,
    output     [63:0] alloc_seq0_out,
    output     [63:0] alloc_seq1_out,
    output      [3:0] rob_count_out,
    output      [3:0] free_count_out,
    output            any_control_out,
    output            any_fence_out,
    output            head_valid_out,
    output      [2:0] head_tag_out,
    output            head_is_store_out,
    output            head_is_fence_out,
    output            barrier_valid_out,
    output     [63:0] barrier_seq_out,

    input             cdb0_valid_in,
    input       [2:0] cdb0_rob_tag_in,
    input      [31:0] cdb0_value_in,
    input             cdb0_control_in,
    input      [31:0] cdb0_target_in,
    input             cdb0_mispredict_in,

    input             cdb1_valid_in,
    input       [2:0] cdb1_rob_tag_in,
    input      [31:0] cdb1_value_in,
    input             cdb1_control_in,
    input      [31:0] cdb1_target_in,
    input             cdb1_mispredict_in,

    input             store_complete_valid_in,
    input       [2:0] store_complete_rob_tag_in,
    input             fence_can_complete_in,

    output reg        recovery_out,
    output reg [31:0] recovery_target_out,

    output reg        commit0_valid_out,
    output reg        commit0_writes_rd_out,
    output reg  [4:0] commit0_arch_rd_out,
    output reg  [5:0] commit0_pdst_out,
    output reg  [5:0] commit0_old_pdst_out,
    output reg        commit1_valid_out,
    output reg        commit1_writes_rd_out,
    output reg  [4:0] commit1_arch_rd_out,
    output reg  [5:0] commit1_pdst_out,
    output reg  [5:0] commit1_old_pdst_out,

    output reg  [1:0] retire_valid_out,
    output reg [63:0] retire_pc_out,
    output reg [63:0] retire_instr_out,
    output reg  [1:0] retire_rd_write_out,
    output reg  [9:0] retire_rd_addr_out,
    output reg [63:0] retire_rd_data_out
);

    localparam ROB_DEPTH = 8;

    reg [2:0] head_q;
    reg [2:0] tail_q;
    reg [3:0] count_q;
    reg [63:0] next_seq_q;

    reg        valid_q [0:ROB_DEPTH-1];
    reg        ready_q [0:ROB_DEPTH-1];
    reg [63:0] seq_q [0:ROB_DEPTH-1];
    reg [31:0] pc_q [0:ROB_DEPTH-1];
    reg [31:0] instr_q [0:ROB_DEPTH-1];
    reg        reports_rd_q [0:ROB_DEPTH-1];
    reg        writes_rd_q [0:ROB_DEPTH-1];
    reg  [4:0] arch_rd_q [0:ROB_DEPTH-1];
    reg  [5:0] pdst_q [0:ROB_DEPTH-1];
    reg  [5:0] old_pdst_q [0:ROB_DEPTH-1];
    reg [31:0] value_q [0:ROB_DEPTH-1];
    reg        is_control_q [0:ROB_DEPTH-1];
    reg        is_fence_q [0:ROB_DEPTH-1];
    reg        is_store_q [0:ROB_DEPTH-1];
    reg        control_complete_q [0:ROB_DEPTH-1];
    reg [31:0] control_target_q [0:ROB_DEPTH-1];
    reg        mispredict_q [0:ROB_DEPTH-1];

    wire [2:0] second_tag;
    wire       head_ready;
    wire       second_ready;
    wire       head_special;
    wire       second_special;
    reg  [1:0] retire_count;

    integer scan_index;
    integer reset_index;
    reg barrier_found;
    reg [63:0] barrier_seq;
    reg any_control;
    reg any_fence;

    assign alloc_tag0_out = tail_q;
    assign alloc_tag1_out = tail_q + 3'd1;
    assign alloc_seq0_out = next_seq_q;
    assign alloc_seq1_out = next_seq_q + 64'd1;
    assign rob_count_out = count_q;
    assign free_count_out = 4'd8 - count_q;
    assign head_valid_out = (count_q != 4'd0) && valid_q[head_q];
    assign head_tag_out = head_q;
    assign head_is_store_out = head_valid_out && is_store_q[head_q];
    assign head_is_fence_out = head_valid_out && is_fence_q[head_q];
    assign second_tag = head_q + 3'd1;
    assign head_ready = head_valid_out &&
        (ready_q[head_q] || (is_fence_q[head_q] && fence_can_complete_in));
    assign second_ready = (count_q >= 4'd2) && valid_q[second_tag] &&
        (ready_q[second_tag] ||
         (is_fence_q[second_tag] && fence_can_complete_in));
    assign head_special = head_valid_out &&
        (is_control_q[head_q] || is_fence_q[head_q] || is_store_q[head_q]);
    assign second_special = (count_q >= 4'd2) && valid_q[second_tag] &&
        (is_control_q[second_tag] || is_fence_q[second_tag] ||
         is_store_q[second_tag]);
    assign any_control_out = any_control;
    assign any_fence_out = any_fence;
    assign barrier_valid_out = barrier_found;
    assign barrier_seq_out = barrier_seq;

    always @(*) begin
        any_control = 1'b0;
        any_fence = 1'b0;
        barrier_found = 1'b0;
        barrier_seq = 64'b0;
        for (scan_index = 0; scan_index < ROB_DEPTH;
             scan_index = scan_index + 1) begin
            if (valid_q[scan_index]) begin
                if (is_control_q[scan_index])
                    any_control = 1'b1;
                if (is_fence_q[scan_index])
                    any_fence = 1'b1;
                if (is_control_q[scan_index] || is_fence_q[scan_index]) begin
                    if (!barrier_found || (seq_q[scan_index] < barrier_seq)) begin
                        barrier_found = 1'b1;
                        barrier_seq = seq_q[scan_index];
                    end
                end
            end
        end
    end

    always @(*) begin
        retire_count = 2'd0;
        if (head_ready) begin
            retire_count = 2'd1;
            if (!head_special && !second_special && second_ready)
                retire_count = 2'd2;
        end

        recovery_out = 1'b0;
        recovery_target_out = 32'b0;

        commit0_valid_out = 1'b0;
        commit0_writes_rd_out = 1'b0;
        commit0_arch_rd_out = 5'b0;
        commit0_pdst_out = 6'b0;
        commit0_old_pdst_out = 6'b0;
        commit1_valid_out = 1'b0;
        commit1_writes_rd_out = 1'b0;
        commit1_arch_rd_out = 5'b0;
        commit1_pdst_out = 6'b0;
        commit1_old_pdst_out = 6'b0;

        retire_valid_out = 2'b00;
        retire_pc_out = 64'b0;
        retire_instr_out = 64'b0;
        retire_rd_write_out = 2'b00;
        retire_rd_addr_out = 10'b0;
        retire_rd_data_out = 64'b0;

        if (retire_count != 2'd0) begin
            commit0_valid_out = 1'b1;
            commit0_writes_rd_out = writes_rd_q[head_q];
            commit0_arch_rd_out = arch_rd_q[head_q];
            commit0_pdst_out = pdst_q[head_q];
            commit0_old_pdst_out = old_pdst_q[head_q];

            retire_valid_out[0] = 1'b1;
            retire_pc_out[31:0] = pc_q[head_q];
            retire_instr_out[31:0] = instr_q[head_q];
            retire_rd_write_out[0] = reports_rd_q[head_q];
            if (reports_rd_q[head_q]) begin
                retire_rd_addr_out[4:0] = arch_rd_q[head_q];
                if (arch_rd_q[head_q] == 5'd0)
                    retire_rd_data_out[31:0] = 32'b0;
                else
                    retire_rd_data_out[31:0] = value_q[head_q];
            end

            if (is_control_q[head_q] && control_complete_q[head_q] &&
                mispredict_q[head_q]) begin
                recovery_out = 1'b1;
                recovery_target_out = control_target_q[head_q];
            end
        end

        if (retire_count == 2'd2) begin
            commit1_valid_out = 1'b1;
            commit1_writes_rd_out = writes_rd_q[second_tag];
            commit1_arch_rd_out = arch_rd_q[second_tag];
            commit1_pdst_out = pdst_q[second_tag];
            commit1_old_pdst_out = old_pdst_q[second_tag];

            retire_valid_out[1] = 1'b1;
            retire_pc_out[63:32] = pc_q[second_tag];
            retire_instr_out[63:32] = instr_q[second_tag];
            retire_rd_write_out[1] = reports_rd_q[second_tag];
            if (reports_rd_q[second_tag]) begin
                retire_rd_addr_out[9:5] = arch_rd_q[second_tag];
                if (arch_rd_q[second_tag] == 5'd0)
                    retire_rd_data_out[63:32] = 32'b0;
                else
                    retire_rd_data_out[63:32] = value_q[second_tag];
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head_q <= 3'b0;
            tail_q <= 3'b0;
            count_q <= 4'b0;
            next_seq_q <= 64'b0;
            for (reset_index = 0; reset_index < ROB_DEPTH;
                 reset_index = reset_index + 1) begin
                valid_q[reset_index] <= 1'b0;
                ready_q[reset_index] <= 1'b0;
                seq_q[reset_index] <= 64'b0;
                pc_q[reset_index] <= 32'b0;
                instr_q[reset_index] <= 32'h0000_0013;
                reports_rd_q[reset_index] <= 1'b0;
                writes_rd_q[reset_index] <= 1'b0;
                arch_rd_q[reset_index] <= 5'b0;
                pdst_q[reset_index] <= 6'b0;
                old_pdst_q[reset_index] <= 6'b0;
                value_q[reset_index] <= 32'b0;
                is_control_q[reset_index] <= 1'b0;
                is_fence_q[reset_index] <= 1'b0;
                is_store_q[reset_index] <= 1'b0;
                control_complete_q[reset_index] <= 1'b0;
                control_target_q[reset_index] <= 32'b0;
                mispredict_q[reset_index] <= 1'b0;
            end
        end
        else if (recovery_out) begin
            head_q <= head_q + 3'd1;
            tail_q <= head_q + 3'd1;
            count_q <= 4'b0;
            next_seq_q <= next_seq_q;
            for (reset_index = 0; reset_index < ROB_DEPTH;
                 reset_index = reset_index + 1) begin
                valid_q[reset_index] <= 1'b0;
                ready_q[reset_index] <= 1'b0;
                control_complete_q[reset_index] <= 1'b0;
                mispredict_q[reset_index] <= 1'b0;
            end
        end
        else begin
            if (cdb0_valid_in && valid_q[cdb0_rob_tag_in]) begin
                ready_q[cdb0_rob_tag_in] <= 1'b1;
                value_q[cdb0_rob_tag_in] <= cdb0_value_in;
                if (cdb0_control_in) begin
                    control_complete_q[cdb0_rob_tag_in] <= 1'b1;
                    control_target_q[cdb0_rob_tag_in] <= cdb0_target_in;
                    mispredict_q[cdb0_rob_tag_in] <= cdb0_mispredict_in;
                end
            end
            if (cdb1_valid_in && valid_q[cdb1_rob_tag_in]) begin
                ready_q[cdb1_rob_tag_in] <= 1'b1;
                value_q[cdb1_rob_tag_in] <= cdb1_value_in;
                if (cdb1_control_in) begin
                    control_complete_q[cdb1_rob_tag_in] <= 1'b1;
                    control_target_q[cdb1_rob_tag_in] <= cdb1_target_in;
                    mispredict_q[cdb1_rob_tag_in] <= cdb1_mispredict_in;
                end
            end
            if (store_complete_valid_in &&
                valid_q[store_complete_rob_tag_in] &&
                is_store_q[store_complete_rob_tag_in]) begin
                ready_q[store_complete_rob_tag_in] <= 1'b1;
            end

            if (retire_count != 2'd0) begin
                valid_q[head_q] <= 1'b0;
                ready_q[head_q] <= 1'b0;
                head_q <= head_q + retire_count;
            end
            if (retire_count == 2'd2) begin
                valid_q[second_tag] <= 1'b0;
                ready_q[second_tag] <= 1'b0;
            end

            if (dispatch_count_in != 2'd0) begin
                valid_q[tail_q] <= 1'b1;
                ready_q[tail_q] <= !alloc0_supported_in;
                seq_q[tail_q] <= next_seq_q;
                pc_q[tail_q] <= alloc0_pc_in;
                instr_q[tail_q] <= alloc0_instr_in;
                reports_rd_q[tail_q] <= alloc0_reports_rd_in;
                writes_rd_q[tail_q] <= alloc0_writes_rd_in;
                arch_rd_q[tail_q] <= alloc0_arch_rd_in;
                pdst_q[tail_q] <= alloc0_pdst_in;
                old_pdst_q[tail_q] <= alloc0_old_pdst_in;
                value_q[tail_q] <= 32'b0;
                is_control_q[tail_q] <= alloc0_is_control_in;
                is_fence_q[tail_q] <= alloc0_is_fence_in;
                is_store_q[tail_q] <= alloc0_is_store_in;
                control_complete_q[tail_q] <= 1'b0;
                control_target_q[tail_q] <= 32'b0;
                mispredict_q[tail_q] <= 1'b0;
            end
            if (dispatch_count_in == 2'd2) begin
                valid_q[tail_q + 3'd1] <= 1'b1;
                ready_q[tail_q + 3'd1] <= !alloc1_supported_in;
                seq_q[tail_q + 3'd1] <= next_seq_q + 64'd1;
                pc_q[tail_q + 3'd1] <= alloc1_pc_in;
                instr_q[tail_q + 3'd1] <= alloc1_instr_in;
                reports_rd_q[tail_q + 3'd1] <= alloc1_reports_rd_in;
                writes_rd_q[tail_q + 3'd1] <= alloc1_writes_rd_in;
                arch_rd_q[tail_q + 3'd1] <= alloc1_arch_rd_in;
                pdst_q[tail_q + 3'd1] <= alloc1_pdst_in;
                old_pdst_q[tail_q + 3'd1] <= alloc1_old_pdst_in;
                value_q[tail_q + 3'd1] <= 32'b0;
                is_control_q[tail_q + 3'd1] <= alloc1_is_control_in;
                is_fence_q[tail_q + 3'd1] <= alloc1_is_fence_in;
                is_store_q[tail_q + 3'd1] <= alloc1_is_store_in;
                control_complete_q[tail_q + 3'd1] <= 1'b0;
                control_target_q[tail_q + 3'd1] <= 32'b0;
                mispredict_q[tail_q + 3'd1] <= 1'b0;
            end

            if (dispatch_count_in != 2'd0) begin
                tail_q <= tail_q + dispatch_count_in;
                next_seq_q <= next_seq_q +
                              {{62{1'b0}}, dispatch_count_in};
            end
            count_q <= count_q + {2'b0, dispatch_count_in} -
                       {2'b0, retire_count};
        end
    end

endmodule
