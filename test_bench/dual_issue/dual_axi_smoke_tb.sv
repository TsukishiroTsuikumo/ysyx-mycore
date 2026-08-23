`timescale 1ns/1ps

// End-to-end phase-4 smoke test:
//   mycore_dual -> instruction-line AXI master
//               -> scalar D-cache -> data-line AXI master
//               -> shared AXI RAM
//
// The C model independently executes the installed program to generate the
// retirement, core-side data-request and final-register oracle.  Traffic
// checks additionally prove that both AXI read masters, read arbitration,
// D-cache hits/misses and dirty replacement were really exercised.
module dual_axi_smoke_tb;

    `include "cmodel_dpi.svh"

    localparam integer TRACE_DEPTH = 64;

    localparam [6:0] OPCODE_OP     = 7'b0110011;
    localparam [6:0] OPCODE_OPIMM  = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JAL    = 7'b1101111;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;

    localparam [31:0] JAL_HALT = 32'h0000_006f;

    reg clk;
    reg reset;

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

    wire sticky_bus_fault_valid;
    wire sticky_bus_fault_is_write;
    wire [31:0] sticky_bus_fault_addr;
    wire [1:0] sticky_bus_fault_resp;

    mycore_dual_axi_wrapper #(
        .ISSUE_WIDTH   (2),
        .FETCH_DEPTH   (8),
        .COUNTER_WIDTH (64),
        .RESET_PC      (32'h0000_0000),
        .MEM_WIDTH     (16),
        .MEM_BYTES     (65536)
    ) dut (
        .clk                                 (clk),
        .reset                               (reset),
        .retire_valid                        (retire_valid),
        .commit_valid                        (commit_valid),
        .retire_pc                           (retire_pc),
        .retire_instr                        (retire_instr),
        .commit_rd_addr                      (commit_rd_addr),
        .commit_rd_data                      (commit_rd_data),
        .arch_regfile                        (arch_regfile),
        .perf_cycle_count                    (perf_cycle_count),
        .perf_issued_instr_count             (perf_issued_instr_count),
        .perf_retired_instr_count            (perf_retired_instr_count),
        .perf_dual_issue_cycle_count          (perf_dual_issue_cycle_count),
        .perf_dual_retire_cycle_count         (perf_dual_retire_cycle_count),
        .perf_frontend_empty_cycle_count      (perf_frontend_empty_cycle_count),
        .perf_data_hazard_stall_cycle_count   (perf_data_hazard_stall_cycle_count),
        .perf_memory_stall_cycle_count        (perf_memory_stall_cycle_count),
        .perf_pair_serialize_cycle_count      (perf_pair_serialize_cycle_count),
        .sticky_bus_fault_valid               (sticky_bus_fault_valid),
        .sticky_bus_fault_is_write            (sticky_bus_fault_is_write),
        .sticky_bus_fault_addr                (sticky_bus_fault_addr),
        .sticky_bus_fault_resp                (sticky_bus_fault_resp)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Minimal RV32IM instruction encoders
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
        begin
            enc_i = {immediate[11:0], rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s(
        input signed [31:0] immediate,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        begin
            enc_s = {immediate[11:5], rs2, rs1, funct3,
                     immediate[4:0], OPCODE_STORE};
        end
    endfunction

    function automatic [31:0] enc_b(
        input signed [31:0] offset,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        begin
            enc_b = {offset[12], offset[10:5], rs2, rs1, funct3,
                     offset[4:1], offset[11], OPCODE_BRANCH};
        end
    endfunction

    function automatic [31:0] enc_j(
        input signed [31:0] offset,
        input [4:0] rd
    );
        begin
            enc_j = {offset[20], offset[10:1], offset[11],
                     offset[19:12], rd, OPCODE_JAL};
        end
    endfunction

    function automatic [31:0] insn_lui(
        input [4:0] rd,
        input [19:0] upper
    );
        begin
            insn_lui = {upper, rd, OPCODE_LUI};
        end
    endfunction

    function automatic [31:0] insn_addi(
        input [4:0] rd,
        input [4:0] rs1,
        input signed [31:0] immediate
    );
        begin
            insn_addi = enc_i(immediate, rs1, 3'b000, rd,
                              OPCODE_OPIMM);
        end
    endfunction

    function automatic [31:0] insn_add(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        begin
            insn_add = enc_r(7'b0000000, rs2, rs1, 3'b000, rd,
                             OPCODE_OP);
        end
    endfunction

    function automatic [31:0] insn_mul(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        begin
            insn_mul = enc_r(7'b0000001, rs2, rs1, 3'b000, rd,
                             OPCODE_OP);
        end
    endfunction

    function automatic [31:0] insn_lw(
        input [4:0] rd,
        input [4:0] rs1,
        input signed [31:0] immediate
    );
        begin
            insn_lw = enc_i(immediate, rs1, 3'b010, rd, OPCODE_LOAD);
        end
    endfunction

    function automatic [31:0] insn_sw(
        input [4:0] rs2,
        input [4:0] rs1,
        input signed [31:0] immediate
    );
        begin
            insn_sw = enc_s(immediate, rs2, rs1, 3'b010);
        end
    endfunction

    function automatic [31:0] insn_beq(
        input [4:0] rs1,
        input [4:0] rs2,
        input signed [31:0] offset
    );
        begin
            insn_beq = enc_b(offset, rs2, rs1, 3'b000);
        end
    endfunction

    function automatic [31:0] insn_bne(
        input [4:0] rs1,
        input [4:0] rs2,
        input signed [31:0] offset
    );
        begin
            insn_bne = enc_b(offset, rs2, rs1, 3'b001);
        end
    endfunction

    // ------------------------------------------------------------
    // Exact two-lane retirement trace
    // ------------------------------------------------------------

    reg [31:0] expected_pc [0:TRACE_DEPTH-1];
    reg [31:0] expected_instr [0:TRACE_DEPTH-1];
    reg        expected_commit [0:TRACE_DEPTH-1];
    reg [4:0]  expected_rd [0:TRACE_DEPTH-1];
    reg [31:0] expected_data [0:TRACE_DEPTH-1];
    reg expected_mem_write [0:TRACE_DEPTH-1];
    reg [31:0] expected_mem_addr [0:TRACE_DEPTH-1];
    reg [3:0] expected_mem_wstrb [0:TRACE_DEPTH-1];
    reg [31:0] expected_mem_wdata [0:TRACE_DEPTH-1];
    reg [31:0] expected_arch_regs [0:31];
    integer expected_count;
    integer expected_index;
    integer expected_mem_count;
    integer expected_mem_index;
    reg trace_enable;
    reg trace_complete;
    integer dual_retire_observed;

    task automatic install_instruction(
        input integer word_index,
        input [31:0] instruction
    );
        begin
            dut.write_word(word_index * 4, instruction);
        end
    endtask

    task automatic build_reference_oracle;
        integer oracle_word;
        integer oracle_reg;
        integer oracle_ok;
        integer oracle_halt_seen;
        reg [31:0] oracle_word_data;
        int unsigned oracle_pc;
        int unsigned oracle_instr;
        int unsigned oracle_commit;
        int unsigned oracle_rd;
        int unsigned oracle_data;
        int unsigned oracle_addr;
        int unsigned oracle_is_read;
        int unsigned oracle_rdata;
        int unsigned oracle_is_write;
        int unsigned oracle_wstrb;
        int unsigned oracle_wdata;
        begin
            if (!cmodel_init_empty())
                $fatal(1, "dual AXI C model initialization failed");
            for (oracle_word = 0; oracle_word < TRACE_DEPTH;
                 oracle_word = oracle_word + 1) begin
                dut.read_word(oracle_word * 4, oracle_word_data);
                cmodel_imem_write32(oracle_word * 4, oracle_word_data);
            end

            expected_count = 0;
            expected_mem_count = 0;
            oracle_halt_seen = 0;
            while (!oracle_halt_seen && (expected_count < TRACE_DEPTH)) begin
                oracle_ok = cmodel_step(
                    oracle_pc, oracle_instr, oracle_commit, oracle_rd,
                    oracle_data, oracle_addr, oracle_is_read, oracle_rdata,
                    oracle_is_write, oracle_wstrb, oracle_wdata);
                if (!oracle_ok)
                    $fatal(1, "dual AXI C model step failed");

                expected_pc[expected_count] = oracle_pc;
                expected_instr[expected_count] = oracle_instr;
                expected_commit[expected_count] = oracle_commit[0];
                expected_rd[expected_count] = oracle_rd[4:0];
                expected_data[expected_count] = oracle_data;
                expected_count = expected_count + 1;

                if (oracle_is_read || oracle_is_write) begin
                    if (expected_mem_count >= TRACE_DEPTH)
                        $fatal(1, "dual AXI reference memory trace overflow");
                    expected_mem_write[expected_mem_count] =
                        oracle_is_write[0];
                    expected_mem_addr[expected_mem_count] = oracle_addr;
                    expected_mem_wstrb[expected_mem_count] =
                        oracle_wstrb[3:0];
                    expected_mem_wdata[expected_mem_count] = oracle_wdata;
                    expected_mem_count = expected_mem_count + 1;
                end

                if (oracle_instr == JAL_HALT)
                    oracle_halt_seen = 1;
            end

            if (!oracle_halt_seen)
                $fatal(1,
                    "dual AXI C model did not reach terminal self-loop");
            for (oracle_reg = 0; oracle_reg < 32;
                 oracle_reg = oracle_reg + 1)
                expected_arch_regs[oracle_reg] = cmodel_get_reg(oracle_reg);

            $display(
                "DUAL_AXI_REFERENCE_ORACLE PASS retired=%0d memory=%0d",
                expected_count, expected_mem_count);
        end
    endtask

    task automatic check_reference_memory_request(input bit actual_write);
        integer index;
        begin
            index = expected_mem_index;
            if (index >= expected_mem_count)
                $fatal(1,
                    "unexpected dual AXI core memory request write=%0b addr=%08x",
                    actual_write, dut.core_dm_req_addr);
            if (actual_write !== expected_mem_write[index])
                $fatal(1,
                    "dual AXI memory[%0d] kind got=%0b expected=%0b",
                    index, actual_write, expected_mem_write[index]);
            if (dut.core_dm_req_addr !== expected_mem_addr[index])
                $fatal(1,
                    "dual AXI memory[%0d] address got=%08x expected=%08x",
                    index, dut.core_dm_req_addr,
                    expected_mem_addr[index]);
            if (actual_write) begin
                if (dut.core_dm_req_wstrb !== expected_mem_wstrb[index])
                    $fatal(1,
                        "dual AXI memory[%0d] strobe got=%x expected=%x",
                        index, dut.core_dm_req_wstrb,
                        expected_mem_wstrb[index]);
                if (dut.core_dm_req_wdata !== expected_mem_wdata[index])
                    $fatal(1,
                        "dual AXI memory[%0d] data got=%08x expected=%08x",
                        index, dut.core_dm_req_wdata,
                        expected_mem_wdata[index]);
            end
            expected_mem_index = expected_mem_index + 1;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            expected_mem_index = 0;
        end
        else begin
            if (dut.core_dm_req_rvalid && dut.core_dm_req_rready)
                check_reference_memory_request(1'b0);
            if (dut.core_dm_req_wvalid && dut.core_dm_req_wready)
                check_reference_memory_request(1'b1);
        end
    end

    task automatic check_retire_lane(input integer lane);
        integer index;
        begin
            index = expected_index;
            if (index >= expected_count)
                $fatal(1, "unexpected lane%0d retire pc=%08x instr=%08x",
                       lane, retire_pc[lane], retire_instr[lane]);
            if (retire_pc[lane] !== expected_pc[index])
                $fatal(1,
                       "trace[%0d] lane%0d PC got=%08x expected=%08x",
                       index, lane, retire_pc[lane], expected_pc[index]);
            if (retire_instr[lane] !== expected_instr[index])
                $fatal(1,
                       "trace[%0d] lane%0d instruction got=%08x expected=%08x",
                       index, lane, retire_instr[lane],
                       expected_instr[index]);
            if (commit_valid[lane] !== expected_commit[index])
                $fatal(1,
                       "trace[%0d] lane%0d commit got=%0b expected=%0b",
                       index, lane, commit_valid[lane],
                       expected_commit[index]);
            if (expected_commit[index]) begin
                if (commit_rd_addr[lane] !== expected_rd[index])
                    $fatal(1,
                           "trace[%0d] lane%0d rd got=x%0d expected=x%0d",
                           index, lane, commit_rd_addr[lane],
                           expected_rd[index]);
                if (commit_rd_data[lane] !== expected_data[index])
                    $fatal(1,
                           "trace[%0d] lane%0d data got=%08x expected=%08x",
                           index, lane, commit_rd_data[lane],
                           expected_data[index]);
            end
            expected_index = expected_index + 1;
        end
    endtask

    always @(posedge clk) begin
        if (!reset && trace_enable) begin
            if (retire_valid[1] && !retire_valid[0])
                $fatal(1, "lane1 retired without older lane0");
            if ((commit_valid & ~retire_valid) != 2'b00)
                $fatal(1, "commit without retirement");
            if ((retire_valid == 2'b11) &&
                (retire_pc[1] != (retire_pc[0] + 4)))
                $fatal(1, "unordered dual retire %08x/%08x",
                       retire_pc[0], retire_pc[1]);

            if (retire_valid == 2'b11)
                dual_retire_observed = dual_retire_observed + 1;
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
    end

    // ------------------------------------------------------------
    // Structural traffic coverage
    // ------------------------------------------------------------

    integer ic_read_bursts;
    integer dc_read_bursts;
    integer dc_write_bursts;
    integer dc_write_beats;
    integer id_read_contention_cycles;
    integer id_active_overlap_cycles;
    integer dcache_hit_requests;
    integer dcache_miss_requests;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ic_read_bursts = 0;
            dc_read_bursts = 0;
            dc_write_bursts = 0;
            dc_write_beats = 0;
            id_read_contention_cycles = 0;
            id_active_overlap_cycles = 0;
            dcache_hit_requests = 0;
            dcache_miss_requests = 0;
        end
        else begin
            if (dut.u_mem.ic_axi_arvalid && dut.u_mem.ic_axi_arready)
                ic_read_bursts = ic_read_bursts + 1;
            if (dut.u_mem.dc_axi_arvalid && dut.u_mem.dc_axi_arready)
                dc_read_bursts = dc_read_bursts + 1;
            if (dut.u_mem.dc_axi_awvalid && dut.u_mem.dc_axi_awready)
                dc_write_bursts = dc_write_bursts + 1;
            if (dut.u_mem.dc_axi_wvalid && dut.u_mem.dc_axi_wready)
                dc_write_beats = dc_write_beats + 1;

            // Both AXI masters are presenting address requests to the shared
            // arbiter.  This is stronger than merely seeing the two kinds of
            // traffic at unrelated times.
            if (dut.u_mem.ic_axi_arvalid && dut.u_mem.dc_axi_arvalid)
                id_read_contention_cycles =
                    id_read_contention_cycles + 1;

            if ((dut.u_mem.u_icache_adapter.state_q != 2'd0) &&
                (dut.u_mem.u_dcache_adapter.state_q != 3'd0))
                id_active_overlap_cycles = id_active_overlap_cycles + 1;

            if (dut.u_dcache.cpu_req_fire) begin
                if (dut.u_dcache.selected_miss)
                    dcache_miss_requests = dcache_miss_requests + 1;
                if (dut.u_dcache.selected_rd_hit ||
                    dut.u_dcache.selected_wr_hit)
                    dcache_hit_requests = dcache_hit_requests + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Directed program and acceptance checks
    // ------------------------------------------------------------

    reg [31:0] instruction;
    reg [31:0] ram_word;
    reg [31:0] oracle_ram_word;
    integer timeout_cycles;
    integer reg_index;

    task automatic build_program;
        begin
            expected_count = 0;

            instruction = insn_lui(5'd1, 20'h00002);
            install_instruction(0, instruction);
            instruction = insn_addi(5'd2, 5'd0, 17);
            install_instruction(1, instruction);

            // Five dirty lines separated by 0x100 map to the same one of the
            // 16 D-cache sets.  The fifth access must evict a dirty way.
            instruction = insn_sw(5'd2, 5'd1, 0);
            install_instruction(2, instruction);
            instruction = insn_addi(5'd1, 5'd1, 256);
            install_instruction(3, instruction);
            instruction = insn_addi(5'd2, 5'd2, 1);
            install_instruction(4, instruction);
            instruction = insn_sw(5'd2, 5'd1, 0);
            install_instruction(5, instruction);
            instruction = insn_addi(5'd1, 5'd1, 256);
            install_instruction(6, instruction);
            instruction = insn_addi(5'd2, 5'd2, 1);
            install_instruction(7, instruction);
            instruction = insn_sw(5'd2, 5'd1, 0);
            install_instruction(8, instruction);
            instruction = insn_addi(5'd1, 5'd1, 256);
            install_instruction(9, instruction);
            instruction = insn_addi(5'd2, 5'd2, 1);
            install_instruction(10, instruction);
            instruction = insn_sw(5'd2, 5'd1, 0);
            install_instruction(11, instruction);
            instruction = insn_addi(5'd1, 5'd1, 256);
            install_instruction(12, instruction);
            instruction = insn_addi(5'd2, 5'd2, 1);
            install_instruction(13, instruction);
            instruction = insn_sw(5'd2, 5'd1, 0);
            install_instruction(14, instruction);

            // Hit the newest line, then reload the first evicted dirty line.
            // The latter miss also forces a second dirty writeback.
            instruction = insn_lw(5'd3, 5'd1, 0);
            install_instruction(15, instruction);
            instruction = insn_lui(5'd4, 20'h00002);
            install_instruction(16, instruction);
            instruction = insn_lw(5'd5, 5'd4, 0);
            install_instruction(17, instruction);

            // M extension plus taken branch and JAL wrong-path flushing.
            instruction = insn_mul(5'd6, 5'd3, 5'd5);
            install_instruction(18, instruction);
            instruction = insn_addi(5'd7, 5'd0, 1);
            install_instruction(19, instruction);
            instruction = insn_beq(5'd7, 5'd7, 8);
            install_instruction(20, instruction);
            install_instruction(21, insn_addi(5'd8, 5'd0, 99));
            instruction = enc_j(8, 5'd9);
            install_instruction(22, instruction);
            install_instruction(23, insn_addi(5'd10, 5'd0, 77));

            instruction = insn_add(5'd11, 5'd6, 5'd5);
            install_instruction(24, instruction);
            instruction = insn_sw(5'd11, 5'd4, 4);
            install_instruction(25, instruction);
            instruction = insn_lw(5'd12, 5'd4, 4);
            install_instruction(26, instruction);
            instruction = insn_addi(5'd13, 5'd0, 42);
            install_instruction(27, instruction);
            instruction = insn_bne(5'd13, 5'd0, 8);
            install_instruction(28, instruction);
            install_instruction(29, insn_addi(5'd14, 5'd0, 66));
            install_instruction(30, JAL_HALT);
        end
    endtask

    initial begin
        reset = 1'b1;
        expected_count = 0;
        expected_index = 0;
        trace_enable = 1'b0;
        trace_complete = 1'b0;
        dual_retire_observed = 0;

        // Let the RAM's deterministic NOP initialization finish before
        // installing the program while reset still holds all clients idle.
        repeat (3) @(posedge clk);
        @(negedge clk);
        build_program();
        build_reference_oracle();
        expected_index = 0;
        trace_enable = 1'b1;
        reset = 1'b0;

        timeout_cycles = 0;
        while (!trace_complete && (timeout_cycles < 10000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!trace_complete)
            $fatal(1, "dual AXI integration timeout: retired %0d/%0d",
                   expected_index, expected_count);

        @(negedge clk);
        if (sticky_bus_fault_valid)
            $fatal(1,
                   "unexpected sticky bus fault write=%0b addr=%08x resp=%0b",
                   sticky_bus_fault_is_write, sticky_bus_fault_addr,
                   sticky_bus_fault_resp);
        if (expected_index != expected_count)
            $fatal(1, "retirement trace incomplete");
        if (expected_mem_index != expected_mem_count)
            $fatal(1,
                "core memory trace incomplete got=%0d expected=%0d",
                expected_mem_index, expected_mem_count);
        if (dual_retire_observed == 0 ||
            perf_dual_issue_cycle_count == 0 ||
            perf_dual_retire_cycle_count == 0)
            $fatal(1, "two-wide path never issued and retired a pair");

        if (ic_read_bursts == 0 || dc_read_bursts < 6)
            $fatal(1, "missing I/D AXI reads ic=%0d dc=%0d",
                   ic_read_bursts, dc_read_bursts);
        if (dc_write_bursts < 2 || dc_write_beats < 8)
            $fatal(1, "dirty writeback not exercised bursts=%0d beats=%0d",
                   dc_write_bursts, dc_write_beats);
        if (dcache_miss_requests < 6 || dcache_hit_requests < 3)
            $fatal(1, "D-cache hit/miss coverage insufficient hit=%0d miss=%0d",
                   dcache_hit_requests, dcache_miss_requests);
        if (id_read_contention_cycles == 0 ||
            id_active_overlap_cycles == 0)
            $fatal(1,
                   "shared AXI read arbitration saw no I/D overlap contention=%0d active=%0d",
                   id_read_contention_cycles, id_active_overlap_cycles);

        for (reg_index = 0; reg_index < 32;
             reg_index = reg_index + 1) begin
            if (arch_regfile[reg_index] !==
                expected_arch_regs[reg_index])
                $fatal(1,
                    "dual AXI final x%0d got=%08x expected=%08x",
                    reg_index, arch_regfile[reg_index],
                    expected_arch_regs[reg_index]);
        end

        // These two lines were made dirty, evicted, and acknowledged before
        // the final halt.  Read the backing RAM, not the resident D-cache.
        dut.read_word(32'h0000_2000, ram_word);
        oracle_ram_word = cmodel_mem_peek32(32'h0000_2000);
        if (ram_word !== oracle_ram_word)
            $fatal(1,
                "RAM writeback 0x2000 got=%08x reference=%08x",
                ram_word, oracle_ram_word);
        dut.read_word(32'h0000_2100, ram_word);
        oracle_ram_word = cmodel_mem_peek32(32'h0000_2100);
        if (ram_word !== oracle_ram_word)
            $fatal(1,
                "RAM writeback 0x2100 got=%08x reference=%08x",
                ram_word, oracle_ram_word);

        $display(
            "DUAL_AXI_REFERENCE_STATE PASS regs=32 memory_requests=%0d",
            expected_mem_count);

        $display("DUAL_AXI_INTEGRATION PASS");
        $finish;
    end

endmodule
