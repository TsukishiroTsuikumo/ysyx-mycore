`timescale 1ns/1ps

module ooo_core_tb;
    localparam integer EXPECTED_RETIRE = 33;

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
        imem[37] = enc_j(0, 0);                          // terminal self-loop
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
    integer byte_i;
    assign dmem_req_ready = !dmem_pending_q && (cycle_count[1:0] != 2'b01);

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

    logic [31:0] expected_pc [0:EXPECTED_RETIRE-1];
    logic expected_write [0:EXPECTED_RETIRE-1];
    logic [4:0] expected_rd [0:EXPECTED_RETIRE-1];
    logic [31:0] expected_value [0:EXPECTED_RETIRE-1];

    task automatic expect_trace(
        input integer index,
        input integer pc,
        input integer writes,
        input integer rd,
        input logic [31:0] value
    );
        begin
            expected_pc[index] = pc;
            expected_write[index] = writes;
            expected_rd[index] = rd[4:0];
            expected_value[index] = value;
        end
    endtask

    initial begin
        expect_trace(0,   0, 1,  1, 32'd6);
        expect_trace(1,   4, 1,  2, 32'd7);
        expect_trace(2,   8, 1,  3, 32'd42);
        expect_trace(3,  12, 1, 10, 32'd1);
        expect_trace(4,  16, 1, 11, 32'd2);
        expect_trace(5,  20, 1, 12, 32'd3);
        expect_trace(6,  24, 1, 13, 32'd4);
        expect_trace(7,  28, 1, 13, 32'd5);
        expect_trace(8,  32, 1,  4, 32'd48);
        expect_trace(9,  36, 1,  1, 32'd9);
        expect_trace(10, 40, 1,  5, 32'd16);
        expect_trace(11, 44, 1,  6, 32'd17);
        expect_trace(12, 48, 1,  7, 32'd8);
        expect_trace(13, 52, 1,  2, 32'd100);
        expect_trace(14, 56, 0,  0, 32'd0);
        expect_trace(15, 60, 1,  8, 32'd42);
        expect_trace(16, 64, 1,  9, 32'd4);
        expect_trace(17, 68, 1, 15, 32'd6);
        expect_trace(18, 72, 0,  0, 32'd0);
        expect_trace(19, 76, 0,  0, 32'd0);
        expect_trace(20, 88, 1, 20, 32'd7);
        expect_trace(21, 92, 1, 22, 32'd96);
        expect_trace(22,100, 1, 23, 32'd8);
        expect_trace(23,104, 1, 25, 32'hffff_fffe);
        expect_trace(24,108, 1, 24, 32'hffff_ffff);
        expect_trace(25,112, 1, 26, 32'hffff_ffff);
        expect_trace(26,116, 1, 27, 32'd0);
        expect_trace(27,120, 1, 28, 32'd11);
        expect_trace(28,124, 1, 29, 32'd1);
        expect_trace(29,128, 1, 30, 32'd128);
        expect_trace(30,132, 1, 30, 32'd144);
        expect_trace(31,136, 1, 31, 32'd140);
        expect_trace(32,144, 1, 19, 32'd9);
    end

    integer trace_index;
    integer lane;
    logic test_done;
    // Sample registered retirement pulses half a cycle after the DUT edge so
    // the final check completes before a following instruction can retire.
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            trace_index = 0;
            test_done = 1'b0;
        end
        else if (!test_done) begin
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (retire_valid[lane]) begin
                    if (trace_index >= EXPECTED_RETIRE)
                        $fatal(1, "retired more instructions than expected");
                    if (retire_pc[lane] !== expected_pc[trace_index])
                        $fatal(1, "retire[%0d] PC mismatch: got %08x expected %08x instr=%08x",
                               trace_index, retire_pc[lane], expected_pc[trace_index],
                               retire_instr[lane]);
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
                    if (trace_index == EXPECTED_RETIRE)
                        test_done = 1'b1;
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer timeout_cycles;
    initial begin
        reset = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
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

        if (arch_regs[0] !== 32'b0) $fatal(1, "x0 changed");
        if (arch_regs[1] !== 32'd9) $fatal(1, "x1 mismatch");
        if (arch_regs[2] !== 32'd100) $fatal(1, "x2 mismatch");
        if (arch_regs[3] !== 32'd42) $fatal(1, "x3 mismatch");
        if (arch_regs[4] !== 32'd48) $fatal(1, "WAR rename failure x4");
        if (arch_regs[5] !== 32'd16) $fatal(1, "x5 mismatch");
        if (arch_regs[6] !== 32'd17) $fatal(1, "pair RAW failure x6");
        if (arch_regs[7] !== 32'd8) $fatal(1, "WAR rename failure x7");
        if (arch_regs[8] !== 32'd42) $fatal(1, "load mismatch x8");
        if (arch_regs[9] !== 32'd4) $fatal(1, "DIV mismatch x9");
        if (arch_regs[13] !== 32'd5) $fatal(1, "same-packet WAW failure");
        if (arch_regs[15] !== 32'd6) $fatal(1, "REM mismatch x15");
        if (arch_regs[19] !== 32'd9) $fatal(1, "JALR recovery failed");
        if (arch_regs[20] !== 32'd7) $fatal(1, "branch recovery failed");
        if (arch_regs[21] !== 32'd0) $fatal(1, "wrong branch path committed");
        if (arch_regs[22] !== 32'd96) $fatal(1, "JAL link mismatch");
        if (arch_regs[23] !== 32'd8) $fatal(1, "JAL recovery failed");
        if (arch_regs[24] !== 32'hffff_ffff) $fatal(1, "MULH mismatch");
        if (arch_regs[26] !== 32'hffff_ffff) $fatal(1, "MULHSU mismatch");
        if (arch_regs[27] !== 32'b0) $fatal(1, "MULHU mismatch");
        if (arch_regs[28] !== 32'd11) $fatal(1, "DIVU mismatch");
        if (arch_regs[29] !== 32'd1) $fatal(1, "REMU mismatch");
        if (arch_regs[30] !== 32'd144) $fatal(1, "JALR base mismatch");
        if (arch_regs[31] !== 32'd140) $fatal(1, "JALR link mismatch");
        if ({data_mem[3], data_mem[2], data_mem[1], data_mem[0]} !== 32'd42)
            $fatal(1, "store result mismatch");
        if (ooo_completion_count == 0)
            $fatal(1, "no younger instruction completed ahead of a blocked head");
        if (rob_full_cycles == 0)
            $fatal(1, "ROB-full condition was not exercised");
        if (load_block_cycles == 0)
            $fatal(1, "conservative store/load blocking was not exercised");
        if (branch_recoveries != 3)
            $fatal(1, "expected three branch/JAL/JALR recoveries, got %0d",
                   branch_recoveries);
        if (memory_fault)
            $fatal(1, "unexpected memory fault");

        $display("OOO_CORE_TEST PASS cycles=%0d retired=%0d ooo=%0d rob_full=%0d load_block=%0d recoveries=%0d",
                 cycle_count, retired_count, ooo_completion_count,
                 rob_full_cycles, load_block_cycles, branch_recoveries);
        $finish;
    end

endmodule
