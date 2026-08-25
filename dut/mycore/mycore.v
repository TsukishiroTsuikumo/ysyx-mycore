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

    localparam [31:0] NOP = 32'h0000_0013;

    function [31:0] extend_load_data;
        input [2:0] operation;
        input [31:0] raw_data;
        begin
            case (operation)
                3'b000: extend_load_data =
                    {{24{raw_data[7]}}, raw_data[7:0]};
                3'b001: extend_load_data =
                    {{16{raw_data[15]}}, raw_data[15:0]};
                3'b010: extend_load_data = raw_data;
                3'b011: extend_load_data = {24'b0, raw_data[7:0]};
                3'b100: extend_load_data = {16'b0, raw_data[15:0]};
                default: extend_load_data = 32'b0;
            endcase
        end
    endfunction

    /*
     * IF and line queue.  The queue is also the IF/ID boundary: its two
     * oldest outputs remain stable until issue consumes one or two slots.
     */
    wire [1:0] fetch_valid;
    wire [31:0] fetch_instr0;
    wire [31:0] fetch_instr1;
    wire [31:0] fetch_pc0;
    wire [31:0] fetch_pc1;
    wire [1:0] issue_consume_count;
    wire redirect_fire;
    wire [31:0] redirect_target;
    wire fetch_queue_full;
    wire fetch_queue_empty;
    wire [31:0] stale_response_count;

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
        .redirect_valid       (redirect_fire),
        .redirect_target      (redirect_target),
        .consume_count        (issue_consume_count),
        .instr_valid          (fetch_valid),
        .instr0               (fetch_instr0),
        .instr1               (fetch_instr1),
        .pc0                  (fetch_pc0),
        .pc1                  (fetch_pc1),
        .queue_full           (fetch_queue_full),
        .queue_empty          (fetch_queue_empty),
        .stale_response_count (stale_response_count)
    );

    /*
     * Two independent decoders.  Only the issue selector decides whether
     * the younger decoded instruction may enter lane 1.
     */
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
        .is_jalr       (dec_is_jalr0)
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
        .is_jalr       (dec_is_jalr1)
    );

    /*
     * MEM/WB state and architectural writes are declared before the read
     * ports so all four decode operands receive same-cycle two-port bypass.
     */
    reg mem_wb_valid0;
    reg mem_wb_valid1;
    reg [31:0] mem_wb_pc0;
    reg [31:0] mem_wb_pc1;
    reg [31:0] mem_wb_instr0;
    reg [31:0] mem_wb_instr1;
    reg mem_wb_writes_rd0;
    reg mem_wb_writes_rd1;
    reg [4:0] mem_wb_rd_addr0;
    reg [4:0] mem_wb_rd_addr1;
    reg [31:0] mem_wb_result0;
    reg [31:0] mem_wb_result1;

    wire wb_write0;
    wire wb_write1;
    wire [31:0] wb_data0;
    wire [31:0] wb_data1;
    wire [31:0] dec_rs1_value0;
    wire [31:0] dec_rs2_value0;
    wire [31:0] dec_rs1_value1;
    wire [31:0] dec_rs2_value1;

    assign wb_write0 = mem_wb_valid0 && mem_wb_writes_rd0 &&
                       (mem_wb_rd_addr0 != 5'd0);
    assign wb_write1 = mem_wb_valid1 && mem_wb_writes_rd1 &&
                       (mem_wb_rd_addr1 != 5'd0);
    assign wb_data0 = (mem_wb_rd_addr0 == 5'd0) ?
                      32'b0 : mem_wb_result0;
    assign wb_data1 = (mem_wb_rd_addr1 == 5'd0) ?
                      32'b0 : mem_wb_result1;

    reg_R regfile (
        .clk     (clk),
        .reset   (reset),
        .r1_addr (dec_rs1_addr0),
        .r1_out  (dec_rs1_value0),
        .r2_addr (dec_rs2_addr0),
        .r2_out  (dec_rs2_value0),
        .r3_addr (dec_rs1_addr1),
        .r3_out  (dec_rs1_value1),
        .r4_addr (dec_rs2_addr1),
        .r4_out  (dec_rs2_value1),
        .w1_en   (wb_write0),
        .w1_addr (mem_wb_rd_addr0),
        .w1_in   (wb_data0),
        .w2_en   (wb_write1),
        .w2_addr (mem_wb_rd_addr1),
        .w2_in   (wb_data1)
    );

    /*
     * ID/EX bundle.  Lane 0 is always older.  A lone instruction is always
     * represented by valid0=1, valid1=0.
     */
    reg id_ex_valid0;
    reg id_ex_valid1;
    reg [31:0] id_ex_pc0;
    reg [31:0] id_ex_pc1;
    reg [31:0] id_ex_instr0;
    reg [31:0] id_ex_instr1;
    reg [31:0] id_ex_rs1_value0;
    reg [31:0] id_ex_rs2_value0;
    reg [31:0] id_ex_rs1_value1;
    reg [31:0] id_ex_rs2_value1;
    reg id_ex_sel_imm0;
    reg id_ex_sel_imm1;
    reg [31:0] id_ex_imm0;
    reg [31:0] id_ex_imm1;
    reg id_ex_writes_rd0;
    reg id_ex_writes_rd1;
    reg [4:0] id_ex_rd_addr0;
    reg [4:0] id_ex_rd_addr1;
    reg [2:0] id_ex_adder_op0;
    reg [2:0] id_ex_adder_op1;
    reg [1:0] id_ex_shifter_op0;
    reg [1:0] id_ex_shifter_op1;
    reg [3:0] id_ex_multiplier_op0;
    reg [3:0] id_ex_divider_op0;
    reg [1:0] id_ex_alu_op0;
    reg [1:0] id_ex_alu_op1;
    reg [2:0] id_ex_lsu_op0;
    reg [1:0] id_ex_imu_op0;
    reg [1:0] id_ex_imu_op1;
    reg [6:0] id_ex_use_signal0;
    reg [6:0] id_ex_use_signal1;
    reg id_ex_is_branch0;
    reg id_ex_is_jal0;
    reg id_ex_is_jalr0;

    /*
     * EX/MEM bundle and the single outstanding scalar memory token.
     */
    reg ex_mem_valid0;
    reg ex_mem_valid1;
    reg [31:0] ex_mem_pc0;
    reg [31:0] ex_mem_pc1;
    reg [31:0] ex_mem_instr0;
    reg [31:0] ex_mem_instr1;
    reg ex_mem_writes_rd0;
    reg ex_mem_writes_rd1;
    reg [4:0] ex_mem_rd_addr0;
    reg [4:0] ex_mem_rd_addr1;
    reg [31:0] ex_mem_result0;
    reg [31:0] ex_mem_result1;
    reg ex_mem_is_load;
    reg ex_mem_is_store;
    reg [2:0] ex_mem_lsu_op;
    reg [31:0] ex_mem_addr;
    reg [3:0] ex_mem_store_wstrb;
    reg [31:0] ex_mem_store_data;
    reg ex_mem_mem_req_sent;

    wire ex_mem_memory_active;
    wire dm_read_request_fire;
    wire dm_write_request_fire;
    wire load_complete;
    wire store_complete;
    wire memory_complete;
    wire pipeline_advance;

    assign ex_mem_memory_active = ex_mem_valid0 &&
                                  (ex_mem_is_load || ex_mem_is_store);
    assign dm_req_addr_out = ex_mem_addr;
    assign dm_req_rvalid_out = ex_mem_memory_active &&
                               ex_mem_is_load &&
                               !ex_mem_mem_req_sent;
    assign dm_req_wvalid_out = ex_mem_memory_active &&
                               ex_mem_is_store &&
                               !ex_mem_mem_req_sent;
    assign dm_req_wstrb_out = ex_mem_store_wstrb;
    assign dm_req_wdata_out = ex_mem_store_data;
    assign dm_read_request_fire = dm_req_rvalid_out &&
                                  dm_req_rready_in;
    assign dm_write_request_fire = dm_req_wvalid_out &&
                                   dm_req_wready_in;
    assign load_complete = ex_mem_memory_active && ex_mem_is_load &&
                           dm_resp_rvalid_in &&
                           (ex_mem_mem_req_sent || dm_read_request_fire);
    assign store_complete = ex_mem_memory_active && ex_mem_is_store &&
                            dm_resp_wvalid_in &&
                            (ex_mem_mem_req_sent || dm_write_request_fire);
    assign memory_complete = load_complete || store_complete;
    assign pipeline_advance = !ex_mem_memory_active || memory_complete;

    /*
     * Oldest-first issue.  RAW waits until the producer reaches MEM/WB,
     * whose two write ports are bypassed by reg_R.  WAW and WAR are legal.
     */
    wire [1:0] issue_valid;
    wire slot0_old_raw;
    wire slot1_old_raw;
    wire intra_pair_raw;
    wire structural_pair_block;
    wire data_hazard_stall;
    wire pair_serialize;

    hazard hazard_inst (
        .backend_ready       (pipeline_advance),
        .kill_issue          (redirect_fire),
        .slot0_valid         (fetch_valid[0]),
        .slot1_valid         (fetch_valid[1]),
        .slot0_class         (dec_class0),
        .slot1_class         (dec_class1),
        .slot0_rs1_used      (dec_rs1_used0),
        .slot0_rs2_used      (dec_rs2_used0),
        .slot1_rs1_used      (dec_rs1_used1),
        .slot1_rs2_used      (dec_rs2_used1),
        .slot0_rs1_addr      (dec_rs1_addr0),
        .slot0_rs2_addr      (dec_rs2_addr0),
        .slot1_rs1_addr      (dec_rs1_addr1),
        .slot1_rs2_addr      (dec_rs2_addr1),
        .slot0_writes_rd     (dec_sel_rd0),
        .slot1_writes_rd     (dec_sel_rd1),
        .slot0_rd_addr       (dec_rd_addr0),
        .slot1_rd_addr       (dec_rd_addr1),
        .id_ex_valid0        (id_ex_valid0),
        .id_ex_valid1        (id_ex_valid1),
        .id_ex_writes_rd0    (id_ex_writes_rd0),
        .id_ex_writes_rd1    (id_ex_writes_rd1),
        .id_ex_rd_addr0      (id_ex_rd_addr0),
        .id_ex_rd_addr1      (id_ex_rd_addr1),
        .ex_mem_valid0       (ex_mem_valid0),
        .ex_mem_valid1       (ex_mem_valid1),
        .ex_mem_writes_rd0   (ex_mem_writes_rd0),
        .ex_mem_writes_rd1   (ex_mem_writes_rd1),
        .ex_mem_rd_addr0     (ex_mem_rd_addr0),
        .ex_mem_rd_addr1     (ex_mem_rd_addr1),
        .issue_valid         (issue_valid),
        .consume_count       (issue_consume_count),
        .slot0_old_raw       (slot0_old_raw),
        .slot1_old_raw       (slot1_old_raw),
        .intra_pair_raw      (intra_pair_raw),
        .structural_pair_block(structural_pair_block),
        .data_hazard_stall   (data_hazard_stall),
        .pair_serialize      (pair_serialize)
    );

    /*
     * Two combinational execution lanes.  Lane 1 is admitted only for the
     * simple class, while lane 0 retains the original M and LSU units.
     */
    wire [31:0] ex_operand_b0;
    wire [31:0] ex_operand_b1;
    wire [31:0] ex_add_result0;
    wire [31:0] ex_add_result1;
    wire ex_branch_taken0;
    wire ex_branch_unused1;
    wire [31:0] ex_alu_result0;
    wire [31:0] ex_alu_result1;
    wire [31:0] ex_shift_result0;
    wire [31:0] ex_shift_result1;
    wire [31:0] ex_multiply_result0;
    wire [31:0] ex_divide_result0;
    wire [31:0] ex_imu_result0;
    wire [31:0] ex_imu_result1;
    wire [31:0] ex_lsu_result0;
    wire [31:0] ex_lsu_addr0;
    wire [3:0] ex_load_mask0;
    wire [3:0] ex_store_mask0;
    reg [31:0] ex_result0;
    reg [31:0] ex_result1;

    assign ex_operand_b0 = id_ex_sel_imm0 ?
                           id_ex_imm0 : id_ex_rs2_value0;
    assign ex_operand_b1 = id_ex_sel_imm1 ?
                           id_ex_imm1 : id_ex_rs2_value1;

    adder adder_lane0 (
        .is_used  (id_ex_use_signal0[0]),
        .opcode   (id_ex_adder_op0),
        .sel_rd   (id_ex_writes_rd0),
        .addA     (id_ex_rs1_value0),
        .addB     (ex_operand_b0),
        .addC     (ex_add_result0),
        .branch_cd(ex_branch_taken0)
    );

    adder adder_lane1 (
        .is_used  (id_ex_use_signal1[0]),
        .opcode   (id_ex_adder_op1),
        .sel_rd   (id_ex_writes_rd1),
        .addA     (id_ex_rs1_value1),
        .addB     (ex_operand_b1),
        .addC     (ex_add_result1),
        .branch_cd(ex_branch_unused1)
    );

    alu alu_lane0 (
        .is_used(id_ex_use_signal0[1]),
        .opcode (id_ex_alu_op0),
        .aluA   (id_ex_rs1_value0),
        .aluB   (ex_operand_b0),
        .aluC   (ex_alu_result0)
    );

    alu alu_lane1 (
        .is_used(id_ex_use_signal1[1]),
        .opcode (id_ex_alu_op1),
        .aluA   (id_ex_rs1_value1),
        .aluB   (ex_operand_b1),
        .aluC   (ex_alu_result1)
    );

    shifter shifter_lane0 (
        .is_used(id_ex_use_signal0[2]),
        .opcode (id_ex_shifter_op0),
        .shfA   (id_ex_rs1_value0),
        .shfB   (ex_operand_b0),
        .shfC   (ex_shift_result0)
    );

    shifter shifter_lane1 (
        .is_used(id_ex_use_signal1[2]),
        .opcode (id_ex_shifter_op1),
        .shfA   (id_ex_rs1_value1),
        .shfB   (ex_operand_b1),
        .shfC   (ex_shift_result1)
    );

    multiplier multiplier_lane0 (
        .is_used(id_ex_use_signal0[3]),
        .opcode (id_ex_multiplier_op0),
        .mpyA   (id_ex_rs1_value0),
        .mpyB   (ex_operand_b0),
        .mpyC   (ex_multiply_result0)
    );

    divider divider_lane0 (
        .is_used(id_ex_use_signal0[4]),
        .opcode (id_ex_divider_op0),
        .divA   (id_ex_rs1_value0),
        .divB   (ex_operand_b0),
        .divC   (ex_divide_result0)
    );

    lsu lsu_lane0 (
        .is_used (id_ex_use_signal0[5]),
        .opcode  (id_ex_lsu_op0),
        .lsuA    (id_ex_rs1_value0),
        .lsuB    (ex_operand_b0),
        .st_value(id_ex_rs2_value0),
        .dm_addr (ex_lsu_addr0),
        .dm_out  (ex_lsu_result0),
        .is_ld   (ex_load_mask0),
        .is_st   (ex_store_mask0)
    );

    imu imu_lane0 (
        .is_used  (id_ex_use_signal0[6]),
        .opcode   (id_ex_imu_op0),
        .current_pc(id_ex_pc0),
        .imm       (id_ex_imm0),
        .out       (ex_imu_result0)
    );

    imu imu_lane1 (
        .is_used  (id_ex_use_signal1[6]),
        .opcode   (id_ex_imu_op1),
        .current_pc(id_ex_pc1),
        .imm       (id_ex_imm1),
        .out       (ex_imu_result1)
    );

    always @(*) begin
        ex_result0 = 32'b0;
        if (id_ex_is_jal0 || id_ex_is_jalr0)
            ex_result0 = id_ex_pc0 + 32'd4;
        else begin
            case (id_ex_use_signal0)
                7'b0000001: ex_result0 = ex_add_result0;
                7'b0000010: ex_result0 = ex_alu_result0;
                7'b0000100: ex_result0 = ex_shift_result0;
                7'b0001000: ex_result0 = ex_multiply_result0;
                7'b0010000: ex_result0 = ex_divide_result0;
                7'b0100000: ex_result0 = ex_lsu_result0;
                7'b1000000: ex_result0 = ex_imu_result0;
                default: ex_result0 = 32'b0;
            endcase
        end
    end

    always @(*) begin
        ex_result1 = 32'b0;
        case (id_ex_use_signal1)
            7'b0000001: ex_result1 = ex_add_result1;
            7'b0000010: ex_result1 = ex_alu_result1;
            7'b0000100: ex_result1 = ex_shift_result1;
            7'b1000000: ex_result1 = ex_imu_result1;
            default: ex_result1 = 32'b0;
        endcase
    end

    /*
     * All controls resolve in EX.  A redirect is delayed while an older LSU
     * occupies EX/MEM, and only fires when this control can advance.
     */
    wire ex_redirect_needed;
    assign ex_redirect_needed = id_ex_is_jal0 || id_ex_is_jalr0 ||
                                (id_ex_is_branch0 && ex_branch_taken0);
    assign redirect_fire = id_ex_valid0 && ex_redirect_needed &&
                           pipeline_advance;
    assign redirect_target = id_ex_is_jalr0 ?
                             (ex_add_result0 & 32'hffff_fffe) :
                             (id_ex_pc0 + id_ex_imm0);

    /*
     * ID/EX update.  A redirect has priority over the younger decode bundle,
     * while the redirecting instruction itself advances through EX/MEM.
     */
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            id_ex_valid0 <= 1'b0;
            id_ex_valid1 <= 1'b0;
            id_ex_pc0 <= 32'b0;
            id_ex_pc1 <= 32'b0;
            id_ex_instr0 <= NOP;
            id_ex_instr1 <= NOP;
            id_ex_rs1_value0 <= 32'b0;
            id_ex_rs2_value0 <= 32'b0;
            id_ex_rs1_value1 <= 32'b0;
            id_ex_rs2_value1 <= 32'b0;
            id_ex_sel_imm0 <= 1'b0;
            id_ex_sel_imm1 <= 1'b0;
            id_ex_imm0 <= 32'b0;
            id_ex_imm1 <= 32'b0;
            id_ex_writes_rd0 <= 1'b0;
            id_ex_writes_rd1 <= 1'b0;
            id_ex_rd_addr0 <= 5'b0;
            id_ex_rd_addr1 <= 5'b0;
            id_ex_adder_op0 <= 3'b0;
            id_ex_adder_op1 <= 3'b0;
            id_ex_shifter_op0 <= 2'b0;
            id_ex_shifter_op1 <= 2'b0;
            id_ex_multiplier_op0 <= 4'b0;
            id_ex_divider_op0 <= 4'b0;
            id_ex_alu_op0 <= 2'b0;
            id_ex_alu_op1 <= 2'b0;
            id_ex_lsu_op0 <= 3'b0;
            id_ex_imu_op0 <= 2'b0;
            id_ex_imu_op1 <= 2'b0;
            id_ex_use_signal0 <= 7'b0;
            id_ex_use_signal1 <= 7'b0;
            id_ex_is_branch0 <= 1'b0;
            id_ex_is_jal0 <= 1'b0;
            id_ex_is_jalr0 <= 1'b0;
        end
        else if (redirect_fire) begin
            id_ex_valid0 <= 1'b0;
            id_ex_valid1 <= 1'b0;
            id_ex_writes_rd0 <= 1'b0;
            id_ex_writes_rd1 <= 1'b0;
            id_ex_is_branch0 <= 1'b0;
            id_ex_is_jal0 <= 1'b0;
            id_ex_is_jalr0 <= 1'b0;
        end
        else if (pipeline_advance) begin
            id_ex_valid0 <= issue_valid[0];
            id_ex_valid1 <= issue_valid[1];
            id_ex_pc0 <= fetch_pc0;
            id_ex_pc1 <= fetch_pc1;
            id_ex_instr0 <= fetch_instr0;
            id_ex_instr1 <= fetch_instr1;
            id_ex_rs1_value0 <= dec_rs1_value0;
            id_ex_rs2_value0 <= dec_rs2_value0;
            id_ex_rs1_value1 <= dec_rs1_value1;
            id_ex_rs2_value1 <= dec_rs2_value1;
            id_ex_sel_imm0 <= dec_sel_imm0;
            id_ex_sel_imm1 <= dec_sel_imm1;
            id_ex_imm0 <= dec_imm0;
            id_ex_imm1 <= dec_imm1;
            id_ex_writes_rd0 <= issue_valid[0] && dec_sel_rd0;
            id_ex_writes_rd1 <= issue_valid[1] && dec_sel_rd1;
            id_ex_rd_addr0 <= dec_rd_addr0;
            id_ex_rd_addr1 <= dec_rd_addr1;
            id_ex_adder_op0 <= dec_adder_op0;
            id_ex_adder_op1 <= dec_adder_op1;
            id_ex_shifter_op0 <= dec_shifter_op0;
            id_ex_shifter_op1 <= dec_shifter_op1;
            id_ex_multiplier_op0 <= dec_multiplier_op0;
            id_ex_divider_op0 <= dec_divider_op0;
            id_ex_alu_op0 <= dec_alu_op0;
            id_ex_alu_op1 <= dec_alu_op1;
            id_ex_lsu_op0 <= dec_lsu_op0;
            id_ex_imu_op0 <= dec_imu_op0;
            id_ex_imu_op1 <= dec_imu_op1;
            id_ex_use_signal0 <= dec_use_signal0;
            id_ex_use_signal1 <= dec_use_signal1;
            id_ex_is_branch0 <= issue_valid[0] && dec_is_branch0;
            id_ex_is_jal0 <= issue_valid[0] && dec_is_jal0;
            id_ex_is_jalr0 <= issue_valid[0] && dec_is_jalr0;
        end
    end

    /*
     * EX/MEM update.  During an LSU wait this entire bundle and all younger
     * stages hold.  Request acceptance is remembered separately so valid is
     * never asserted twice for the same architectural memory operation.
     */
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_mem_valid0 <= 1'b0;
            ex_mem_valid1 <= 1'b0;
            ex_mem_pc0 <= 32'b0;
            ex_mem_pc1 <= 32'b0;
            ex_mem_instr0 <= NOP;
            ex_mem_instr1 <= NOP;
            ex_mem_writes_rd0 <= 1'b0;
            ex_mem_writes_rd1 <= 1'b0;
            ex_mem_rd_addr0 <= 5'b0;
            ex_mem_rd_addr1 <= 5'b0;
            ex_mem_result0 <= 32'b0;
            ex_mem_result1 <= 32'b0;
            ex_mem_is_load <= 1'b0;
            ex_mem_is_store <= 1'b0;
            ex_mem_lsu_op <= 3'b0;
            ex_mem_addr <= 32'b0;
            ex_mem_store_wstrb <= 4'b0;
            ex_mem_store_data <= 32'b0;
            ex_mem_mem_req_sent <= 1'b0;
        end
        else if (pipeline_advance) begin
            ex_mem_valid0 <= id_ex_valid0;
            ex_mem_valid1 <= id_ex_valid1;
            ex_mem_pc0 <= id_ex_pc0;
            ex_mem_pc1 <= id_ex_pc1;
            ex_mem_instr0 <= id_ex_instr0;
            ex_mem_instr1 <= id_ex_instr1;
            ex_mem_writes_rd0 <= id_ex_writes_rd0;
            ex_mem_writes_rd1 <= id_ex_writes_rd1;
            ex_mem_rd_addr0 <= id_ex_rd_addr0;
            ex_mem_rd_addr1 <= id_ex_rd_addr1;
            ex_mem_result0 <= ex_result0;
            ex_mem_result1 <= ex_result1;
            ex_mem_is_load <= id_ex_valid0 && (ex_load_mask0 != 4'b0);
            ex_mem_is_store <= id_ex_valid0 && (ex_store_mask0 != 4'b0);
            ex_mem_lsu_op <= id_ex_lsu_op0;
            ex_mem_addr <= ex_lsu_addr0;
            ex_mem_store_wstrb <= ex_store_mask0;
            ex_mem_store_data <= ex_lsu_result0;
            ex_mem_mem_req_sent <= 1'b0;
        end
        else if (dm_read_request_fire || dm_write_request_fire) begin
            ex_mem_mem_req_sent <= 1'b1;
        end
    end

    /*
     * MEM/WB accepts only completed memory operations.  While EX/MEM waits,
     * valid is cleared after the older resident bundle retires, preventing a
     * level-held retirement indication from being counted repeatedly.
     */
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_wb_valid0 <= 1'b0;
            mem_wb_valid1 <= 1'b0;
            mem_wb_pc0 <= 32'b0;
            mem_wb_pc1 <= 32'b0;
            mem_wb_instr0 <= NOP;
            mem_wb_instr1 <= NOP;
            mem_wb_writes_rd0 <= 1'b0;
            mem_wb_writes_rd1 <= 1'b0;
            mem_wb_rd_addr0 <= 5'b0;
            mem_wb_rd_addr1 <= 5'b0;
            mem_wb_result0 <= 32'b0;
            mem_wb_result1 <= 32'b0;
        end
        else if (pipeline_advance) begin
            mem_wb_valid0 <= ex_mem_valid0;
            mem_wb_valid1 <= ex_mem_valid1;
            mem_wb_pc0 <= ex_mem_pc0;
            mem_wb_pc1 <= ex_mem_pc1;
            mem_wb_instr0 <= ex_mem_instr0;
            mem_wb_instr1 <= ex_mem_instr1;
            mem_wb_writes_rd0 <= ex_mem_writes_rd0;
            mem_wb_writes_rd1 <= ex_mem_writes_rd1;
            mem_wb_rd_addr0 <= ex_mem_rd_addr0;
            mem_wb_rd_addr1 <= ex_mem_rd_addr1;
            if (ex_mem_is_load)
                mem_wb_result0 <=
                    extend_load_data(ex_mem_lsu_op, dm_resp_rdata_in);
            else
                mem_wb_result0 <= ex_mem_result0;
            mem_wb_result1 <= ex_mem_result1;
        end
        else begin
            mem_wb_valid0 <= 1'b0;
            mem_wb_valid1 <= 1'b0;
            mem_wb_writes_rd0 <= 1'b0;
            mem_wb_writes_rd1 <= 1'b0;
        end
    end

    /*
     * Stable flat retirement interface.  Lane 0 occupies the low bits and is
     * older whenever both lanes are valid.
     */
    assign retire_valid_out = {mem_wb_valid1, mem_wb_valid0};
    assign retire_pc_out = {mem_wb_pc1, mem_wb_pc0};
    assign retire_instr_out = {mem_wb_instr1, mem_wb_instr0};
    assign retire_rd_write_out = {wb_write1, wb_write0};
    assign retire_rd_addr_out = {mem_wb_rd_addr1, mem_wb_rd_addr0};
    assign retire_rd_data_out = {wb_data1, wb_data0};

`ifndef SYNTHESIS
    task write_arch_reg;
        input [4:0] address;
        input [31:0] data;
        begin
            if (address == 5'd0)
                regfile.reg_val[0] = 32'b0;
            else
                regfile.reg_val[address] = data;
        end
    endtask

    task read_arch_reg;
        input [4:0] address;
        output [31:0] data;
        begin
            if (address == 5'd0)
                data = 32'b0;
            else
                data = regfile.reg_val[address];
        end
    endtask
`endif

    wire unused_diagnostics;
    assign unused_diagnostics = fetch_queue_full ^ fetch_queue_empty ^
                                stale_response_count[0] ^
                                dec_supported0 ^ dec_supported1 ^
                                dec_multiplier_op1[0] ^
                                dec_divider_op1[0] ^
                                dec_lsu_op1[0] ^
                                dec_is_branch1 ^ dec_is_jal1 ^
                                dec_is_jalr1 ^ slot0_old_raw ^
                                slot1_old_raw ^ intra_pair_raw ^
                                structural_pair_block ^
                                data_hazard_stall ^ pair_serialize ^
                                ex_branch_unused1;

endmodule
