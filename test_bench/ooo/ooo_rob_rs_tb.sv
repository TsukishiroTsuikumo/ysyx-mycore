`timescale 1ns/1ps

module ooo_rob_rs_tb;

    localparam logic [2:0] CLASS_ALU     = 3'd0;
    localparam logic [2:0] CLASS_MULDIV  = 3'd1;
    localparam logic [2:0] CLASS_LOAD    = 3'd2;
    localparam logic [2:0] CLASS_CONTROL = 3'd4;

    logic clk;
    logic rob_reset;
    logic rs_reset;
    integer errors;

    logic [1:0] rob_dispatch_count;
    logic rob_alloc0_supported;
    logic [31:0] rob_alloc0_pc;
    logic [31:0] rob_alloc0_instr;
    logic rob_alloc0_reports_rd;
    logic rob_alloc0_writes_rd;
    logic [4:0] rob_alloc0_arch_rd;
    logic [5:0] rob_alloc0_pdst;
    logic [5:0] rob_alloc0_old_pdst;
    logic rob_alloc0_is_control;
    logic rob_alloc0_is_fence;
    logic rob_alloc0_is_store;
    logic rob_alloc1_supported;
    logic [31:0] rob_alloc1_pc;
    logic [31:0] rob_alloc1_instr;
    logic rob_alloc1_reports_rd;
    logic rob_alloc1_writes_rd;
    logic [4:0] rob_alloc1_arch_rd;
    logic [5:0] rob_alloc1_pdst;
    logic [5:0] rob_alloc1_old_pdst;
    logic rob_alloc1_is_control;
    logic rob_alloc1_is_fence;
    logic rob_alloc1_is_store;
    wire [2:0] rob_alloc_tag0;
    wire [2:0] rob_alloc_tag1;
    wire [63:0] rob_alloc_seq0;
    wire [63:0] rob_alloc_seq1;
    wire [3:0] rob_count;
    wire [3:0] rob_free_count;
    wire rob_any_control;
    wire rob_any_fence;
    wire rob_head_valid;
    wire [2:0] rob_head_tag;
    wire rob_head_is_store;
    wire rob_head_is_fence;
    wire rob_barrier_valid;
    wire [63:0] rob_barrier_seq;
    logic rob_cdb0_valid;
    logic [2:0] rob_cdb0_tag;
    logic [31:0] rob_cdb0_value;
    logic rob_cdb0_control;
    logic [31:0] rob_cdb0_target;
    logic rob_cdb0_mispredict;
    logic rob_cdb1_valid;
    logic [2:0] rob_cdb1_tag;
    logic [31:0] rob_cdb1_value;
    logic rob_cdb1_control;
    logic [31:0] rob_cdb1_target;
    logic rob_cdb1_mispredict;
    logic rob_store_complete_valid;
    logic [2:0] rob_store_complete_tag;
    logic rob_fence_can_complete;
    wire rob_recovery;
    wire [31:0] rob_recovery_target;
    wire rob_commit0_valid;
    wire rob_commit0_writes;
    wire [4:0] rob_commit0_arch;
    wire [5:0] rob_commit0_pdst;
    wire [5:0] rob_commit0_old_pdst;
    wire rob_commit1_valid;
    wire rob_commit1_writes;
    wire [4:0] rob_commit1_arch;
    wire [5:0] rob_commit1_pdst;
    wire [5:0] rob_commit1_old_pdst;
    wire [1:0] rob_retire_valid;
    wire [63:0] rob_retire_pc;
    wire [63:0] rob_retire_instr;
    wire [1:0] rob_retire_rd_write;
    wire [9:0] rob_retire_rd_addr;
    wire [63:0] rob_retire_rd_data;

    rob u_rob (
        .clk                         (clk),
        .reset                       (rob_reset),
        .dispatch_count_in           (rob_dispatch_count),
        .alloc0_supported_in         (rob_alloc0_supported),
        .alloc0_pc_in                (rob_alloc0_pc),
        .alloc0_instr_in             (rob_alloc0_instr),
        .alloc0_reports_rd_in        (rob_alloc0_reports_rd),
        .alloc0_writes_rd_in         (rob_alloc0_writes_rd),
        .alloc0_arch_rd_in           (rob_alloc0_arch_rd),
        .alloc0_pdst_in              (rob_alloc0_pdst),
        .alloc0_old_pdst_in          (rob_alloc0_old_pdst),
        .alloc0_is_control_in        (rob_alloc0_is_control),
        .alloc0_is_fence_in          (rob_alloc0_is_fence),
        .alloc0_is_store_in          (rob_alloc0_is_store),
        .alloc1_supported_in         (rob_alloc1_supported),
        .alloc1_pc_in                (rob_alloc1_pc),
        .alloc1_instr_in             (rob_alloc1_instr),
        .alloc1_reports_rd_in        (rob_alloc1_reports_rd),
        .alloc1_writes_rd_in         (rob_alloc1_writes_rd),
        .alloc1_arch_rd_in           (rob_alloc1_arch_rd),
        .alloc1_pdst_in              (rob_alloc1_pdst),
        .alloc1_old_pdst_in          (rob_alloc1_old_pdst),
        .alloc1_is_control_in        (rob_alloc1_is_control),
        .alloc1_is_fence_in          (rob_alloc1_is_fence),
        .alloc1_is_store_in          (rob_alloc1_is_store),
        .alloc_tag0_out              (rob_alloc_tag0),
        .alloc_tag1_out              (rob_alloc_tag1),
        .alloc_seq0_out              (rob_alloc_seq0),
        .alloc_seq1_out              (rob_alloc_seq1),
        .rob_count_out               (rob_count),
        .free_count_out              (rob_free_count),
        .any_control_out             (rob_any_control),
        .any_fence_out               (rob_any_fence),
        .head_valid_out              (rob_head_valid),
        .head_tag_out                (rob_head_tag),
        .head_is_store_out           (rob_head_is_store),
        .head_is_fence_out           (rob_head_is_fence),
        .barrier_valid_out           (rob_barrier_valid),
        .barrier_seq_out             (rob_barrier_seq),
        .cdb0_valid_in               (rob_cdb0_valid),
        .cdb0_rob_tag_in             (rob_cdb0_tag),
        .cdb0_value_in               (rob_cdb0_value),
        .cdb0_control_in             (rob_cdb0_control),
        .cdb0_target_in              (rob_cdb0_target),
        .cdb0_mispredict_in          (rob_cdb0_mispredict),
        .cdb1_valid_in               (rob_cdb1_valid),
        .cdb1_rob_tag_in             (rob_cdb1_tag),
        .cdb1_value_in               (rob_cdb1_value),
        .cdb1_control_in             (rob_cdb1_control),
        .cdb1_target_in              (rob_cdb1_target),
        .cdb1_mispredict_in          (rob_cdb1_mispredict),
        .store_complete_valid_in     (rob_store_complete_valid),
        .store_complete_rob_tag_in   (rob_store_complete_tag),
        .fence_can_complete_in       (rob_fence_can_complete),
        .recovery_out                (rob_recovery),
        .recovery_target_out         (rob_recovery_target),
        .commit0_valid_out           (rob_commit0_valid),
        .commit0_writes_rd_out       (rob_commit0_writes),
        .commit0_arch_rd_out         (rob_commit0_arch),
        .commit0_pdst_out            (rob_commit0_pdst),
        .commit0_old_pdst_out        (rob_commit0_old_pdst),
        .commit1_valid_out           (rob_commit1_valid),
        .commit1_writes_rd_out       (rob_commit1_writes),
        .commit1_arch_rd_out         (rob_commit1_arch),
        .commit1_pdst_out            (rob_commit1_pdst),
        .commit1_old_pdst_out        (rob_commit1_old_pdst),
        .retire_valid_out            (rob_retire_valid),
        .retire_pc_out               (rob_retire_pc),
        .retire_instr_out            (rob_retire_instr),
        .retire_rd_write_out         (rob_retire_rd_write),
        .retire_rd_addr_out          (rob_retire_rd_addr),
        .retire_rd_data_out          (rob_retire_rd_data)
    );

    logic [1:0] rs_dispatch_count;
    logic rs_dispatch0_enable;
    logic [63:0] rs_dispatch0_seq;
    logic [2:0] rs_dispatch0_rob_tag;
    logic [2:0] rs_dispatch0_lsq_tag;
    logic [2:0] rs_dispatch0_class;
    logic [31:0] rs_dispatch0_pc;
    logic [31:0] rs_dispatch0_instr;
    logic rs_dispatch0_writes;
    logic [5:0] rs_dispatch0_pdst;
    logic rs_dispatch0_src1_used;
    logic [5:0] rs_dispatch0_src1_tag;
    logic rs_dispatch0_src1_ready;
    logic [31:0] rs_dispatch0_src1_value;
    logic rs_dispatch0_src2_used;
    logic [5:0] rs_dispatch0_src2_tag;
    logic rs_dispatch0_src2_ready;
    logic [31:0] rs_dispatch0_src2_value;
    logic rs_dispatch0_sel_imm;
    logic [31:0] rs_dispatch0_imm;
    logic [6:0] rs_dispatch0_use_signal;
    logic [2:0] rs_dispatch0_adder_op;
    logic [1:0] rs_dispatch0_shifter_op;
    logic [3:0] rs_dispatch0_multiplier_op;
    logic [3:0] rs_dispatch0_divider_op;
    logic [1:0] rs_dispatch0_alu_op;
    logic [2:0] rs_dispatch0_lsu_op;
    logic [1:0] rs_dispatch0_imu_op;
    logic rs_dispatch0_semantic_sel_rd;
    logic rs_dispatch0_is_branch;
    logic rs_dispatch0_is_jal;
    logic rs_dispatch0_is_jalr;
    logic rs_dispatch1_enable;
    logic [63:0] rs_dispatch1_seq;
    logic [2:0] rs_dispatch1_rob_tag;
    logic [2:0] rs_dispatch1_lsq_tag;
    logic [2:0] rs_dispatch1_class;
    logic [31:0] rs_dispatch1_pc;
    logic [31:0] rs_dispatch1_instr;
    logic rs_dispatch1_writes;
    logic [5:0] rs_dispatch1_pdst;
    logic rs_dispatch1_src1_used;
    logic [5:0] rs_dispatch1_src1_tag;
    logic rs_dispatch1_src1_ready;
    logic [31:0] rs_dispatch1_src1_value;
    logic rs_dispatch1_src2_used;
    logic [5:0] rs_dispatch1_src2_tag;
    logic rs_dispatch1_src2_ready;
    logic [31:0] rs_dispatch1_src2_value;
    logic rs_dispatch1_sel_imm;
    logic [31:0] rs_dispatch1_imm;
    logic [6:0] rs_dispatch1_use_signal;
    logic [2:0] rs_dispatch1_adder_op;
    logic [1:0] rs_dispatch1_shifter_op;
    logic [3:0] rs_dispatch1_multiplier_op;
    logic [3:0] rs_dispatch1_divider_op;
    logic [1:0] rs_dispatch1_alu_op;
    logic [2:0] rs_dispatch1_lsu_op;
    logic [1:0] rs_dispatch1_imu_op;
    logic rs_dispatch1_semantic_sel_rd;
    logic rs_dispatch1_is_branch;
    logic rs_dispatch1_is_jal;
    logic rs_dispatch1_is_jalr;
    logic rs_cdb0_valid;
    logic rs_cdb0_writes;
    logic [5:0] rs_cdb0_pdst;
    logic [31:0] rs_cdb0_value;
    logic rs_cdb1_valid;
    logic rs_cdb1_writes;
    logic [5:0] rs_cdb1_pdst;
    logic [31:0] rs_cdb1_value;
    wire [3:0] rs_free_count;
    wire rs_int0_valid;
    wire [63:0] rs_int0_seq;
    wire [2:0] rs_int0_rob_tag;
    wire [2:0] rs_int0_class;
    wire [31:0] rs_int0_src1_value;
    wire rs_int0_is_branch;
    logic rs_int0_grant;
    wire rs_int1_valid;
    wire [63:0] rs_int1_seq;
    wire [2:0] rs_int1_rob_tag;
    wire [2:0] rs_int1_class;
    logic rs_int1_grant;
    wire rs_m_valid;
    wire [63:0] rs_m_seq;
    wire [2:0] rs_m_rob_tag;
    logic rs_m_accept;
    wire rs_lsu_valid;
    wire [63:0] rs_lsu_seq;
    wire [2:0] rs_lsu_rob_tag;
    logic rs_lsu_capture;

    reservation_station u_rs (
        .clk                          (clk),
        .reset                        (rs_reset),
        .flush_in                     (1'b0),
        .dispatch_count_in            (rs_dispatch_count),
        .dispatch0_enable_in          (rs_dispatch0_enable),
        .dispatch0_seq_in             (rs_dispatch0_seq),
        .dispatch0_rob_tag_in         (rs_dispatch0_rob_tag),
        .dispatch0_lsq_tag_in         (rs_dispatch0_lsq_tag),
        .dispatch0_class_in           (rs_dispatch0_class),
        .dispatch0_pc_in              (rs_dispatch0_pc),
        .dispatch0_instr_in           (rs_dispatch0_instr),
        .dispatch0_writes_pdst_in     (rs_dispatch0_writes),
        .dispatch0_pdst_in            (rs_dispatch0_pdst),
        .dispatch0_src1_used_in       (rs_dispatch0_src1_used),
        .dispatch0_src1_tag_in        (rs_dispatch0_src1_tag),
        .dispatch0_src1_ready_in      (rs_dispatch0_src1_ready),
        .dispatch0_src1_value_in      (rs_dispatch0_src1_value),
        .dispatch0_src2_used_in       (rs_dispatch0_src2_used),
        .dispatch0_src2_tag_in        (rs_dispatch0_src2_tag),
        .dispatch0_src2_ready_in      (rs_dispatch0_src2_ready),
        .dispatch0_src2_value_in      (rs_dispatch0_src2_value),
        .dispatch0_sel_imm_in         (rs_dispatch0_sel_imm),
        .dispatch0_imm_in             (rs_dispatch0_imm),
        .dispatch0_use_signal_in      (rs_dispatch0_use_signal),
        .dispatch0_adder_op_in        (rs_dispatch0_adder_op),
        .dispatch0_shifter_op_in      (rs_dispatch0_shifter_op),
        .dispatch0_multiplier_op_in   (rs_dispatch0_multiplier_op),
        .dispatch0_divider_op_in      (rs_dispatch0_divider_op),
        .dispatch0_alu_op_in          (rs_dispatch0_alu_op),
        .dispatch0_lsu_op_in          (rs_dispatch0_lsu_op),
        .dispatch0_imu_op_in          (rs_dispatch0_imu_op),
        .dispatch0_semantic_sel_rd_in (rs_dispatch0_semantic_sel_rd),
        .dispatch0_is_branch_in       (rs_dispatch0_is_branch),
        .dispatch0_is_jal_in          (rs_dispatch0_is_jal),
        .dispatch0_is_jalr_in         (rs_dispatch0_is_jalr),
        .dispatch1_enable_in          (rs_dispatch1_enable),
        .dispatch1_seq_in             (rs_dispatch1_seq),
        .dispatch1_rob_tag_in         (rs_dispatch1_rob_tag),
        .dispatch1_lsq_tag_in         (rs_dispatch1_lsq_tag),
        .dispatch1_class_in           (rs_dispatch1_class),
        .dispatch1_pc_in              (rs_dispatch1_pc),
        .dispatch1_instr_in           (rs_dispatch1_instr),
        .dispatch1_writes_pdst_in     (rs_dispatch1_writes),
        .dispatch1_pdst_in            (rs_dispatch1_pdst),
        .dispatch1_src1_used_in       (rs_dispatch1_src1_used),
        .dispatch1_src1_tag_in        (rs_dispatch1_src1_tag),
        .dispatch1_src1_ready_in      (rs_dispatch1_src1_ready),
        .dispatch1_src1_value_in      (rs_dispatch1_src1_value),
        .dispatch1_src2_used_in       (rs_dispatch1_src2_used),
        .dispatch1_src2_tag_in        (rs_dispatch1_src2_tag),
        .dispatch1_src2_ready_in      (rs_dispatch1_src2_ready),
        .dispatch1_src2_value_in      (rs_dispatch1_src2_value),
        .dispatch1_sel_imm_in         (rs_dispatch1_sel_imm),
        .dispatch1_imm_in             (rs_dispatch1_imm),
        .dispatch1_use_signal_in      (rs_dispatch1_use_signal),
        .dispatch1_adder_op_in        (rs_dispatch1_adder_op),
        .dispatch1_shifter_op_in      (rs_dispatch1_shifter_op),
        .dispatch1_multiplier_op_in   (rs_dispatch1_multiplier_op),
        .dispatch1_divider_op_in      (rs_dispatch1_divider_op),
        .dispatch1_alu_op_in          (rs_dispatch1_alu_op),
        .dispatch1_lsu_op_in          (rs_dispatch1_lsu_op),
        .dispatch1_imu_op_in          (rs_dispatch1_imu_op),
        .dispatch1_semantic_sel_rd_in (rs_dispatch1_semantic_sel_rd),
        .dispatch1_is_branch_in       (rs_dispatch1_is_branch),
        .dispatch1_is_jal_in          (rs_dispatch1_is_jal),
        .dispatch1_is_jalr_in         (rs_dispatch1_is_jalr),
        .cdb0_valid_in                (rs_cdb0_valid),
        .cdb0_writes_pdst_in          (rs_cdb0_writes),
        .cdb0_pdst_in                 (rs_cdb0_pdst),
        .cdb0_value_in                (rs_cdb0_value),
        .cdb1_valid_in                (rs_cdb1_valid),
        .cdb1_writes_pdst_in          (rs_cdb1_writes),
        .cdb1_pdst_in                 (rs_cdb1_pdst),
        .cdb1_value_in                (rs_cdb1_value),
        .free_count_out               (rs_free_count),
        .int0_valid_out               (rs_int0_valid),
        .int0_seq_out                 (rs_int0_seq),
        .int0_rob_tag_out             (rs_int0_rob_tag),
        .int0_class_out               (rs_int0_class),
        .int0_src1_value_out          (rs_int0_src1_value),
        .int0_is_branch_out           (rs_int0_is_branch),
        .int0_grant_in                (rs_int0_grant),
        .int1_valid_out               (rs_int1_valid),
        .int1_seq_out                 (rs_int1_seq),
        .int1_rob_tag_out             (rs_int1_rob_tag),
        .int1_class_out               (rs_int1_class),
        .int1_grant_in                (rs_int1_grant),
        .m_valid_out                  (rs_m_valid),
        .m_seq_out                    (rs_m_seq),
        .m_rob_tag_out                (rs_m_rob_tag),
        .m_accept_in                  (rs_m_accept),
        .lsu_valid_out                (rs_lsu_valid),
        .lsu_seq_out                  (rs_lsu_seq),
        .lsu_rob_tag_out              (rs_lsu_rob_tag),
        .lsu_capture_in               (rs_lsu_capture)
    );

    task automatic check_condition(input logic condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("OOO_ROB_RS_ERROR %s", message);
        end
    endtask

    task automatic clear_rob_inputs;
        begin
            rob_dispatch_count = 2'd0;
            rob_alloc0_supported = 1'b1;
            rob_alloc0_pc = 32'b0;
            rob_alloc0_instr = 32'h0000_0013;
            rob_alloc0_reports_rd = 1'b0;
            rob_alloc0_writes_rd = 1'b0;
            rob_alloc0_arch_rd = 5'b0;
            rob_alloc0_pdst = 6'b0;
            rob_alloc0_old_pdst = 6'b0;
            rob_alloc0_is_control = 1'b0;
            rob_alloc0_is_fence = 1'b0;
            rob_alloc0_is_store = 1'b0;
            rob_alloc1_supported = 1'b1;
            rob_alloc1_pc = 32'b0;
            rob_alloc1_instr = 32'h0000_0013;
            rob_alloc1_reports_rd = 1'b0;
            rob_alloc1_writes_rd = 1'b0;
            rob_alloc1_arch_rd = 5'b0;
            rob_alloc1_pdst = 6'b0;
            rob_alloc1_old_pdst = 6'b0;
            rob_alloc1_is_control = 1'b0;
            rob_alloc1_is_fence = 1'b0;
            rob_alloc1_is_store = 1'b0;
            rob_cdb0_valid = 1'b0;
            rob_cdb0_tag = 3'b0;
            rob_cdb0_value = 32'b0;
            rob_cdb0_control = 1'b0;
            rob_cdb0_target = 32'b0;
            rob_cdb0_mispredict = 1'b0;
            rob_cdb1_valid = 1'b0;
            rob_cdb1_tag = 3'b0;
            rob_cdb1_value = 32'b0;
            rob_cdb1_control = 1'b0;
            rob_cdb1_target = 32'b0;
            rob_cdb1_mispredict = 1'b0;
            rob_store_complete_valid = 1'b0;
            rob_store_complete_tag = 3'b0;
            rob_fence_can_complete = 1'b0;
        end
    endtask

    task automatic set_rob_alloc0(
        input logic [31:0] pc,
        input logic reports_rd,
        input logic writes_rd,
        input logic [4:0] arch_rd,
        input logic [5:0] pdst,
        input logic is_control,
        input logic is_fence,
        input logic is_store
    );
        begin
            rob_alloc0_pc = pc;
            rob_alloc0_instr = 32'h1000_0013 | pc;
            rob_alloc0_reports_rd = reports_rd;
            rob_alloc0_writes_rd = writes_rd;
            rob_alloc0_arch_rd = arch_rd;
            rob_alloc0_pdst = pdst;
            rob_alloc0_old_pdst = {1'b0, arch_rd};
            rob_alloc0_is_control = is_control;
            rob_alloc0_is_fence = is_fence;
            rob_alloc0_is_store = is_store;
        end
    endtask

    task automatic set_rob_alloc1(
        input logic [31:0] pc,
        input logic reports_rd,
        input logic writes_rd,
        input logic [4:0] arch_rd,
        input logic [5:0] pdst,
        input logic is_control,
        input logic is_fence,
        input logic is_store
    );
        begin
            rob_alloc1_pc = pc;
            rob_alloc1_instr = 32'h2000_0013 | pc;
            rob_alloc1_reports_rd = reports_rd;
            rob_alloc1_writes_rd = writes_rd;
            rob_alloc1_arch_rd = arch_rd;
            rob_alloc1_pdst = pdst;
            rob_alloc1_old_pdst = {1'b0, arch_rd};
            rob_alloc1_is_control = is_control;
            rob_alloc1_is_fence = is_fence;
            rob_alloc1_is_store = is_store;
        end
    endtask

    task automatic clear_rs_inputs;
        begin
            rs_dispatch_count = 2'd0;
            rs_dispatch0_enable = 1'b0;
            rs_dispatch0_seq = 64'b0;
            rs_dispatch0_rob_tag = 3'b0;
            rs_dispatch0_lsq_tag = 3'b0;
            rs_dispatch0_class = CLASS_ALU;
            rs_dispatch0_pc = 32'b0;
            rs_dispatch0_instr = 32'h0000_0013;
            rs_dispatch0_writes = 1'b0;
            rs_dispatch0_pdst = 6'b0;
            rs_dispatch0_src1_used = 1'b0;
            rs_dispatch0_src1_tag = 6'b0;
            rs_dispatch0_src1_ready = 1'b1;
            rs_dispatch0_src1_value = 32'b0;
            rs_dispatch0_src2_used = 1'b0;
            rs_dispatch0_src2_tag = 6'b0;
            rs_dispatch0_src2_ready = 1'b1;
            rs_dispatch0_src2_value = 32'b0;
            rs_dispatch0_sel_imm = 1'b0;
            rs_dispatch0_imm = 32'b0;
            rs_dispatch0_use_signal = 7'b0000001;
            rs_dispatch0_adder_op = 3'b0;
            rs_dispatch0_shifter_op = 2'b0;
            rs_dispatch0_multiplier_op = 4'b0;
            rs_dispatch0_divider_op = 4'b0;
            rs_dispatch0_alu_op = 2'b0;
            rs_dispatch0_lsu_op = 3'b0;
            rs_dispatch0_imu_op = 2'b0;
            rs_dispatch0_semantic_sel_rd = 1'b1;
            rs_dispatch0_is_branch = 1'b0;
            rs_dispatch0_is_jal = 1'b0;
            rs_dispatch0_is_jalr = 1'b0;
            rs_dispatch1_enable = 1'b0;
            rs_dispatch1_seq = 64'b0;
            rs_dispatch1_rob_tag = 3'b0;
            rs_dispatch1_lsq_tag = 3'b0;
            rs_dispatch1_class = CLASS_ALU;
            rs_dispatch1_pc = 32'b0;
            rs_dispatch1_instr = 32'h0000_0013;
            rs_dispatch1_writes = 1'b0;
            rs_dispatch1_pdst = 6'b0;
            rs_dispatch1_src1_used = 1'b0;
            rs_dispatch1_src1_tag = 6'b0;
            rs_dispatch1_src1_ready = 1'b1;
            rs_dispatch1_src1_value = 32'b0;
            rs_dispatch1_src2_used = 1'b0;
            rs_dispatch1_src2_tag = 6'b0;
            rs_dispatch1_src2_ready = 1'b1;
            rs_dispatch1_src2_value = 32'b0;
            rs_dispatch1_sel_imm = 1'b0;
            rs_dispatch1_imm = 32'b0;
            rs_dispatch1_use_signal = 7'b0000001;
            rs_dispatch1_adder_op = 3'b0;
            rs_dispatch1_shifter_op = 2'b0;
            rs_dispatch1_multiplier_op = 4'b0;
            rs_dispatch1_divider_op = 4'b0;
            rs_dispatch1_alu_op = 2'b0;
            rs_dispatch1_lsu_op = 3'b0;
            rs_dispatch1_imu_op = 2'b0;
            rs_dispatch1_semantic_sel_rd = 1'b1;
            rs_dispatch1_is_branch = 1'b0;
            rs_dispatch1_is_jal = 1'b0;
            rs_dispatch1_is_jalr = 1'b0;
            rs_cdb0_valid = 1'b0;
            rs_cdb0_writes = 1'b0;
            rs_cdb0_pdst = 6'b0;
            rs_cdb0_value = 32'b0;
            rs_cdb1_valid = 1'b0;
            rs_cdb1_writes = 1'b0;
            rs_cdb1_pdst = 6'b0;
            rs_cdb1_value = 32'b0;
            rs_int0_grant = 1'b0;
            rs_int1_grant = 1'b0;
            rs_m_accept = 1'b0;
            rs_lsu_capture = 1'b0;
        end
    endtask

    task automatic set_rs_slot0(
        input logic [63:0] seq,
        input logic [2:0] rob_tag,
        input logic [2:0] class_code
    );
        begin
            rs_dispatch0_enable = 1'b1;
            rs_dispatch0_seq = seq;
            rs_dispatch0_rob_tag = rob_tag;
            rs_dispatch0_class = class_code;
            rs_dispatch0_pc = seq[31:0] << 2;
            rs_dispatch0_instr = 32'h0100_0013 |
                                 {24'b0, seq[7:0]};
            rs_dispatch0_writes = (class_code != CLASS_CONTROL);
            rs_dispatch0_pdst = 6'd32 + {3'b0, rob_tag};
            if (class_code == CLASS_CONTROL) begin
                rs_dispatch0_semantic_sel_rd = 1'b0;
                rs_dispatch0_is_branch = 1'b1;
            end
        end
    endtask

    task automatic set_rs_slot1(
        input logic [63:0] seq,
        input logic [2:0] rob_tag,
        input logic [2:0] class_code
    );
        begin
            rs_dispatch1_enable = 1'b1;
            rs_dispatch1_seq = seq;
            rs_dispatch1_rob_tag = rob_tag;
            rs_dispatch1_class = class_code;
            rs_dispatch1_pc = seq[31:0] << 2;
            rs_dispatch1_instr = 32'h0200_0013 |
                                 {24'b0, seq[7:0]};
            rs_dispatch1_writes = (class_code != CLASS_CONTROL);
            rs_dispatch1_pdst = 6'd40 + {3'b0, rob_tag};
            if (class_code == CLASS_CONTROL) begin
                rs_dispatch1_semantic_sel_rd = 1'b0;
                rs_dispatch1_is_branch = 1'b1;
            end
        end
    endtask

    task automatic retire_rob_head;
        begin
            @(posedge clk);
            #1;
            clear_rob_inputs();
        end
    endtask

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        #20000;
        $fatal(1, "OOO ROB/RS timeout");
    end

    initial begin
        errors = 0;
        rob_reset = 1'b1;
        rs_reset = 1'b1;
        clear_rob_inputs();
        clear_rs_inputs();

        repeat (3) @(posedge clk);
        @(negedge clk);
        rob_reset = 1'b0;

        // Two allocations, younger completion first, then dual in-order retire.
        clear_rob_inputs();
        rob_dispatch_count = 2'd2;
        set_rob_alloc0(32'd0, 1'b1, 1'b1, 5'd1, 6'd32,
                       1'b0, 1'b0, 1'b0);
        set_rob_alloc1(32'd4, 1'b1, 1'b1, 5'd2, 6'd33,
                       1'b0, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_condition(rob_count == 4'd2, "ROB dual allocation count");
        check_condition((rob_alloc_seq0 == 64'd2) && (rob_alloc_tag0 == 3'd2),
               "ROB tail/sequence advanced by two");

        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd1;
        rob_cdb0_value = 32'd22;
        @(posedge clk); #1;
        check_condition(rob_retire_valid == 2'b00,
               "younger completion retired ahead of head");

        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd0;
        rob_cdb0_value = 32'd11;
        @(posedge clk); #1;
        check_condition(rob_retire_valid == 2'b11, "ROB did not dual retire");
        check_condition((rob_retire_pc[31:0] == 32'd0) &&
               (rob_retire_pc[63:32] == 32'd4),
               "ROB dual retire order");
        check_condition((rob_retire_rd_data[31:0] == 32'd11) &&
               (rob_retire_rd_data[63:32] == 32'd22),
               "ROB dual retire values");
        check_condition(rob_commit0_writes && rob_commit1_writes &&
               (rob_commit0_pdst == 6'd32) &&
               (rob_commit1_pdst == 6'd33),
               "ROB commit rename metadata");
        retire_rob_head();
        check_condition(rob_count == 4'd0, "ROB dual retirement did not drain");

        // A normal instruction before a control cannot co-retire with it.
        @(negedge clk);
        clear_rob_inputs();
        rob_dispatch_count = 2'd2;
        set_rob_alloc0(32'd8, 1'b1, 1'b1, 5'd3, 6'd34,
                       1'b0, 1'b0, 1'b0);
        set_rob_alloc1(32'd12, 1'b0, 1'b0, 5'd0, 6'd0,
                       1'b1, 1'b0, 1'b0);
        @(posedge clk); #1;
        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd2;
        rob_cdb0_value = 32'd33;
        rob_cdb1_valid = 1'b1;
        rob_cdb1_tag = 3'd3;
        rob_cdb1_control = 1'b1;
        rob_cdb1_target = 32'd16;
        @(posedge clk); #1;
        check_condition((rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd8),
               "control co-retired in lane1");
        retire_rob_head();
        check_condition((rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd12),
               "control did not retire alone in lane0");
        retire_rob_head();

        // FENCE waits for permission and retires alone after an older normal.
        @(negedge clk);
        clear_rob_inputs();
        rob_dispatch_count = 2'd2;
        set_rob_alloc0(32'd16, 1'b1, 1'b1, 5'd4, 6'd35,
                       1'b0, 1'b0, 1'b0);
        set_rob_alloc1(32'd20, 1'b0, 1'b0, 5'd0, 6'd0,
                       1'b0, 1'b1, 1'b0);
        @(posedge clk); #1;
        check_condition(rob_any_fence && rob_barrier_valid,
               "FENCE not exposed as barrier");
        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd4;
        rob_cdb0_value = 32'd44;
        rob_fence_can_complete = 1'b1;
        @(posedge clk); #1;
        check_condition((rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd16),
               "FENCE co-retired with older normal");
        retire_rob_head();
        rob_fence_can_complete = 1'b1;
        #1;
        check_condition(rob_head_is_fence && (rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd20),
               "FENCE did not retire alone when permitted");
        retire_rob_head();

        // A completed head store cannot co-retire with a younger normal.
        @(negedge clk);
        clear_rob_inputs();
        rob_dispatch_count = 2'd2;
        set_rob_alloc0(32'd24, 1'b0, 1'b0, 5'd0, 6'd0,
                       1'b0, 1'b0, 1'b1);
        set_rob_alloc1(32'd28, 1'b1, 1'b1, 5'd5, 6'd36,
                       1'b0, 1'b0, 1'b0);
        @(posedge clk); #1;
        @(negedge clk);
        clear_rob_inputs();
        rob_store_complete_valid = 1'b1;
        rob_store_complete_tag = 3'd6;
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd7;
        rob_cdb0_value = 32'd55;
        @(posedge clk); #1;
        check_condition(rob_head_is_store && (rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd24),
               "store did not retire alone");
        retire_rob_head();
        check_condition((rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd28),
               "younger normal missing after store");
        retire_rob_head();

        // Mispredicted control retires itself and discards a ready younger op.
        @(negedge clk);
        clear_rob_inputs();
        rob_dispatch_count = 2'd2;
        set_rob_alloc0(32'd32, 1'b0, 1'b0, 5'd0, 6'd0,
                       1'b1, 1'b0, 1'b0);
        set_rob_alloc1(32'd36, 1'b1, 1'b1, 5'd6, 6'd37,
                       1'b0, 1'b0, 1'b0);
        @(posedge clk); #1;
        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd0;
        rob_cdb0_control = 1'b1;
        rob_cdb0_target = 32'd100;
        rob_cdb0_mispredict = 1'b1;
        rob_cdb1_valid = 1'b1;
        rob_cdb1_tag = 3'd1;
        rob_cdb1_value = 32'd66;
        @(posedge clk); #1;
        check_condition(rob_recovery && (rob_recovery_target == 32'd100),
               "mispredict recovery missing/target wrong");
        check_condition((rob_retire_valid == 2'b01) &&
               (rob_retire_pc[31:0] == 32'd32),
               "mispredicting control did not self-retire alone");
        @(posedge clk); #1;
        check_condition((rob_count == 4'd0) && !rob_recovery &&
               (rob_retire_valid == 2'b00),
               "mispredict did not flush younger entry exactly once");

        // x0 retains decoded trace intent but must never expose a nonzero value.
        @(negedge clk);
        clear_rob_inputs();
        rob_dispatch_count = 2'd1;
        set_rob_alloc0(32'd40, 1'b1, 1'b0, 5'd0, 6'd0,
                       1'b0, 1'b0, 1'b0);
        @(posedge clk); #1;
        @(negedge clk);
        clear_rob_inputs();
        rob_cdb0_valid = 1'b1;
        rob_cdb0_tag = 3'd1;
        rob_cdb0_value = 32'hdead_beef;
        @(posedge clk); #1;
        check_condition((rob_retire_valid == 2'b01) && rob_retire_rd_write[0] &&
               (rob_retire_rd_addr[4:0] == 5'd0) &&
               (rob_retire_rd_data[31:0] == 32'b0) &&
               !rob_commit0_writes,
               "x0 retirement trace/commit semantics");
        retire_rob_head();

        // Begin reservation-station tests from a clean independent reset.
        @(negedge clk);
        rob_reset = 1'b1;
        rs_reset = 1'b0;
        clear_rs_inputs();

        // Pair enqueue, oldest ordering, and hold-until-grant.
        rs_dispatch_count = 2'd2;
        set_rs_slot0(64'd10, 3'd0, CLASS_ALU);
        set_rs_slot1(64'd11, 3'd1, CLASS_ALU);
        @(posedge clk); #1;
        check_condition((rs_free_count == 4'd10) && rs_int0_valid && rs_int1_valid,
               "RS pair enqueue/free count");
        check_condition((rs_int0_seq == 64'd10) && (rs_int1_seq == 64'd11),
               "RS two-lane oldest ordering");
        @(negedge clk);
        clear_rs_inputs();
        @(posedge clk); #1;
        check_condition(rs_int0_valid && rs_int1_valid &&
               (rs_int0_seq == 64'd10) && (rs_int1_seq == 64'd11),
               "integer candidates did not hold without grants");
        @(negedge clk);
        rs_int0_grant = 1'b1;
        rs_int1_grant = 1'b1;
        @(posedge clk); #1;
        check_condition(rs_free_count == 4'd12, "integer grants did not free RS");

        // Older blocked ALU is bypassed, then CDB wake restores oldest order.
        @(negedge clk);
        clear_rs_inputs();
        rs_dispatch_count = 2'd2;
        set_rs_slot0(64'd20, 3'd2, CLASS_ALU);
        rs_dispatch0_src1_used = 1'b1;
        rs_dispatch0_src1_tag = 6'd40;
        rs_dispatch0_src1_ready = 1'b0;
        set_rs_slot1(64'd21, 3'd3, CLASS_ALU);
        @(posedge clk); #1;
        check_condition(rs_int0_valid && (rs_int0_seq == 64'd21) && !rs_int1_valid,
               "RS did not bypass blocked older ALU");
        @(negedge clk);
        clear_rs_inputs();
        rs_cdb0_valid = 1'b1;
        rs_cdb0_writes = 1'b1;
        rs_cdb0_pdst = 6'd40;
        rs_cdb0_value = 32'h1234_5678;
        @(posedge clk); #1;
        check_condition(rs_int0_valid && rs_int1_valid &&
               (rs_int0_seq == 64'd20) && (rs_int1_seq == 64'd21) &&
               (rs_int0_src1_value == 32'h1234_5678),
               "CDB wakeup/oldest reselection failed");
        @(negedge clk);
        clear_rs_inputs();
        rs_int0_grant = 1'b1;
        rs_int1_grant = 1'b1;
        @(posedge clk); #1;
        check_condition(rs_free_count == 4'd12, "woken ALUs not released by grants");

        // Control appears only on lane0, never on integer lane1.
        @(negedge clk);
        clear_rs_inputs();
        rs_dispatch_count = 2'd1;
        set_rs_slot0(64'd30, 3'd4, CLASS_CONTROL);
        @(posedge clk); #1;
        check_condition(rs_int0_valid && (rs_int0_class == CLASS_CONTROL) &&
               rs_int0_is_branch && !rs_int1_valid,
               "control was not restricted to integer lane0");
        @(negedge clk);
        clear_rs_inputs();
        rs_int0_grant = 1'b1;
        @(posedge clk); #1;
        check_condition(rs_free_count == 4'd12, "control grant did not free RS");

        // M entry holds until m_accept.
        @(negedge clk);
        clear_rs_inputs();
        rs_dispatch_count = 2'd1;
        set_rs_slot0(64'd40, 3'd5, CLASS_MULDIV);
        rs_dispatch0_use_signal = 7'b0001000;
        @(posedge clk); #1;
        check_condition(rs_m_valid && (rs_m_seq == 64'd40) &&
               (rs_m_rob_tag == 3'd5), "M candidate selection");
        @(negedge clk);
        clear_rs_inputs();
        @(posedge clk); #1;
        check_condition(rs_m_valid && (rs_free_count == 4'd11),
               "M entry did not hold before accept");
        @(negedge clk);
        rs_m_accept = 1'b1;
        @(posedge clk); #1;
        check_condition(!rs_m_valid && (rs_free_count == 4'd12),
               "M accept did not release entry");

        // LSU address entry holds until capture.
        @(negedge clk);
        clear_rs_inputs();
        rs_dispatch_count = 2'd1;
        set_rs_slot0(64'd50, 3'd6, CLASS_LOAD);
        rs_dispatch0_lsq_tag = 3'd3;
        rs_dispatch0_use_signal = 7'b0100000;
        @(posedge clk); #1;
        check_condition(rs_lsu_valid && (rs_lsu_seq == 64'd50) &&
               (rs_lsu_rob_tag == 3'd6), "LSU candidate selection");
        @(negedge clk);
        clear_rs_inputs();
        @(posedge clk); #1;
        check_condition(rs_lsu_valid && (rs_free_count == 4'd11),
               "LSU entry did not hold before capture");
        @(negedge clk);
        rs_lsu_capture = 1'b1;
        @(posedge clk); #1;
        check_condition(!rs_lsu_valid && (rs_free_count == 4'd12),
               "LSU capture did not release entry");

        if (errors == 0) begin
            $display("OOO_ROB_RS_TEST PASS");
            $finish;
        end
        else begin
            $fatal(1, "OOO_ROB_RS_TEST FAIL errors=%0d", errors);
        end
    end

endmodule
