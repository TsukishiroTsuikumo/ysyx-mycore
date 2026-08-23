`timescale 1ns/1ps

// Standalone two-wide in-order RV32IM core used by the phase-4 acceptance
// test.  It deliberately has a small backend: one ordered execution bundle
// may be resident at a time.  Non-memory bundles complete every cycle and can
// be replaced by the next bundle in the same edge.  An LSU instruction is
// always alone in lane 0 and backpressures issue until its response arrives.
module mycore_dual #(
    parameter integer ISSUE_WIDTH   = 2,
    parameter integer FETCH_DEPTH   = 8,
    parameter integer COUNTER_WIDTH = 64,
    parameter [31:0]  RESET_PC      = 32'h0000_0000
)(
    input  wire                         clk,
    input  wire                         reset,

    // Ordered 128-bit instruction-line interface.
    output wire                         pm_req_valid_out,
    output wire [31:0]                  pm_req_addr_out,
    input  wire                         pm_req_ready_in,
    input  wire                         pm_resp_valid_in,
    input  wire [127:0]                 pm_resp_data_in,
    input  wire [1:0]                   pm_resp_code_in,

    // Existing scalar data-memory request/response interface.
    output wire [31:0]                  dm_req_addr_out,
    output wire                         dm_req_rvalid_out,
    input  wire                         dm_req_rready_in,
    input  wire                         dm_resp_rvalid_in,
    input  wire [31:0]                  dm_resp_rdata_in,

    output wire                         dm_req_wvalid_out,
    input  wire                         dm_req_wready_in,
    output wire [3:0]                   dm_req_wstrb_out,
    output wire [31:0]                  dm_req_wdata_out,
    input  wire                         dm_resp_wvalid_in,

    // Registered, one-cycle retirement pulses.  Lane 0 is always older.
    output reg  [1:0]                   retire_valid_out,
    output reg  [1:0]                   commit_valid_out,
    output reg  [1:0][31:0]             retire_pc_out,
    output reg  [1:0][31:0]             retire_instr_out,
    output reg  [1:0][4:0]              commit_rd_addr_out,
    output reg  [1:0][31:0]             commit_rd_data_out,

    output wire [31:0]                  arch_regfile_out [0:31],

    output wire [COUNTER_WIDTH-1:0]     perf_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_issued_instr_count,
    output wire [COUNTER_WIDTH-1:0]     perf_retired_instr_count,
    output wire [COUNTER_WIDTH-1:0]     perf_dual_issue_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_dual_retire_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_frontend_empty_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_data_hazard_stall_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_memory_stall_cycle_count,
    output wire [COUNTER_WIDTH-1:0]     perf_pair_serialize_cycle_count
);

    localparam [2:0] CLASS_SIMPLE_INT = 3'd0;
    localparam [2:0] CLASS_MULDIV     = 3'd1;
    localparam [2:0] CLASS_LSU        = 3'd2;
    localparam [2:0] CLASS_CONTROL    = 3'd3;

    localparam [6:0] OPCODE_LOAD     = 7'b0000011;
    localparam [6:0] OPCODE_STORE    = 7'b0100011;

    localparam [31:0] NOP = 32'h0000_0013;

    // ------------------------------------------------------------
    // Architectural register file
    // ------------------------------------------------------------

    reg [31:0] arch_regs [0:31];
    genvar probe_index;
    generate
        for (probe_index = 0; probe_index < 32; probe_index = probe_index + 1) begin : gen_arch_probe
            assign arch_regfile_out[probe_index] =
                (probe_index == 0) ? 32'b0 : arch_regs[probe_index];
        end
    endgenerate

    // ------------------------------------------------------------
    // Fetch frontend
    // ------------------------------------------------------------

    wire [1:0] fetch_instr_valid;
    wire [31:0] fetch_instr0;
    wire [31:0] fetch_instr1;
    wire [31:0] fetch_pc0;
    wire [31:0] fetch_pc1;
    wire fetch_queue_full;
    wire fetch_queue_empty;
    wire [31:0] stale_response_count;
    wire [1:0] issue_consume_count;
    wire redirect_fire;
    wire [31:0] redirect_target;

    // The current core has no architectural instruction-access exception.
    // Preserve forward progress with a NOP line while exposing the bad
    // response to simulation assertions below.
    wire [127:0] checked_pm_resp_data =
        (pm_resp_code_in == 2'b00) ? pm_resp_data_in : {4{NOP}};

    fetch_frontend #(
        .LINE_BYTES(16),
        .QUEUE_DEPTH(FETCH_DEPTH),
        .RESET_PC(RESET_PC)
    ) u_fetch_frontend (
        .clk(clk),
        .reset(reset),
        .pm_req_valid(pm_req_valid_out),
        .pm_req_addr(pm_req_addr_out),
        .pm_req_ready(pm_req_ready_in),
        .pm_resp_valid(pm_resp_valid_in),
        .pm_resp_data(checked_pm_resp_data),
        .redirect_valid(redirect_fire),
        .redirect_target(redirect_target),
        .consume_count(issue_consume_count),
        .instr_valid(fetch_instr_valid),
        .instr0(fetch_instr0),
        .instr1(fetch_instr1),
        .pc0(fetch_pc0),
        .pc1(fetch_pc1),
        .queue_full(fetch_queue_full),
        .queue_empty(fetch_queue_empty),
        .stale_response_count(stale_response_count)
    );

    // ------------------------------------------------------------
    // Decode and combinational integer execution
    // ------------------------------------------------------------

    wire [1:0][31:0] id_instr;
    wire [1:0][31:0] id_pc;
    wire [1:0][4:0] id_rs1_addr;
    wire [1:0][4:0] id_rs2_addr;
    wire [1:0][31:0] id_rs1_value;
    wire [1:0][31:0] id_rs2_value;

    assign id_instr[0] = fetch_instr0;
    assign id_instr[1] = fetch_instr1;
    assign id_pc[0] = fetch_pc0;
    assign id_pc[1] = fetch_pc1;
    assign id_rs1_addr[0] = fetch_instr0[19:15];
    assign id_rs1_addr[1] = fetch_instr1[19:15];
    assign id_rs2_addr[0] = fetch_instr0[24:20];
    assign id_rs2_addr[1] = fetch_instr1[24:20];

    assign id_rs1_value[0] = (id_rs1_addr[0] == 5'd0) ? 32'b0 :
                             arch_regs[id_rs1_addr[0]];
    assign id_rs1_value[1] = (id_rs1_addr[1] == 5'd0) ? 32'b0 :
                             arch_regs[id_rs1_addr[1]];
    assign id_rs2_value[0] = (id_rs2_addr[0] == 5'd0) ? 32'b0 :
                             arch_regs[id_rs2_addr[0]];
    assign id_rs2_value[1] = (id_rs2_addr[1] == 5'd0) ? 32'b0 :
                             arch_regs[id_rs2_addr[1]];

    wire [1:0][2:0] id_class;
    wire [1:0] id_supported;
    wire [1:0] id_pairable_simple;
    wire [1:0] id_rs1_used;
    wire [1:0] id_rs2_used;
    wire [1:0] id_writes_rd;
    wire [1:0][4:0] id_rd_addr;
    wire [1:0] id_result_valid;
    wire [1:0][31:0] id_result;
    wire [1:0] id_control_valid;
    wire [1:0] id_branch_valid;
    wire [1:0] id_branch_taken;
    wire [1:0] id_redirect_valid;
    wire [1:0][31:0] id_redirect_target;

    execute_lane u_execute_lane0 (
        .valid(fetch_instr_valid[0]),
        .instr(id_instr[0]),
        .pc(id_pc[0]),
        .rs1_value(id_rs1_value[0]),
        .rs2_value(id_rs2_value[0]),
        .instr_class(id_class[0]),
        .supported(id_supported[0]),
        .pairable_simple(id_pairable_simple[0]),
        .rs1_used(id_rs1_used[0]),
        .rs2_used(id_rs2_used[0]),
        .writes_rd(id_writes_rd[0]),
        .rd_addr(id_rd_addr[0]),
        .result_valid(id_result_valid[0]),
        .result(id_result[0]),
        .control_valid(id_control_valid[0]),
        .branch_valid(id_branch_valid[0]),
        .branch_taken(id_branch_taken[0]),
        .redirect_valid(id_redirect_valid[0]),
        .redirect_target(id_redirect_target[0])
    );

    execute_lane u_execute_lane1 (
        .valid(fetch_instr_valid[1]),
        .instr(id_instr[1]),
        .pc(id_pc[1]),
        .rs1_value(id_rs1_value[1]),
        .rs2_value(id_rs2_value[1]),
        .instr_class(id_class[1]),
        .supported(id_supported[1]),
        .pairable_simple(id_pairable_simple[1]),
        .rs1_used(id_rs1_used[1]),
        .rs2_used(id_rs2_used[1]),
        .writes_rd(id_writes_rd[1]),
        .rd_addr(id_rd_addr[1]),
        .result_valid(id_result_valid[1]),
        .result(id_result[1]),
        .control_valid(id_control_valid[1]),
        .branch_valid(id_branch_valid[1]),
        .branch_taken(id_branch_taken[1]),
        .redirect_valid(id_redirect_valid[1]),
        .redirect_target(id_redirect_target[1])
    );

    // ------------------------------------------------------------
    // Ordered backend bundle
    // ------------------------------------------------------------

    reg [1:0] pipe_valid;
    reg [1:0][2:0] pipe_class;
    reg [1:0][31:0] pipe_pc;
    reg [1:0][31:0] pipe_instr;
    reg [1:0] pipe_writes_rd;
    reg [1:0][4:0] pipe_rd_addr;
    reg [1:0][31:0] pipe_result;

    reg pipe_is_load;
    reg pipe_is_store;
    reg [2:0] pipe_mem_funct3;
    reg [31:0] pipe_mem_addr;
    reg [3:0] pipe_store_wstrb;
    reg [31:0] pipe_store_data;
    reg mem_req_sent_q;

    wire pipe_any = |pipe_valid;
    wire pipe_lsu_active = pipe_valid[0] &&
                           (pipe_class[0] == CLASS_LSU) &&
                           (pipe_is_load || pipe_is_store);

    assign dm_req_addr_out = pipe_mem_addr;
    assign dm_req_rvalid_out = pipe_lsu_active && pipe_is_load &&
                               !mem_req_sent_q;
    assign dm_req_wvalid_out = pipe_lsu_active && pipe_is_store &&
                               !mem_req_sent_q;
    assign dm_req_wstrb_out = pipe_store_wstrb;
    assign dm_req_wdata_out = pipe_store_data;

    wire dm_read_request_fire = dm_req_rvalid_out && dm_req_rready_in;
    wire dm_write_request_fire = dm_req_wvalid_out && dm_req_wready_in;
    wire load_complete = pipe_lsu_active && pipe_is_load &&
                         dm_resp_rvalid_in &&
                         (mem_req_sent_q || dm_read_request_fire);
    wire store_complete = pipe_lsu_active && pipe_is_store &&
                          dm_resp_wvalid_in &&
                          (mem_req_sent_q || dm_write_request_fire);

    wire pipe_complete = pipe_any &&
                         (!pipe_lsu_active || load_complete || store_complete);
    wire backend_ready = !pipe_any || pipe_complete;

    wire [1:0] issue_valid;
    wire slot0_old_raw;
    wire slot1_old_raw;
    wire intra_pair_raw;
    wire structural_pair_block;
    wire data_hazard_stall;
    wire pair_serialize;

    issue_control #(
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_issue_control (
        .backend_ready(backend_ready),
        .kill_issue(1'b0),
        .slot_valid(fetch_instr_valid),
        .slot_class(id_class),
        .slot_rs1_used(id_rs1_used),
        .slot_rs2_used(id_rs2_used),
        .slot_rs1_addr(id_rs1_addr),
        .slot_rs2_addr(id_rs2_addr),
        .slot_writes_rd(id_writes_rd),
        .slot_rd_addr(id_rd_addr),
        .id_ex_valid(pipe_valid),
        .id_ex_writes_rd(pipe_writes_rd),
        .id_ex_rd_addr(pipe_rd_addr),
        .ex_mem_valid(2'b00),
        .ex_mem_writes_rd(2'b00),
        .ex_mem_rd_addr('0),
        .issue_valid(issue_valid),
        .consume_count(issue_consume_count),
        .slot0_old_raw(slot0_old_raw),
        .slot1_old_raw(slot1_old_raw),
        .intra_pair_raw(intra_pair_raw),
        .structural_pair_block(structural_pair_block),
        .data_hazard_stall(data_hazard_stall),
        .pair_serialize(pair_serialize)
    );

    assign redirect_fire = issue_valid[0] && id_control_valid[0] &&
                           id_redirect_valid[0];
    assign redirect_target = id_redirect_target[0];

    // ------------------------------------------------------------
    // RV32M and LSU helpers
    // ------------------------------------------------------------

    function automatic [31:0] rv32m_result(
        input [2:0] funct3,
        input [31:0] operand_a,
        input [31:0] operand_b
    );
        reg signed [32:0] a_signed_ext;
        reg signed [32:0] b_signed_ext;
        reg signed [32:0] b_unsigned_ext;
        reg signed [65:0] product_ss;
        reg signed [65:0] product_su;
        reg [63:0] product_uu;
        begin
            a_signed_ext = {operand_a[31], operand_a};
            b_signed_ext = {operand_b[31], operand_b};
            b_unsigned_ext = {1'b0, operand_b};
            product_ss = a_signed_ext * b_signed_ext;
            product_su = a_signed_ext * b_unsigned_ext;
            product_uu = {32'b0, operand_a} * {32'b0, operand_b};

            case (funct3)
                3'b000: rv32m_result = product_ss[31:0]; // MUL
                3'b001: rv32m_result = product_ss[63:32]; // MULH
                3'b010: rv32m_result = product_su[63:32]; // MULHSU
                3'b011: rv32m_result = product_uu[63:32]; // MULHU
                3'b100: begin // DIV
                    if (operand_b == 32'b0)
                        rv32m_result = 32'hffff_ffff;
                    else if ((operand_a == 32'h8000_0000) &&
                             (operand_b == 32'hffff_ffff))
                        rv32m_result = 32'h8000_0000;
                    else
                        rv32m_result = $signed(operand_a) / $signed(operand_b);
                end
                3'b101: begin // DIVU
                    rv32m_result = (operand_b == 32'b0) ? 32'hffff_ffff :
                                   (operand_a / operand_b);
                end
                3'b110: begin // REM
                    if (operand_b == 32'b0)
                        rv32m_result = operand_a;
                    else if ((operand_a == 32'h8000_0000) &&
                             (operand_b == 32'hffff_ffff))
                        rv32m_result = 32'b0;
                    else
                        rv32m_result = $signed(operand_a) % $signed(operand_b);
                end
                3'b111: begin // REMU
                    rv32m_result = (operand_b == 32'b0) ? operand_a :
                                   (operand_a % operand_b);
                end
                default: rv32m_result = 32'b0;
            endcase
        end
    endfunction

    function automatic [31:0] extend_load_data(
        input [2:0] funct3,
        input [31:0] raw_data
    );
        begin
            case (funct3)
                3'b000: extend_load_data = {{24{raw_data[7]}}, raw_data[7:0]};
                3'b001: extend_load_data = {{16{raw_data[15]}}, raw_data[15:0]};
                3'b010: extend_load_data = raw_data;
                3'b100: extend_load_data = {24'b0, raw_data[7:0]};
                3'b101: extend_load_data = {16'b0, raw_data[15:0]};
                default: extend_load_data = 32'b0;
            endcase
        end
    endfunction

    function automatic [3:0] decode_store_strobe(input [2:0] funct3);
        begin
            case (funct3)
                3'b000: decode_store_strobe = 4'b0001;
                3'b001: decode_store_strobe = 4'b0011;
                3'b010: decode_store_strobe = 4'b1111;
                default: decode_store_strobe = 4'b0000;
            endcase
        end
    endfunction

    wire [31:0] id_imm_i = {{20{id_instr[0][31]}}, id_instr[0][31:20]};
    wire [31:0] id_imm_s = {{20{id_instr[0][31]}}, id_instr[0][31:25],
                            id_instr[0][11:7]};
    wire id_lane0_is_load = (id_instr[0][6:0] == OPCODE_LOAD);
    wire id_lane0_is_store = (id_instr[0][6:0] == OPCODE_STORE);
    wire [31:0] id_mem_addr = id_rs1_value[0] +
                              (id_lane0_is_store ? id_imm_s : id_imm_i);
    wire [31:0] id_m_result = rv32m_result(
        id_instr[0][14:12], id_rs1_value[0], id_rs2_value[0]);
    wire [31:0] id_lane0_result =
        (id_class[0] == CLASS_MULDIV) ? id_m_result : id_result[0];

    wire [31:0] pipe_lane0_retire_data =
        pipe_is_load ? extend_load_data(pipe_mem_funct3, dm_resp_rdata_in) :
                       pipe_result[0];

    // ------------------------------------------------------------
    // Retirement, architectural writes and bundle replacement
    // ------------------------------------------------------------

    integer reg_index;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pipe_valid <= 2'b00;
            pipe_class <= '0;
            pipe_pc <= '0;
            pipe_instr <= '0;
            pipe_writes_rd <= 2'b00;
            pipe_rd_addr <= '0;
            pipe_result <= '0;
            pipe_is_load <= 1'b0;
            pipe_is_store <= 1'b0;
            pipe_mem_funct3 <= 3'b0;
            pipe_mem_addr <= 32'b0;
            pipe_store_wstrb <= 4'b0;
            pipe_store_data <= 32'b0;
            mem_req_sent_q <= 1'b0;

            retire_valid_out <= 2'b00;
            commit_valid_out <= 2'b00;
            retire_pc_out <= '0;
            retire_instr_out <= '0;
            commit_rd_addr_out <= '0;
            commit_rd_data_out <= '0;

            for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1)
                arch_regs[reg_index] <= 32'b0;
        end
        else begin
            // Retire outputs are registered pulses, never level indications.
            retire_valid_out <= 2'b00;
            commit_valid_out <= 2'b00;
            retire_pc_out <= '0;
            retire_instr_out <= '0;
            commit_rd_addr_out <= '0;
            commit_rd_data_out <= '0;
            arch_regs[0] <= 32'b0;

            if (pipe_complete) begin
                retire_valid_out <= pipe_valid;
                commit_valid_out <= pipe_valid & pipe_writes_rd;
                retire_pc_out <= pipe_pc;
                retire_instr_out <= pipe_instr;
                commit_rd_addr_out <= pipe_rd_addr;
                // Keep the retirement record canonical for writes to x0.
                // commit_valid still identifies the decoded rd write, while
                // its architectural value is always zero.
                commit_rd_data_out[0] <= (pipe_rd_addr[0] == 5'd0) ?
                                         32'b0 : pipe_lane0_retire_data;
                commit_rd_data_out[1] <= (pipe_rd_addr[1] == 5'd0) ?
                                         32'b0 : pipe_result[1];

                if (pipe_valid[0] && pipe_writes_rd[0] &&
                    (pipe_rd_addr[0] != 5'd0)) begin
                    arch_regs[pipe_rd_addr[0]] <= pipe_lane0_retire_data;
                end
                // Younger lane 1 is assigned second and therefore wins a
                // same-address WAW at this retirement edge.
                if (pipe_valid[1] && pipe_writes_rd[1] &&
                    (pipe_rd_addr[1] != 5'd0)) begin
                    arch_regs[pipe_rd_addr[1]] <= pipe_result[1];
                end
            end

            if (issue_valid[0]) begin
                pipe_valid <= issue_valid;
                pipe_class <= id_class;
                pipe_pc <= id_pc;
                pipe_instr <= id_instr;
                pipe_writes_rd <= id_writes_rd & issue_valid;
                pipe_rd_addr <= id_rd_addr;
                pipe_result[0] <= id_lane0_result;
                pipe_result[1] <= id_result[1];

                pipe_is_load <= (id_class[0] == CLASS_LSU) &&
                                id_lane0_is_load;
                pipe_is_store <= (id_class[0] == CLASS_LSU) &&
                                 id_lane0_is_store;
                pipe_mem_funct3 <= id_instr[0][14:12];
                pipe_mem_addr <= id_mem_addr;
                pipe_store_wstrb <= decode_store_strobe(id_instr[0][14:12]);
                pipe_store_data <= id_rs2_value[0];
                mem_req_sent_q <= 1'b0;
            end
            else if (pipe_complete) begin
                pipe_valid <= 2'b00;
                pipe_writes_rd <= 2'b00;
                pipe_is_load <= 1'b0;
                pipe_is_store <= 1'b0;
                mem_req_sent_q <= 1'b0;
            end
            else if (dm_read_request_fire || dm_write_request_fire) begin
                mem_req_sent_q <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Performance events
    // ------------------------------------------------------------

    wire [1:0] retire_event = pipe_complete ? pipe_valid : 2'b00;
    wire memory_stall_event = pipe_lsu_active && !pipe_complete;

    perf_counters #(
        .COUNTER_WIDTH(COUNTER_WIDTH),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_perf_counters (
        .clk(clk),
        .reset(reset),
        .clear(1'b0),
        .issue_valid(issue_valid),
        .retire_valid(retire_event),
        .frontend_empty(!fetch_instr_valid[0]),
        .data_hazard_stall(data_hazard_stall),
        .memory_stall(memory_stall_event),
        .pair_serialize(pair_serialize),
        .cycle_count(perf_cycle_count),
        .issued_instr_count(perf_issued_instr_count),
        .retired_instr_count(perf_retired_instr_count),
        .dual_issue_cycle_count(perf_dual_issue_cycle_count),
        .dual_retire_cycle_count(perf_dual_retire_cycle_count),
        .frontend_empty_cycle_count(perf_frontend_empty_cycle_count),
        .data_hazard_stall_cycle_count(perf_data_hazard_stall_cycle_count),
        .memory_stall_cycle_count(perf_memory_stall_cycle_count),
        .pair_serialize_cycle_count(perf_pair_serialize_cycle_count)
    );

    // ------------------------------------------------------------
    // Non-synthesis invariants
    // ------------------------------------------------------------

    // synthesis translate_off
    initial begin
        if ((ISSUE_WIDTH != 1) && (ISSUE_WIDTH != 2))
            $fatal(1, "mycore_dual ISSUE_WIDTH must be 1 or 2");
        if (FETCH_DEPTH < 2 || ((FETCH_DEPTH & (FETCH_DEPTH - 1)) != 0))
            $fatal(1, "mycore_dual FETCH_DEPTH must be a power of two >= 2");
        if (COUNTER_WIDTH < 32)
            $fatal(1, "mycore_dual COUNTER_WIDTH must be at least 32");
        if (RESET_PC[1:0] != 2'b00)
            $fatal(1, "mycore_dual RESET_PC must be four-byte aligned");
    end

    reg waw_check_valid_q;
    reg [4:0] waw_check_addr_q;
    reg [31:0] waw_check_value_q;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            waw_check_valid_q <= 1'b0;
            waw_check_addr_q <= 5'b0;
            waw_check_value_q <= 32'b0;
        end
        else begin
            if (waw_check_valid_q &&
                (arch_regs[waw_check_addr_q] !== waw_check_value_q))
                $error("mycore_dual lane1 did not win prior WAW retirement");

            waw_check_valid_q <= pipe_complete && pipe_valid[0] &&
                                 pipe_valid[1] && pipe_writes_rd[0] &&
                                 pipe_writes_rd[1] &&
                                 (pipe_rd_addr[0] != 5'd0) &&
                                 (pipe_rd_addr[0] == pipe_rd_addr[1]);
            waw_check_addr_q <= pipe_rd_addr[1];
            waw_check_value_q <= pipe_result[1];
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            if (issue_valid[1] && !issue_valid[0])
                $error("mycore_dual issued orphan lane1");
            if (issue_valid[1] &&
                ((id_class[0] != CLASS_SIMPLE_INT) ||
                 (id_class[1] != CLASS_SIMPLE_INT)))
                $error("mycore_dual dual-issued a serialized class");
            if (redirect_fire && issue_valid[1])
                $error("mycore_dual issued a younger instruction with redirect");
            if (pipe_valid[1] && !pipe_valid[0])
                $error("mycore_dual backend contains orphan lane1");
            if (pipe_valid[1] && (pipe_class[1] != CLASS_SIMPLE_INT))
                $error("mycore_dual lane1 contains a non-simple instruction");
            if (dm_req_rvalid_out && dm_req_wvalid_out)
                $error("mycore_dual asserted read and write requests together");
            if (dm_resp_rvalid_in &&
                !(pipe_lsu_active && pipe_is_load &&
                  (mem_req_sent_q || dm_read_request_fire)))
                $error("mycore_dual received an unsolicited read response");
            if (dm_resp_wvalid_in &&
                !(pipe_lsu_active && pipe_is_store &&
                  (mem_req_sent_q || dm_write_request_fire)))
                $error("mycore_dual received an unsolicited write response");
            if (retire_valid_out[1] && !retire_valid_out[0])
                $error("mycore_dual retired orphan lane1");
            if ((commit_valid_out & ~retire_valid_out) != 2'b00)
                $error("mycore_dual commit without retirement");
            if (&retire_valid_out &&
                (retire_pc_out[1] != (retire_pc_out[0] + 4)))
                $error("mycore_dual dual-retire PCs are not ordered");
            if (arch_regs[0] !== 32'b0)
                $error("mycore_dual architectural x0 changed");
            if (pm_resp_valid_in && (pm_resp_code_in != 2'b00))
                $display("mycore_dual: instruction response error code=%0b, substituting NOP line",
                         pm_resp_code_in);
        end
    end
    // synthesis translate_on

    // Keep diagnostic signals visible to waveform and lint tools.
    wire unused_diagnostics = fetch_queue_full ^ fetch_queue_empty ^
                              stale_response_count[0] ^ id_supported[0] ^
                              id_supported[1] ^ id_pairable_simple[0] ^
                              id_pairable_simple[1] ^ id_result_valid[0] ^
                              id_result_valid[1] ^ id_branch_valid[0] ^
                              id_branch_valid[1] ^ id_branch_taken[0] ^
                              id_branch_taken[1] ^ slot0_old_raw ^
                              slot1_old_raw ^ intra_pair_raw ^
                              structural_pair_block;

endmodule
