`timescale 1ns/1ps

// Self-contained phase-4 acceptance test for mycore_dual.
//
// Example Verilator invocations from the repository root:
//   verilator --binary --timing --sv -Wall -Wno-fatal \
//     --top-module dual_issue_core_tb -f test_bench/dual_issue/flist_dual.f
//   verilator --binary --timing --sv -Wall -Wno-fatal \
//     --top-module dual_issue_core_tb -GISSUE_WIDTH=1 \
//     -f test_bench/dual_issue/flist_dual.f
//
// No UVM, DPI, external memory image or plusarg is required.  The expected
// retirement queue is the primary oracle; architectural register checks are
// deliberately secondary so that dropped, duplicated, reordered and
// wrong-path retirement records cannot hide behind a correct final value.
module dual_issue_core_tb #(
    parameter integer ISSUE_WIDTH = 2
);

    localparam integer IMEM_WORDS = 512;
    localparam integer DMEM_BYTES = 1024;
    localparam integer TRACE_DEPTH = 512;
    localparam [31:0] NOP = 32'h0000_0013;
    localparam [31:0] JAL_HALT = 32'h0000_006f;

    localparam [6:0] OPCODE_OP     = 7'b0110011;
    localparam [6:0] OPCODE_OPIMM  = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;
    localparam [6:0] OPCODE_JAL    = 7'b1101111;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111;

    reg clk;
    reg reset;

    wire pm_req_valid;
    wire [31:0] pm_req_addr;
    wire pm_req_ready;
    wire pm_resp_valid;
    wire [127:0] pm_resp_data;
    wire [1:0] pm_resp_code;

    wire [31:0] dm_req_addr;
    wire dm_req_rvalid;
    wire dm_req_rready;
    wire dm_resp_rvalid;
    wire [31:0] dm_resp_rdata;
    wire dm_req_wvalid;
    wire dm_req_wready;
    wire [3:0] dm_req_wstrb;
    wire [31:0] dm_req_wdata;
    wire dm_resp_wvalid;

    wire [1:0] retire_valid;
    wire [1:0] commit_valid;
    wire [1:0][31:0] retire_pc;
    wire [1:0][31:0] retire_instr;
    wire [1:0][4:0] commit_rd_addr;
    wire [1:0][31:0] commit_rd_data;
    wire [31:0] arch_regfile [0:31];

    wire [63:0] perf_cycle_count;
    wire [63:0] perf_issued_instr_count;
    wire [63:0] perf_retired_instr_count;
    wire [63:0] perf_dual_issue_cycle_count;
    wire [63:0] perf_dual_retire_cycle_count;
    wire [63:0] perf_frontend_empty_cycle_count;
    wire [63:0] perf_data_hazard_stall_cycle_count;
    wire [63:0] perf_memory_stall_cycle_count;
    wire [63:0] perf_pair_serialize_cycle_count;

    mycore_dual #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FETCH_DEPTH(8),
        .COUNTER_WIDTH(64),
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk(clk),
        .reset(reset),
        .pm_req_valid_out(pm_req_valid),
        .pm_req_addr_out(pm_req_addr),
        .pm_req_ready_in(pm_req_ready),
        .pm_resp_valid_in(pm_resp_valid),
        .pm_resp_data_in(pm_resp_data),
        .pm_resp_code_in(pm_resp_code),
        .dm_req_addr_out(dm_req_addr),
        .dm_req_rvalid_out(dm_req_rvalid),
        .dm_req_rready_in(dm_req_rready),
        .dm_resp_rvalid_in(dm_resp_rvalid),
        .dm_resp_rdata_in(dm_resp_rdata),
        .dm_req_wvalid_out(dm_req_wvalid),
        .dm_req_wready_in(dm_req_wready),
        .dm_req_wstrb_out(dm_req_wstrb),
        .dm_req_wdata_out(dm_req_wdata),
        .dm_resp_wvalid_in(dm_resp_wvalid),
        .retire_valid_out(retire_valid),
        .commit_valid_out(commit_valid),
        .retire_pc_out(retire_pc),
        .retire_instr_out(retire_instr),
        .commit_rd_addr_out(commit_rd_addr),
        .commit_rd_data_out(commit_rd_data),
        .arch_regfile_out(arch_regfile),
        .perf_cycle_count(perf_cycle_count),
        .perf_issued_instr_count(perf_issued_instr_count),
        .perf_retired_instr_count(perf_retired_instr_count),
        .perf_dual_issue_cycle_count(perf_dual_issue_cycle_count),
        .perf_dual_retire_cycle_count(perf_dual_retire_cycle_count),
        .perf_frontend_empty_cycle_count(perf_frontend_empty_cycle_count),
        .perf_data_hazard_stall_cycle_count(
            perf_data_hazard_stall_cycle_count),
        .perf_memory_stall_cycle_count(perf_memory_stall_cycle_count),
        .perf_pair_serialize_cycle_count(perf_pair_serialize_cycle_count)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Instruction encoders
    // ------------------------------------------------------------

    function automatic [31:0] enc_r(
        input [6:0] funct7,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3,
        input [4:0] rd,
        input [6:0] opcode
    );
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_i(
        input signed [31:0] immediate,
        input [4:0] rs1,
        input [2:0] funct3,
        input [4:0] rd,
        input [6:0] opcode
    );
        reg [11:0] imm12;
        begin
            imm12 = immediate[11:0];
            enc_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s(
        input signed [31:0] immediate,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        reg [11:0] imm12;
        begin
            imm12 = immediate[11:0];
            enc_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0],
                     OPCODE_STORE};
        end
    endfunction

    function automatic [31:0] enc_b(
        input signed [31:0] offset,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        reg [12:0] imm13;
        begin
            imm13 = offset[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, funct3,
                     imm13[4:1], imm13[11], OPCODE_BRANCH};
        end
    endfunction

    function automatic [31:0] enc_u(
        input [19:0] immediate,
        input [4:0] rd,
        input [6:0] opcode
    );
        begin
            enc_u = {immediate, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_j(
        input signed [31:0] offset,
        input [4:0] rd
    );
        reg [20:0] imm21;
        begin
            imm21 = offset[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11],
                     imm21[19:12], rd, OPCODE_JAL};
        end
    endfunction

    function automatic [31:0] insn_addi(
        input [4:0] rd,
        input [4:0] rs1,
        input signed [31:0] immediate
    );
        begin
            insn_addi = enc_i(immediate, rs1, 3'b000, rd, OPCODE_OPIMM);
        end
    endfunction

    function automatic [31:0] insn_jal_halt;
        begin
            insn_jal_halt = JAL_HALT;
        end
    endfunction

    // ------------------------------------------------------------
    // One-cycle, pipelined, ordered line memory
    // ------------------------------------------------------------

    reg [31:0] imem [0:IMEM_WORDS-1];
    reg pm_pending_valid;
    reg [31:0] pm_pending_addr;

    function automatic [31:0] read_imem_word(input integer word_index);
        begin
            if ((word_index >= 0) && (word_index < IMEM_WORDS))
                read_imem_word = imem[word_index];
            else
                read_imem_word = NOP;
        end
    endfunction

    function automatic [127:0] read_imem_line(input [31:0] byte_addr);
        integer base_word;
        begin
            base_word = byte_addr[31:2];
            read_imem_line = {
                read_imem_word(base_word + 3),
                read_imem_word(base_word + 2),
                read_imem_word(base_word + 1),
                read_imem_word(base_word + 0)
            };
        end
    endfunction

    assign pm_req_ready = !reset;
    assign pm_resp_valid = pm_pending_valid;
    assign pm_resp_data = read_imem_line(pm_pending_addr);
    assign pm_resp_code = 2'b00;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pm_pending_valid <= 1'b0;
            pm_pending_addr <= 32'b0;
        end
        else begin
            pm_pending_valid <= pm_req_valid && pm_req_ready;
            if (pm_req_valid && pm_req_ready)
                pm_pending_addr <= pm_req_addr;
        end
    end

    // ------------------------------------------------------------
    // One-cycle scalar data memory
    // ------------------------------------------------------------

    reg [7:0] dmem [0:DMEM_BYTES-1];
    reg dm_pending_read;
    reg dm_pending_write;
    reg [31:0] dm_pending_addr;
    integer dmem_byte;
    integer dm_read_handshake_count;
    integer dm_write_handshake_count;

    function automatic [31:0] read_dmem_word(input [31:0] byte_addr);
        integer address;
        begin
            address = byte_addr;
            if ((address >= 0) && ((address + 3) < DMEM_BYTES)) begin
                read_dmem_word = {dmem[address + 3], dmem[address + 2],
                                  dmem[address + 1], dmem[address + 0]};
            end
            else begin
                read_dmem_word = 32'b0;
            end
        end
    endfunction

    assign dm_req_rready = !reset && !dm_pending_read && !dm_pending_write;
    assign dm_req_wready = !reset && !dm_pending_read && !dm_pending_write;
    assign dm_resp_rvalid = dm_pending_read;
    assign dm_resp_wvalid = dm_pending_write;
    assign dm_resp_rdata = read_dmem_word(dm_pending_addr);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dm_pending_read <= 1'b0;
            dm_pending_write <= 1'b0;
            dm_pending_addr <= 32'b0;
            dm_read_handshake_count <= 0;
            dm_write_handshake_count <= 0;
            for (dmem_byte = 0; dmem_byte < DMEM_BYTES;
                 dmem_byte = dmem_byte + 1)
                dmem[dmem_byte] <= 8'b0;
        end
        else begin
            dm_pending_read <= 1'b0;
            dm_pending_write <= 1'b0;

            if (dm_req_rvalid && dm_req_rready) begin
                dm_pending_read <= 1'b1;
                dm_pending_addr <= dm_req_addr;
                dm_read_handshake_count <= dm_read_handshake_count + 1;
            end

            if (dm_req_wvalid && dm_req_wready) begin
                dm_pending_write <= 1'b1;
                dm_pending_addr <= dm_req_addr;
                dm_write_handshake_count <= dm_write_handshake_count + 1;
                for (dmem_byte = 0; dmem_byte < 4;
                     dmem_byte = dmem_byte + 1) begin
                    if (dm_req_wstrb[dmem_byte] &&
                        ((dm_req_addr + dmem_byte) < DMEM_BYTES)) begin
                        dmem[dm_req_addr + dmem_byte] <=
                            dm_req_wdata[(dmem_byte * 8) +: 8];
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Ordered retirement scoreboard
    // ------------------------------------------------------------

    reg [31:0] expected_pc [0:TRACE_DEPTH-1];
    reg [31:0] expected_instr [0:TRACE_DEPTH-1];
    reg expected_commit [0:TRACE_DEPTH-1];
    reg [4:0] expected_rd [0:TRACE_DEPTH-1];
    reg [31:0] expected_data [0:TRACE_DEPTH-1];
    integer expected_count;
    integer expected_index;
    reg trace_enable;
    reg trace_complete;
    reg [63:0] trace_hash;
    reg [31:0] halt_pc;
    string active_test;

    reg saw_raw_illegal_dual;
    reg saw_waw_dual;
    reg saw_war_dual;
    reg saw_x0_dual;
    reg saw_redirect_with_response;

    // redirect_fire is combinational from the FIFO head and is consumed on
    // the rising edge.  Sample it in that same active region; by the following
    // falling edge the redirect has already cleared the frontend outputs.
    always @(posedge clk or posedge reset) begin
        if (reset)
            saw_redirect_with_response <= 1'b0;
        else if (dut.redirect_fire && pm_resp_valid)
            saw_redirect_with_response <= 1'b1;
    end

    task automatic append_expected(
        input integer word_index,
        input [31:0] instruction,
        input commit,
        input [4:0] rd,
        input [31:0] data
    );
        begin
            if ((word_index < 0) || (word_index >= IMEM_WORDS))
                $fatal(1, "%s: imem word index %0d is out of range",
                       active_test, word_index);
            if (expected_count >= TRACE_DEPTH)
                $fatal(1, "%s: expected trace overflow", active_test);

            imem[word_index] = instruction;
            expected_pc[expected_count] = word_index * 4;
            expected_instr[expected_count] = instruction;
            expected_commit[expected_count] = commit;
            expected_rd[expected_count] = rd;
            expected_data[expected_count] = data;
            expected_count = expected_count + 1;
        end
    endtask

    task automatic set_instruction(
        input integer word_index,
        input [31:0] instruction
    );
        begin
            if ((word_index < 0) || (word_index >= IMEM_WORDS))
                $fatal(1, "%s: imem word index %0d is out of range",
                       active_test, word_index);
            imem[word_index] = instruction;
            if (instruction == JAL_HALT)
                halt_pc = word_index * 4;
        end
    endtask

    task automatic check_retire_lane(input integer lane);
        integer index;
        begin
            index = expected_index;
            if (index >= expected_count)
                $fatal(1, "%s: unexpected lane%0d retire pc=%08x instr=%08x",
                       active_test, lane, retire_pc[lane], retire_instr[lane]);
            if (retire_pc[lane] !== expected_pc[index])
                $fatal(1,
                    "%s: trace[%0d] lane%0d PC got=%08x expected=%08x",
                    active_test, index, lane, retire_pc[lane],
                    expected_pc[index]);
            if (retire_instr[lane] !== expected_instr[index])
                $fatal(1,
                    "%s: trace[%0d] lane%0d instruction got=%08x expected=%08x",
                    active_test, index, lane, retire_instr[lane],
                    expected_instr[index]);
            if (commit_valid[lane] !== expected_commit[index])
                $fatal(1,
                    "%s: trace[%0d] lane%0d commit got=%0b expected=%0b",
                    active_test, index, lane, commit_valid[lane],
                    expected_commit[index]);
            if (expected_commit[index]) begin
                if (commit_rd_addr[lane] !== expected_rd[index])
                    $fatal(1,
                        "%s: trace[%0d] lane%0d rd got=x%0d expected=x%0d",
                        active_test, index, lane, commit_rd_addr[lane],
                        expected_rd[index]);
                if (commit_rd_data[lane] !== expected_data[index])
                    $fatal(1,
                        "%s: trace[%0d] lane%0d data got=%08x expected=%08x",
                        active_test, index, lane, commit_rd_data[lane],
                        expected_data[index]);
            end

            trace_hash = {trace_hash[62:0], trace_hash[63]} ^
                         {retire_pc[lane], retire_instr[lane]} ^
                         {59'b0, commit_rd_addr[lane]};
            expected_index = expected_index + 1;
        end
    endtask

    always @(negedge clk) begin
        if (!reset) begin
            if (retire_valid[1] && !retire_valid[0])
                $fatal(1, "%s: lane1 retired without older lane0", active_test);
            if ((commit_valid & ~retire_valid) != 2'b00)
                $fatal(1, "%s: commit without retirement", active_test);
            if ((retire_valid == 2'b11) &&
                (retire_pc[1] != (retire_pc[0] + 4)))
                $fatal(1, "%s: unordered dual retire %08x/%08x",
                       active_test, retire_pc[0], retire_pc[1]);
            if (arch_regfile[0] !== 32'b0)
                $fatal(1, "%s: architectural x0 changed to %08x",
                       active_test, arch_regfile[0]);
            if (dm_req_rvalid && dm_req_wvalid)
                $fatal(1, "%s: simultaneous data read and write request",
                       active_test);
            if (pm_req_valid && (pm_req_addr[3:0] != 4'b0000))
                $fatal(1, "%s: unaligned line request %08x",
                       active_test, pm_req_addr);
            if ((retire_valid == 2'b11) &&
                (retire_pc[0] == 32'h0000_0000) &&
                (retire_pc[1] == 32'h0000_0004)) begin
                if (active_test == "raw")
                    saw_raw_illegal_dual = 1'b1;
                if (active_test == "waw-war-x0")
                    saw_waw_dual = 1'b1;
            end
            if ((retire_valid == 2'b11) &&
                (active_test == "waw-war-x0") &&
                (retire_pc[0] == 32'h0000_0008) &&
                (retire_pc[1] == 32'h0000_000c))
                saw_war_dual = 1'b1;
            if ((retire_valid == 2'b11) &&
                (active_test == "waw-war-x0") &&
                (retire_pc[0] == 32'h0000_0010) &&
                (retire_pc[1] == 32'h0000_0014))
                saw_x0_dual = 1'b1;

            if (trace_enable) begin
                if (retire_valid[0])
                    check_retire_lane(0);
                if (retire_valid[1])
                    check_retire_lane(1);

                if ((expected_count != 0) &&
                    (expected_index == expected_count)) begin
                    trace_enable = 1'b0;
                    trace_complete = 1'b1;
                end
            end
            else if (trace_complete && (|retire_valid)) begin
                // A halt sentinel may already have entered the backend when
                // the final expected instruction retires.  It is the only
                // legal post-trace event; a repeated final instruction is a
                // real registered-pulse bug and must not be hidden by ending
                // the scoreboard early.
                if (retire_valid[0] &&
                    ((retire_pc[0] !== halt_pc) ||
                     (retire_instr[0] !== JAL_HALT)))
                    $fatal(1,
                        "%s: non-halt retirement after trace completion pc=%08x",
                        active_test, retire_pc[0]);
                if (retire_valid[1] &&
                    ((retire_pc[1] !== halt_pc) ||
                     (retire_instr[1] !== JAL_HALT)))
                    $fatal(1,
                        "%s: lane1 non-halt retirement after trace completion pc=%08x",
                        active_test, retire_pc[1]);
            end
        end
    end

    // ------------------------------------------------------------
    // Test control helpers
    // ------------------------------------------------------------

    integer clear_index;
    task automatic begin_test(input string test_name);
        begin
            reset = 1'b1;
            trace_enable = 1'b0;
            repeat (3) @(posedge clk);

            active_test = test_name;
            expected_count = 0;
            expected_index = 0;
            trace_complete = 1'b0;
            trace_hash = 64'hcbf2_9ce4_8422_2325;
            halt_pc = 32'hffff_ffff;
            saw_raw_illegal_dual = 1'b0;
            saw_waw_dual = 1'b0;
            saw_war_dual = 1'b0;
            saw_x0_dual = 1'b0;

            for (clear_index = 0; clear_index < IMEM_WORDS;
                 clear_index = clear_index + 1)
                imem[clear_index] = NOP;
        end
    endtask

    task automatic launch_test;
        begin
            if (expected_count == 0)
                $fatal(1, "%s: no expected retirement records", active_test);
            expected_index = 0;
            trace_complete = 1'b0;
            trace_enable = 1'b1;
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic wait_for_trace(input integer timeout_cycles);
        integer waited;
        begin
            waited = 0;
            while (!trace_complete && (waited < timeout_cycles)) begin
                @(negedge clk);
                waited = waited + 1;
            end
            if (!trace_complete)
                $fatal(1,
                    "%s: timeout after %0d cycles, retired %0d/%0d records",
                    active_test, waited, expected_index, expected_count);
            $display("TRACE PASS width=%0d test=%s retired=%0d hash=%016x",
                     ISSUE_WIDTH, active_test, expected_index, trace_hash);
        end
    endtask

    task automatic end_test;
        begin
            trace_enable = 1'b0;
            @(negedge clk);
            reset = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic expect_reg(
        input [4:0] reg_addr,
        input [31:0] expected_value
    );
        begin
            if (arch_regfile[reg_addr] !== expected_value)
                $fatal(1, "%s: x%0d got=%08x expected=%08x",
                       active_test, reg_addr, arch_regfile[reg_addr],
                       expected_value);
        end
    endtask

    // ------------------------------------------------------------
    // Directed programs
    // ------------------------------------------------------------

    task automatic test_performance;
        integer instruction_index;
        reg [4:0] rd;
        reg [31:0] instruction;
        reg [63:0] issue_cycles;
        reg [63:0] ipc_milli;
        reg [63:0] dual_percent;
        begin
            begin_test("performance");
            for (instruction_index = 0; instruction_index < 128;
                 instruction_index = instruction_index + 1) begin
                rd = (instruction_index % 31) + 1;
                instruction = insn_addi(
                    rd, 5'd0, instruction_index + 1);
                append_expected(instruction_index, instruction, 1'b1, rd,
                                instruction_index + 1);
            end
            set_instruction(128, insn_jal_halt());

            launch_test();
            wait_for_trace(400);

            if (perf_cycle_count == 0)
                $fatal(1, "performance: zero measured cycles");
            issue_cycles = perf_issued_instr_count -
                           perf_dual_issue_cycle_count;
            ipc_milli = (perf_retired_instr_count * 1000) /
                        perf_cycle_count;
            dual_percent = (issue_cycles == 0) ? 0 :
                           ((perf_dual_issue_cycle_count * 100) /
                            issue_cycles);

            if (ISSUE_WIDTH == 2) begin
                if (ipc_milli < 1600)
                    $fatal(1,
                        "performance: IPC %0d.%03d is below 1.600",
                        ipc_milli / 1000, ipc_milli % 1000);
                if (dual_percent < 80)
                    $fatal(1,
                        "performance: dual issue %0d%% is below 80%%",
                        dual_percent);
                if ((perf_dual_issue_cycle_count == 0) ||
                    (perf_dual_retire_cycle_count == 0))
                    $fatal(1, "performance: no genuine dual issue/retire");
            end
            else begin
                if ((perf_dual_issue_cycle_count != 0) ||
                    (perf_dual_retire_cycle_count != 0))
                    $fatal(1,
                        "performance: ISSUE_WIDTH=1 observed a dual event");
            end

            $display(
                "PERF PASS width=%0d cycles=%0d issued=%0d retired=%0d ipc=%0d.%03d dual_issue=%0d dual_retire=%0d dual_pct=%0d%%",
                ISSUE_WIDTH, perf_cycle_count, perf_issued_instr_count,
                perf_retired_instr_count, ipc_milli / 1000,
                ipc_milli % 1000, perf_dual_issue_cycle_count,
                perf_dual_retire_cycle_count, dual_percent);
            end_test();
        end
    endtask

    task automatic test_raw;
        reg [31:0] instruction;
        begin
            begin_test("raw");
            instruction = insn_addi(5'd1, 5'd0, 32'sd5);
            append_expected(0, instruction, 1'b1, 5'd1, 32'd5);
            instruction = insn_addi(5'd2, 5'd1, 32'sd3);
            append_expected(1, instruction, 1'b1, 5'd2, 32'd8);
            set_instruction(2, insn_jal_halt());

            launch_test();
            wait_for_trace(100);
            if ((ISSUE_WIDTH == 2) && saw_raw_illegal_dual)
                $fatal(1, "raw: dependent pc=0/4 pair retired together");
            expect_reg(5'd1, 32'd5);
            expect_reg(5'd2, 32'd8);
            end_test();
        end
    endtask

    task automatic test_waw_war_x0;
        reg [31:0] instruction;
        begin
            begin_test("waw-war-x0");
            instruction = insn_addi(5'd5, 5'd0, 32'sd11);
            append_expected(0, instruction, 1'b1, 5'd5, 32'd11);
            instruction = insn_addi(5'd5, 5'd0, 32'sd22);
            append_expected(1, instruction, 1'b1, 5'd5, 32'd22);
            instruction = insn_addi(5'd7, 5'd5, 32'sd1);
            append_expected(2, instruction, 1'b1, 5'd7, 32'd23);
            instruction = insn_addi(5'd5, 5'd0, 32'sd33);
            append_expected(3, instruction, 1'b1, 5'd5, 32'd33);
            instruction = insn_addi(5'd0, 5'd0, 32'sd99);
            append_expected(4, instruction, 1'b1, 5'd0, 32'b0);
            instruction = insn_addi(5'd8, 5'd0, 32'sd9);
            append_expected(5, instruction, 1'b1, 5'd8, 32'd9);
            set_instruction(6, insn_jal_halt());

            launch_test();
            wait_for_trace(120);
            expect_reg(5'd0, 32'b0);
            expect_reg(5'd5, 32'd33);
            expect_reg(5'd7, 32'd23);
            expect_reg(5'd8, 32'd9);
            if (ISSUE_WIDTH == 2) begin
                if (!saw_waw_dual)
                    $fatal(1, "waw-war-x0: WAW pair did not dual retire");
                if (!saw_war_dual)
                    $fatal(1, "waw-war-x0: WAR pair did not dual retire");
                if (!saw_x0_dual)
                    $fatal(1, "waw-war-x0: x0 pair did not dual retire");
            end
            end_test();
        end
    endtask

    task automatic test_m_extension;
        reg [31:0] instruction;
        begin
            begin_test("rv32m");
            instruction = enc_u(20'h80000, 5'd1, OPCODE_LUI);
            append_expected(0, instruction, 1'b1, 5'd1, 32'h8000_0000);
            instruction = insn_addi(5'd2, 5'd0, -32'sd1);
            append_expected(1, instruction, 1'b1, 5'd2, 32'hffff_ffff);

            instruction = enc_r(7'b0000001, 5'd2, 5'd1, 3'b100,
                                5'd3, OPCODE_OP);
            append_expected(2, instruction, 1'b1, 5'd3, 32'h8000_0000);
            instruction = enc_r(7'b0000001, 5'd2, 5'd1, 3'b110,
                                5'd4, OPCODE_OP);
            append_expected(3, instruction, 1'b1, 5'd4, 32'b0);
            instruction = enc_r(7'b0000001, 5'd0, 5'd1, 3'b100,
                                5'd5, OPCODE_OP);
            append_expected(4, instruction, 1'b1, 5'd5, 32'hffff_ffff);
            instruction = enc_r(7'b0000001, 5'd0, 5'd1, 3'b110,
                                5'd6, OPCODE_OP);
            append_expected(5, instruction, 1'b1, 5'd6, 32'h8000_0000);
            instruction = enc_r(7'b0000001, 5'd0, 5'd1, 3'b101,
                                5'd7, OPCODE_OP);
            append_expected(6, instruction, 1'b1, 5'd7, 32'hffff_ffff);
            instruction = enc_r(7'b0000001, 5'd0, 5'd1, 3'b111,
                                5'd8, OPCODE_OP);
            append_expected(7, instruction, 1'b1, 5'd8, 32'h8000_0000);
            instruction = enc_r(7'b0000001, 5'd2, 5'd1, 3'b000,
                                5'd9, OPCODE_OP);
            append_expected(8, instruction, 1'b1, 5'd9, 32'h8000_0000);
            instruction = enc_r(7'b0000001, 5'd2, 5'd1, 3'b001,
                                5'd10, OPCODE_OP);
            append_expected(9, instruction, 1'b1, 5'd10, 32'h0000_0000);
            instruction = enc_r(7'b0000001, 5'd1, 5'd2, 3'b010,
                                5'd11, OPCODE_OP);
            append_expected(10, instruction, 1'b1, 5'd11,
                            32'hffff_ffff);
            instruction = enc_r(7'b0000001, 5'd2, 5'd1, 3'b011,
                                5'd12, OPCODE_OP);
            append_expected(11, instruction, 1'b1, 5'd12,
                            32'h7fff_ffff);
            set_instruction(12, insn_jal_halt());

            launch_test();
            wait_for_trace(200);
            expect_reg(5'd3, 32'h8000_0000);
            expect_reg(5'd4, 32'b0);
            expect_reg(5'd5, 32'hffff_ffff);
            expect_reg(5'd6, 32'h8000_0000);
            expect_reg(5'd7, 32'hffff_ffff);
            expect_reg(5'd8, 32'h8000_0000);
            expect_reg(5'd9, 32'h8000_0000);
            expect_reg(5'd10, 32'b0);
            expect_reg(5'd11, 32'hffff_ffff);
            expect_reg(5'd12, 32'h7fff_ffff);
            end_test();
        end
    endtask

    task automatic test_load_store;
        reg [31:0] instruction;
        begin
            begin_test("load-store");
            instruction = insn_addi(5'd1, 5'd0, 32'sd64);
            append_expected(0, instruction, 1'b1, 5'd1, 32'd64);
            instruction = insn_addi(5'd2, 5'd0, -32'sd1);
            append_expected(1, instruction, 1'b1, 5'd2, 32'hffff_ffff);
            instruction = enc_s(32'sd0, 5'd2, 5'd1, 3'b000);
            append_expected(2, instruction, 1'b0, 5'd0, 32'b0);
            instruction = enc_s(32'sd2, 5'd2, 5'd1, 3'b001);
            append_expected(3, instruction, 1'b0, 5'd0, 32'b0);
            instruction = enc_s(32'sd4, 5'd2, 5'd1, 3'b010);
            append_expected(4, instruction, 1'b0, 5'd0, 32'b0);
            instruction = enc_i(32'sd0, 5'd1, 3'b000, 5'd3,
                                OPCODE_LOAD);
            append_expected(5, instruction, 1'b1, 5'd3, 32'hffff_ffff);
            instruction = enc_i(32'sd0, 5'd1, 3'b100, 5'd4,
                                OPCODE_LOAD);
            append_expected(6, instruction, 1'b1, 5'd4, 32'h0000_00ff);
            instruction = enc_i(32'sd2, 5'd1, 3'b001, 5'd5,
                                OPCODE_LOAD);
            append_expected(7, instruction, 1'b1, 5'd5, 32'hffff_ffff);
            instruction = enc_i(32'sd2, 5'd1, 3'b101, 5'd6,
                                OPCODE_LOAD);
            append_expected(8, instruction, 1'b1, 5'd6, 32'h0000_ffff);
            instruction = enc_i(32'sd4, 5'd1, 3'b010, 5'd7,
                                OPCODE_LOAD);
            append_expected(9, instruction, 1'b1, 5'd7, 32'hffff_ffff);
            set_instruction(10, insn_jal_halt());

            launch_test();
            wait_for_trace(250);
            if (dm_write_handshake_count != 3)
                $fatal(1, "load-store: got %0d writes, expected 3",
                       dm_write_handshake_count);
            if (dm_read_handshake_count != 5)
                $fatal(1, "load-store: got %0d reads, expected 5",
                       dm_read_handshake_count);
            if ((dmem[64] !== 8'hff) || (dmem[66] !== 8'hff) ||
                (dmem[67] !== 8'hff) || (dmem[68] !== 8'hff) ||
                (dmem[69] !== 8'hff) || (dmem[70] !== 8'hff) ||
                (dmem[71] !== 8'hff))
                $fatal(1, "load-store: byte strobes or write data are wrong");
            expect_reg(5'd3, 32'hffff_ffff);
            expect_reg(5'd4, 32'h0000_00ff);
            expect_reg(5'd5, 32'hffff_ffff);
            expect_reg(5'd6, 32'h0000_ffff);
            expect_reg(5'd7, 32'hffff_ffff);
            end_test();
        end
    endtask

    task automatic test_illegal_lsu_encodings;
        reg [31:0] instruction;
        begin
            begin_test("illegal-lsu");

            // funct3=011 is reserved for both RV32I LOAD and STORE.  The
            // instructions still retire in this no-exception intermediate
            // core, but must not commit a fabricated load value or launch a
            // zero-strobe memory transaction.
            instruction = enc_i(32'sd0, 5'd0, 3'b011, 5'd3,
                                OPCODE_LOAD);
            append_expected(0, instruction, 1'b0, 5'd0, 32'b0);
            instruction = enc_s(32'sd0, 5'd3, 5'd0, 3'b011);
            append_expected(1, instruction, 1'b0, 5'd0, 32'b0);
            instruction = insn_addi(5'd9, 5'd0, 32'sd9);
            append_expected(2, instruction, 1'b1, 5'd9, 32'd9);
            set_instruction(3, insn_jal_halt());

            launch_test();
            wait_for_trace(100);
            if ((dm_read_handshake_count != 0) ||
                (dm_write_handshake_count != 0))
                $fatal(1,
                    "illegal-lsu: reserved encoding launched a DM request");
            expect_reg(5'd3, 32'b0);
            expect_reg(5'd9, 32'd9);
            end_test();
        end
    endtask

    task automatic test_control_flow;
        reg [31:0] instruction;
        begin
            begin_test("control-flow");
            instruction = insn_addi(5'd1, 5'd0, 32'sd1);
            append_expected(0, instruction, 1'b1, 5'd1, 32'd1);
            instruction = enc_b(32'sd12, 5'd1, 5'd1, 3'b000);
            append_expected(1, instruction, 1'b0, 5'd0, 32'b0);

            set_instruction(2, insn_addi(5'd20, 5'd0, 32'sd99));
            set_instruction(3, insn_addi(5'd21, 5'd0, 32'sd99));

            instruction = enc_j(32'sd12, 5'd2);
            append_expected(4, instruction, 1'b1, 5'd2, 32'd20);
            // Wrong-path store: a redirect bug must be observable as a DM
            // handshake, not merely as an overwritten register value.
            set_instruction(5, enc_s(32'sd0, 5'd1, 5'd0, 3'b010));
            set_instruction(6, insn_addi(5'd23, 5'd0, 32'sd99));

            instruction = enc_u(20'h00000, 5'd3, OPCODE_AUIPC);
            append_expected(7, instruction, 1'b1, 5'd3, 32'd28);
            instruction = insn_addi(5'd3, 5'd3, 32'sd16);
            append_expected(8, instruction, 1'b1, 5'd3, 32'd44);
            instruction = enc_i(32'sd0, 5'd3, 3'b000, 5'd4,
                                OPCODE_JALR);
            append_expected(9, instruction, 1'b1, 5'd4, 32'd40);
            set_instruction(10, insn_addi(5'd24, 5'd0, 32'sd99));

            instruction = enc_b(32'sd8, 5'd0, 5'd0, 3'b001);
            append_expected(11, instruction, 1'b0, 5'd0, 32'b0);
            instruction = insn_addi(5'd5, 5'd0, 32'sd55);
            append_expected(12, instruction, 1'b1, 5'd5, 32'd55);
            set_instruction(13, insn_jal_halt());

            launch_test();
            wait_for_trace(250);
            expect_reg(5'd2, 32'd20);
            expect_reg(5'd3, 32'd44);
            expect_reg(5'd4, 32'd40);
            expect_reg(5'd5, 32'd55);
            expect_reg(5'd20, 32'b0);
            expect_reg(5'd21, 32'b0);
            expect_reg(5'd22, 32'b0);
            expect_reg(5'd23, 32'b0);
            expect_reg(5'd24, 32'b0);
            if ((dm_read_handshake_count != 0) ||
                (dm_write_handshake_count != 0))
                $fatal(1,
                    "control-flow: wrong-path instruction reached data memory");
            if (!saw_redirect_with_response)
                $fatal(1,
                    "control-flow: did not exercise redirect with stale response");
            end_test();
        end
    endtask

    // ------------------------------------------------------------
    // Top-level sequence
    // ------------------------------------------------------------

    initial begin
        if ((ISSUE_WIDTH != 1) && (ISSUE_WIDTH != 2))
            $fatal(1, "dual_issue_core_tb ISSUE_WIDTH must be 1 or 2");

        reset = 1'b1;
        trace_enable = 1'b0;
        trace_complete = 1'b0;
        expected_count = 0;
        expected_index = 0;
        active_test = "startup";

        test_performance();
        test_raw();
        test_waw_war_x0();
        test_m_extension();
        test_load_store();
        test_illegal_lsu_encodings();
        test_control_flow();

        $display("DUAL ISSUE CORE PASS ISSUE_WIDTH=%0d", ISSUE_WIDTH);
        $finish;
    end

endmodule
