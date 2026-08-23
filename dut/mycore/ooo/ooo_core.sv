`timescale 1ns/1ps

// Bounded, experimental two-wide RV32IM out-of-order core.
//
// The implementation is intentionally self-contained so it cannot perturb the
// repository's legacy pipeline.  It demonstrates the mechanisms called out by
// the project roadmap: a physical register file, speculative RAT, committed
// RAT, free list, ROB, reservation station, conservative LSQ, two integer
// execution lanes, a serialized multi-cycle M unit, and precise retirement.
// Branches are predicted not-taken and redirect at the ROB head.  See
// docs/ooo-core.md for the deliberately bounded architectural contract.
module ooo_core #(
    parameter integer ROB_DEPTH   = 8,
    parameter integer RS_DEPTH    = 12,
    parameter integer LSQ_DEPTH   = 8,
    parameter integer PRF_COUNT   = 48,
    parameter integer M_LATENCY   = 12,
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic clk,
    input  logic reset,

    // One request returns the two consecutive instructions beginning at addr.
    // There is at most one outstanding request and responses are not stalled.
    output logic        imem_req_valid_out,
    output logic [31:0] imem_req_addr_out,
    input  logic        imem_req_ready_in,
    input  logic        imem_resp_valid_in,
    input  logic [63:0] imem_resp_data_in,

    // One outstanding data request.  Loads and stores use an aligned word
    // address plus byte strobes.  A response is required for both operations.
    output logic        dmem_req_valid_out,
    input  logic        dmem_req_ready_in,
    output logic        dmem_req_write_out,
    output logic [31:0] dmem_req_addr_out,
    output logic [31:0] dmem_req_wdata_out,
    output logic [3:0]  dmem_req_wstrb_out,
    input  logic        dmem_resp_valid_in,
    input  logic [31:0] dmem_resp_rdata_in,
    input  logic        dmem_resp_error_in,

    // Ordered architectural retirement trace.  Lane 0 is always older.
    output logic [1:0]       retire_valid_out,
    output logic [1:0][31:0] retire_pc_out,
    output logic [1:0][31:0] retire_instr_out,
    output logic [1:0]       retire_rd_write_out,
    output logic [1:0][4:0]  retire_rd_addr_out,
    output logic [1:0][31:0] retire_rd_data_out,

    output logic [31:0] arch_regfile_out [0:31],

    output logic [31:0] rob_occupancy_out,
    output logic [63:0] cycle_count_out,
    output logic [63:0] retired_count_out,
    output logic [63:0] ooo_completion_count_out,
    output logic [63:0] rob_full_cycle_count_out,
    output logic [63:0] load_block_cycle_count_out,
    output logic [63:0] branch_recovery_count_out,
    output logic        memory_fault_sticky_out
);

    localparam logic [2:0] CLASS_ALU     = 3'd0;
    localparam logic [2:0] CLASS_MULDIV  = 3'd1;
    localparam logic [2:0] CLASS_LOAD    = 3'd2;
    localparam logic [2:0] CLASS_STORE   = 3'd3;
    localparam logic [2:0] CLASS_CONTROL = 3'd4;

    localparam integer ROB_W = $clog2(ROB_DEPTH);
    localparam integer RS_W  = $clog2(RS_DEPTH);
    localparam integer LSQ_W = $clog2(LSQ_DEPTH);
    localparam integer PRF_W = $clog2(PRF_COUNT);
    localparam integer ROB_COUNT_W = $clog2(ROB_DEPTH + 1);
    localparam integer M_COUNT_W = (M_LATENCY < 2) ? 1 : $clog2(M_LATENCY + 1);

    function automatic [ROB_W-1:0] rob_next(input [ROB_W-1:0] index);
        begin
            rob_next = (index == ROB_DEPTH-1) ? {ROB_W{1'b0}} : index + 1'b1;
        end
    endfunction

    function automatic logic [31:0] imm_i(input logic [31:0] instr);
        imm_i = {{20{instr[31]}}, instr[31:20]};
    endfunction

    function automatic logic [31:0] imm_s(input logic [31:0] instr);
        imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    endfunction

    function automatic logic [31:0] imm_b(input logic [31:0] instr);
        imm_b = {{20{instr[31]}}, instr[7], instr[30:25],
                 instr[11:8], 1'b0};
    endfunction

    function automatic logic [31:0] imm_j(input logic [31:0] instr);
        imm_j = {{12{instr[31]}}, instr[19:12], instr[20],
                 instr[30:21], 1'b0};
    endfunction

    function automatic logic [31:0] alu_result(
        input logic [31:0] instr,
        input logic [31:0] pc,
        input logic [31:0] a,
        input logic [31:0] b
    );
        logic [31:0] result;
        begin
            result = 32'b0;
            unique case (instr[6:0])
                7'b0110011: begin
                    unique case (instr[14:12])
                        3'b000: result = instr[30] ? (a - b) : (a + b);
                        3'b001: result = a << b[4:0];
                        3'b010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                        3'b011: result = (a < b) ? 32'd1 : 32'd0;
                        3'b100: result = a ^ b;
                        3'b101: result = instr[30] ?
                                          ($signed(a) >>> b[4:0]) : (a >> b[4:0]);
                        3'b110: result = a | b;
                        3'b111: result = a & b;
                        default: result = 32'b0;
                    endcase
                end
                7'b0010011: begin
                    unique case (instr[14:12])
                        3'b000: result = a + imm_i(instr);
                        3'b010: result = ($signed(a) < $signed(imm_i(instr))) ?
                                         32'd1 : 32'd0;
                        3'b011: result = (a < imm_i(instr)) ? 32'd1 : 32'd0;
                        3'b100: result = a ^ imm_i(instr);
                        3'b110: result = a | imm_i(instr);
                        3'b111: result = a & imm_i(instr);
                        3'b001: result = a << instr[24:20];
                        3'b101: result = instr[30] ?
                                          ($signed(a) >>> instr[24:20]) :
                                          (a >> instr[24:20]);
                        default: result = 32'b0;
                    endcase
                end
                7'b0110111: result = {instr[31:12], 12'b0};
                7'b0010111: result = pc + {instr[31:12], 12'b0};
                default: result = 32'b0;
            endcase
            alu_result = result;
        end
    endfunction

    function automatic logic branch_taken(
        input logic [31:0] instr,
        input logic [31:0] a,
        input logic [31:0] b
    );
        begin
            unique case (instr[14:12])
                3'b000: branch_taken = (a == b);
                3'b001: branch_taken = (a != b);
                3'b100: branch_taken = ($signed(a) < $signed(b));
                3'b101: branch_taken = ($signed(a) >= $signed(b));
                3'b110: branch_taken = (a < b);
                3'b111: branch_taken = (a >= b);
                default: branch_taken = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] control_target(
        input logic [31:0] instr,
        input logic [31:0] pc,
        input logic [31:0] a,
        input logic [31:0] b
    );
        begin
            unique case (instr[6:0])
                7'b1100011: control_target = branch_taken(instr, a, b) ?
                                                (pc + imm_b(instr)) : (pc + 4);
                7'b1101111: control_target = pc + imm_j(instr);
                7'b1100111: control_target = (a + imm_i(instr)) & 32'hffff_fffe;
                default: control_target = pc + 4;
            endcase
        end
    endfunction

    function automatic logic [31:0] control_result(
        input logic [31:0] instr,
        input logic [31:0] pc
    );
        begin
            control_result = ((instr[6:0] == 7'b1101111) ||
                              (instr[6:0] == 7'b1100111)) ? (pc + 4) : 32'b0;
        end
    endfunction

    function automatic logic [31:0] muldiv_result(
        input logic [31:0] instr,
        input logic [31:0] a,
        input logic [31:0] b
    );
        logic signed [32:0] a_signed_33;
        logic signed [32:0] b_signed_33;
        logic signed [32:0] b_unsigned_33;
        logic signed [65:0] product_ss;
        logic signed [65:0] product_su;
        logic [63:0] product_uu;
        begin
            a_signed_33 = {a[31], a};
            b_signed_33 = {b[31], b};
            b_unsigned_33 = {1'b0, b};
            product_ss = a_signed_33 * b_signed_33;
            product_su = a_signed_33 * b_unsigned_33;
            product_uu = a * b;
            unique case (instr[14:12])
                3'b000: muldiv_result = product_uu[31:0];                    // MUL
                3'b001: muldiv_result = product_ss[63:32];                  // MULH
                3'b010: muldiv_result = product_su[63:32];                  // MULHSU
                3'b011: muldiv_result = product_uu[63:32];                  // MULHU
                3'b100: begin                                               // DIV
                    if (b == 32'b0)
                        muldiv_result = 32'hffff_ffff;
                    else if ((a == 32'h8000_0000) && (b == 32'hffff_ffff))
                        muldiv_result = 32'h8000_0000;
                    else
                        muldiv_result = $signed(a) / $signed(b);
                end
                3'b101: muldiv_result = (b == 32'b0) ?
                                           32'hffff_ffff : (a / b);          // DIVU
                3'b110: begin                                               // REM
                    if (b == 32'b0)
                        muldiv_result = a;
                    else if ((a == 32'h8000_0000) && (b == 32'hffff_ffff))
                        muldiv_result = 32'b0;
                    else
                        muldiv_result = $signed(a) % $signed(b);
                end
                3'b111: muldiv_result = (b == 32'b0) ? a : (a % b);          // REMU
                default: muldiv_result = 32'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] load_result(
        input logic [31:0] word,
        input logic [2:0] funct3,
        input logic [1:0] byte_offset
    );
        logic [31:0] shifted;
        begin
            shifted = word >> (byte_offset * 8);
            unique case (funct3)
                3'b000: load_result = {{24{shifted[7]}}, shifted[7:0]};
                3'b001: load_result = {{16{shifted[15]}}, shifted[15:0]};
                3'b010: load_result = word;
                3'b100: load_result = {24'b0, shifted[7:0]};
                3'b101: load_result = {16'b0, shifted[15:0]};
                default: load_result = 32'b0;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Fetch packet buffer
    // ------------------------------------------------------------------

    logic [31:0] fetch_pc_q;
    logic        fetch_outstanding_q;
    logic [31:0] fetch_request_pc_q;
    logic        fetch_response_stale_q;
    logic        fetch_buf_valid_q;
    logic [63:0] fetch_buf_data_q;
    logic [31:0] fetch_buf_pc_q;
    logic        fetch_buf_second_q;

    logic [1:0] dispatch_count;
    logic recovery_now;
    logic [31:0] recovery_target;

    assign imem_req_valid_out = !reset && !recovery_now &&
                                !fetch_outstanding_q && !fetch_buf_valid_q;
    assign imem_req_addr_out = fetch_pc_q;
    wire imem_request_fire = imem_req_valid_out && imem_req_ready_in;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_pc_q <= RESET_PC;
            fetch_outstanding_q <= 1'b0;
            fetch_request_pc_q <= RESET_PC;
            fetch_response_stale_q <= 1'b0;
            fetch_buf_valid_q <= 1'b0;
            fetch_buf_data_q <= 64'h0000_0013_0000_0013;
            fetch_buf_pc_q <= RESET_PC;
            fetch_buf_second_q <= 1'b0;
        end
        else if (recovery_now) begin
            fetch_pc_q <= recovery_target;
            fetch_buf_valid_q <= 1'b0;
            fetch_buf_second_q <= 1'b0;
            if (fetch_outstanding_q) begin
                if (imem_resp_valid_in) begin
                    fetch_outstanding_q <= 1'b0;
                    fetch_response_stale_q <= 1'b0;
                end
                else begin
                    fetch_response_stale_q <= 1'b1;
                end
            end
        end
        else begin
            if (imem_request_fire) begin
                fetch_outstanding_q <= 1'b1;
                fetch_request_pc_q <= fetch_pc_q;
                fetch_pc_q <= fetch_pc_q + 8;
            end

            if (imem_resp_valid_in && fetch_outstanding_q) begin
                fetch_outstanding_q <= 1'b0;
                if (fetch_response_stale_q) begin
                    fetch_response_stale_q <= 1'b0;
                end
                else begin
                    fetch_buf_valid_q <= 1'b1;
                    fetch_buf_data_q <= imem_resp_data_in;
                    fetch_buf_pc_q <= fetch_request_pc_q;
                    fetch_buf_second_q <= 1'b0;
                end
            end

            if (dispatch_count == 2) begin
                fetch_buf_valid_q <= 1'b0;
                fetch_buf_second_q <= 1'b0;
            end
            else if (dispatch_count == 1) begin
                if (!fetch_buf_second_q) begin
                    fetch_buf_second_q <= 1'b1;
                end
                else begin
                    fetch_buf_valid_q <= 1'b0;
                    fetch_buf_second_q <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Rename state, ROB, reservation station, and LSQ
    // ------------------------------------------------------------------

    logic [PRF_W-1:0] rat [0:31];
    logic [PRF_W-1:0] committed_rat [0:31];
    logic [31:0] prf_value [0:PRF_COUNT-1];
    logic              prf_ready [0:PRF_COUNT-1];
    logic [PRF_COUNT-1:0] free_mask;

    logic [ROB_W-1:0] rob_head_q, rob_tail_q;
    logic [ROB_COUNT_W-1:0] rob_count_q;
    logic rob_valid [0:ROB_DEPTH-1];
    logic rob_ready [0:ROB_DEPTH-1];
    logic [31:0] rob_pc [0:ROB_DEPTH-1];
    logic [31:0] rob_instr [0:ROB_DEPTH-1];
    logic [31:0] rob_seq [0:ROB_DEPTH-1];
    logic rob_writes_rd [0:ROB_DEPTH-1];
    logic [4:0] rob_arch_rd [0:ROB_DEPTH-1];
    logic [PRF_W-1:0] rob_pdst [0:ROB_DEPTH-1];
    logic [PRF_W-1:0] rob_old_pdst [0:ROB_DEPTH-1];
    logic [31:0] rob_value [0:ROB_DEPTH-1];
    logic rob_is_control [0:ROB_DEPTH-1];
    logic [31:0] rob_control_target [0:ROB_DEPTH-1];
    logic rob_mispredict [0:ROB_DEPTH-1];
    logic rob_is_store [0:ROB_DEPTH-1];
    logic rob_store_done [0:ROB_DEPTH-1];

    logic rs_valid [0:RS_DEPTH-1];
    logic [31:0] rs_seq [0:RS_DEPTH-1];
    logic [ROB_W-1:0] rs_rob [0:RS_DEPTH-1];
    logic [LSQ_W-1:0] rs_lsq [0:RS_DEPTH-1];
    logic [2:0] rs_class [0:RS_DEPTH-1];
    logic [31:0] rs_pc [0:RS_DEPTH-1];
    logic [31:0] rs_instr [0:RS_DEPTH-1];
    logic rs_writes_rd [0:RS_DEPTH-1];
    logic [PRF_W-1:0] rs_pdst [0:RS_DEPTH-1];
    logic rs_src1_ready [0:RS_DEPTH-1];
    logic rs_src2_ready [0:RS_DEPTH-1];
    logic [PRF_W-1:0] rs_src1_tag [0:RS_DEPTH-1];
    logic [PRF_W-1:0] rs_src2_tag [0:RS_DEPTH-1];
    logic [31:0] rs_src1_value [0:RS_DEPTH-1];
    logic [31:0] rs_src2_value [0:RS_DEPTH-1];

    logic lsq_valid [0:LSQ_DEPTH-1];
    logic lsq_is_store [0:LSQ_DEPTH-1];
    logic lsq_addr_valid [0:LSQ_DEPTH-1];
    logic lsq_issued [0:LSQ_DEPTH-1];
    logic [31:0] lsq_seq [0:LSQ_DEPTH-1];
    logic [ROB_W-1:0] lsq_rob [0:LSQ_DEPTH-1];
    logic [PRF_W-1:0] lsq_pdst [0:LSQ_DEPTH-1];
    logic [31:0] lsq_addr [0:LSQ_DEPTH-1];
    logic [31:0] lsq_wdata [0:LSQ_DEPTH-1];
    logic [3:0] lsq_wstrb [0:LSQ_DEPTH-1];
    logic [2:0] lsq_funct3 [0:LSQ_DEPTH-1];
    logic [1:0] lsq_byte_offset [0:LSQ_DEPTH-1];

    logic [31:0] next_seq_q;
    logic unresolved_branch_q;
    logic [31:0] unresolved_branch_seq_q;

    genvar arch_probe;
    generate
        for (arch_probe = 0; arch_probe < 32; arch_probe = arch_probe + 1) begin : gen_arch_probe
            assign arch_regfile_out[arch_probe] = (arch_probe == 0) ? 32'b0 :
                prf_value[committed_rat[arch_probe]];
        end
    endgenerate
    assign rob_occupancy_out = {{(32-ROB_COUNT_W){1'b0}}, rob_count_q};

    // Current fetch slots and decoders.
    logic [31:0] slot_instr [0:1];
    logic [31:0] slot_pc [0:1];
    logic slot_valid [0:1];
    logic slot_supported [0:1];
    logic [2:0] slot_class [0:1];
    logic slot_rs1_used [0:1];
    logic slot_rs2_used [0:1];
    logic slot_writes_rd [0:1];
    logic [4:0] slot_rs1 [0:1];
    logic [4:0] slot_rs2 [0:1];
    logic [4:0] slot_rd [0:1];

    always_comb begin
        slot_instr[0] = fetch_buf_second_q ? fetch_buf_data_q[63:32] :
                                                   fetch_buf_data_q[31:0];
        slot_pc[0] = fetch_buf_pc_q + (fetch_buf_second_q ? 4 : 0);
        slot_valid[0] = fetch_buf_valid_q;
        slot_instr[1] = fetch_buf_data_q[63:32];
        slot_pc[1] = fetch_buf_pc_q + 4;
        slot_valid[1] = fetch_buf_valid_q && !fetch_buf_second_q;
    end

    ooo_decode u_decode0 (
        .instr(slot_instr[0]), .supported(slot_supported[0]),
        .op_class(slot_class[0]), .rs1_used(slot_rs1_used[0]),
        .rs2_used(slot_rs2_used[0]), .writes_rd(slot_writes_rd[0]),
        .rs1_addr(slot_rs1[0]), .rs2_addr(slot_rs2[0]),
        .rd_addr(slot_rd[0])
    );
    ooo_decode u_decode1 (
        .instr(slot_instr[1]), .supported(slot_supported[1]),
        .op_class(slot_class[1]), .rs1_used(slot_rs1_used[1]),
        .rs2_used(slot_rs2_used[1]), .writes_rd(slot_writes_rd[1]),
        .rs1_addr(slot_rs1[1]), .rs2_addr(slot_rs2[1]),
        .rd_addr(slot_rd[1])
    );

    integer free_phys_count;
    integer free_rs_count;
    integer free_lsq_count;
    integer phys_alloc0_i, phys_alloc1_i;
    integer rs_alloc0_i, rs_alloc1_i;
    integer lsq_alloc0_i, lsq_alloc1_i;
    integer alloc_i;
    logic slot0_can_dispatch, slot1_can_dispatch;
    integer slot0_phys_need, slot1_phys_need;
    integer slot0_rs_need, slot1_rs_need;
    integer slot0_lsq_need, slot1_lsq_need;

    always_comb begin
        free_phys_count = 0;
        phys_alloc0_i = -1;
        phys_alloc1_i = -1;
        for (alloc_i = 0; alloc_i < PRF_COUNT; alloc_i = alloc_i + 1) begin
            if (free_mask[alloc_i]) begin
                free_phys_count = free_phys_count + 1;
                if (phys_alloc0_i < 0)
                    phys_alloc0_i = alloc_i;
                else if (phys_alloc1_i < 0)
                    phys_alloc1_i = alloc_i;
            end
        end

        free_rs_count = 0;
        rs_alloc0_i = -1;
        rs_alloc1_i = -1;
        for (alloc_i = 0; alloc_i < RS_DEPTH; alloc_i = alloc_i + 1) begin
            if (!rs_valid[alloc_i]) begin
                free_rs_count = free_rs_count + 1;
                if (rs_alloc0_i < 0)
                    rs_alloc0_i = alloc_i;
                else if (rs_alloc1_i < 0)
                    rs_alloc1_i = alloc_i;
            end
        end

        free_lsq_count = 0;
        lsq_alloc0_i = -1;
        lsq_alloc1_i = -1;
        for (alloc_i = 0; alloc_i < LSQ_DEPTH; alloc_i = alloc_i + 1) begin
            if (!lsq_valid[alloc_i]) begin
                free_lsq_count = free_lsq_count + 1;
                if (lsq_alloc0_i < 0)
                    lsq_alloc0_i = alloc_i;
                else if (lsq_alloc1_i < 0)
                    lsq_alloc1_i = alloc_i;
            end
        end

        slot0_phys_need = slot_writes_rd[0] ? 1 : 0;
        slot1_phys_need = slot_writes_rd[1] ? 1 : 0;
        slot0_rs_need = slot_supported[0] ? 1 : 0;
        slot1_rs_need = slot_supported[1] ? 1 : 0;
        slot0_lsq_need = slot_supported[0] &&
                         ((slot_class[0] == CLASS_LOAD) ||
                          (slot_class[0] == CLASS_STORE)) ? 1 : 0;
        slot1_lsq_need = slot_supported[1] &&
                         ((slot_class[1] == CLASS_LOAD) ||
                          (slot_class[1] == CLASS_STORE)) ? 1 : 0;

        slot0_can_dispatch = slot_valid[0] && !recovery_now &&
            (rob_count_q < ROB_DEPTH) &&
            (free_phys_count >= slot0_phys_need) &&
            (free_rs_count >= slot0_rs_need) &&
            (free_lsq_count >= slot0_lsq_need) &&
            !((slot_class[0] == CLASS_CONTROL) && slot_supported[0] &&
              unresolved_branch_q);

        slot1_can_dispatch = slot0_can_dispatch && slot_valid[1] &&
            (rob_count_q <= ROB_DEPTH-2) &&
            (free_phys_count >= (slot0_phys_need + slot1_phys_need)) &&
            (free_rs_count >= (slot0_rs_need + slot1_rs_need)) &&
            (free_lsq_count >= (slot0_lsq_need + slot1_lsq_need)) &&
            !((slot_class[1] == CLASS_CONTROL) && slot_supported[1] &&
              (unresolved_branch_q ||
               ((slot_class[0] == CLASS_CONTROL) && slot_supported[0])));

        dispatch_count = 2'd0;
        if (slot0_can_dispatch)
            dispatch_count = slot1_can_dispatch ? 2'd2 : 2'd1;
    end

    logic [PRF_W-1:0] slot_new_pdst [0:1];
    logic [PRF_W-1:0] slot_old_pdst [0:1];
    logic [PRF_W-1:0] slot_src1_tag [0:1];
    logic [PRF_W-1:0] slot_src2_tag [0:1];
    integer slot_rs_index [0:1];
    integer slot_lsq_index [0:1];

    always_comb begin
        slot_new_pdst[0] = (phys_alloc0_i < 0) ? {PRF_W{1'b0}} :
                                                  phys_alloc0_i[PRF_W-1:0];
        slot_new_pdst[1] = slot_writes_rd[0] ?
            ((phys_alloc1_i < 0) ? {PRF_W{1'b0}} : phys_alloc1_i[PRF_W-1:0]) :
            ((phys_alloc0_i < 0) ? {PRF_W{1'b0}} : phys_alloc0_i[PRF_W-1:0]);

        slot_old_pdst[0] = rat[slot_rd[0]];
        slot_old_pdst[1] = (slot_writes_rd[0] &&
                            (slot_rd[1] == slot_rd[0])) ?
                           slot_new_pdst[0] : rat[slot_rd[1]];

        slot_src1_tag[0] = slot_rs1_used[0] ? rat[slot_rs1[0]] : {PRF_W{1'b0}};
        slot_src2_tag[0] = slot_rs2_used[0] ? rat[slot_rs2[0]] : {PRF_W{1'b0}};
        slot_src1_tag[1] = slot_rs1_used[1] ?
            ((slot_writes_rd[0] && (slot_rs1[1] == slot_rd[0])) ?
             slot_new_pdst[0] : rat[slot_rs1[1]]) : {PRF_W{1'b0}};
        slot_src2_tag[1] = slot_rs2_used[1] ?
            ((slot_writes_rd[0] && (slot_rs2[1] == slot_rd[0])) ?
             slot_new_pdst[0] : rat[slot_rs2[1]]) : {PRF_W{1'b0}};

        slot_rs_index[0] = rs_alloc0_i;
        slot_rs_index[1] = slot0_rs_need ? rs_alloc1_i : rs_alloc0_i;
        slot_lsq_index[0] = lsq_alloc0_i;
        slot_lsq_index[1] = slot0_lsq_need ? lsq_alloc1_i : lsq_alloc0_i;
    end

    // ------------------------------------------------------------------
    // Oldest-ready execution selection
    // ------------------------------------------------------------------

    // Serialized M unit state is declared before selection because its busy
    // bit participates in the combinational eligibility test.
    logic mul_busy_q;
    logic [M_COUNT_W-1:0] mul_count_q;
    logic [ROB_W-1:0] mul_rob_q;
    logic [PRF_W-1:0] mul_pdst_q;
    logic mul_writes_q;
    logic [31:0] mul_result_q;
    logic mul_wb_valid;
    assign mul_wb_valid = mul_busy_q && (mul_count_q == 1);

    integer alu_sel0_i, alu_sel1_i, mul_sel_i, lsu_sel_i;
    integer exec_i;
    logic [31:0] best_seq0, best_seq1, best_mul_seq, best_lsu_seq;

    always_comb begin
        alu_sel0_i = -1;
        alu_sel1_i = -1;
        mul_sel_i = -1;
        lsu_sel_i = -1;
        best_seq0 = 32'hffff_ffff;
        best_seq1 = 32'hffff_ffff;
        best_mul_seq = 32'hffff_ffff;
        best_lsu_seq = 32'hffff_ffff;

        if (!recovery_now) begin
            for (exec_i = 0; exec_i < RS_DEPTH; exec_i = exec_i + 1) begin
                if (rs_valid[exec_i] && rs_src1_ready[exec_i] &&
                    rs_src2_ready[exec_i] &&
                    ((rs_class[exec_i] == CLASS_ALU) ||
                     (rs_class[exec_i] == CLASS_CONTROL)) &&
                    (rs_seq[exec_i] < best_seq0)) begin
                    alu_sel0_i = exec_i;
                    best_seq0 = rs_seq[exec_i];
                end
                if (rs_valid[exec_i] && rs_src1_ready[exec_i] &&
                    rs_src2_ready[exec_i] &&
                    (rs_class[exec_i] == CLASS_MULDIV) && !mul_busy_q &&
                    (rs_seq[exec_i] < best_mul_seq)) begin
                    mul_sel_i = exec_i;
                    best_mul_seq = rs_seq[exec_i];
                end
                if (rs_valid[exec_i] && rs_src1_ready[exec_i] &&
                    rs_src2_ready[exec_i] &&
                    ((rs_class[exec_i] == CLASS_LOAD) ||
                     (rs_class[exec_i] == CLASS_STORE)) &&
                    (rs_seq[exec_i] < best_lsu_seq)) begin
                    lsu_sel_i = exec_i;
                    best_lsu_seq = rs_seq[exec_i];
                end
            end

            for (exec_i = 0; exec_i < RS_DEPTH; exec_i = exec_i + 1) begin
                if (rs_valid[exec_i] && (exec_i != alu_sel0_i) &&
                    rs_src1_ready[exec_i] && rs_src2_ready[exec_i] &&
                    ((rs_class[exec_i] == CLASS_ALU) ||
                     (rs_class[exec_i] == CLASS_CONTROL)) &&
                    (rs_seq[exec_i] < best_seq1)) begin
                    alu_sel1_i = exec_i;
                    best_seq1 = rs_seq[exec_i];
                end
            end
        end
    end

    logic alu0_valid, alu1_valid;
    logic [ROB_W-1:0] alu0_rob, alu1_rob;
    logic [PRF_W-1:0] alu0_pdst, alu1_pdst;
    logic alu0_writes, alu1_writes;
    logic [31:0] alu0_value, alu1_value;
    logic alu0_control, alu1_control;
    logic [31:0] alu0_target, alu1_target;

    always_comb begin
        alu0_valid = (alu_sel0_i >= 0);
        alu1_valid = (alu_sel1_i >= 0);
        alu0_rob = {ROB_W{1'b0}};
        alu1_rob = {ROB_W{1'b0}};
        alu0_pdst = {PRF_W{1'b0}};
        alu1_pdst = {PRF_W{1'b0}};
        alu0_writes = 1'b0;
        alu1_writes = 1'b0;
        alu0_value = 32'b0;
        alu1_value = 32'b0;
        alu0_control = 1'b0;
        alu1_control = 1'b0;
        alu0_target = 32'b0;
        alu1_target = 32'b0;
        if (alu_sel0_i >= 0) begin
            alu0_rob = rs_rob[alu_sel0_i];
            alu0_pdst = rs_pdst[alu_sel0_i];
            alu0_writes = rs_writes_rd[alu_sel0_i];
            alu0_control = (rs_class[alu_sel0_i] == CLASS_CONTROL);
            alu0_value = alu0_control ?
                control_result(rs_instr[alu_sel0_i], rs_pc[alu_sel0_i]) :
                alu_result(rs_instr[alu_sel0_i], rs_pc[alu_sel0_i],
                           rs_src1_value[alu_sel0_i], rs_src2_value[alu_sel0_i]);
            alu0_target = control_target(rs_instr[alu_sel0_i],
                                         rs_pc[alu_sel0_i],
                                         rs_src1_value[alu_sel0_i],
                                         rs_src2_value[alu_sel0_i]);
        end
        if (alu_sel1_i >= 0) begin
            alu1_rob = rs_rob[alu_sel1_i];
            alu1_pdst = rs_pdst[alu_sel1_i];
            alu1_writes = rs_writes_rd[alu_sel1_i];
            alu1_control = (rs_class[alu_sel1_i] == CLASS_CONTROL);
            alu1_value = alu1_control ?
                control_result(rs_instr[alu_sel1_i], rs_pc[alu_sel1_i]) :
                alu_result(rs_instr[alu_sel1_i], rs_pc[alu_sel1_i],
                           rs_src1_value[alu_sel1_i], rs_src2_value[alu_sel1_i]);
            alu1_target = control_target(rs_instr[alu_sel1_i],
                                         rs_pc[alu_sel1_i],
                                         rs_src1_value[alu_sel1_i],
                                         rs_src2_value[alu_sel1_i]);
        end
    end

    // ------------------------------------------------------------------
    // Conservative memory scheduler
    // ------------------------------------------------------------------

    integer mem_candidate_i;
    logic any_load_blocked;
    logic [31:0] best_load_seq;
    logic older_store_found;
    integer mem_i, mem_j;

    logic mem_pending_q;
    logic mem_busy_q;
    logic mem_drop_response_q;
    logic mem_req_write_q;
    logic [31:0] mem_req_addr_q;
    logic [31:0] mem_req_wdata_q;
    logic [3:0] mem_req_wstrb_q;
    logic [LSQ_W-1:0] mem_lsq_q;
    logic [ROB_W-1:0] mem_rob_q;
    logic [PRF_W-1:0] mem_pdst_q;
    logic mem_writes_q;
    logic [2:0] mem_funct3_q;
    logic [1:0] mem_byte_offset_q;

    always_comb begin
        mem_candidate_i = -1;
        any_load_blocked = 1'b0;
        best_load_seq = 32'hffff_ffff;
        older_store_found = 1'b0;

        if (!recovery_now && !mem_pending_q && !mem_busy_q &&
            !mem_drop_response_q) begin
            // Stores become externally visible only at the ROB head.
            for (mem_i = 0; mem_i < LSQ_DEPTH; mem_i = mem_i + 1) begin
                if ((mem_candidate_i < 0) && lsq_valid[mem_i] &&
                    lsq_is_store[mem_i] && lsq_addr_valid[mem_i] &&
                    !lsq_issued[mem_i] && rob_valid[rob_head_q] &&
                    rob_is_store[rob_head_q] &&
                    (lsq_rob[mem_i] == rob_head_q))
                    mem_candidate_i = mem_i;
            end

            // A load waits behind every older store and behind an older
            // unresolved control instruction.  This avoids both speculative
            // store forwarding and externally visible wrong-path reads.
            if (mem_candidate_i < 0) begin
                for (mem_i = 0; mem_i < LSQ_DEPTH; mem_i = mem_i + 1) begin
                    if (lsq_valid[mem_i] && !lsq_is_store[mem_i] &&
                        lsq_addr_valid[mem_i] && !lsq_issued[mem_i]) begin
                        if (unresolved_branch_q &&
                            (lsq_seq[mem_i] > unresolved_branch_seq_q)) begin
                            any_load_blocked = 1'b1;
                        end
                        else begin
                            older_store_found = 1'b0;
                            for (mem_j = 0; mem_j < LSQ_DEPTH; mem_j = mem_j + 1) begin
                                if (lsq_valid[mem_j] && lsq_is_store[mem_j] &&
                                    (lsq_seq[mem_j] < lsq_seq[mem_i]))
                                    older_store_found = 1'b1;
                            end
                            if (older_store_found)
                                any_load_blocked = 1'b1;
                            else if (lsq_seq[mem_i] < best_load_seq) begin
                                best_load_seq = lsq_seq[mem_i];
                                mem_candidate_i = mem_i;
                            end
                        end
                    end
                end
            end
        end
        else begin
            // Count blocked loads even while another request owns the port.
            for (mem_i = 0; mem_i < LSQ_DEPTH; mem_i = mem_i + 1) begin
                if (lsq_valid[mem_i] && !lsq_is_store[mem_i] &&
                    lsq_addr_valid[mem_i] && !lsq_issued[mem_i]) begin
                    if (unresolved_branch_q &&
                        (lsq_seq[mem_i] > unresolved_branch_seq_q)) begin
                        any_load_blocked = 1'b1;
                    end
                    else begin
                        older_store_found = 1'b0;
                        for (mem_j = 0; mem_j < LSQ_DEPTH; mem_j = mem_j + 1) begin
                            if (lsq_valid[mem_j] && lsq_is_store[mem_j] &&
                                (lsq_seq[mem_j] < lsq_seq[mem_i]))
                                older_store_found = 1'b1;
                        end
                        if (older_store_found)
                            any_load_blocked = 1'b1;
                    end
                end
            end
        end
    end

    assign dmem_req_valid_out = mem_pending_q && !recovery_now;
    assign dmem_req_write_out = mem_req_write_q;
    assign dmem_req_addr_out = mem_req_addr_q;
    assign dmem_req_wdata_out = mem_req_wdata_q;
    assign dmem_req_wstrb_out = mem_req_wstrb_q;
    wire dmem_request_fire = dmem_req_valid_out && dmem_req_ready_in;
    wire [31:0] memory_load_value = dmem_resp_error_in ? 32'b0 :
        load_result(dmem_resp_rdata_in, mem_funct3_q, mem_byte_offset_q);
    wire memory_load_wb_valid = mem_busy_q && dmem_resp_valid_in &&
                                !mem_req_write_q && !mem_drop_response_q;

    logic [2:0] ooo_completion_events;
    always_comb begin
        ooo_completion_events = 3'd0;
        if (rob_valid[rob_head_q] && !rob_ready[rob_head_q]) begin
            if (alu0_valid && (alu0_rob != rob_head_q))
                ooo_completion_events = ooo_completion_events + 1'b1;
            if (alu1_valid && (alu1_rob != rob_head_q))
                ooo_completion_events = ooo_completion_events + 1'b1;
            if (mul_wb_valid && (mul_rob_q != rob_head_q))
                ooo_completion_events = ooo_completion_events + 1'b1;
            if (memory_load_wb_valid && (mem_rob_q != rob_head_q))
                ooo_completion_events = ooo_completion_events + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // In-order two-wide commit and recovery decision
    // ------------------------------------------------------------------

    logic [ROB_W-1:0] rob_head_next;
    logic head_commit_ready, second_commit_ready;
    logic [1:0] commit_count;

    always_comb begin
        rob_head_next = rob_next(rob_head_q);
        head_commit_ready = rob_valid[rob_head_q] && rob_ready[rob_head_q] &&
            (!rob_is_store[rob_head_q] || rob_store_done[rob_head_q]);
        second_commit_ready = head_commit_ready &&
            !rob_is_control[rob_head_q] &&
            rob_valid[rob_head_next] && rob_ready[rob_head_next] &&
            (!rob_is_store[rob_head_next] || rob_store_done[rob_head_next]) &&
            !rob_is_control[rob_head_next];

        recovery_now = head_commit_ready && rob_is_control[rob_head_q] &&
                       rob_mispredict[rob_head_q];
        recovery_target = rob_control_target[rob_head_q];
        commit_count = head_commit_ready ?
                       (second_commit_ready ? 2'd2 : 2'd1) : 2'd0;
    end

    logic [PRF_COUNT-1:0] recovery_free_mask;
    integer recovery_i;
    always_comb begin
        recovery_free_mask = {PRF_COUNT{1'b1}};
        for (recovery_i = 0; recovery_i < 32; recovery_i = recovery_i + 1) begin
            if ((recovery_i == rob_arch_rd[rob_head_q]) &&
                rob_writes_rd[rob_head_q])
                recovery_free_mask[rob_pdst[rob_head_q]] = 1'b0;
            else
                recovery_free_mask[committed_rat[recovery_i]] = 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // State update
    // ------------------------------------------------------------------

    integer i, p;
    integer dispatch_lane;
    integer dispatch_rs;
    integer dispatch_lsq;
    integer commit_lane;
    integer commit_rob;
    logic [ROB_W-1:0] dispatch_rob_idx;
    logic [31:0] effective_addr;
    logic [31:0] shifted_store_data;
    logic [3:0] generated_strobe;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rob_head_q <= {ROB_W{1'b0}};
            rob_tail_q <= {ROB_W{1'b0}};
            rob_count_q <= {ROB_COUNT_W{1'b0}};
            next_seq_q <= 32'b0;
            unresolved_branch_q <= 1'b0;
            unresolved_branch_seq_q <= 32'b0;

            mul_busy_q <= 1'b0;
            mul_count_q <= {M_COUNT_W{1'b0}};
            mul_rob_q <= {ROB_W{1'b0}};
            mul_pdst_q <= {PRF_W{1'b0}};
            mul_writes_q <= 1'b0;
            mul_result_q <= 32'b0;

            mem_pending_q <= 1'b0;
            mem_busy_q <= 1'b0;
            mem_drop_response_q <= 1'b0;
            mem_req_write_q <= 1'b0;
            mem_req_addr_q <= 32'b0;
            mem_req_wdata_q <= 32'b0;
            mem_req_wstrb_q <= 4'b0;
            mem_lsq_q <= {LSQ_W{1'b0}};
            mem_rob_q <= {ROB_W{1'b0}};
            mem_pdst_q <= {PRF_W{1'b0}};
            mem_writes_q <= 1'b0;
            mem_funct3_q <= 3'b0;
            mem_byte_offset_q <= 2'b0;

            retire_valid_out <= 2'b0;
            retire_pc_out <= '0;
            retire_instr_out <= '0;
            retire_rd_write_out <= 2'b0;
            retire_rd_addr_out <= '0;
            retire_rd_data_out <= '0;

            cycle_count_out <= 64'b0;
            retired_count_out <= 64'b0;
            ooo_completion_count_out <= 64'b0;
            rob_full_cycle_count_out <= 64'b0;
            load_block_cycle_count_out <= 64'b0;
            branch_recovery_count_out <= 64'b0;
            memory_fault_sticky_out <= 1'b0;

            for (i = 0; i < 32; i = i + 1) begin
                rat[i] <= i[PRF_W-1:0];
                committed_rat[i] <= i[PRF_W-1:0];
            end
            for (p = 0; p < PRF_COUNT; p = p + 1) begin
                prf_value[p] <= 32'b0;
                prf_ready[p] <= (p < 32);
                free_mask[p] <= (p >= 32);
            end
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                rob_valid[i] <= 1'b0;
                rob_ready[i] <= 1'b0;
                rob_pc[i] <= 32'b0;
                rob_instr[i] <= 32'h0000_0013;
                rob_seq[i] <= 32'b0;
                rob_writes_rd[i] <= 1'b0;
                rob_arch_rd[i] <= 5'b0;
                rob_pdst[i] <= {PRF_W{1'b0}};
                rob_old_pdst[i] <= {PRF_W{1'b0}};
                rob_value[i] <= 32'b0;
                rob_is_control[i] <= 1'b0;
                rob_control_target[i] <= 32'b0;
                rob_mispredict[i] <= 1'b0;
                rob_is_store[i] <= 1'b0;
                rob_store_done[i] <= 1'b0;
            end
            for (i = 0; i < RS_DEPTH; i = i + 1) begin
                rs_valid[i] <= 1'b0;
                rs_seq[i] <= 32'b0;
                rs_rob[i] <= {ROB_W{1'b0}};
                rs_lsq[i] <= {LSQ_W{1'b0}};
                rs_class[i] <= CLASS_ALU;
                rs_pc[i] <= 32'b0;
                rs_instr[i] <= 32'h0000_0013;
                rs_writes_rd[i] <= 1'b0;
                rs_pdst[i] <= {PRF_W{1'b0}};
                rs_src1_ready[i] <= 1'b0;
                rs_src2_ready[i] <= 1'b0;
                rs_src1_tag[i] <= {PRF_W{1'b0}};
                rs_src2_tag[i] <= {PRF_W{1'b0}};
                rs_src1_value[i] <= 32'b0;
                rs_src2_value[i] <= 32'b0;
            end
            for (i = 0; i < LSQ_DEPTH; i = i + 1) begin
                lsq_valid[i] <= 1'b0;
                lsq_is_store[i] <= 1'b0;
                lsq_addr_valid[i] <= 1'b0;
                lsq_issued[i] <= 1'b0;
                lsq_seq[i] <= 32'b0;
                lsq_rob[i] <= {ROB_W{1'b0}};
                lsq_pdst[i] <= {PRF_W{1'b0}};
                lsq_addr[i] <= 32'b0;
                lsq_wdata[i] <= 32'b0;
                lsq_wstrb[i] <= 4'b0;
                lsq_funct3[i] <= 3'b0;
                lsq_byte_offset[i] <= 2'b0;
            end
        end
        else begin
            retire_valid_out <= 2'b0;
            retire_rd_write_out <= 2'b0;
            retire_pc_out <= '0;
            retire_instr_out <= '0;
            retire_rd_addr_out <= '0;
            retire_rd_data_out <= '0;

            cycle_count_out <= cycle_count_out + 1'b1;
            if (rob_count_q == ROB_DEPTH)
                rob_full_cycle_count_out <= rob_full_cycle_count_out + 1'b1;
            if (any_load_blocked)
                load_block_cycle_count_out <= load_block_cycle_count_out + 1'b1;

            if (recovery_now) begin
                // The redirecting control instruction is the sole retirement
                // in a recovery cycle.  Its committed destination (JAL/JALR)
                // is included before rebuilding the speculative map/free list.
                retire_valid_out[0] <= 1'b1;
                retire_pc_out[0] <= rob_pc[rob_head_q];
                retire_instr_out[0] <= rob_instr[rob_head_q];
                retire_rd_write_out[0] <= rob_writes_rd[rob_head_q];
                retire_rd_addr_out[0] <= rob_arch_rd[rob_head_q];
                retire_rd_data_out[0] <= rob_writes_rd[rob_head_q] ?
                                         rob_value[rob_head_q] : 32'b0;
                retired_count_out <= retired_count_out + 1'b1;
                branch_recovery_count_out <= branch_recovery_count_out + 1'b1;

                for (i = 0; i < 32; i = i + 1) begin
                    if ((i == rob_arch_rd[rob_head_q]) &&
                        rob_writes_rd[rob_head_q]) begin
                        committed_rat[i] <= rob_pdst[rob_head_q];
                        rat[i] <= rob_pdst[rob_head_q];
                    end
                    else begin
                        rat[i] <= committed_rat[i];
                    end
                end
                free_mask <= recovery_free_mask;
                for (p = 0; p < PRF_COUNT; p = p + 1) begin
                    if (!recovery_free_mask[p])
                        prf_ready[p] <= 1'b1;
                end

                rob_head_q <= {ROB_W{1'b0}};
                rob_tail_q <= {ROB_W{1'b0}};
                rob_count_q <= {ROB_COUNT_W{1'b0}};
                unresolved_branch_q <= 1'b0;
                unresolved_branch_seq_q <= 32'b0;
                mul_busy_q <= 1'b0;
                mul_count_q <= {M_COUNT_W{1'b0}};
                mem_pending_q <= 1'b0;
                if (mem_busy_q && !dmem_resp_valid_in)
                    mem_drop_response_q <= 1'b1;
                else
                    mem_drop_response_q <= 1'b0;
                mem_busy_q <= 1'b0;

                for (i = 0; i < ROB_DEPTH; i = i + 1)
                    rob_valid[i] <= 1'b0;
                for (i = 0; i < RS_DEPTH; i = i + 1)
                    rs_valid[i] <= 1'b0;
                for (i = 0; i < LSQ_DEPTH; i = i + 1)
                    lsq_valid[i] <= 1'b0;
            end
            else begin
                if (ooo_completion_events != 0)
                    ooo_completion_count_out <= ooo_completion_count_out +
                                                ooo_completion_events;

                // Keep waiting operands synchronized with completed physical
                // registers.  Explicit broadcasts below remove the extra
                // cycle for same-edge wakeups.
                for (i = 0; i < RS_DEPTH; i = i + 1) begin
                    if (rs_valid[i] && !rs_src1_ready[i] &&
                        prf_ready[rs_src1_tag[i]]) begin
                        rs_src1_ready[i] <= 1'b1;
                        rs_src1_value[i] <= prf_value[rs_src1_tag[i]];
                    end
                    if (rs_valid[i] && !rs_src2_ready[i] &&
                        prf_ready[rs_src2_tag[i]]) begin
                        rs_src2_ready[i] <= 1'b1;
                        rs_src2_value[i] <= prf_value[rs_src2_tag[i]];
                    end
                end

                // Two combinational integer/control completions.
                if (alu0_valid) begin
                    rs_valid[alu_sel0_i] <= 1'b0;
                    rob_ready[alu0_rob] <= 1'b1;
                    rob_value[alu0_rob] <= alu0_value;
                    if (alu0_control) begin
                        rob_control_target[alu0_rob] <= alu0_target;
                        rob_mispredict[alu0_rob] <=
                            (alu0_target != (rob_pc[alu0_rob] + 4));
                    end
                    if (alu0_writes) begin
                        prf_value[alu0_pdst] <= alu0_value;
                        prf_ready[alu0_pdst] <= 1'b1;
                    end
                end
                if (alu1_valid) begin
                    rs_valid[alu_sel1_i] <= 1'b0;
                    rob_ready[alu1_rob] <= 1'b1;
                    rob_value[alu1_rob] <= alu1_value;
                    if (alu1_control) begin
                        rob_control_target[alu1_rob] <= alu1_target;
                        rob_mispredict[alu1_rob] <=
                            (alu1_target != (rob_pc[alu1_rob] + 4));
                    end
                    if (alu1_writes) begin
                        prf_value[alu1_pdst] <= alu1_value;
                        prf_ready[alu1_pdst] <= 1'b1;
                    end
                end

                // Broadcast both integer lanes.
                for (i = 0; i < RS_DEPTH; i = i + 1) begin
                    if (rs_valid[i] && alu0_valid && alu0_writes) begin
                        if (!rs_src1_ready[i] && (rs_src1_tag[i] == alu0_pdst)) begin
                            rs_src1_ready[i] <= 1'b1;
                            rs_src1_value[i] <= alu0_value;
                        end
                        if (!rs_src2_ready[i] && (rs_src2_tag[i] == alu0_pdst)) begin
                            rs_src2_ready[i] <= 1'b1;
                            rs_src2_value[i] <= alu0_value;
                        end
                    end
                    if (rs_valid[i] && alu1_valid && alu1_writes) begin
                        if (!rs_src1_ready[i] && (rs_src1_tag[i] == alu1_pdst)) begin
                            rs_src1_ready[i] <= 1'b1;
                            rs_src1_value[i] <= alu1_value;
                        end
                        if (!rs_src2_ready[i] && (rs_src2_tag[i] == alu1_pdst)) begin
                            rs_src2_ready[i] <= 1'b1;
                            rs_src2_value[i] <= alu1_value;
                        end
                    end
                end

                // M unit issue/countdown/writeback.
                if (mul_sel_i >= 0) begin
                    rs_valid[mul_sel_i] <= 1'b0;
                    mul_busy_q <= 1'b1;
                    mul_count_q <= M_LATENCY;
                    mul_rob_q <= rs_rob[mul_sel_i];
                    mul_pdst_q <= rs_pdst[mul_sel_i];
                    mul_writes_q <= rs_writes_rd[mul_sel_i];
                    mul_result_q <= muldiv_result(rs_instr[mul_sel_i],
                                                  rs_src1_value[mul_sel_i],
                                                  rs_src2_value[mul_sel_i]);
                end
                else if (mul_busy_q && (mul_count_q != 0)) begin
                    mul_count_q <= mul_count_q - 1'b1;
                end
                if (mul_wb_valid) begin
                    mul_busy_q <= 1'b0;
                    mul_count_q <= {M_COUNT_W{1'b0}};
                    rob_ready[mul_rob_q] <= 1'b1;
                    rob_value[mul_rob_q] <= mul_result_q;
                    if (mul_writes_q) begin
                        prf_value[mul_pdst_q] <= mul_result_q;
                        prf_ready[mul_pdst_q] <= 1'b1;
                        for (i = 0; i < RS_DEPTH; i = i + 1) begin
                            if (rs_valid[i] && !rs_src1_ready[i] &&
                                (rs_src1_tag[i] == mul_pdst_q)) begin
                                rs_src1_ready[i] <= 1'b1;
                                rs_src1_value[i] <= mul_result_q;
                            end
                            if (rs_valid[i] && !rs_src2_ready[i] &&
                                (rs_src2_tag[i] == mul_pdst_q)) begin
                                rs_src2_ready[i] <= 1'b1;
                                rs_src2_value[i] <= mul_result_q;
                            end
                        end
                    end
                end

                // One LSU address/data generation per cycle.
                if (lsu_sel_i >= 0) begin
                    rs_valid[lsu_sel_i] <= 1'b0;
                    dispatch_lsq = rs_lsq[lsu_sel_i];
                    effective_addr = rs_src1_value[lsu_sel_i] +
                        ((rs_class[lsu_sel_i] == CLASS_STORE) ?
                         imm_s(rs_instr[lsu_sel_i]) : imm_i(rs_instr[lsu_sel_i]));
                    lsq_addr_valid[dispatch_lsq] <= 1'b1;
                    lsq_addr[dispatch_lsq] <= {effective_addr[31:2], 2'b00};
                    lsq_byte_offset[dispatch_lsq] <= effective_addr[1:0];
                    lsq_funct3[dispatch_lsq] <= rs_instr[lsu_sel_i][14:12];
                    if (rs_class[lsu_sel_i] == CLASS_STORE) begin
                        shifted_store_data = rs_src2_value[lsu_sel_i] <<
                                             (effective_addr[1:0] * 8);
                        unique case (rs_instr[lsu_sel_i][14:12])
                            3'b000: generated_strobe = 4'b0001 << effective_addr[1:0];
                            3'b001: generated_strobe = 4'b0011 << effective_addr[1:0];
                            default: generated_strobe = 4'b1111;
                        endcase
                        lsq_wdata[dispatch_lsq] <= shifted_store_data;
                        lsq_wstrb[dispatch_lsq] <= generated_strobe;
                        rob_ready[rs_rob[lsu_sel_i]] <= 1'b1;
                    end
                end

                // Select and latch a stable memory request.
                if (!mem_pending_q && !mem_busy_q && !mem_drop_response_q &&
                    (mem_candidate_i >= 0)) begin
                    mem_pending_q <= 1'b1;
                    mem_req_write_q <= lsq_is_store[mem_candidate_i];
                    mem_req_addr_q <= lsq_addr[mem_candidate_i];
                    mem_req_wdata_q <= lsq_wdata[mem_candidate_i];
                    mem_req_wstrb_q <= lsq_wstrb[mem_candidate_i];
                    mem_lsq_q <= mem_candidate_i[LSQ_W-1:0];
                    mem_rob_q <= lsq_rob[mem_candidate_i];
                    mem_pdst_q <= lsq_pdst[mem_candidate_i];
                    mem_writes_q <= rob_writes_rd[lsq_rob[mem_candidate_i]];
                    mem_funct3_q <= lsq_funct3[mem_candidate_i];
                    mem_byte_offset_q <= lsq_byte_offset[mem_candidate_i];
                end
                if (dmem_request_fire) begin
                    mem_pending_q <= 1'b0;
                    mem_busy_q <= 1'b1;
                    lsq_issued[mem_lsq_q] <= 1'b1;
                end
                if (mem_drop_response_q && dmem_resp_valid_in)
                    mem_drop_response_q <= 1'b0;
                else if (mem_busy_q && dmem_resp_valid_in) begin
                    mem_busy_q <= 1'b0;
                    if (dmem_resp_error_in)
                        memory_fault_sticky_out <= 1'b1;
                    if (mem_req_write_q) begin
                        rob_store_done[mem_rob_q] <= 1'b1;
                    end
                    else begin
                        rob_ready[mem_rob_q] <= 1'b1;
                        rob_value[mem_rob_q] <= memory_load_value;
                        lsq_valid[mem_lsq_q] <= 1'b0;
                        if (mem_writes_q) begin
                            prf_value[mem_pdst_q] <= memory_load_value;
                            prf_ready[mem_pdst_q] <= 1'b1;
                            for (i = 0; i < RS_DEPTH; i = i + 1) begin
                                if (rs_valid[i] && !rs_src1_ready[i] &&
                                    (rs_src1_tag[i] == mem_pdst_q)) begin
                                    rs_src1_ready[i] <= 1'b1;
                                    rs_src1_value[i] <= memory_load_value;
                                end
                                if (rs_valid[i] && !rs_src2_ready[i] &&
                                    (rs_src2_tag[i] == mem_pdst_q)) begin
                                    rs_src2_ready[i] <= 1'b1;
                                    rs_src2_value[i] <= memory_load_value;
                                end
                            end
                        end
                    end
                end

                // Rename and dispatch up to two instructions.  Lane 1 sees
                // lane 0's newly allocated mapping, which implements same-
                // packet RAW and WAW correctly without architectural stalls.
                for (dispatch_lane = 0; dispatch_lane < 2; dispatch_lane = dispatch_lane + 1) begin
                    if (dispatch_count > dispatch_lane) begin
                        dispatch_rob_idx = (dispatch_lane == 0) ?
                                           rob_tail_q : rob_next(rob_tail_q);
                        rob_valid[dispatch_rob_idx] <= 1'b1;
                        rob_ready[dispatch_rob_idx] <= !slot_supported[dispatch_lane];
                        rob_pc[dispatch_rob_idx] <= slot_pc[dispatch_lane];
                        rob_instr[dispatch_rob_idx] <= slot_instr[dispatch_lane];
                        rob_seq[dispatch_rob_idx] <= next_seq_q + dispatch_lane;
                        rob_writes_rd[dispatch_rob_idx] <= slot_writes_rd[dispatch_lane];
                        rob_arch_rd[dispatch_rob_idx] <= slot_rd[dispatch_lane];
                        rob_pdst[dispatch_rob_idx] <= slot_new_pdst[dispatch_lane];
                        rob_old_pdst[dispatch_rob_idx] <= slot_old_pdst[dispatch_lane];
                        rob_value[dispatch_rob_idx] <= 32'b0;
                        rob_is_control[dispatch_rob_idx] <= slot_supported[dispatch_lane] &&
                                                           (slot_class[dispatch_lane] == CLASS_CONTROL);
                        rob_control_target[dispatch_rob_idx] <= slot_pc[dispatch_lane] + 4;
                        rob_mispredict[dispatch_rob_idx] <= 1'b0;
                        rob_is_store[dispatch_rob_idx] <= slot_supported[dispatch_lane] &&
                                                         (slot_class[dispatch_lane] == CLASS_STORE);
                        rob_store_done[dispatch_rob_idx] <= 1'b0;

                        if (slot_writes_rd[dispatch_lane]) begin
                            rat[slot_rd[dispatch_lane]] <= slot_new_pdst[dispatch_lane];
                            free_mask[slot_new_pdst[dispatch_lane]] <= 1'b0;
                            prf_ready[slot_new_pdst[dispatch_lane]] <= 1'b0;
                        end
                        if (slot_supported[dispatch_lane] &&
                            (slot_class[dispatch_lane] == CLASS_CONTROL)) begin
                            unresolved_branch_q <= 1'b1;
                            unresolved_branch_seq_q <= next_seq_q + dispatch_lane;
                        end

                        if (slot_supported[dispatch_lane]) begin
                            dispatch_rs = slot_rs_index[dispatch_lane];
                            rs_valid[dispatch_rs] <= 1'b1;
                            rs_seq[dispatch_rs] <= next_seq_q + dispatch_lane;
                            rs_rob[dispatch_rs] <= dispatch_rob_idx;
                            rs_class[dispatch_rs] <= slot_class[dispatch_lane];
                            rs_pc[dispatch_rs] <= slot_pc[dispatch_lane];
                            rs_instr[dispatch_rs] <= slot_instr[dispatch_lane];
                            rs_writes_rd[dispatch_rs] <= slot_writes_rd[dispatch_lane];
                            rs_pdst[dispatch_rs] <= slot_new_pdst[dispatch_lane];
                            rs_src1_tag[dispatch_rs] <= slot_src1_tag[dispatch_lane];
                            rs_src2_tag[dispatch_rs] <= slot_src2_tag[dispatch_lane];
                            rs_src1_ready[dispatch_rs] <=
                                !slot_rs1_used[dispatch_lane] ? 1'b1 :
                                (((dispatch_lane == 1) && slot_writes_rd[0] &&
                                  (slot_rs1[1] == slot_rd[0])) ? 1'b0 :
                                 prf_ready[slot_src1_tag[dispatch_lane]]);
                            rs_src2_ready[dispatch_rs] <=
                                !slot_rs2_used[dispatch_lane] ? 1'b1 :
                                (((dispatch_lane == 1) && slot_writes_rd[0] &&
                                  (slot_rs2[1] == slot_rd[0])) ? 1'b0 :
                                 prf_ready[slot_src2_tag[dispatch_lane]]);
                            rs_src1_value[dispatch_rs] <= !slot_rs1_used[dispatch_lane] ? 32'b0 :
                                prf_value[slot_src1_tag[dispatch_lane]];
                            rs_src2_value[dispatch_rs] <= !slot_rs2_used[dispatch_lane] ? 32'b0 :
                                prf_value[slot_src2_tag[dispatch_lane]];

                            if ((slot_class[dispatch_lane] == CLASS_LOAD) ||
                                (slot_class[dispatch_lane] == CLASS_STORE)) begin
                                dispatch_lsq = slot_lsq_index[dispatch_lane];
                                rs_lsq[dispatch_rs] <= dispatch_lsq[LSQ_W-1:0];
                                lsq_valid[dispatch_lsq] <= 1'b1;
                                lsq_is_store[dispatch_lsq] <=
                                    (slot_class[dispatch_lane] == CLASS_STORE);
                                lsq_addr_valid[dispatch_lsq] <= 1'b0;
                                lsq_issued[dispatch_lsq] <= 1'b0;
                                lsq_seq[dispatch_lsq] <= next_seq_q + dispatch_lane;
                                lsq_rob[dispatch_lsq] <= dispatch_rob_idx;
                                lsq_pdst[dispatch_lsq] <= slot_new_pdst[dispatch_lane];
                            end
                            else begin
                                rs_lsq[dispatch_rs] <= {LSQ_W{1'b0}};
                            end
                        end
                    end
                end

                // Normal in-order commit.  Control instructions are kept in
                // lane 0; a redirecting one is handled by the recovery branch
                // above on its following head-ready cycle.
                for (commit_lane = 0; commit_lane < 2; commit_lane = commit_lane + 1) begin
                    if (commit_count > commit_lane) begin
                        commit_rob = (commit_lane == 0) ? rob_head_q : rob_head_next;
                        retire_valid_out[commit_lane] <= 1'b1;
                        retire_pc_out[commit_lane] <= rob_pc[commit_rob];
                        retire_instr_out[commit_lane] <= rob_instr[commit_rob];
                        retire_rd_write_out[commit_lane] <= rob_writes_rd[commit_rob];
                        retire_rd_addr_out[commit_lane] <= rob_arch_rd[commit_rob];
                        retire_rd_data_out[commit_lane] <= rob_writes_rd[commit_rob] ?
                                                          rob_value[commit_rob] : 32'b0;
                        rob_valid[commit_rob] <= 1'b0;
                        if (rob_writes_rd[commit_rob]) begin
                            committed_rat[rob_arch_rd[commit_rob]] <= rob_pdst[commit_rob];
                            free_mask[rob_old_pdst[commit_rob]] <= 1'b1;
                        end
                        if (rob_is_store[commit_rob]) begin
                            for (i = 0; i < LSQ_DEPTH; i = i + 1) begin
                                if (lsq_valid[i] && (lsq_rob[i] == commit_rob))
                                    lsq_valid[i] <= 1'b0;
                            end
                        end
                        if (rob_is_control[commit_rob])
                            unresolved_branch_q <= 1'b0;
                    end
                end

                rob_head_q <= (commit_count == 2) ? rob_next(rob_head_next) :
                              ((commit_count == 1) ? rob_head_next : rob_head_q);
                rob_tail_q <= (dispatch_count == 2) ? rob_next(rob_next(rob_tail_q)) :
                              ((dispatch_count == 1) ? rob_next(rob_tail_q) : rob_tail_q);
                rob_count_q <= rob_count_q + dispatch_count - commit_count;
                next_seq_q <= next_seq_q + dispatch_count;
                retired_count_out <= retired_count_out + commit_count;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (ROB_DEPTH < 4 || ((ROB_DEPTH & (ROB_DEPTH-1)) != 0))
            $fatal(1, "ooo_core ROB_DEPTH must be a power of two >= 4");
        if (RS_DEPTH < ROB_DEPTH)
            $fatal(1, "ooo_core RS_DEPTH must be at least ROB_DEPTH");
        if (LSQ_DEPTH < 2 || ((LSQ_DEPTH & (LSQ_DEPTH-1)) != 0))
            $fatal(1, "ooo_core LSQ_DEPTH must be a power of two >= 2");
        if (PRF_COUNT < 40)
            $fatal(1, "ooo_core PRF_COUNT must leave at least eight rename registers");
        if (M_LATENCY < 2)
            $fatal(1, "ooo_core M_LATENCY must be >= 2");
    end

    always_ff @(posedge clk) begin
        if (!reset) begin
            if (retire_valid_out[1] && !retire_valid_out[0])
                $fatal(1, "ooo_core retired lane 1 without lane 0");
            if (rat[0] != 0 || committed_rat[0] != 0 || prf_value[0] != 0)
                $fatal(1, "ooo_core x0 mapping/value invariant failed");
            if (rob_count_q > ROB_DEPTH)
                $fatal(1, "ooo_core ROB occupancy overflow");
            if (dmem_resp_valid_in && !mem_busy_q && !mem_drop_response_q)
                $fatal(1, "ooo_core received an unsolicited data response");
        end
    end
    // synthesis translate_on

endmodule
