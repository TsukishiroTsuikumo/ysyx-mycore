`timescale 1ns/1ps

// Combinational execution/control steering for the two directly-instantiated
// integer lanes.  Arithmetic remains in the original function-unit modules;
// this block only selects operands/results and records resolved control flow.
module controller (
    input             lane0_valid_in,
    input      [31:0] lane0_pc_in,
    input      [31:0] lane0_src2_in,
    input             lane0_sel_imm_in,
    input      [31:0] lane0_imm_in,
    input       [6:0] lane0_use_signal_in,
    input             lane0_is_branch_in,
    input             lane0_is_jal_in,
    input             lane0_is_jalr_in,
    input      [31:0] lane0_add_result_in,
    input             lane0_branch_taken_in,
    input      [31:0] lane0_alu_result_in,
    input      [31:0] lane0_shift_result_in,
    input      [31:0] lane0_imu_result_in,

    input             lane1_valid_in,
    input      [31:0] lane1_pc_in,
    input      [31:0] lane1_src2_in,
    input             lane1_sel_imm_in,
    input      [31:0] lane1_imm_in,
    input       [6:0] lane1_use_signal_in,
    input             lane1_is_branch_in,
    input             lane1_is_jal_in,
    input             lane1_is_jalr_in,
    input      [31:0] lane1_add_result_in,
    input             lane1_branch_taken_in,
    input      [31:0] lane1_alu_result_in,
    input      [31:0] lane1_shift_result_in,
    input      [31:0] lane1_imu_result_in,

    input             retire_recovery_in,
    input      [31:0] retire_target_in,

    output     [31:0] lane0_operand_b_out,
    output     [31:0] lane1_operand_b_out,
    output reg [31:0] lane0_value_out,
    output reg [31:0] lane1_value_out,
    output            lane0_complete_out,
    output            lane1_complete_out,
    output            lane0_control_out,
    output            lane1_control_out,
    output reg [31:0] lane0_target_out,
    output reg [31:0] lane1_target_out,
    output            lane0_mispredict_out,
    output            lane1_mispredict_out,
    output            redirect_valid_out,
    output     [31:0] redirect_target_out
);

    wire [31:0] lane0_sequential_pc;
    wire [31:0] lane1_sequential_pc;

    assign lane0_operand_b_out = lane0_sel_imm_in ?
                                 lane0_imm_in : lane0_src2_in;
    assign lane1_operand_b_out = lane1_sel_imm_in ?
                                 lane1_imm_in : lane1_src2_in;
    assign lane0_sequential_pc = lane0_pc_in + 32'd4;
    assign lane1_sequential_pc = lane1_pc_in + 32'd4;

    always @(*) begin
        lane0_value_out = 32'b0;
        if (lane0_is_jal_in || lane0_is_jalr_in)
            lane0_value_out = lane0_sequential_pc;
        else begin
            case (lane0_use_signal_in)
                7'b0000001: lane0_value_out = lane0_add_result_in;
                7'b0000010: lane0_value_out = lane0_alu_result_in;
                7'b0000100: lane0_value_out = lane0_shift_result_in;
                7'b1000000: lane0_value_out = lane0_imu_result_in;
                default:    lane0_value_out = 32'b0;
            endcase
        end
    end

    always @(*) begin
        lane1_value_out = 32'b0;
        if (lane1_is_jal_in || lane1_is_jalr_in)
            lane1_value_out = lane1_sequential_pc;
        else begin
            case (lane1_use_signal_in)
                7'b0000001: lane1_value_out = lane1_add_result_in;
                7'b0000010: lane1_value_out = lane1_alu_result_in;
                7'b0000100: lane1_value_out = lane1_shift_result_in;
                7'b1000000: lane1_value_out = lane1_imu_result_in;
                default:    lane1_value_out = 32'b0;
            endcase
        end
    end

    always @(*) begin
        lane0_target_out = lane0_sequential_pc;
        if (lane0_is_branch_in && lane0_branch_taken_in)
            lane0_target_out = lane0_pc_in + lane0_imm_in;
        else if (lane0_is_jal_in)
            lane0_target_out = lane0_pc_in + lane0_imm_in;
        else if (lane0_is_jalr_in)
            lane0_target_out = lane0_add_result_in & 32'hffff_fffe;
    end

    always @(*) begin
        lane1_target_out = lane1_sequential_pc;
        if (lane1_is_branch_in && lane1_branch_taken_in)
            lane1_target_out = lane1_pc_in + lane1_imm_in;
        else if (lane1_is_jal_in)
            lane1_target_out = lane1_pc_in + lane1_imm_in;
        else if (lane1_is_jalr_in)
            lane1_target_out = lane1_add_result_in & 32'hffff_fffe;
    end

    assign lane0_complete_out = lane0_valid_in;
    assign lane1_complete_out = lane1_valid_in;
    assign lane0_control_out = lane0_valid_in &&
        (lane0_is_branch_in || lane0_is_jal_in || lane0_is_jalr_in);
    assign lane1_control_out = lane1_valid_in &&
        (lane1_is_branch_in || lane1_is_jal_in || lane1_is_jalr_in);
    assign lane0_mispredict_out = lane0_control_out &&
                                  (lane0_target_out != lane0_sequential_pc);
    assign lane1_mispredict_out = lane1_control_out &&
                                  (lane1_target_out != lane1_sequential_pc);

    // Redirect is deliberately sourced by in-order ROB retirement, never by
    // speculative execution completion.
    assign redirect_valid_out = retire_recovery_in;
    assign redirect_target_out = retire_target_in;

endmodule
