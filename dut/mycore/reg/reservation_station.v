`timescale 1ns/1ps

/*
 * Twelve-entry unified reservation station.
 *
 * Up to two decoded and renamed instructions are inserted each cycle.  The
 * station stores the complete decoder payload, wakes operands from two CDBs,
 * and presents four independent oldest-ready candidates: two integer lanes,
 * one shared M lane, and one shared LSU address lane.  Integer entries remain
 * resident until their CDB grant arrives; M and LSU entries remain resident
 * until the corresponding consumer explicitly accepts or captures them.
 * Free slots are computed only from entries empty at the start of the cycle.
 */
module reservation_station (
    input             clk,
    input             reset,
    input             flush_in,

    input       [1:0] dispatch_count_in,

    input             dispatch0_enable_in,
    input      [63:0] dispatch0_seq_in,
    input       [2:0] dispatch0_rob_tag_in,
    input       [2:0] dispatch0_lsq_tag_in,
    input       [2:0] dispatch0_class_in,
    input      [31:0] dispatch0_pc_in,
    input      [31:0] dispatch0_instr_in,
    input             dispatch0_writes_pdst_in,
    input       [5:0] dispatch0_pdst_in,
    input             dispatch0_src1_used_in,
    input       [5:0] dispatch0_src1_tag_in,
    input             dispatch0_src1_ready_in,
    input      [31:0] dispatch0_src1_value_in,
    input             dispatch0_src2_used_in,
    input       [5:0] dispatch0_src2_tag_in,
    input             dispatch0_src2_ready_in,
    input      [31:0] dispatch0_src2_value_in,
    input             dispatch0_sel_imm_in,
    input      [31:0] dispatch0_imm_in,
    input       [6:0] dispatch0_use_signal_in,
    input       [2:0] dispatch0_adder_op_in,
    input       [1:0] dispatch0_shifter_op_in,
    input       [3:0] dispatch0_multiplier_op_in,
    input       [3:0] dispatch0_divider_op_in,
    input       [1:0] dispatch0_alu_op_in,
    input       [2:0] dispatch0_lsu_op_in,
    input       [1:0] dispatch0_imu_op_in,
    input             dispatch0_semantic_sel_rd_in,
    input             dispatch0_is_branch_in,
    input             dispatch0_is_jal_in,
    input             dispatch0_is_jalr_in,

    input             dispatch1_enable_in,
    input      [63:0] dispatch1_seq_in,
    input       [2:0] dispatch1_rob_tag_in,
    input       [2:0] dispatch1_lsq_tag_in,
    input       [2:0] dispatch1_class_in,
    input      [31:0] dispatch1_pc_in,
    input      [31:0] dispatch1_instr_in,
    input             dispatch1_writes_pdst_in,
    input       [5:0] dispatch1_pdst_in,
    input             dispatch1_src1_used_in,
    input       [5:0] dispatch1_src1_tag_in,
    input             dispatch1_src1_ready_in,
    input      [31:0] dispatch1_src1_value_in,
    input             dispatch1_src2_used_in,
    input       [5:0] dispatch1_src2_tag_in,
    input             dispatch1_src2_ready_in,
    input      [31:0] dispatch1_src2_value_in,
    input             dispatch1_sel_imm_in,
    input      [31:0] dispatch1_imm_in,
    input       [6:0] dispatch1_use_signal_in,
    input       [2:0] dispatch1_adder_op_in,
    input       [1:0] dispatch1_shifter_op_in,
    input       [3:0] dispatch1_multiplier_op_in,
    input       [3:0] dispatch1_divider_op_in,
    input       [1:0] dispatch1_alu_op_in,
    input       [2:0] dispatch1_lsu_op_in,
    input       [1:0] dispatch1_imu_op_in,
    input             dispatch1_semantic_sel_rd_in,
    input             dispatch1_is_branch_in,
    input             dispatch1_is_jal_in,
    input             dispatch1_is_jalr_in,

    input             cdb0_valid_in,
    input             cdb0_writes_pdst_in,
    input       [5:0] cdb0_pdst_in,
    input      [31:0] cdb0_value_in,
    input             cdb1_valid_in,
    input             cdb1_writes_pdst_in,
    input       [5:0] cdb1_pdst_in,
    input      [31:0] cdb1_value_in,

    output reg  [3:0] free_count_out,

    output            int0_valid_out,
    output     [63:0] int0_seq_out,
    output      [2:0] int0_rob_tag_out,
    output      [2:0] int0_lsq_tag_out,
    output      [2:0] int0_class_out,
    output     [31:0] int0_pc_out,
    output     [31:0] int0_instr_out,
    output            int0_writes_pdst_out,
    output      [5:0] int0_pdst_out,
    output            int0_src1_used_out,
    output      [5:0] int0_src1_tag_out,
    output            int0_src1_ready_out,
    output     [31:0] int0_src1_value_out,
    output            int0_src2_used_out,
    output      [5:0] int0_src2_tag_out,
    output            int0_src2_ready_out,
    output     [31:0] int0_src2_value_out,
    output            int0_sel_imm_out,
    output     [31:0] int0_imm_out,
    output      [6:0] int0_use_signal_out,
    output      [2:0] int0_adder_op_out,
    output      [1:0] int0_shifter_op_out,
    output      [3:0] int0_multiplier_op_out,
    output      [3:0] int0_divider_op_out,
    output      [1:0] int0_alu_op_out,
    output      [2:0] int0_lsu_op_out,
    output      [1:0] int0_imu_op_out,
    output            int0_semantic_sel_rd_out,
    output            int0_is_branch_out,
    output            int0_is_jal_out,
    output            int0_is_jalr_out,
    input             int0_grant_in,

    output            int1_valid_out,
    output     [63:0] int1_seq_out,
    output      [2:0] int1_rob_tag_out,
    output      [2:0] int1_lsq_tag_out,
    output      [2:0] int1_class_out,
    output     [31:0] int1_pc_out,
    output     [31:0] int1_instr_out,
    output            int1_writes_pdst_out,
    output      [5:0] int1_pdst_out,
    output            int1_src1_used_out,
    output      [5:0] int1_src1_tag_out,
    output            int1_src1_ready_out,
    output     [31:0] int1_src1_value_out,
    output            int1_src2_used_out,
    output      [5:0] int1_src2_tag_out,
    output            int1_src2_ready_out,
    output     [31:0] int1_src2_value_out,
    output            int1_sel_imm_out,
    output     [31:0] int1_imm_out,
    output      [6:0] int1_use_signal_out,
    output      [2:0] int1_adder_op_out,
    output      [1:0] int1_shifter_op_out,
    output      [3:0] int1_multiplier_op_out,
    output      [3:0] int1_divider_op_out,
    output      [1:0] int1_alu_op_out,
    output      [2:0] int1_lsu_op_out,
    output      [1:0] int1_imu_op_out,
    output            int1_semantic_sel_rd_out,
    output            int1_is_branch_out,
    output            int1_is_jal_out,
    output            int1_is_jalr_out,
    input             int1_grant_in,

    output            m_valid_out,
    output     [63:0] m_seq_out,
    output      [2:0] m_rob_tag_out,
    output      [2:0] m_lsq_tag_out,
    output      [2:0] m_class_out,
    output     [31:0] m_pc_out,
    output     [31:0] m_instr_out,
    output            m_writes_pdst_out,
    output      [5:0] m_pdst_out,
    output            m_src1_used_out,
    output      [5:0] m_src1_tag_out,
    output            m_src1_ready_out,
    output     [31:0] m_src1_value_out,
    output            m_src2_used_out,
    output      [5:0] m_src2_tag_out,
    output            m_src2_ready_out,
    output     [31:0] m_src2_value_out,
    output            m_sel_imm_out,
    output     [31:0] m_imm_out,
    output      [6:0] m_use_signal_out,
    output      [2:0] m_adder_op_out,
    output      [1:0] m_shifter_op_out,
    output      [3:0] m_multiplier_op_out,
    output      [3:0] m_divider_op_out,
    output      [1:0] m_alu_op_out,
    output      [2:0] m_lsu_op_out,
    output      [1:0] m_imu_op_out,
    output            m_semantic_sel_rd_out,
    output            m_is_branch_out,
    output            m_is_jal_out,
    output            m_is_jalr_out,
    input             m_accept_in,

    output            lsu_valid_out,
    output     [63:0] lsu_seq_out,
    output      [2:0] lsu_rob_tag_out,
    output      [2:0] lsu_lsq_tag_out,
    output      [2:0] lsu_class_out,
    output     [31:0] lsu_pc_out,
    output     [31:0] lsu_instr_out,
    output            lsu_writes_pdst_out,
    output      [5:0] lsu_pdst_out,
    output            lsu_src1_used_out,
    output      [5:0] lsu_src1_tag_out,
    output            lsu_src1_ready_out,
    output     [31:0] lsu_src1_value_out,
    output            lsu_src2_used_out,
    output      [5:0] lsu_src2_tag_out,
    output            lsu_src2_ready_out,
    output     [31:0] lsu_src2_value_out,
    output            lsu_sel_imm_out,
    output     [31:0] lsu_imm_out,
    output      [6:0] lsu_use_signal_out,
    output      [2:0] lsu_adder_op_out,
    output      [1:0] lsu_shifter_op_out,
    output      [3:0] lsu_multiplier_op_out,
    output      [3:0] lsu_divider_op_out,
    output      [1:0] lsu_alu_op_out,
    output      [2:0] lsu_lsu_op_out,
    output      [1:0] lsu_imu_op_out,
    output            lsu_semantic_sel_rd_out,
    output            lsu_is_branch_out,
    output            lsu_is_jal_out,
    output            lsu_is_jalr_out,
    input             lsu_capture_in
);

    localparam RS_DEPTH      = 12;
    localparam CLASS_ALU     = 3'd0;
    localparam CLASS_MULDIV  = 3'd1;
    localparam CLASS_LOAD    = 3'd2;
    localparam CLASS_STORE   = 3'd3;
    localparam CLASS_CONTROL = 3'd4;

    reg        valid_q [0:RS_DEPTH-1];
    reg [63:0] seq_q [0:RS_DEPTH-1];
    reg  [2:0] rob_tag_q [0:RS_DEPTH-1];
    reg  [2:0] lsq_tag_q [0:RS_DEPTH-1];
    reg  [2:0] class_q [0:RS_DEPTH-1];
    reg [31:0] pc_q [0:RS_DEPTH-1];
    reg [31:0] instr_q [0:RS_DEPTH-1];
    reg        writes_pdst_q [0:RS_DEPTH-1];
    reg  [5:0] pdst_q [0:RS_DEPTH-1];
    reg        src1_used_q [0:RS_DEPTH-1];
    reg  [5:0] src1_tag_q [0:RS_DEPTH-1];
    reg        src1_ready_q [0:RS_DEPTH-1];
    reg [31:0] src1_value_q [0:RS_DEPTH-1];
    reg        src2_used_q [0:RS_DEPTH-1];
    reg  [5:0] src2_tag_q [0:RS_DEPTH-1];
    reg        src2_ready_q [0:RS_DEPTH-1];
    reg [31:0] src2_value_q [0:RS_DEPTH-1];
    reg        sel_imm_q [0:RS_DEPTH-1];
    reg [31:0] imm_q [0:RS_DEPTH-1];
    reg  [6:0] use_signal_q [0:RS_DEPTH-1];
    reg  [2:0] adder_op_q [0:RS_DEPTH-1];
    reg  [1:0] shifter_op_q [0:RS_DEPTH-1];
    reg  [3:0] multiplier_op_q [0:RS_DEPTH-1];
    reg  [3:0] divider_op_q [0:RS_DEPTH-1];
    reg  [1:0] alu_op_q [0:RS_DEPTH-1];
    reg  [2:0] lsu_op_q [0:RS_DEPTH-1];
    reg  [1:0] imu_op_q [0:RS_DEPTH-1];
    reg        semantic_sel_rd_q [0:RS_DEPTH-1];
    reg        is_branch_q [0:RS_DEPTH-1];
    reg        is_jal_q [0:RS_DEPTH-1];
    reg        is_jalr_q [0:RS_DEPTH-1];

    wire enqueue0;
    wire enqueue1;
    integer free_scan_index;
    reg [3:0] free_index0;
    reg [3:0] free_index1;
    reg free_index0_found;
    reg free_index1_found;

    reg int0_found;
    reg int1_found;
    reg m_found;
    reg lsu_found;
    reg [3:0] int0_index;
    reg [3:0] int1_index;
    reg [3:0] m_index;
    reg [3:0] lsu_index;
    reg [63:0] int0_best_seq;
    reg [63:0] int1_best_seq;
    reg [63:0] m_best_seq;
    reg [63:0] lsu_best_seq;
    integer select_index;
    integer state_index;

    assign enqueue0 = (dispatch_count_in != 2'd0) &&
                      dispatch0_enable_in;
    assign enqueue1 = (dispatch_count_in == 2'd2) &&
                      dispatch1_enable_in;

    always @(*) begin
        free_count_out = 4'b0;
        free_index0 = 4'b0;
        free_index1 = 4'b0;
        free_index0_found = 1'b0;
        free_index1_found = 1'b0;
        for (free_scan_index = 0; free_scan_index < RS_DEPTH;
             free_scan_index = free_scan_index + 1) begin
            if (!valid_q[free_scan_index]) begin
                free_count_out = free_count_out + 4'd1;
                if (!free_index0_found) begin
                    free_index0 = free_scan_index[3:0];
                    free_index0_found = 1'b1;
                end
                else if (!free_index1_found) begin
                    free_index1 = free_scan_index[3:0];
                    free_index1_found = 1'b1;
                end
            end
        end
    end

    always @(*) begin
        int0_found = 1'b0;
        int1_found = 1'b0;
        m_found = 1'b0;
        lsu_found = 1'b0;
        int0_index = 4'b0;
        int1_index = 4'b0;
        m_index = 4'b0;
        lsu_index = 4'b0;
        int0_best_seq = 64'b0;
        int1_best_seq = 64'b0;
        m_best_seq = 64'b0;
        lsu_best_seq = 64'b0;

        for (select_index = 0; select_index < RS_DEPTH;
             select_index = select_index + 1) begin
            if (valid_q[select_index] &&
                (!src1_used_q[select_index] || src1_ready_q[select_index]) &&
                (!src2_used_q[select_index] || src2_ready_q[select_index]) &&
                ((class_q[select_index] == CLASS_ALU) ||
                 (class_q[select_index] == CLASS_CONTROL))) begin
                if (!int0_found || (seq_q[select_index] < int0_best_seq)) begin
                    int0_found = 1'b1;
                    int0_index = select_index[3:0];
                    int0_best_seq = seq_q[select_index];
                end
            end
        end

        for (select_index = 0; select_index < RS_DEPTH;
             select_index = select_index + 1) begin
            if (valid_q[select_index] &&
                (!src1_used_q[select_index] || src1_ready_q[select_index]) &&
                (!src2_used_q[select_index] || src2_ready_q[select_index]) &&
                (class_q[select_index] == CLASS_ALU) &&
                (!int0_found || (select_index[3:0] != int0_index))) begin
                if (!int1_found || (seq_q[select_index] < int1_best_seq)) begin
                    int1_found = 1'b1;
                    int1_index = select_index[3:0];
                    int1_best_seq = seq_q[select_index];
                end
            end
        end

        for (select_index = 0; select_index < RS_DEPTH;
             select_index = select_index + 1) begin
            if (valid_q[select_index] &&
                (!src1_used_q[select_index] || src1_ready_q[select_index]) &&
                (!src2_used_q[select_index] || src2_ready_q[select_index]) &&
                (class_q[select_index] == CLASS_MULDIV)) begin
                if (!m_found || (seq_q[select_index] < m_best_seq)) begin
                    m_found = 1'b1;
                    m_index = select_index[3:0];
                    m_best_seq = seq_q[select_index];
                end
            end
        end

        for (select_index = 0; select_index < RS_DEPTH;
             select_index = select_index + 1) begin
            if (valid_q[select_index] &&
                (!src1_used_q[select_index] || src1_ready_q[select_index]) &&
                (!src2_used_q[select_index] || src2_ready_q[select_index]) &&
                ((class_q[select_index] == CLASS_LOAD) ||
                 (class_q[select_index] == CLASS_STORE))) begin
                if (!lsu_found || (seq_q[select_index] < lsu_best_seq)) begin
                    lsu_found = 1'b1;
                    lsu_index = select_index[3:0];
                    lsu_best_seq = seq_q[select_index];
                end
            end
        end
    end

    assign int0_valid_out = int0_found && !flush_in;
    assign int0_seq_out = int0_found ? seq_q[int0_index] : 64'b0;
    assign int0_rob_tag_out = int0_found ? rob_tag_q[int0_index] : 3'b0;
    assign int0_lsq_tag_out = int0_found ? lsq_tag_q[int0_index] : 3'b0;
    assign int0_class_out = int0_found ? class_q[int0_index] : 3'b0;
    assign int0_pc_out = int0_found ? pc_q[int0_index] : 32'b0;
    assign int0_instr_out = int0_found ? instr_q[int0_index] : 32'h0000_0013;
    assign int0_writes_pdst_out = int0_found && writes_pdst_q[int0_index];
    assign int0_pdst_out = int0_found ? pdst_q[int0_index] : 6'b0;
    assign int0_src1_used_out = int0_found && src1_used_q[int0_index];
    assign int0_src1_tag_out = int0_found ? src1_tag_q[int0_index] : 6'b0;
    assign int0_src1_ready_out = int0_found && src1_ready_q[int0_index];
    assign int0_src1_value_out = int0_found ? src1_value_q[int0_index] : 32'b0;
    assign int0_src2_used_out = int0_found && src2_used_q[int0_index];
    assign int0_src2_tag_out = int0_found ? src2_tag_q[int0_index] : 6'b0;
    assign int0_src2_ready_out = int0_found && src2_ready_q[int0_index];
    assign int0_src2_value_out = int0_found ? src2_value_q[int0_index] : 32'b0;
    assign int0_sel_imm_out = int0_found && sel_imm_q[int0_index];
    assign int0_imm_out = int0_found ? imm_q[int0_index] : 32'b0;
    assign int0_use_signal_out = int0_found ? use_signal_q[int0_index] : 7'b0;
    assign int0_adder_op_out = int0_found ? adder_op_q[int0_index] : 3'b0;
    assign int0_shifter_op_out = int0_found ? shifter_op_q[int0_index] : 2'b0;
    assign int0_multiplier_op_out = int0_found ? multiplier_op_q[int0_index] : 4'b0;
    assign int0_divider_op_out = int0_found ? divider_op_q[int0_index] : 4'b0;
    assign int0_alu_op_out = int0_found ? alu_op_q[int0_index] : 2'b0;
    assign int0_lsu_op_out = int0_found ? lsu_op_q[int0_index] : 3'b0;
    assign int0_imu_op_out = int0_found ? imu_op_q[int0_index] : 2'b0;
    assign int0_semantic_sel_rd_out = int0_found && semantic_sel_rd_q[int0_index];
    assign int0_is_branch_out = int0_found && is_branch_q[int0_index];
    assign int0_is_jal_out = int0_found && is_jal_q[int0_index];
    assign int0_is_jalr_out = int0_found && is_jalr_q[int0_index];

    assign int1_valid_out = int1_found && !flush_in;
    assign int1_seq_out = int1_found ? seq_q[int1_index] : 64'b0;
    assign int1_rob_tag_out = int1_found ? rob_tag_q[int1_index] : 3'b0;
    assign int1_lsq_tag_out = int1_found ? lsq_tag_q[int1_index] : 3'b0;
    assign int1_class_out = int1_found ? class_q[int1_index] : 3'b0;
    assign int1_pc_out = int1_found ? pc_q[int1_index] : 32'b0;
    assign int1_instr_out = int1_found ? instr_q[int1_index] : 32'h0000_0013;
    assign int1_writes_pdst_out = int1_found && writes_pdst_q[int1_index];
    assign int1_pdst_out = int1_found ? pdst_q[int1_index] : 6'b0;
    assign int1_src1_used_out = int1_found && src1_used_q[int1_index];
    assign int1_src1_tag_out = int1_found ? src1_tag_q[int1_index] : 6'b0;
    assign int1_src1_ready_out = int1_found && src1_ready_q[int1_index];
    assign int1_src1_value_out = int1_found ? src1_value_q[int1_index] : 32'b0;
    assign int1_src2_used_out = int1_found && src2_used_q[int1_index];
    assign int1_src2_tag_out = int1_found ? src2_tag_q[int1_index] : 6'b0;
    assign int1_src2_ready_out = int1_found && src2_ready_q[int1_index];
    assign int1_src2_value_out = int1_found ? src2_value_q[int1_index] : 32'b0;
    assign int1_sel_imm_out = int1_found && sel_imm_q[int1_index];
    assign int1_imm_out = int1_found ? imm_q[int1_index] : 32'b0;
    assign int1_use_signal_out = int1_found ? use_signal_q[int1_index] : 7'b0;
    assign int1_adder_op_out = int1_found ? adder_op_q[int1_index] : 3'b0;
    assign int1_shifter_op_out = int1_found ? shifter_op_q[int1_index] : 2'b0;
    assign int1_multiplier_op_out = int1_found ? multiplier_op_q[int1_index] : 4'b0;
    assign int1_divider_op_out = int1_found ? divider_op_q[int1_index] : 4'b0;
    assign int1_alu_op_out = int1_found ? alu_op_q[int1_index] : 2'b0;
    assign int1_lsu_op_out = int1_found ? lsu_op_q[int1_index] : 3'b0;
    assign int1_imu_op_out = int1_found ? imu_op_q[int1_index] : 2'b0;
    assign int1_semantic_sel_rd_out = int1_found && semantic_sel_rd_q[int1_index];
    assign int1_is_branch_out = int1_found && is_branch_q[int1_index];
    assign int1_is_jal_out = int1_found && is_jal_q[int1_index];
    assign int1_is_jalr_out = int1_found && is_jalr_q[int1_index];

    assign m_valid_out = m_found && !flush_in;
    assign m_seq_out = m_found ? seq_q[m_index] : 64'b0;
    assign m_rob_tag_out = m_found ? rob_tag_q[m_index] : 3'b0;
    assign m_lsq_tag_out = m_found ? lsq_tag_q[m_index] : 3'b0;
    assign m_class_out = m_found ? class_q[m_index] : 3'b0;
    assign m_pc_out = m_found ? pc_q[m_index] : 32'b0;
    assign m_instr_out = m_found ? instr_q[m_index] : 32'h0000_0013;
    assign m_writes_pdst_out = m_found && writes_pdst_q[m_index];
    assign m_pdst_out = m_found ? pdst_q[m_index] : 6'b0;
    assign m_src1_used_out = m_found && src1_used_q[m_index];
    assign m_src1_tag_out = m_found ? src1_tag_q[m_index] : 6'b0;
    assign m_src1_ready_out = m_found && src1_ready_q[m_index];
    assign m_src1_value_out = m_found ? src1_value_q[m_index] : 32'b0;
    assign m_src2_used_out = m_found && src2_used_q[m_index];
    assign m_src2_tag_out = m_found ? src2_tag_q[m_index] : 6'b0;
    assign m_src2_ready_out = m_found && src2_ready_q[m_index];
    assign m_src2_value_out = m_found ? src2_value_q[m_index] : 32'b0;
    assign m_sel_imm_out = m_found && sel_imm_q[m_index];
    assign m_imm_out = m_found ? imm_q[m_index] : 32'b0;
    assign m_use_signal_out = m_found ? use_signal_q[m_index] : 7'b0;
    assign m_adder_op_out = m_found ? adder_op_q[m_index] : 3'b0;
    assign m_shifter_op_out = m_found ? shifter_op_q[m_index] : 2'b0;
    assign m_multiplier_op_out = m_found ? multiplier_op_q[m_index] : 4'b0;
    assign m_divider_op_out = m_found ? divider_op_q[m_index] : 4'b0;
    assign m_alu_op_out = m_found ? alu_op_q[m_index] : 2'b0;
    assign m_lsu_op_out = m_found ? lsu_op_q[m_index] : 3'b0;
    assign m_imu_op_out = m_found ? imu_op_q[m_index] : 2'b0;
    assign m_semantic_sel_rd_out = m_found && semantic_sel_rd_q[m_index];
    assign m_is_branch_out = m_found && is_branch_q[m_index];
    assign m_is_jal_out = m_found && is_jal_q[m_index];
    assign m_is_jalr_out = m_found && is_jalr_q[m_index];

    assign lsu_valid_out = lsu_found && !flush_in;
    assign lsu_seq_out = lsu_found ? seq_q[lsu_index] : 64'b0;
    assign lsu_rob_tag_out = lsu_found ? rob_tag_q[lsu_index] : 3'b0;
    assign lsu_lsq_tag_out = lsu_found ? lsq_tag_q[lsu_index] : 3'b0;
    assign lsu_class_out = lsu_found ? class_q[lsu_index] : 3'b0;
    assign lsu_pc_out = lsu_found ? pc_q[lsu_index] : 32'b0;
    assign lsu_instr_out = lsu_found ? instr_q[lsu_index] : 32'h0000_0013;
    assign lsu_writes_pdst_out = lsu_found && writes_pdst_q[lsu_index];
    assign lsu_pdst_out = lsu_found ? pdst_q[lsu_index] : 6'b0;
    assign lsu_src1_used_out = lsu_found && src1_used_q[lsu_index];
    assign lsu_src1_tag_out = lsu_found ? src1_tag_q[lsu_index] : 6'b0;
    assign lsu_src1_ready_out = lsu_found && src1_ready_q[lsu_index];
    assign lsu_src1_value_out = lsu_found ? src1_value_q[lsu_index] : 32'b0;
    assign lsu_src2_used_out = lsu_found && src2_used_q[lsu_index];
    assign lsu_src2_tag_out = lsu_found ? src2_tag_q[lsu_index] : 6'b0;
    assign lsu_src2_ready_out = lsu_found && src2_ready_q[lsu_index];
    assign lsu_src2_value_out = lsu_found ? src2_value_q[lsu_index] : 32'b0;
    assign lsu_sel_imm_out = lsu_found && sel_imm_q[lsu_index];
    assign lsu_imm_out = lsu_found ? imm_q[lsu_index] : 32'b0;
    assign lsu_use_signal_out = lsu_found ? use_signal_q[lsu_index] : 7'b0;
    assign lsu_adder_op_out = lsu_found ? adder_op_q[lsu_index] : 3'b0;
    assign lsu_shifter_op_out = lsu_found ? shifter_op_q[lsu_index] : 2'b0;
    assign lsu_multiplier_op_out = lsu_found ? multiplier_op_q[lsu_index] : 4'b0;
    assign lsu_divider_op_out = lsu_found ? divider_op_q[lsu_index] : 4'b0;
    assign lsu_alu_op_out = lsu_found ? alu_op_q[lsu_index] : 2'b0;
    assign lsu_lsu_op_out = lsu_found ? lsu_op_q[lsu_index] : 3'b0;
    assign lsu_imu_op_out = lsu_found ? imu_op_q[lsu_index] : 2'b0;
    assign lsu_semantic_sel_rd_out = lsu_found && semantic_sel_rd_q[lsu_index];
    assign lsu_is_branch_out = lsu_found && is_branch_q[lsu_index];
    assign lsu_is_jal_out = lsu_found && is_jal_q[lsu_index];
    assign lsu_is_jalr_out = lsu_found && is_jalr_q[lsu_index];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (state_index = 0; state_index < RS_DEPTH;
                 state_index = state_index + 1) begin
                valid_q[state_index] <= 1'b0;
                seq_q[state_index] <= 64'b0;
                rob_tag_q[state_index] <= 3'b0;
                lsq_tag_q[state_index] <= 3'b0;
                class_q[state_index] <= CLASS_ALU;
                pc_q[state_index] <= 32'b0;
                instr_q[state_index] <= 32'h0000_0013;
                writes_pdst_q[state_index] <= 1'b0;
                pdst_q[state_index] <= 6'b0;
                src1_used_q[state_index] <= 1'b0;
                src1_tag_q[state_index] <= 6'b0;
                src1_ready_q[state_index] <= 1'b1;
                src1_value_q[state_index] <= 32'b0;
                src2_used_q[state_index] <= 1'b0;
                src2_tag_q[state_index] <= 6'b0;
                src2_ready_q[state_index] <= 1'b1;
                src2_value_q[state_index] <= 32'b0;
                sel_imm_q[state_index] <= 1'b0;
                imm_q[state_index] <= 32'b0;
                use_signal_q[state_index] <= 7'b0;
                adder_op_q[state_index] <= 3'b0;
                shifter_op_q[state_index] <= 2'b0;
                multiplier_op_q[state_index] <= 4'b0;
                divider_op_q[state_index] <= 4'b0;
                alu_op_q[state_index] <= 2'b0;
                lsu_op_q[state_index] <= 3'b0;
                imu_op_q[state_index] <= 2'b0;
                semantic_sel_rd_q[state_index] <= 1'b0;
                is_branch_q[state_index] <= 1'b0;
                is_jal_q[state_index] <= 1'b0;
                is_jalr_q[state_index] <= 1'b0;
            end
        end
        else if (flush_in) begin
            for (state_index = 0; state_index < RS_DEPTH;
                 state_index = state_index + 1)
                valid_q[state_index] <= 1'b0;
        end
        else begin
            for (state_index = 0; state_index < RS_DEPTH;
                 state_index = state_index + 1) begin
                if (valid_q[state_index]) begin
                    if (cdb0_valid_in && cdb0_writes_pdst_in &&
                        (src1_tag_q[state_index] == cdb0_pdst_in) &&
                        src1_used_q[state_index] &&
                        !src1_ready_q[state_index]) begin
                        src1_ready_q[state_index] <= 1'b1;
                        src1_value_q[state_index] <= cdb0_value_in;
                    end
                    if (cdb0_valid_in && cdb0_writes_pdst_in &&
                        (src2_tag_q[state_index] == cdb0_pdst_in) &&
                        src2_used_q[state_index] &&
                        !src2_ready_q[state_index]) begin
                        src2_ready_q[state_index] <= 1'b1;
                        src2_value_q[state_index] <= cdb0_value_in;
                    end
                    if (cdb1_valid_in && cdb1_writes_pdst_in &&
                        (src1_tag_q[state_index] == cdb1_pdst_in) &&
                        src1_used_q[state_index] &&
                        !src1_ready_q[state_index]) begin
                        src1_ready_q[state_index] <= 1'b1;
                        src1_value_q[state_index] <= cdb1_value_in;
                    end
                    if (cdb1_valid_in && cdb1_writes_pdst_in &&
                        (src2_tag_q[state_index] == cdb1_pdst_in) &&
                        src2_used_q[state_index] &&
                        !src2_ready_q[state_index]) begin
                        src2_ready_q[state_index] <= 1'b1;
                        src2_value_q[state_index] <= cdb1_value_in;
                    end
                end
            end

            if (int0_found && int0_grant_in)
                valid_q[int0_index] <= 1'b0;
            if (int1_found && int1_grant_in)
                valid_q[int1_index] <= 1'b0;
            if (m_found && m_accept_in)
                valid_q[m_index] <= 1'b0;
            if (lsu_found && lsu_capture_in)
                valid_q[lsu_index] <= 1'b0;

            if (enqueue0 && free_index0_found) begin
                valid_q[free_index0] <= 1'b1;
                seq_q[free_index0] <= dispatch0_seq_in;
                rob_tag_q[free_index0] <= dispatch0_rob_tag_in;
                lsq_tag_q[free_index0] <= dispatch0_lsq_tag_in;
                class_q[free_index0] <= dispatch0_class_in;
                pc_q[free_index0] <= dispatch0_pc_in;
                instr_q[free_index0] <= dispatch0_instr_in;
                writes_pdst_q[free_index0] <= dispatch0_writes_pdst_in;
                pdst_q[free_index0] <= dispatch0_pdst_in;
                src1_used_q[free_index0] <= dispatch0_src1_used_in;
                src1_tag_q[free_index0] <= dispatch0_src1_tag_in;
                src1_ready_q[free_index0] <= dispatch0_src1_ready_in;
                src1_value_q[free_index0] <= dispatch0_src1_value_in;
                src2_used_q[free_index0] <= dispatch0_src2_used_in;
                src2_tag_q[free_index0] <= dispatch0_src2_tag_in;
                src2_ready_q[free_index0] <= dispatch0_src2_ready_in;
                src2_value_q[free_index0] <= dispatch0_src2_value_in;
                sel_imm_q[free_index0] <= dispatch0_sel_imm_in;
                imm_q[free_index0] <= dispatch0_imm_in;
                use_signal_q[free_index0] <= dispatch0_use_signal_in;
                adder_op_q[free_index0] <= dispatch0_adder_op_in;
                shifter_op_q[free_index0] <= dispatch0_shifter_op_in;
                multiplier_op_q[free_index0] <= dispatch0_multiplier_op_in;
                divider_op_q[free_index0] <= dispatch0_divider_op_in;
                alu_op_q[free_index0] <= dispatch0_alu_op_in;
                lsu_op_q[free_index0] <= dispatch0_lsu_op_in;
                imu_op_q[free_index0] <= dispatch0_imu_op_in;
                semantic_sel_rd_q[free_index0] <=
                    dispatch0_semantic_sel_rd_in;
                is_branch_q[free_index0] <= dispatch0_is_branch_in;
                is_jal_q[free_index0] <= dispatch0_is_jal_in;
                is_jalr_q[free_index0] <= dispatch0_is_jalr_in;
            end

            if (enqueue1) begin
                if (enqueue0 && free_index1_found) begin
                    valid_q[free_index1] <= 1'b1;
                    seq_q[free_index1] <= dispatch1_seq_in;
                    rob_tag_q[free_index1] <= dispatch1_rob_tag_in;
                    lsq_tag_q[free_index1] <= dispatch1_lsq_tag_in;
                    class_q[free_index1] <= dispatch1_class_in;
                    pc_q[free_index1] <= dispatch1_pc_in;
                    instr_q[free_index1] <= dispatch1_instr_in;
                    writes_pdst_q[free_index1] <= dispatch1_writes_pdst_in;
                    pdst_q[free_index1] <= dispatch1_pdst_in;
                    src1_used_q[free_index1] <= dispatch1_src1_used_in;
                    src1_tag_q[free_index1] <= dispatch1_src1_tag_in;
                    src1_ready_q[free_index1] <= dispatch1_src1_ready_in;
                    src1_value_q[free_index1] <= dispatch1_src1_value_in;
                    src2_used_q[free_index1] <= dispatch1_src2_used_in;
                    src2_tag_q[free_index1] <= dispatch1_src2_tag_in;
                    src2_ready_q[free_index1] <= dispatch1_src2_ready_in;
                    src2_value_q[free_index1] <= dispatch1_src2_value_in;
                    sel_imm_q[free_index1] <= dispatch1_sel_imm_in;
                    imm_q[free_index1] <= dispatch1_imm_in;
                    use_signal_q[free_index1] <= dispatch1_use_signal_in;
                    adder_op_q[free_index1] <= dispatch1_adder_op_in;
                    shifter_op_q[free_index1] <= dispatch1_shifter_op_in;
                    multiplier_op_q[free_index1] <= dispatch1_multiplier_op_in;
                    divider_op_q[free_index1] <= dispatch1_divider_op_in;
                    alu_op_q[free_index1] <= dispatch1_alu_op_in;
                    lsu_op_q[free_index1] <= dispatch1_lsu_op_in;
                    imu_op_q[free_index1] <= dispatch1_imu_op_in;
                    semantic_sel_rd_q[free_index1] <=
                        dispatch1_semantic_sel_rd_in;
                    is_branch_q[free_index1] <= dispatch1_is_branch_in;
                    is_jal_q[free_index1] <= dispatch1_is_jal_in;
                    is_jalr_q[free_index1] <= dispatch1_is_jalr_in;
                end
                else if (!enqueue0 && free_index0_found) begin
                    valid_q[free_index0] <= 1'b1;
                    seq_q[free_index0] <= dispatch1_seq_in;
                    rob_tag_q[free_index0] <= dispatch1_rob_tag_in;
                    lsq_tag_q[free_index0] <= dispatch1_lsq_tag_in;
                    class_q[free_index0] <= dispatch1_class_in;
                    pc_q[free_index0] <= dispatch1_pc_in;
                    instr_q[free_index0] <= dispatch1_instr_in;
                    writes_pdst_q[free_index0] <= dispatch1_writes_pdst_in;
                    pdst_q[free_index0] <= dispatch1_pdst_in;
                    src1_used_q[free_index0] <= dispatch1_src1_used_in;
                    src1_tag_q[free_index0] <= dispatch1_src1_tag_in;
                    src1_ready_q[free_index0] <= dispatch1_src1_ready_in;
                    src1_value_q[free_index0] <= dispatch1_src1_value_in;
                    src2_used_q[free_index0] <= dispatch1_src2_used_in;
                    src2_tag_q[free_index0] <= dispatch1_src2_tag_in;
                    src2_ready_q[free_index0] <= dispatch1_src2_ready_in;
                    src2_value_q[free_index0] <= dispatch1_src2_value_in;
                    sel_imm_q[free_index0] <= dispatch1_sel_imm_in;
                    imm_q[free_index0] <= dispatch1_imm_in;
                    use_signal_q[free_index0] <= dispatch1_use_signal_in;
                    adder_op_q[free_index0] <= dispatch1_adder_op_in;
                    shifter_op_q[free_index0] <= dispatch1_shifter_op_in;
                    multiplier_op_q[free_index0] <= dispatch1_multiplier_op_in;
                    divider_op_q[free_index0] <= dispatch1_divider_op_in;
                    alu_op_q[free_index0] <= dispatch1_alu_op_in;
                    lsu_op_q[free_index0] <= dispatch1_lsu_op_in;
                    imu_op_q[free_index0] <= dispatch1_imu_op_in;
                    semantic_sel_rd_q[free_index0] <=
                        dispatch1_semantic_sel_rd_in;
                    is_branch_q[free_index0] <= dispatch1_is_branch_in;
                    is_jal_q[free_index0] <= dispatch1_is_jal_in;
                    is_jalr_q[free_index0] <= dispatch1_is_jalr_in;
                end
            end
        end
    end

endmodule
