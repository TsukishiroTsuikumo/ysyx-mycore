`timescale 1ns/1ps

module mycore (
    input             clk,
    input             reset,

    output            pm_req_valid_out,
    output     [31:0] pm_req_addr_out,
    input             pm_req_ready_in,
    input             pm_resp_valid_in,
    input     [127:0] pm_resp_data_in,

    output     [31:0] dm_req_addr_out,
    output            dm_req_rvalid_out,
    input             dm_req_rready_in,
    input             dm_resp_rvalid_in,
    input      [31:0] dm_resp_rdata_in,
    output            dm_req_wvalid_out,
    input             dm_req_wready_in,
    output      [3:0] dm_req_wstrb_out,
    output     [31:0] dm_req_wdata_out,
    input             dm_resp_wvalid_in,

    output      [1:0] retire_valid_out,
    output     [63:0] retire_pc_out,
    output     [63:0] retire_instr_out,
    output      [1:0] retire_rd_write_out,
    output      [9:0] retire_rd_addr_out,
    output     [63:0] retire_rd_data_out
);

    /*
     * IF and line queue.  This remains the flat IF/ID boundary inherited
     * from the fixed dual-issue core; recovery only changes its redirect and
     * consume control wires.
     */
    wire [1:0] fetch_valid;
    wire [31:0] fetch_instr0;
    wire [31:0] fetch_instr1;
    wire [31:0] fetch_pc0;
    wire [31:0] fetch_pc1;
    wire [1:0] fetch_consume_count;
    wire redirect_valid;
    wire [31:0] redirect_target;

    instr_queue #(
        .QUEUE_DEPTH (8),
        .RESET_PC    (32'h0000_0000)
    ) instr_queue_inst (
        .clk                  (clk),
        .reset                (reset),
        .pm_req_valid         (pm_req_valid_out),
        .pm_req_addr          (pm_req_addr_out),
        .pm_req_ready         (pm_req_ready_in),
        .pm_resp_valid        (pm_resp_valid_in),
        .pm_resp_data         (pm_resp_data_in),
        .redirect_valid       (redirect_valid),
        .redirect_target      (redirect_target),
        .consume_count        (fetch_consume_count),
        .instr_valid          (fetch_valid),
        .instr0               (fetch_instr0),
        .instr1               (fetch_instr1),
        .pc0                  (fetch_pc0),
        .pc1                  (fetch_pc1),
        .queue_full           (),
        .queue_empty          (),
        .stale_response_count ()
    );

    /* Two directly visible decode lanes. */
    wire [4:0] dec_rs1_addr0;
    wire [4:0] dec_rs2_addr0;
    wire dec_rs1_used0;
    wire dec_rs2_used0;
    wire dec_sel_imm0;
    wire [31:0] dec_imm0;
    wire dec_sel_rd0;
    wire [4:0] dec_rd_addr0;
    wire [2:0] dec_adder_op0;
    wire [1:0] dec_shifter_op0;
    wire [3:0] dec_multiplier_op0;
    wire [3:0] dec_divider_op0;
    wire [1:0] dec_alu_op0;
    wire [2:0] dec_lsu_op0;
    wire [1:0] dec_imu_op0;
    wire [6:0] dec_use_signal0;
    wire [2:0] dec_class0;
    wire dec_supported0;
    wire dec_is_branch0;
    wire dec_is_jal0;
    wire dec_is_jalr0;
    wire dec_is_load0;
    wire dec_is_store0;
    wire dec_is_fence0;
    wire dec_reports_rd0;
    wire dec_writes_rd0;

    wire [4:0] dec_rs1_addr1;
    wire [4:0] dec_rs2_addr1;
    wire dec_rs1_used1;
    wire dec_rs2_used1;
    wire dec_sel_imm1;
    wire [31:0] dec_imm1;
    wire dec_sel_rd1;
    wire [4:0] dec_rd_addr1;
    wire [2:0] dec_adder_op1;
    wire [1:0] dec_shifter_op1;
    wire [3:0] dec_multiplier_op1;
    wire [3:0] dec_divider_op1;
    wire [1:0] dec_alu_op1;
    wire [2:0] dec_lsu_op1;
    wire [1:0] dec_imu_op1;
    wire [6:0] dec_use_signal1;
    wire [2:0] dec_class1;
    wire dec_supported1;
    wire dec_is_branch1;
    wire dec_is_jal1;
    wire dec_is_jalr1;
    wire dec_is_load1;
    wire dec_is_store1;
    wire dec_is_fence1;
    wire dec_reports_rd1;
    wire dec_writes_rd1;

    decoder decoder_lane0 (
        .instr         (fetch_instr0),
        .rs1_addr      (dec_rs1_addr0),
        .rs2_addr      (dec_rs2_addr0),
        .rs1_used      (dec_rs1_used0),
        .rs2_used      (dec_rs2_used0),
        .sel_imm       (dec_sel_imm0),
        .imm           (dec_imm0),
        .sel_rd        (dec_sel_rd0),
        .rd_addr       (dec_rd_addr0),
        .adder_op      (dec_adder_op0),
        .shifter_op    (dec_shifter_op0),
        .multiplier_op (dec_multiplier_op0),
        .divider_op    (dec_divider_op0),
        .alu_op        (dec_alu_op0),
        .lsu_op        (dec_lsu_op0),
        .imu_op        (dec_imu_op0),
        .use_signal    (dec_use_signal0),
        .instr_class   (dec_class0),
        .supported     (dec_supported0),
        .is_branch     (dec_is_branch0),
        .is_jal        (dec_is_jal0),
        .is_jalr       (dec_is_jalr0),
        .is_load       (dec_is_load0),
        .is_store      (dec_is_store0),
        .is_fence      (dec_is_fence0),
        .reports_rd    (dec_reports_rd0),
        .writes_rd     (dec_writes_rd0)
    );

    decoder decoder_lane1 (
        .instr         (fetch_instr1),
        .rs1_addr      (dec_rs1_addr1),
        .rs2_addr      (dec_rs2_addr1),
        .rs1_used      (dec_rs1_used1),
        .rs2_used      (dec_rs2_used1),
        .sel_imm       (dec_sel_imm1),
        .imm           (dec_imm1),
        .sel_rd        (dec_sel_rd1),
        .rd_addr       (dec_rd_addr1),
        .adder_op      (dec_adder_op1),
        .shifter_op    (dec_shifter_op1),
        .multiplier_op (dec_multiplier_op1),
        .divider_op    (dec_divider_op1),
        .alu_op        (dec_alu_op1),
        .lsu_op        (dec_lsu_op1),
        .imu_op        (dec_imu_op1),
        .use_signal    (dec_use_signal1),
        .instr_class   (dec_class1),
        .supported     (dec_supported1),
        .is_branch     (dec_is_branch1),
        .is_jal        (dec_is_jal1),
        .is_jalr       (dec_is_jalr1),
        .is_load       (dec_is_load1),
        .is_store      (dec_is_store1),
        .is_fence      (dec_is_fence1),
        .reports_rd    (dec_reports_rd1),
        .writes_rd     (dec_writes_rd1)
    );

    /*
     * Rename, structural admission, and retirement bookkeeping.  The old
     * ID/EX register role is now represented by named RS entries; no second
     * decoder or hidden execution backend exists below this level.
     */
    wire dec_is_control0;
    wire dec_is_control1;
    wire [1:0] phys_need;
    wire [1:0] rs_need;
    wire [1:0] lsq_need;
    wire [1:0] dispatch_count;
    wire [1:0] dispatch_valid;
    wire issue_enable;
    wire fence_complete;
    wire [3:0] rob_free_count;
    wire [5:0] prf_free_count;
    wire [3:0] rs_free_count;
    wire [3:0] lsq_free_count;
    wire any_control_inflight;
    wire any_fence_inflight;
    wire rob_recovery;
    wire [31:0] rob_recovery_target;
    wire rob_head_valid;
    wire [2:0] rob_head_tag;
    wire rob_head_is_store;
    wire rob_head_is_fence;
    wire rob_barrier_valid;
    wire [63:0] rob_barrier_seq;
    wire memory_idle;

    assign dec_is_control0 = dec_is_branch0 || dec_is_jal0 || dec_is_jalr0;
    assign dec_is_control1 = dec_is_branch1 || dec_is_jal1 || dec_is_jalr1;
    assign phys_need = {dec_writes_rd1, dec_writes_rd0};
    assign rs_need[0] = dec_supported0 && !dec_is_fence0;
    assign rs_need[1] = dec_supported1 && !dec_is_fence1;
    assign lsq_need[0] = dec_is_load0 || dec_is_store0;
    assign lsq_need[1] = dec_is_load1 || dec_is_store1;
    assign fetch_consume_count = dispatch_count;

    hazard hazard_inst (
        .fetch_valid_in             (fetch_valid),
        .recovery_in                (rob_recovery),
        .rob_free_count_in          (rob_free_count),
        .prf_free_count_in          (prf_free_count),
        .rs_free_count_in           (rs_free_count),
        .lsq_free_count_in          (lsq_free_count),
        .phys_need_in               (phys_need),
        .rs_need_in                 (rs_need),
        .lsq_need_in                (lsq_need),
        .is_control_in              ({dec_is_control1, dec_is_control0}),
        .is_fence_in                ({dec_is_fence1, dec_is_fence0}),
        .any_control_inflight_in    (any_control_inflight),
        .any_fence_inflight_in      (any_fence_inflight),
        .rob_head_is_fence_in       (rob_head_is_fence),
        .memory_idle_in             (memory_idle),
        .dispatch_count_out         (dispatch_count),
        .dispatch_valid_out         (dispatch_valid),
        .issue_enable_out           (issue_enable),
        .fence_complete_out         (fence_complete)
    );

    wire [5:0] src1_tag0;
    wire [5:0] src2_tag0;
    wire [5:0] src1_tag1;
    wire [5:0] src2_tag1;
    wire [5:0] new_pdst0;
    wire [5:0] new_pdst1;
    wire [5:0] old_pdst0;
    wire [5:0] old_pdst1;
    wire commit0_valid;
    wire commit0_writes;
    wire [4:0] commit0_arch;
    wire [5:0] commit0_pdst;
    wire [5:0] commit0_old_pdst;
    wire commit1_valid;
    wire commit1_writes;
    wire [4:0] commit1_arch;
    wire [5:0] commit1_pdst;
    wire [5:0] commit1_old_pdst;

    rat rat_state (
        .clk                 (clk),
        .reset               (reset),
        .recovery_in         (rob_recovery),
        .dispatch_count_in   (dispatch_count),
        .src0_1_used_in      (dec_rs1_used0),
        .src0_1_addr_in      (dec_rs1_addr0),
        .src0_1_tag_out      (src1_tag0),
        .src0_2_used_in      (dec_rs2_used0),
        .src0_2_addr_in      (dec_rs2_addr0),
        .src0_2_tag_out      (src2_tag0),
        .src1_1_used_in      (dec_rs1_used1),
        .src1_1_addr_in      (dec_rs1_addr1),
        .src1_1_tag_out      (src1_tag1),
        .src1_2_used_in      (dec_rs2_used1),
        .src1_2_addr_in      (dec_rs2_addr1),
        .src1_2_tag_out      (src2_tag1),
        .dst0_writes_in      (dec_writes_rd0),
        .dst0_arch_in        (dec_rd_addr0),
        .new_pdst0_out       (new_pdst0),
        .old_pdst0_out       (old_pdst0),
        .dst1_writes_in      (dec_writes_rd1),
        .dst1_arch_in        (dec_rd_addr1),
        .new_pdst1_out       (new_pdst1),
        .old_pdst1_out       (old_pdst1),
        .free_count_out      (prf_free_count),
        .commit0_valid_in    (commit0_valid),
        .commit0_writes_in   (commit0_writes),
        .commit0_arch_in     (commit0_arch),
        .commit0_pdst_in     (commit0_pdst),
        .commit0_old_pdst_in (commit0_old_pdst),
        .commit1_valid_in    (commit1_valid),
        .commit1_writes_in   (commit1_writes),
        .commit1_arch_in     (commit1_arch),
        .commit1_pdst_in     (commit1_pdst),
        .commit1_old_pdst_in (commit1_old_pdst)
    );

    wire [31:0] src1_value0;
    wire [31:0] src2_value0;
    wire [31:0] src1_value1;
    wire [31:0] src2_value1;
    wire src1_ready0;
    wire src2_ready0;
    wire src1_ready1;
    wire src2_ready1;

    wire cdb0_valid;
    wire [2:0] cdb0_rob;
    wire cdb0_writes;
    wire [5:0] cdb0_pdst;
    wire [31:0] cdb0_value;
    wire cdb0_control;
    wire [31:0] cdb0_target;
    wire cdb0_mispredict;
    wire cdb1_valid;
    wire [2:0] cdb1_rob;
    wire cdb1_writes;
    wire [5:0] cdb1_pdst;
    wire [31:0] cdb1_value;
    wire cdb1_control;
    wire [31:0] cdb1_target;
    wire cdb1_mispredict;

    reg_R physical_register_file (
        .clk                (clk),
        .reset              (reset),
        .read0_tag_in       (src1_tag0),
        .read0_data_out     (src1_value0),
        .read0_ready_out    (src1_ready0),
        .read1_tag_in       (src2_tag0),
        .read1_data_out     (src2_value0),
        .read1_ready_out    (src2_ready0),
        .read2_tag_in       (src1_tag1),
        .read2_data_out     (src1_value1),
        .read2_ready_out    (src1_ready1),
        .read3_tag_in       (src2_tag1),
        .read3_data_out     (src2_value1),
        .read3_ready_out    (src2_ready1),
        .allocate0_en_in    (dispatch_valid[0] && dec_writes_rd0),
        .allocate0_tag_in   (new_pdst0),
        .allocate1_en_in    (dispatch_valid[1] && dec_writes_rd1),
        .allocate1_tag_in   (new_pdst1),
        .cdb0_en_in         (cdb0_valid && cdb0_writes),
        .cdb0_tag_in        (cdb0_pdst),
        .cdb0_data_in       (cdb0_value),
        .cdb1_en_in         (cdb1_valid && cdb1_writes),
        .cdb1_tag_in        (cdb1_pdst),
        .cdb1_data_in       (cdb1_value)
    );

    wire [2:0] rob_alloc_tag0;
    wire [2:0] rob_alloc_tag1;
    wire [63:0] rob_alloc_seq0;
    wire [63:0] rob_alloc_seq1;
    wire [3:0] rob_count;
    wire store_complete_valid;
    wire [2:0] store_complete_rob;

    rob reorder_buffer (
        .clk                         (clk),
        .reset                       (reset),
        .dispatch_count_in           (dispatch_count),
        .alloc0_supported_in         (dec_supported0),
        .alloc0_pc_in                (fetch_pc0),
        .alloc0_instr_in             (fetch_instr0),
        .alloc0_reports_rd_in        (dec_reports_rd0),
        .alloc0_writes_rd_in         (dec_writes_rd0),
        .alloc0_arch_rd_in           (dec_rd_addr0),
        .alloc0_pdst_in              (new_pdst0),
        .alloc0_old_pdst_in          (old_pdst0),
        .alloc0_is_control_in        (dec_is_control0),
        .alloc0_is_fence_in          (dec_is_fence0),
        .alloc0_is_store_in          (dec_is_store0),
        .alloc1_supported_in         (dec_supported1),
        .alloc1_pc_in                (fetch_pc1),
        .alloc1_instr_in             (fetch_instr1),
        .alloc1_reports_rd_in        (dec_reports_rd1),
        .alloc1_writes_rd_in         (dec_writes_rd1),
        .alloc1_arch_rd_in           (dec_rd_addr1),
        .alloc1_pdst_in              (new_pdst1),
        .alloc1_old_pdst_in          (old_pdst1),
        .alloc1_is_control_in        (dec_is_control1),
        .alloc1_is_fence_in          (dec_is_fence1),
        .alloc1_is_store_in          (dec_is_store1),
        .alloc_tag0_out              (rob_alloc_tag0),
        .alloc_tag1_out              (rob_alloc_tag1),
        .alloc_seq0_out              (rob_alloc_seq0),
        .alloc_seq1_out              (rob_alloc_seq1),
        .rob_count_out               (rob_count),
        .free_count_out              (rob_free_count),
        .any_control_out             (any_control_inflight),
        .any_fence_out               (any_fence_inflight),
        .head_valid_out              (rob_head_valid),
        .head_tag_out                (rob_head_tag),
        .head_is_store_out           (rob_head_is_store),
        .head_is_fence_out           (rob_head_is_fence),
        .barrier_valid_out           (rob_barrier_valid),
        .barrier_seq_out             (rob_barrier_seq),
        .cdb0_valid_in               (cdb0_valid),
        .cdb0_rob_tag_in             (cdb0_rob),
        .cdb0_value_in               (cdb0_value),
        .cdb0_control_in             (cdb0_control),
        .cdb0_target_in              (cdb0_target),
        .cdb0_mispredict_in          (cdb0_mispredict),
        .cdb1_valid_in               (cdb1_valid),
        .cdb1_rob_tag_in             (cdb1_rob),
        .cdb1_value_in               (cdb1_value),
        .cdb1_control_in             (cdb1_control),
        .cdb1_target_in              (cdb1_target),
        .cdb1_mispredict_in          (cdb1_mispredict),
        .store_complete_valid_in     (store_complete_valid),
        .store_complete_rob_tag_in   (store_complete_rob),
        .fence_can_complete_in       (fence_complete),
        .recovery_out                (rob_recovery),
        .recovery_target_out         (rob_recovery_target),
        .commit0_valid_out           (commit0_valid),
        .commit0_writes_rd_out       (commit0_writes),
        .commit0_arch_rd_out         (commit0_arch),
        .commit0_pdst_out            (commit0_pdst),
        .commit0_old_pdst_out        (commit0_old_pdst),
        .commit1_valid_out           (commit1_valid),
        .commit1_writes_rd_out       (commit1_writes),
        .commit1_arch_rd_out         (commit1_arch),
        .commit1_pdst_out            (commit1_pdst),
        .commit1_old_pdst_out        (commit1_old_pdst),
        .retire_valid_out            (retire_valid_out),
        .retire_pc_out               (retire_pc_out),
        .retire_instr_out            (retire_instr_out),
        .retire_rd_write_out         (retire_rd_write_out),
        .retire_rd_addr_out          (retire_rd_addr_out),
        .retire_rd_data_out          (retire_rd_data_out)
    );

    /*
     * The LSQ replaces the old EX/MEM scalar memory token.  The original LSU
     * remains a direct child of mycore and only supplies its AGU result.
     */
    wire [2:0] lsq_alloc_index0;
    wire [2:0] lsq_alloc_index1;
    wire lsu_issue_valid;
    wire [2:0] lsu_issue_lsq_tag;
    wire [31:0] lsu_issue_src1;
    wire [31:0] lsu_issue_src2;
    wire [31:0] lsu_issue_imm;
    wire [2:0] lsu_issue_op;
    wire agu_capture;
    wire [31:0] agu_addr;
    wire [31:0] agu_wdata;
    wire [3:0] agu_load_mask;
    wire [3:0] agu_store_mask;
    wire load_result_valid;
    wire [2:0] load_result_rob;
    wire [5:0] load_result_pdst;
    wire load_result_writes;
    wire [31:0] load_result_value;
    wire load_result_grant;

    assign agu_capture = lsu_issue_valid && issue_enable;

    lsu address_generation_unit (
        .is_used (agu_capture),
        .opcode  (lsu_issue_op),
        .lsuA    (lsu_issue_src1),
        .lsuB    (lsu_issue_imm),
        .st_value(lsu_issue_src2),
        .dm_addr (agu_addr),
        .dm_out  (agu_wdata),
        .is_ld   (agu_load_mask),
        .is_st   (agu_store_mask)
    );

    lsq load_store_queue (
        .clk                         (clk),
        .reset                       (reset),
        .flush_in                    (rob_recovery),
        .dispatch_count_in           (dispatch_count),
        .dispatch0_enable_in         (dispatch_valid[0] && lsq_need[0]),
        .dispatch0_is_store_in       (dec_is_store0),
        .dispatch0_seq_in            (rob_alloc_seq0),
        .dispatch0_rob_in            (rob_alloc_tag0),
        .dispatch0_pdst_in           (new_pdst0),
        .dispatch0_writes_in         (dec_writes_rd0),
        .dispatch0_lsu_op_in         (dec_lsu_op0),
        .dispatch1_enable_in         (dispatch_valid[1] && lsq_need[1]),
        .dispatch1_is_store_in       (dec_is_store1),
        .dispatch1_seq_in            (rob_alloc_seq1),
        .dispatch1_rob_in            (rob_alloc_tag1),
        .dispatch1_pdst_in           (new_pdst1),
        .dispatch1_writes_in         (dec_writes_rd1),
        .dispatch1_lsu_op_in         (dec_lsu_op1),
        .alloc_index0_out            (lsq_alloc_index0),
        .alloc_index1_out            (lsq_alloc_index1),
        .free_count_out              (lsq_free_count),
        .agu_capture_valid_in        (agu_capture),
        .agu_capture_index_in        (lsu_issue_lsq_tag),
        .agu_addr_in                 (agu_addr),
        .agu_wdata_in                (agu_wdata),
        .agu_wstrb_in                (agu_store_mask),
        .agu_lsu_op_in               (lsu_issue_op),
        .rob_head_valid_in           (rob_head_valid),
        .rob_head_tag_in             (rob_head_tag),
        .rob_head_is_store_in        (rob_head_is_store),
        .barrier_valid_in            (rob_barrier_valid),
        .barrier_seq_in              (rob_barrier_seq),
        .dm_req_addr_out             (dm_req_addr_out),
        .dm_req_rvalid_out           (dm_req_rvalid_out),
        .dm_req_rready_in            (dm_req_rready_in),
        .dm_resp_rvalid_in           (dm_resp_rvalid_in),
        .dm_resp_rdata_in            (dm_resp_rdata_in),
        .dm_req_wvalid_out           (dm_req_wvalid_out),
        .dm_req_wready_in            (dm_req_wready_in),
        .dm_req_wstrb_out            (dm_req_wstrb_out),
        .dm_req_wdata_out            (dm_req_wdata_out),
        .dm_resp_wvalid_in           (dm_resp_wvalid_in),
        .load_result_valid_out       (load_result_valid),
        .load_result_grant_in        (load_result_grant),
        .load_result_rob_out         (load_result_rob),
        .load_result_pdst_out        (load_result_pdst),
        .load_result_writes_out      (load_result_writes),
        .load_result_value_out       (load_result_value),
        .store_complete_valid_out    (store_complete_valid),
        .store_complete_rob_out      (store_complete_rob),
        .memory_idle_out             (memory_idle)
    );

    /* Unified RS: the saved decode payload directly drives the old FUs. */
    wire int0_issue_valid;
    wire [2:0] int0_issue_rob;
    wire [31:0] int0_issue_pc;
    wire int0_issue_writes;
    wire [5:0] int0_issue_pdst;
    wire [31:0] int0_issue_src1;
    wire [31:0] int0_issue_src2;
    wire int0_issue_sel_imm;
    wire [31:0] int0_issue_imm;
    wire [6:0] int0_issue_use_signal;
    wire [2:0] int0_issue_adder_op;
    wire [1:0] int0_issue_shifter_op;
    wire [1:0] int0_issue_alu_op;
    wire [1:0] int0_issue_imu_op;
    wire int0_issue_semantic_sel_rd;
    wire int0_issue_is_branch;
    wire int0_issue_is_jal;
    wire int0_issue_is_jalr;
    wire int0_grant;

    wire int1_issue_valid;
    wire [2:0] int1_issue_rob;
    wire [31:0] int1_issue_pc;
    wire int1_issue_writes;
    wire [5:0] int1_issue_pdst;
    wire [31:0] int1_issue_src1;
    wire [31:0] int1_issue_src2;
    wire int1_issue_sel_imm;
    wire [31:0] int1_issue_imm;
    wire [6:0] int1_issue_use_signal;
    wire [2:0] int1_issue_adder_op;
    wire [1:0] int1_issue_shifter_op;
    wire [1:0] int1_issue_alu_op;
    wire [1:0] int1_issue_imu_op;
    wire int1_issue_semantic_sel_rd;
    wire int1_issue_is_branch;
    wire int1_issue_is_jal;
    wire int1_issue_is_jalr;
    wire int1_grant;

    wire m_issue_valid;
    wire [2:0] m_issue_rob;
    wire m_issue_writes;
    wire [5:0] m_issue_pdst;
    wire [31:0] m_issue_src1;
    wire [31:0] m_issue_src2;
    wire [6:0] m_issue_use_signal;
    wire [3:0] m_issue_multiplier_op;
    wire [3:0] m_issue_divider_op;
    wire m_start_fire;

    reservation_station issue_queue (
        .clk                            (clk),
        .reset                          (reset),
        .flush_in                       (rob_recovery),
        .dispatch_count_in              (dispatch_count),
        .dispatch0_enable_in            (dispatch_valid[0] && rs_need[0]),
        .dispatch0_seq_in               (rob_alloc_seq0),
        .dispatch0_rob_tag_in           (rob_alloc_tag0),
        .dispatch0_lsq_tag_in           (lsq_alloc_index0),
        .dispatch0_class_in             (dec_class0),
        .dispatch0_pc_in                (fetch_pc0),
        .dispatch0_instr_in             (fetch_instr0),
        .dispatch0_writes_pdst_in       (dec_writes_rd0),
        .dispatch0_pdst_in              (new_pdst0),
        .dispatch0_src1_used_in         (dec_rs1_used0),
        .dispatch0_src1_tag_in          (src1_tag0),
        .dispatch0_src1_ready_in        (src1_ready0),
        .dispatch0_src1_value_in        (src1_value0),
        .dispatch0_src2_used_in         (dec_rs2_used0),
        .dispatch0_src2_tag_in          (src2_tag0),
        .dispatch0_src2_ready_in        (src2_ready0),
        .dispatch0_src2_value_in        (src2_value0),
        .dispatch0_sel_imm_in           (dec_sel_imm0),
        .dispatch0_imm_in               (dec_imm0),
        .dispatch0_use_signal_in        (dec_use_signal0),
        .dispatch0_adder_op_in          (dec_adder_op0),
        .dispatch0_shifter_op_in        (dec_shifter_op0),
        .dispatch0_multiplier_op_in     (dec_multiplier_op0),
        .dispatch0_divider_op_in        (dec_divider_op0),
        .dispatch0_alu_op_in            (dec_alu_op0),
        .dispatch0_lsu_op_in            (dec_lsu_op0),
        .dispatch0_imu_op_in            (dec_imu_op0),
        .dispatch0_semantic_sel_rd_in   (dec_sel_rd0),
        .dispatch0_is_branch_in         (dec_is_branch0),
        .dispatch0_is_jal_in            (dec_is_jal0),
        .dispatch0_is_jalr_in           (dec_is_jalr0),
        .dispatch1_enable_in            (dispatch_valid[1] && rs_need[1]),
        .dispatch1_seq_in               (rob_alloc_seq1),
        .dispatch1_rob_tag_in           (rob_alloc_tag1),
        .dispatch1_lsq_tag_in           (lsq_alloc_index1),
        .dispatch1_class_in             (dec_class1),
        .dispatch1_pc_in                (fetch_pc1),
        .dispatch1_instr_in             (fetch_instr1),
        .dispatch1_writes_pdst_in       (dec_writes_rd1),
        .dispatch1_pdst_in              (new_pdst1),
        .dispatch1_src1_used_in         (dec_rs1_used1),
        .dispatch1_src1_tag_in          (src1_tag1),
        .dispatch1_src1_ready_in        (src1_ready1),
        .dispatch1_src1_value_in        (src1_value1),
        .dispatch1_src2_used_in         (dec_rs2_used1),
        .dispatch1_src2_tag_in          (src2_tag1),
        .dispatch1_src2_ready_in        (src2_ready1),
        .dispatch1_src2_value_in        (src2_value1),
        .dispatch1_sel_imm_in           (dec_sel_imm1),
        .dispatch1_imm_in               (dec_imm1),
        .dispatch1_use_signal_in        (dec_use_signal1),
        .dispatch1_adder_op_in          (dec_adder_op1),
        .dispatch1_shifter_op_in        (dec_shifter_op1),
        .dispatch1_multiplier_op_in     (dec_multiplier_op1),
        .dispatch1_divider_op_in        (dec_divider_op1),
        .dispatch1_alu_op_in            (dec_alu_op1),
        .dispatch1_lsu_op_in            (dec_lsu_op1),
        .dispatch1_imu_op_in            (dec_imu_op1),
        .dispatch1_semantic_sel_rd_in   (dec_sel_rd1),
        .dispatch1_is_branch_in         (dec_is_branch1),
        .dispatch1_is_jal_in            (dec_is_jal1),
        .dispatch1_is_jalr_in           (dec_is_jalr1),
        .cdb0_valid_in                  (cdb0_valid),
        .cdb0_writes_pdst_in            (cdb0_writes),
        .cdb0_pdst_in                   (cdb0_pdst),
        .cdb0_value_in                  (cdb0_value),
        .cdb1_valid_in                  (cdb1_valid),
        .cdb1_writes_pdst_in            (cdb1_writes),
        .cdb1_pdst_in                   (cdb1_pdst),
        .cdb1_value_in                  (cdb1_value),
        .free_count_out                 (rs_free_count),
        .int0_valid_out                 (int0_issue_valid),
        .int0_seq_out                   (),
        .int0_rob_tag_out               (int0_issue_rob),
        .int0_lsq_tag_out               (),
        .int0_class_out                 (),
        .int0_pc_out                    (int0_issue_pc),
        .int0_instr_out                 (),
        .int0_writes_pdst_out           (int0_issue_writes),
        .int0_pdst_out                  (int0_issue_pdst),
        .int0_src1_used_out             (),
        .int0_src1_tag_out              (),
        .int0_src1_ready_out            (),
        .int0_src1_value_out            (int0_issue_src1),
        .int0_src2_used_out             (),
        .int0_src2_tag_out              (),
        .int0_src2_ready_out            (),
        .int0_src2_value_out            (int0_issue_src2),
        .int0_sel_imm_out               (int0_issue_sel_imm),
        .int0_imm_out                   (int0_issue_imm),
        .int0_use_signal_out            (int0_issue_use_signal),
        .int0_adder_op_out              (int0_issue_adder_op),
        .int0_shifter_op_out            (int0_issue_shifter_op),
        .int0_multiplier_op_out         (),
        .int0_divider_op_out            (),
        .int0_alu_op_out                (int0_issue_alu_op),
        .int0_lsu_op_out                (),
        .int0_imu_op_out                (int0_issue_imu_op),
        .int0_semantic_sel_rd_out       (int0_issue_semantic_sel_rd),
        .int0_is_branch_out             (int0_issue_is_branch),
        .int0_is_jal_out                (int0_issue_is_jal),
        .int0_is_jalr_out               (int0_issue_is_jalr),
        .int0_grant_in                  (int0_grant),
        .int1_valid_out                 (int1_issue_valid),
        .int1_seq_out                   (),
        .int1_rob_tag_out               (int1_issue_rob),
        .int1_lsq_tag_out               (),
        .int1_class_out                 (),
        .int1_pc_out                    (int1_issue_pc),
        .int1_instr_out                 (),
        .int1_writes_pdst_out           (int1_issue_writes),
        .int1_pdst_out                  (int1_issue_pdst),
        .int1_src1_used_out             (),
        .int1_src1_tag_out              (),
        .int1_src1_ready_out            (),
        .int1_src1_value_out            (int1_issue_src1),
        .int1_src2_used_out             (),
        .int1_src2_tag_out              (),
        .int1_src2_ready_out            (),
        .int1_src2_value_out            (int1_issue_src2),
        .int1_sel_imm_out               (int1_issue_sel_imm),
        .int1_imm_out                   (int1_issue_imm),
        .int1_use_signal_out            (int1_issue_use_signal),
        .int1_adder_op_out              (int1_issue_adder_op),
        .int1_shifter_op_out            (int1_issue_shifter_op),
        .int1_multiplier_op_out         (),
        .int1_divider_op_out            (),
        .int1_alu_op_out                (int1_issue_alu_op),
        .int1_lsu_op_out                (),
        .int1_imu_op_out                (int1_issue_imu_op),
        .int1_semantic_sel_rd_out       (int1_issue_semantic_sel_rd),
        .int1_is_branch_out             (int1_issue_is_branch),
        .int1_is_jal_out                (int1_issue_is_jal),
        .int1_is_jalr_out               (int1_issue_is_jalr),
        .int1_grant_in                  (int1_grant),
        .m_valid_out                    (m_issue_valid),
        .m_seq_out                      (),
        .m_rob_tag_out                  (m_issue_rob),
        .m_lsq_tag_out                  (),
        .m_class_out                    (),
        .m_pc_out                       (),
        .m_instr_out                    (),
        .m_writes_pdst_out              (m_issue_writes),
        .m_pdst_out                     (m_issue_pdst),
        .m_src1_used_out                (),
        .m_src1_tag_out                 (),
        .m_src1_ready_out               (),
        .m_src1_value_out               (m_issue_src1),
        .m_src2_used_out                (),
        .m_src2_tag_out                 (),
        .m_src2_ready_out               (),
        .m_src2_value_out               (m_issue_src2),
        .m_sel_imm_out                  (),
        .m_imm_out                      (),
        .m_use_signal_out               (m_issue_use_signal),
        .m_adder_op_out                 (),
        .m_shifter_op_out               (),
        .m_multiplier_op_out            (m_issue_multiplier_op),
        .m_divider_op_out               (m_issue_divider_op),
        .m_alu_op_out                   (),
        .m_lsu_op_out                   (),
        .m_imu_op_out                   (),
        .m_semantic_sel_rd_out          (),
        .m_is_branch_out                (),
        .m_is_jal_out                   (),
        .m_is_jalr_out                  (),
        .m_accept_in                    (m_start_fire),
        .lsu_valid_out                  (lsu_issue_valid),
        .lsu_seq_out                    (),
        .lsu_rob_tag_out                (),
        .lsu_lsq_tag_out                (lsu_issue_lsq_tag),
        .lsu_class_out                  (),
        .lsu_pc_out                     (),
        .lsu_instr_out                  (),
        .lsu_writes_pdst_out            (),
        .lsu_pdst_out                   (),
        .lsu_src1_used_out              (),
        .lsu_src1_tag_out               (),
        .lsu_src1_ready_out             (),
        .lsu_src1_value_out             (lsu_issue_src1),
        .lsu_src2_used_out              (),
        .lsu_src2_tag_out               (),
        .lsu_src2_ready_out             (),
        .lsu_src2_value_out             (lsu_issue_src2),
        .lsu_sel_imm_out                (),
        .lsu_imm_out                    (lsu_issue_imm),
        .lsu_use_signal_out             (),
        .lsu_adder_op_out               (),
        .lsu_shifter_op_out             (),
        .lsu_multiplier_op_out          (),
        .lsu_divider_op_out             (),
        .lsu_alu_op_out                 (),
        .lsu_lsu_op_out                 (lsu_issue_op),
        .lsu_imu_op_out                 (),
        .lsu_semantic_sel_rd_out        (),
        .lsu_is_branch_out              (),
        .lsu_is_jal_out                 (),
        .lsu_is_jalr_out                (),
        .lsu_capture_in                 (agu_capture)
    );

    /* Two direct integer execution lanes. */
    wire int0_exec_valid;
    wire int1_exec_valid;
    wire [31:0] int0_operand_b;
    wire [31:0] int1_operand_b;
    wire [31:0] int0_add_result;
    wire [31:0] int1_add_result;
    wire int0_branch_taken;
    wire int1_branch_taken;
    wire [31:0] int0_alu_result;
    wire [31:0] int1_alu_result;
    wire [31:0] int0_shift_result;
    wire [31:0] int1_shift_result;
    wire [31:0] int0_imu_result;
    wire [31:0] int1_imu_result;
    wire [31:0] int0_exec_value;
    wire [31:0] int1_exec_value;
    wire int0_complete;
    wire int1_complete;
    wire int0_control;
    wire int1_control;
    wire [31:0] int0_control_target;
    wire [31:0] int1_control_target;
    wire int0_mispredict;
    wire int1_mispredict;

    assign int0_exec_valid = int0_issue_valid && issue_enable;
    assign int1_exec_valid = int1_issue_valid && issue_enable;

    adder adder_lane0 (
        .is_used  (int0_exec_valid && int0_issue_use_signal[0]),
        .opcode   (int0_issue_adder_op),
        .sel_rd   (int0_issue_semantic_sel_rd),
        .addA     (int0_issue_src1),
        .addB     (int0_operand_b),
        .addC     (int0_add_result),
        .branch_cd(int0_branch_taken)
    );

    adder adder_lane1 (
        .is_used  (int1_exec_valid && int1_issue_use_signal[0]),
        .opcode   (int1_issue_adder_op),
        .sel_rd   (int1_issue_semantic_sel_rd),
        .addA     (int1_issue_src1),
        .addB     (int1_operand_b),
        .addC     (int1_add_result),
        .branch_cd(int1_branch_taken)
    );

    alu alu_lane0 (
        .is_used(int0_exec_valid && int0_issue_use_signal[1]),
        .opcode (int0_issue_alu_op),
        .aluA   (int0_issue_src1),
        .aluB   (int0_operand_b),
        .aluC   (int0_alu_result)
    );

    alu alu_lane1 (
        .is_used(int1_exec_valid && int1_issue_use_signal[1]),
        .opcode (int1_issue_alu_op),
        .aluA   (int1_issue_src1),
        .aluB   (int1_operand_b),
        .aluC   (int1_alu_result)
    );

    shifter shifter_lane0 (
        .is_used(int0_exec_valid && int0_issue_use_signal[2]),
        .opcode (int0_issue_shifter_op),
        .shfA   (int0_issue_src1),
        .shfB   (int0_operand_b),
        .shfC   (int0_shift_result)
    );

    shifter shifter_lane1 (
        .is_used(int1_exec_valid && int1_issue_use_signal[2]),
        .opcode (int1_issue_shifter_op),
        .shfA   (int1_issue_src1),
        .shfB   (int1_operand_b),
        .shfC   (int1_shift_result)
    );

    imu imu_lane0 (
        .is_used   (int0_exec_valid && int0_issue_use_signal[6]),
        .opcode    (int0_issue_imu_op),
        .current_pc(int0_issue_pc),
        .imm       (int0_issue_imm),
        .out       (int0_imu_result)
    );

    imu imu_lane1 (
        .is_used   (int1_exec_valid && int1_issue_use_signal[6]),
        .opcode    (int1_issue_imu_op),
        .current_pc(int1_issue_pc),
        .imm       (int1_issue_imm),
        .out       (int1_imu_result)
    );

    controller execution_control (
        .lane0_valid_in          (int0_exec_valid),
        .lane0_pc_in             (int0_issue_pc),
        .lane0_src2_in           (int0_issue_src2),
        .lane0_sel_imm_in        (int0_issue_sel_imm),
        .lane0_imm_in            (int0_issue_imm),
        .lane0_use_signal_in     (int0_issue_use_signal),
        .lane0_is_branch_in      (int0_issue_is_branch),
        .lane0_is_jal_in         (int0_issue_is_jal),
        .lane0_is_jalr_in        (int0_issue_is_jalr),
        .lane0_add_result_in     (int0_add_result),
        .lane0_branch_taken_in   (int0_branch_taken),
        .lane0_alu_result_in     (int0_alu_result),
        .lane0_shift_result_in   (int0_shift_result),
        .lane0_imu_result_in     (int0_imu_result),
        .lane1_valid_in          (int1_exec_valid),
        .lane1_pc_in             (int1_issue_pc),
        .lane1_src2_in           (int1_issue_src2),
        .lane1_sel_imm_in        (int1_issue_sel_imm),
        .lane1_imm_in            (int1_issue_imm),
        .lane1_use_signal_in     (int1_issue_use_signal),
        .lane1_is_branch_in      (int1_issue_is_branch),
        .lane1_is_jal_in         (int1_issue_is_jal),
        .lane1_is_jalr_in        (int1_issue_is_jalr),
        .lane1_add_result_in     (int1_add_result),
        .lane1_branch_taken_in   (int1_branch_taken),
        .lane1_alu_result_in     (int1_alu_result),
        .lane1_shift_result_in   (int1_shift_result),
        .lane1_imu_result_in     (int1_imu_result),
        .retire_recovery_in      (rob_recovery),
        .retire_target_in        (rob_recovery_target),
        .lane0_operand_b_out     (int0_operand_b),
        .lane1_operand_b_out     (int1_operand_b),
        .lane0_value_out         (int0_exec_value),
        .lane1_value_out         (int1_exec_value),
        .lane0_complete_out      (int0_complete),
        .lane1_complete_out      (int1_complete),
        .lane0_control_out       (int0_control),
        .lane1_control_out       (int1_control),
        .lane0_target_out        (int0_control_target),
        .lane1_target_out        (int1_control_target),
        .lane0_mispredict_out    (int0_mispredict),
        .lane1_mispredict_out    (int1_mispredict),
        .redirect_valid_out      (redirect_valid),
        .redirect_target_out     (redirect_target)
    );

    /* One shared direct RV32M lane plus a metadata/latency tracker. */
    wire m_tracker_ready;
    wire m_busy;
    wire [31:0] m_multiply_result;
    wire [31:0] m_divide_result;
    wire m_result_valid;
    wire [31:0] m_result_value;
    wire [2:0] m_result_rob;
    wire [5:0] m_result_pdst;
    wire m_result_writes;
    wire m_result_grant;

    multiplier multiplier_lane (
        .is_used(m_start_fire && m_issue_use_signal[3]),
        .opcode (m_issue_multiplier_op),
        .mpyA   (m_issue_src1),
        .mpyB   (m_issue_src2),
        .mpyC   (m_multiply_result)
    );

    divider divider_lane (
        .is_used(m_start_fire && m_issue_use_signal[4]),
        .opcode (m_issue_divider_op),
        .divA   (m_issue_src1),
        .divB   (m_issue_src2),
        .divC   (m_divide_result)
    );

    muldiv_tracker muldiv_state (
        .clk                  (clk),
        .reset                (reset),
        .flush_in             (rob_recovery),
        .start_valid_in       (m_issue_valid && issue_enable),
        .start_use_signal_in  (m_issue_use_signal),
        .mul_result_in        (m_multiply_result),
        .div_result_in        (m_divide_result),
        .start_rob_in         (m_issue_rob),
        .start_pdst_in        (m_issue_pdst),
        .start_writes_in      (m_issue_writes),
        .start_ready_out      (m_tracker_ready),
        .start_fire_out       (m_start_fire),
        .busy_out             (m_busy),
        .result_valid_out     (m_result_valid),
        .result_grant_in      (m_result_grant),
        .result_value_out     (m_result_value),
        .result_rob_out       (m_result_rob),
        .result_pdst_out      (m_result_pdst),
        .result_writes_out    (m_result_writes)
    );

    /*
     * Two-lane CDB replaces MEM/WB.  It writes PRF, wakes RS operands, and
     * completes ROB entries through the same explicit wires.
     */
    cdb_arbiter common_data_bus (
        .load_valid       (load_result_valid && issue_enable),
        .load_rob         (load_result_rob),
        .load_writes      (load_result_writes),
        .load_pdst        (load_result_pdst),
        .load_value       (load_result_value),
        .load_control     (1'b0),
        .load_target      (32'b0),
        .load_mispredict  (1'b0),
        .muldiv_valid     (m_result_valid && issue_enable),
        .muldiv_rob       (m_result_rob),
        .muldiv_writes    (m_result_writes),
        .muldiv_pdst      (m_result_pdst),
        .muldiv_value     (m_result_value),
        .muldiv_control   (1'b0),
        .muldiv_target    (32'b0),
        .muldiv_mispredict(1'b0),
        .int0_valid       (int0_complete),
        .int0_rob         (int0_issue_rob),
        .int0_writes      (int0_issue_writes),
        .int0_pdst        (int0_issue_pdst),
        .int0_value       (int0_exec_value),
        .int0_control     (int0_control),
        .int0_target      (int0_control_target),
        .int0_mispredict  (int0_mispredict),
        .int1_valid       (int1_complete),
        .int1_rob         (int1_issue_rob),
        .int1_writes      (int1_issue_writes),
        .int1_pdst        (int1_issue_pdst),
        .int1_value       (int1_exec_value),
        .int1_control     (int1_control),
        .int1_target      (int1_control_target),
        .int1_mispredict  (int1_mispredict),
        .cdb0_valid       (cdb0_valid),
        .cdb0_rob         (cdb0_rob),
        .cdb0_writes      (cdb0_writes),
        .cdb0_pdst        (cdb0_pdst),
        .cdb0_value       (cdb0_value),
        .cdb0_control     (cdb0_control),
        .cdb0_target      (cdb0_target),
        .cdb0_mispredict  (cdb0_mispredict),
        .cdb1_valid       (cdb1_valid),
        .cdb1_rob         (cdb1_rob),
        .cdb1_writes      (cdb1_writes),
        .cdb1_pdst        (cdb1_pdst),
        .cdb1_value       (cdb1_value),
        .cdb1_control     (cdb1_control),
        .cdb1_target      (cdb1_target),
        .cdb1_mispredict  (cdb1_mispredict),
        .load_grant       (load_result_grant),
        .muldiv_grant     (m_result_grant),
        .int0_grant       (int0_grant),
        .int1_grant       (int1_grant)
    );

`ifndef SYNTHESIS
    task write_arch_reg;
        input [4:0] address;
        input [31:0] data;
        reg [5:0] physical_tag;
        begin
            rat_state.read_amt(address, physical_tag);
            physical_register_file.write_phys_reg(physical_tag, data);
        end
    endtask

    task read_arch_reg;
        input [4:0] address;
        output [31:0] data;
        reg [5:0] physical_tag;
        begin
            rat_state.read_amt(address, physical_tag);
            physical_register_file.read_phys_reg(physical_tag, data);
        end
    endtask
`endif

    wire unused_flat_diagnostics;
    assign unused_flat_diagnostics = rob_count[0] ^ m_tracker_ready ^
                                     m_busy ^ agu_load_mask[0];

endmodule
