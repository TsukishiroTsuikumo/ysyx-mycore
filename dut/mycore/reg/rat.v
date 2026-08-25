`timescale 1ns/1ps

/*
 * Two-wide rename state for the fixed 48-entry physical register file.
 *
 * rat[] is speculative and amt[] is the committed architectural map.  The
 * free list is deliberately allocated from the state visible at the start
 * of a cycle; physical registers released by commit are not reused until the
 * following cycle.  On recovery, valid commits are applied first and that
 * post-commit AMT is used to rebuild both RAT and the free list.
 */
module rat (
    input             clk,
    input             reset,
    input             recovery_in,

    input       [1:0] dispatch_count_in,

    input             src0_1_used_in,
    input       [4:0] src0_1_addr_in,
    output      [5:0] src0_1_tag_out,
    input             src0_2_used_in,
    input       [4:0] src0_2_addr_in,
    output      [5:0] src0_2_tag_out,
    input             src1_1_used_in,
    input       [4:0] src1_1_addr_in,
    output      [5:0] src1_1_tag_out,
    input             src1_2_used_in,
    input       [4:0] src1_2_addr_in,
    output      [5:0] src1_2_tag_out,

    input             dst0_writes_in,
    input       [4:0] dst0_arch_in,
    output      [5:0] new_pdst0_out,
    output      [5:0] old_pdst0_out,
    input             dst1_writes_in,
    input       [4:0] dst1_arch_in,
    output      [5:0] new_pdst1_out,
    output      [5:0] old_pdst1_out,

    output      [5:0] free_count_out,

    input             commit0_valid_in,
    input             commit0_writes_in,
    input       [4:0] commit0_arch_in,
    input       [5:0] commit0_pdst_in,
    input       [5:0] commit0_old_pdst_in,
    input             commit1_valid_in,
    input             commit1_writes_in,
    input       [4:0] commit1_arch_in,
    input       [5:0] commit1_pdst_in,
    input       [5:0] commit1_old_pdst_in
);

    localparam [5:0] PHYS_REG_COUNT = 6'd48;

    reg [5:0] rat_map [0:31];
    reg [5:0] amt [0:31];
    reg [47:0] free_mask;

    reg [5:0] first_free_tag;
    reg [5:0] second_free_tag;
    reg [5:0] free_count_comb;
    reg       first_free_found;
    reg       second_free_found;
    integer   free_scan_index;

    wire dst0_effective_write;
    wire dst1_effective_write;
    wire dispatch0_fire;
    wire dispatch1_fire;
    wire commit0_map_write;
    wire commit1_map_write;

    assign dst0_effective_write = dst0_writes_in &&
                                  (dst0_arch_in != 5'd0);
    assign dst1_effective_write = dst1_writes_in &&
                                  (dst1_arch_in != 5'd0);
    assign dispatch0_fire = (dispatch_count_in != 2'd0);
    assign dispatch1_fire = (dispatch_count_in == 2'd2);

    assign commit0_map_write = commit0_valid_in && commit0_writes_in &&
                               (commit0_arch_in != 5'd0) &&
                               (commit0_pdst_in < PHYS_REG_COUNT);
    assign commit1_map_write = commit1_valid_in && commit1_writes_in &&
                               (commit1_arch_in != 5'd0) &&
                               (commit1_pdst_in < PHYS_REG_COUNT);

    always @(*) begin
        first_free_tag = 6'd0;
        second_free_tag = 6'd0;
        free_count_comb = 6'd0;
        first_free_found = 1'b0;
        second_free_found = 1'b0;

        for (free_scan_index = 0; free_scan_index < 48;
             free_scan_index = free_scan_index + 1) begin
            if (free_mask[free_scan_index]) begin
                free_count_comb = free_count_comb + 6'd1;
                if (!first_free_found) begin
                    first_free_tag = free_scan_index[5:0];
                    first_free_found = 1'b1;
                end
                else if (!second_free_found) begin
                    second_free_tag = free_scan_index[5:0];
                    second_free_found = 1'b1;
                end
            end
        end
    end

    assign free_count_out = free_count_comb;

    assign new_pdst0_out = dst0_effective_write ? first_free_tag : 6'd0;
    assign new_pdst1_out = !dst1_effective_write ? 6'd0 :
                           dst0_effective_write ? second_free_tag :
                           first_free_tag;

    assign old_pdst0_out = rat_map[dst0_arch_in];
    assign old_pdst1_out = dst0_effective_write &&
                           dst1_effective_write &&
                           (dst1_arch_in == dst0_arch_in) ?
                           new_pdst0_out : rat_map[dst1_arch_in];

    assign src0_1_tag_out = src0_1_used_in ?
                            rat_map[src0_1_addr_in] : 6'd0;
    assign src0_2_tag_out = src0_2_used_in ?
                            rat_map[src0_2_addr_in] : 6'd0;

    assign src1_1_tag_out = !src1_1_used_in ? 6'd0 :
                            (dst0_effective_write &&
                             (src1_1_addr_in == dst0_arch_in)) ?
                            new_pdst0_out : rat_map[src1_1_addr_in];
    assign src1_2_tag_out = !src1_2_used_in ? 6'd0 :
                            (dst0_effective_write &&
                             (src1_2_addr_in == dst0_arch_in)) ?
                            new_pdst0_out : rat_map[src1_2_addr_in];

    reg [5:0] recovery_map [0:31];
    reg [47:0] recovery_free_mask;
    integer recovery_index;

    always @(*) begin
        for (recovery_index = 0; recovery_index < 32;
             recovery_index = recovery_index + 1)
            recovery_map[recovery_index] = amt[recovery_index];

        if (commit0_map_write)
            recovery_map[commit0_arch_in] = commit0_pdst_in;
        if (commit1_map_write)
            recovery_map[commit1_arch_in] = commit1_pdst_in;
        recovery_map[0] = 6'd0;

        recovery_free_mask = {48{1'b1}};
        for (recovery_index = 0; recovery_index < 32;
             recovery_index = recovery_index + 1) begin
            if (recovery_map[recovery_index] < PHYS_REG_COUNT)
                recovery_free_mask[recovery_map[recovery_index]] = 1'b0;
        end
        recovery_free_mask[0] = 1'b0;
    end

    integer state_index;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (state_index = 0; state_index < 32;
                 state_index = state_index + 1) begin
                rat_map[state_index] <= state_index[5:0];
                amt[state_index] <= state_index[5:0];
            end
            free_mask <= 48'hffff_0000_0000;
        end
        else if (recovery_in) begin
            for (state_index = 0; state_index < 32;
                 state_index = state_index + 1) begin
                rat_map[state_index] <= recovery_map[state_index];
                amt[state_index] <= recovery_map[state_index];
            end
            free_mask <= recovery_free_mask;
        end
        else begin
            /* Commit is older than dispatch; lane 1 is the younger commit. */
            if (commit0_map_write) begin
                amt[commit0_arch_in] <= commit0_pdst_in;
                if ((commit0_old_pdst_in != 6'd0) &&
                    (commit0_old_pdst_in < PHYS_REG_COUNT))
                    free_mask[commit0_old_pdst_in] <= 1'b1;
            end
            if (commit1_map_write) begin
                amt[commit1_arch_in] <= commit1_pdst_in;
                if ((commit1_old_pdst_in != 6'd0) &&
                    (commit1_old_pdst_in < PHYS_REG_COUNT))
                    free_mask[commit1_old_pdst_in] <= 1'b1;
            end

            /* Dispatch writes follow commit and therefore win collisions. */
            if (dispatch0_fire && dst0_effective_write) begin
                rat_map[dst0_arch_in] <= new_pdst0_out;
                if ((new_pdst0_out != 6'd0) &&
                    (new_pdst0_out < PHYS_REG_COUNT))
                    free_mask[new_pdst0_out] <= 1'b0;
            end
            if (dispatch1_fire && dst1_effective_write) begin
                rat_map[dst1_arch_in] <= new_pdst1_out;
                if ((new_pdst1_out != 6'd0) &&
                    (new_pdst1_out < PHYS_REG_COUNT))
                    free_mask[new_pdst1_out] <= 1'b0;
            end

            rat_map[0] <= 6'd0;
            amt[0] <= 6'd0;
            free_mask[0] <= 1'b0;
        end
    end

`ifndef SYNTHESIS
    task read_amt;
        input [4:0] address;
        output [5:0] physical_tag;
        begin
            if (address == 5'd0)
                physical_tag = 6'd0;
            else
                physical_tag = amt[address];
        end
    endtask
`endif

endmodule
