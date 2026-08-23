`timescale 1ns/1ps

module ooo_core_tb;
    localparam integer REFERENCE_TRACE_DEPTH = 256;
    localparam integer DIRECTED_RETIRE_COUNT = 40;
    localparam logic [31:0] JAL_HALT = 32'h0000_006f;
    localparam logic [31:0] HALT_PC = 32'd184;

    `include "cmodel_dpi.svh"

    logic clk;
    logic reset;

    logic imem_req_valid;
    logic [31:0] imem_req_addr;
    logic imem_req_ready;
    logic imem_resp_valid;
    logic [63:0] imem_resp_data;

    logic dmem_req_valid;
    logic dmem_req_ready;
    logic dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0] dmem_req_wstrb;
    logic dmem_resp_valid;
    logic [31:0] dmem_resp_rdata;
    logic dmem_resp_error;

    logic [1:0] retire_valid;
    logic [1:0][31:0] retire_pc;
    logic [1:0][31:0] retire_instr;
    logic [1:0] retire_rd_write;
    logic [1:0][4:0] retire_rd_addr;
    logic [1:0][31:0] retire_rd_data;
    logic [31:0] arch_regs [0:31];

    logic [31:0] rob_occupancy;
    logic [63:0] cycle_count;
    logic [63:0] retired_count;
    logic [63:0] ooo_completion_count;
    logic [63:0] rob_full_cycles;
    logic [63:0] load_block_cycles;
    logic [63:0] branch_recoveries;
    logic memory_fault;

    ooo_core #(
        .ROB_DEPTH(8),
        .RS_DEPTH(12),
        .LSQ_DEPTH(8),
        .PRF_COUNT(48),
        .M_LATENCY(24)
    ) dut (
        .clk(clk), .reset(reset),
        .imem_req_valid_out(imem_req_valid),
        .imem_req_addr_out(imem_req_addr),
        .imem_req_ready_in(imem_req_ready),
        .imem_resp_valid_in(imem_resp_valid),
        .imem_resp_data_in(imem_resp_data),
        .dmem_req_valid_out(dmem_req_valid),
        .dmem_req_ready_in(dmem_req_ready),
        .dmem_req_write_out(dmem_req_write),
        .dmem_req_addr_out(dmem_req_addr),
        .dmem_req_wdata_out(dmem_req_wdata),
        .dmem_req_wstrb_out(dmem_req_wstrb),
        .dmem_resp_valid_in(dmem_resp_valid),
        .dmem_resp_rdata_in(dmem_resp_rdata),
        .dmem_resp_error_in(dmem_resp_error),
        .retire_valid_out(retire_valid),
        .retire_pc_out(retire_pc),
        .retire_instr_out(retire_instr),
        .retire_rd_write_out(retire_rd_write),
        .retire_rd_addr_out(retire_rd_addr),
        .retire_rd_data_out(retire_rd_data),
        .arch_regfile_out(arch_regs),
        .rob_occupancy_out(rob_occupancy),
        .cycle_count_out(cycle_count),
        .retired_count_out(retired_count),
        .ooo_completion_count_out(ooo_completion_count),
        .rob_full_cycle_count_out(rob_full_cycles),
        .load_block_cycle_count_out(load_block_cycles),
        .branch_recovery_count_out(branch_recoveries),
        .memory_fault_sticky_out(memory_fault)
    );

    logic [31:0] imem [0:255];
    logic [7:0] data_mem [0:255];

    function automatic logic [31:0] enc_i(
        input integer imm,
        input integer rs1,
        input integer funct3,
        input integer rd,
        input integer opcode
    );
        enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic logic [31:0] enc_r(
        input integer funct7,
        input integer rs2,
        input integer rs1,
        input integer funct3,
        input integer rd
    );
        enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0],
                 rd[4:0], 7'b0110011};
    endfunction

    function automatic logic [31:0] enc_s(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input integer funct3
    );
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0],
                 imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_b(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input integer funct3
    );
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], funct3[2:0],
                 imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_j(
        input integer imm,
        input integer rd
    );
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12],
                 rd[4:0], 7'b1101111};
    endfunction

    function automatic logic [31:0] enc_u(
        input integer upper20,
        input integer rd,
        input integer opcode
    );
        enc_u = {upper20[19:0], rd[4:0], opcode[6:0]};
    endfunction

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 256; init_i = init_i + 1) begin
            imem[init_i] = 32'h0000_0013; // ADDI x0,x0,0
        end

        // Long producer followed by independent work fills the ROB and proves
        // that younger instructions finish while retirement remains ordered.
        imem[0]  = enc_i(6,   0, 3'b000, 1, 7'b0010011); // addi x1,x0,6
        imem[1]  = enc_i(7,   0, 3'b000, 2, 7'b0010011); // addi x2,x0,7
        imem[2]  = enc_r(1, 2, 1, 3'b000, 3);            // mul x3,x1,x2
        imem[3]  = enc_i(1,   0, 3'b000, 10, 7'b0010011);
        imem[4]  = enc_i(2,   0, 3'b000, 11, 7'b0010011);
        imem[5]  = enc_i(3,   0, 3'b000, 12, 7'b0010011);
        imem[6]  = enc_i(4,   0, 3'b000, 13, 7'b0010011);
        imem[7]  = enc_i(5,   0, 3'b000, 13, 7'b0010011); // same-packet WAW

        // RAW, WAR and WAW all rely on physical-register renaming.
        imem[8]  = enc_r(0, 1, 3, 3'b000, 4);            // add x4,x3,x1 = 48
        imem[9]  = enc_i(9,   0, 3'b000, 1, 7'b0010011); // younger WAW x1
        imem[10] = enc_r(0, 2, 1, 3'b000, 5);            // add x5,x1,x2 = 16
        imem[11] = enc_i(1,   5, 3'b000, 6, 7'b0010011); // pair RAW = 17
        imem[12] = enc_r(0, 10, 2, 3'b000, 7);           // reads old x2 = 8
        imem[13] = enc_i(100, 0, 3'b000, 2, 7'b0010011); // younger WAR write

        // No store-to-load forwarding: the load must visibly wait for the
        // older store to reach the head and receive its memory response.
        imem[14] = enc_s(0, 3, 0, 3'b010);               // sw x3,0(x0)
        imem[15] = enc_i(0, 0, 3'b010, 8, 7'b0000011);   // lw x8,0(x0)
        imem[16] = enc_r(1, 1, 3, 3'b100, 9);            // div x9,x3,x1 = 4
        imem[17] = enc_r(1, 1, 3, 3'b110, 15);           // rem x15,x3,x1 = 6
        imem[18] = enc_i(123, 0, 3'b000, 0, 7'b0010011); // x0 remains zero

        // Predicted-not-taken BEQ; PCs 80/84 are wrong-path instructions.
        imem[19] = enc_b(12, 3, 8, 3'b000);              // beq x8,x3,88
        imem[20] = enc_i(99, 0, 3'b000, 20, 7'b0010011);
        imem[21] = enc_i(98, 0, 3'b000, 21, 7'b0010011);
        imem[22] = enc_i(7,  0, 3'b000, 20, 7'b0010011); // target PC 88

        // JAL and JALR each flush a younger instruction and preserve link data.
        imem[23] = enc_j(8, 22);                         // jal x22,100
        imem[24] = enc_i(77, 0, 3'b000, 23, 7'b0010011);// wrong PC 96
        imem[25] = enc_i(8,  0, 3'b000, 23, 7'b0010011);// target PC 100

        // Remaining M encodings exercise signed/unsigned high multiply,
        // unsigned divide and remainder in addition to MUL/DIV/REM above.
        imem[26] = enc_i(-2, 0, 3'b000, 25, 7'b0010011);
        imem[27] = enc_r(1, 2, 25, 3'b001, 24);          // mulh = -1
        imem[28] = enc_r(1, 2, 25, 3'b010, 26);          // mulhsu = -1
        imem[29] = enc_r(1, 1, 2, 3'b011, 27);           // mulhu = 0
        imem[30] = enc_r(1, 1, 2, 3'b101, 28);           // divu 100/9 = 11
        imem[31] = enc_r(1, 1, 2, 3'b111, 29);           // remu = 1
        imem[32] = enc_u(0, 30, 7'b0010111);             // auipc x30,0 = 128
        imem[33] = enc_i(16, 30, 3'b000, 30, 7'b0010011);// x30 = 144
        imem[34] = enc_i(0, 30, 3'b000, 31, 7'b1100111);// jalr x31,0(x30)
        imem[35] = enc_i(66, 0, 3'b000, 19, 7'b0010011);// wrong PC 140
        imem[36] = enc_i(9,  0, 3'b000, 19, 7'b0010011);// target PC 144
        // M/load writes to x0 must complete their ROB entries without writing
        // or broadcasting the unallocated placeholder physical destination.
        // The following ADDIs deliberately allocate those still-free tags
        // while the older operations remain active, exposing any late PRF
        // corruption through the committed architectural probes.
        imem[37] = enc_r(1, 2, 1, 3'b000, 0);            // mul x0,x1,x2
        imem[38] = enc_i(55, 0, 3'b000, 14, 7'b0010011);// live alias candidate
        imem[39] = enc_i(0, 0, 3'b010, 0, 7'b0000011);  // lw x0,0(x0)
        imem[40] = enc_i(77, 0, 3'b000, 16, 7'b0010011);// live alias candidate
        imem[41] = enc_i(256, 0, 3'b000, 17, 7'b0010011);// invalid dmem base
        imem[42] = enc_b(12, 0, 0, 3'b000);              // taken to PC 180
        imem[43] = enc_i(0, 17, 3'b010, 18, 7'b0000011);// wrong-path faulting load
        imem[44] = enc_i(99, 0, 3'b000, 18, 7'b0010011);// wrong path
        imem[45] = enc_i(88, 0, 3'b000, 18, 7'b0010011);// target PC 180
        imem[46] = enc_j(0, 0);                          // terminal self-loop
    end

    // Instruction memory: one-cycle response, one outstanding transaction.
    logic imem_pending_q;
    logic [31:0] imem_addr_q;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            imem_pending_q <= 1'b0;
            imem_addr_q <= 32'b0;
            imem_resp_valid <= 1'b0;
            imem_resp_data <= 64'b0;
        end
        else begin
            imem_resp_valid <= 1'b0;
            if (imem_req_valid && imem_req_ready) begin
                imem_pending_q <= 1'b1;
                imem_addr_q <= imem_req_addr;
            end
            if (imem_pending_q) begin
                imem_pending_q <= 1'b0;
                imem_resp_valid <= 1'b1;
                imem_resp_data <= {imem[(imem_addr_q >> 2) + 1],
                                   imem[imem_addr_q >> 2]};
            end
        end
    end
    assign imem_req_ready = 1'b1;

    // Data memory adds deterministic request backpressure and three response
    // cycles.  This also catches repeated requests and unstable payloads.
    logic dmem_pending_q;
    logic [2:0] dmem_delay_q;
    logic dmem_write_q;
    logic [31:0] dmem_addr_q;
    logic [31:0] dmem_wdata_q;
    logic [3:0] dmem_wstrb_q;
    integer dmem_request_count;
    logic wrong_path_read_seen;
    integer byte_i;
    assign dmem_req_ready = !dmem_pending_q && (cycle_count[1:0] != 2'b01);

    function automatic logic [31:0] read_data_word(
        input logic [31:0] byte_addr
    );
        begin
            if (byte_addr <= 32'd252)
                read_data_word = {data_mem[byte_addr+3],
                                  data_mem[byte_addr+2],
                                  data_mem[byte_addr+1],
                                  data_mem[byte_addr]};
            else
                read_data_word = 32'b0;
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            dmem_pending_q <= 1'b0;
            dmem_delay_q <= 3'b0;
            dmem_write_q <= 1'b0;
            dmem_addr_q <= 32'b0;
            dmem_wdata_q <= 32'b0;
            dmem_wstrb_q <= 4'b0;
            dmem_resp_valid <= 1'b0;
            dmem_resp_rdata <= 32'b0;
            dmem_resp_error <= 1'b0;
            dmem_request_count <= 0;
            wrong_path_read_seen <= 1'b0;
            for (byte_i = 0; byte_i < 256; byte_i = byte_i + 1)
                data_mem[byte_i] <= 8'b0;
        end
        else begin
            dmem_resp_valid <= 1'b0;
            dmem_resp_error <= 1'b0;
            if (dmem_req_valid && dmem_req_ready) begin
                if (dmem_pending_q)
                    $fatal(1, "accepted a second data request while busy");
                dmem_pending_q <= 1'b1;
                dmem_delay_q <= 3;
                dmem_write_q <= dmem_req_write;
                dmem_addr_q <= dmem_req_addr;
                dmem_wdata_q <= dmem_req_wdata;
                dmem_wstrb_q <= dmem_req_wstrb;
                dmem_request_count <= dmem_request_count + 1;
                if (!dmem_req_write && (dmem_req_addr == 32'd256))
                    wrong_path_read_seen <= 1'b1;
            end
            if (dmem_pending_q) begin
                if (dmem_delay_q != 0) begin
                    dmem_delay_q <= dmem_delay_q - 1'b1;
                end
                else begin
                    dmem_pending_q <= 1'b0;
                    dmem_resp_valid <= 1'b1;
                    if (dmem_addr_q > 252) begin
                        dmem_resp_error <= 1'b1;
                        dmem_resp_rdata <= 32'b0;
                    end
                    else if (dmem_write_q) begin
                        for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
                            if (dmem_wstrb_q[byte_i])
                                data_mem[dmem_addr_q + byte_i] <=
                                    dmem_wdata_q[(byte_i*8) +: 8];
                        end
                    end
                    else begin
                        dmem_resp_rdata <= {data_mem[dmem_addr_q+3],
                                           data_mem[dmem_addr_q+2],
                                           data_mem[dmem_addr_q+1],
                                           data_mem[dmem_addr_q]};
                    end
                end
            end
        end
    end

    logic [31:0] expected_pc [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_instr [0:REFERENCE_TRACE_DEPTH-1];
    logic expected_write [0:REFERENCE_TRACE_DEPTH-1];
    logic [4:0] expected_rd [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_value [0:REFERENCE_TRACE_DEPTH-1];
    logic expected_mem_write [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_mem_addr [0:REFERENCE_TRACE_DEPTH-1];
    logic [3:0] expected_mem_wstrb [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_mem_wdata [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_mem_rdata [0:REFERENCE_TRACE_DEPTH-1];
    logic [31:0] expected_arch_regs [0:31];
    logic [7:0] expected_data_mem [0:255];
    integer expected_count;
    integer expected_mem_count;
    integer expected_mem_index;

    task automatic build_reference_oracle;
        integer oracle_word;
        integer oracle_reg;
        integer oracle_byte;
        integer oracle_ok;
        integer oracle_halt_seen;
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
        int unsigned oracle_mem_byte;
        begin
            if (!cmodel_init_empty())
                $fatal(1, "OOO reference C model initialization failed");
            for (oracle_word = 0; oracle_word < 256;
                 oracle_word = oracle_word + 1)
                cmodel_imem_write32(oracle_word * 4, imem[oracle_word]);

            expected_count = 0;
            expected_mem_count = 0;
            oracle_halt_seen = 0;
            while (!oracle_halt_seen &&
                   (expected_count < REFERENCE_TRACE_DEPTH)) begin
                oracle_ok = cmodel_step(
                    oracle_pc, oracle_instr, oracle_commit, oracle_rd,
                    oracle_data, oracle_addr, oracle_is_read, oracle_rdata,
                    oracle_is_write, oracle_wstrb, oracle_wdata);
                if (!oracle_ok)
                    $fatal(1, "OOO reference C model step failed");

                if (oracle_instr == JAL_HALT) begin
                    oracle_halt_seen = 1;
                end
                else begin
                    expected_pc[expected_count] = oracle_pc;
                    expected_instr[expected_count] = oracle_instr;
                    expected_write[expected_count] =
                        oracle_commit[0] && (oracle_rd[4:0] != 5'b0);
                    expected_rd[expected_count] = oracle_rd[4:0];
                    expected_value[expected_count] = oracle_data;
                    expected_count = expected_count + 1;

                    if (oracle_is_read || oracle_is_write) begin
                        if (expected_mem_count >= REFERENCE_TRACE_DEPTH)
                            $fatal(1, "OOO reference memory trace overflow");
                        expected_mem_write[expected_mem_count] =
                            oracle_is_write[0];
                        expected_mem_addr[expected_mem_count] = oracle_addr;
                        expected_mem_wstrb[expected_mem_count] =
                            oracle_wstrb[3:0];
                        expected_mem_wdata[expected_mem_count] = oracle_wdata;
                        expected_mem_rdata[expected_mem_count] = oracle_rdata;
                        expected_mem_count = expected_mem_count + 1;
                    end
                end
            end

            if (!oracle_halt_seen)
                $fatal(1,
                    "OOO reference did not reach terminal self-loop in %0d steps",
                    REFERENCE_TRACE_DEPTH);
            if (expected_count != DIRECTED_RETIRE_COUNT)
                $fatal(1,
                    "OOO reference retired %0d instructions, expected %0d",
                    expected_count, DIRECTED_RETIRE_COUNT);

            for (oracle_reg = 0; oracle_reg < 32;
                 oracle_reg = oracle_reg + 1)
                expected_arch_regs[oracle_reg] = cmodel_get_reg(oracle_reg);
            for (oracle_byte = 0; oracle_byte < 256;
                 oracle_byte = oracle_byte + 1) begin
                oracle_mem_byte = cmodel_mem_peek8(oracle_byte);
                expected_data_mem[oracle_byte] = oracle_mem_byte[7:0];
            end
            $display(
                "OOO_REFERENCE_ORACLE PASS retired=%0d memory=%0d",
                expected_count, expected_mem_count);
        end
    endtask

    task automatic check_reference_memory_request;
        integer index;
        begin
            index = expected_mem_index;
            if (index >= expected_mem_count)
                $fatal(1,
                    "unexpected OOO memory request write=%0b addr=%08x",
                    dmem_req_write, dmem_req_addr);
            if (dmem_req_write !== expected_mem_write[index])
                $fatal(1,
                    "OOO memory[%0d] kind got=%0b expected=%0b",
                    index, dmem_req_write, expected_mem_write[index]);
            if (dmem_req_addr !== expected_mem_addr[index])
                $fatal(1,
                    "OOO memory[%0d] address got=%08x expected=%08x",
                    index, dmem_req_addr, expected_mem_addr[index]);
            if (dmem_req_write) begin
                if (dmem_req_wstrb !== expected_mem_wstrb[index])
                    $fatal(1,
                        "OOO memory[%0d] strobe got=%x expected=%x",
                        index, dmem_req_wstrb,
                        expected_mem_wstrb[index]);
                if (dmem_req_wdata !== expected_mem_wdata[index])
                    $fatal(1,
                        "OOO memory[%0d] data got=%08x expected=%08x",
                        index, dmem_req_wdata,
                        expected_mem_wdata[index]);
            end
            else if (read_data_word(dmem_req_addr) !==
                     expected_mem_rdata[index]) begin
                $fatal(1,
                    "OOO memory[%0d] read data got=%08x expected=%08x",
                    index, read_data_word(dmem_req_addr),
                    expected_mem_rdata[index]);
            end
            expected_mem_index = expected_mem_index + 1;
        end
    endtask

    always @(posedge clk) begin
        if (reset)
            expected_mem_index = 0;
        else if (dmem_req_valid && dmem_req_ready)
            check_reference_memory_request();
    end

    integer trace_index;
    integer lane;
    logic test_done;
    logic [63:0] reference_branch_recoveries;
    // Sample registered retirement pulses half a cycle after the DUT edge so
    // the final check completes before a following instruction can retire.
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            trace_index = 0;
            test_done = 1'b0;
            reference_branch_recoveries = 64'b0;
        end
        else if (!test_done) begin
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (retire_valid[lane]) begin
                    if (trace_index >= expected_count)
                        $fatal(1, "retired more instructions than expected");
                    if (retire_pc[lane] !== expected_pc[trace_index])
                        $fatal(1, "retire[%0d] PC mismatch: got %08x expected %08x instr=%08x",
                               trace_index, retire_pc[lane], expected_pc[trace_index],
                               retire_instr[lane]);
                    if (retire_instr[lane] !== expected_instr[trace_index])
                        $fatal(1, "retire[%0d] instruction mismatch: got %08x expected %08x",
                               trace_index, retire_instr[lane],
                               expected_instr[trace_index]);
                    if (retire_rd_write[lane] !== expected_write[trace_index])
                        $fatal(1, "retire[%0d] write flag mismatch", trace_index);
                    if (retire_rd_write[lane]) begin
                        if (retire_rd_addr[lane] !== expected_rd[trace_index])
                            $fatal(1, "retire[%0d] rd mismatch", trace_index);
                        if (retire_rd_data[lane] !== expected_value[trace_index])
                            $fatal(1, "retire[%0d] value mismatch: got %08x expected %08x",
                                   trace_index, retire_rd_data[lane],
                                   expected_value[trace_index]);
                    end
                    else if (retire_rd_data[lane] !== 32'b0) begin
                        $fatal(1, "retire[%0d] non-writing record exposed nonzero data",
                               trace_index);
                    end

                    trace_index = trace_index + 1;
                    if (trace_index == expected_count) begin
                        // Snapshot the recoveries belonging to the reference
                        // trace.  The allowed terminal JAL sentinel may itself
                        // recover on the additional post-trace guard cycle.
                        reference_branch_recoveries = branch_recoveries;
                        test_done = 1'b1;
                    end
                end
            end
        end
        else begin
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (retire_valid[lane] &&
                    ((retire_pc[lane] !== HALT_PC) ||
                     (retire_instr[lane] !== JAL_HALT))) begin
                    $fatal(1,
                        "non-halt retirement after reference trace pc=%08x instr=%08x",
                        retire_pc[lane], retire_instr[lane]);
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer timeout_cycles;
    integer final_i;
    initial begin
        reset = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        build_reference_oracle();
        reset = 1'b0;

        timeout_cycles = 0;
        while (!test_done && (timeout_cycles < 5000)) begin
            @(negedge clk);
            #1;
            timeout_cycles = timeout_cycles + 1;
        end
        #1;
        if (!test_done)
            $fatal(1, "OOO core timeout: retired=%0d ROB=%0d", trace_index,
                   rob_occupancy);

        // Observe one more retirement edge so a duplicated or otherwise
        // non-terminal record cannot hide behind the expected-count stop.
        @(negedge clk);
        #1;

        for (final_i = 0; final_i < 32; final_i = final_i + 1) begin
            if (arch_regs[final_i] !== expected_arch_regs[final_i])
                $fatal(1,
                    "OOO final x%0d got=%08x expected=%08x",
                    final_i, arch_regs[final_i],
                    expected_arch_regs[final_i]);
        end
        for (final_i = 0; final_i < 256; final_i = final_i + 1) begin
            if (data_mem[final_i] !== expected_data_mem[final_i])
                $fatal(1,
                    "OOO final memory[%0d] got=%02x expected=%02x",
                    final_i, data_mem[final_i],
                    expected_data_mem[final_i]);
        end
        if (expected_mem_index != expected_mem_count)
            $fatal(1,
                "OOO memory trace incomplete got=%0d expected=%0d",
                expected_mem_index, expected_mem_count);
        if (ooo_completion_count == 0)
            $fatal(1, "no younger instruction completed ahead of a blocked head");
        if (rob_full_cycles == 0)
            $fatal(1, "ROB-full condition was not exercised");
        if (load_block_cycles == 0)
            $fatal(1, "conservative store/load blocking was not exercised");
        if (reference_branch_recoveries != 4)
            $fatal(1, "expected four control-flow recoveries, got %0d",
                   reference_branch_recoveries);
        if (dmem_request_count != expected_mem_count)
            $fatal(1,
                "wrong data request count: got %0d reference %0d",
                dmem_request_count, expected_mem_count);
        if (wrong_path_read_seen)
            $fatal(1, "taken-branch wrong-path load reached data memory");
        if (memory_fault)
            $fatal(1, "unexpected memory fault");

        $display(
            "OOO_REFERENCE_STATE PASS regs=32 memory_bytes=256 memory_requests=%0d",
            expected_mem_count);

        $display("OOO_CORE_TEST PASS cycles=%0d retired=%0d ooo=%0d rob_full=%0d load_block=%0d recoveries=%0d",
                 cycle_count, retired_count, ooo_completion_count,
                 rob_full_cycles, load_block_cycles,
                 reference_branch_recoveries);
        $finish;
    end

endmodule
