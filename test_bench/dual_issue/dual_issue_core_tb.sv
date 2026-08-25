`timescale 1ns/1ps

// Fixed two-wide core acceptance test.  This test deliberately uses only the
// public PM/DM and flat retirement interfaces of the one and only `mycore`.
module dual_issue_core_tb;
    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_BYTES = 512;
    localparam integer EXPECTED_RETIRE = 22;
    localparam [31:0] NOP = 32'h0000_0013;
    localparam [31:0] FENCE = 32'h0000_000f;

    reg clk;
    reg reset;

    wire         pm_req_valid;
    wire [31:0]  pm_req_addr;
    wire         pm_req_ready;
    reg          pm_resp_valid;
    reg  [127:0] pm_resp_data;

    wire [31:0] dm_req_addr;
    wire        dm_req_rvalid;
    wire        dm_req_rready;
    reg         dm_resp_rvalid;
    reg  [31:0] dm_resp_rdata;
    wire        dm_req_wvalid;
    wire        dm_req_wready;
    wire [3:0]  dm_req_wstrb;
    wire [31:0] dm_req_wdata;
    reg         dm_resp_wvalid;

    wire [1:0]  retire_valid;
    wire [63:0] retire_pc;
    wire [63:0] retire_instr;
    wire [1:0]  retire_rd_write;
    wire [9:0]  retire_rd_addr;
    wire [63:0] retire_rd_data;

    mycore dut (
        .clk(clk),
        .reset(reset),
        .pm_req_valid_out(pm_req_valid),
        .pm_req_addr_out(pm_req_addr),
        .pm_req_ready_in(pm_req_ready),
        .pm_resp_valid_in(pm_resp_valid),
        .pm_resp_data_in(pm_resp_data),
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
        .retire_pc_out(retire_pc),
        .retire_instr_out(retire_instr),
        .retire_rd_write_out(retire_rd_write),
        .retire_rd_addr_out(retire_rd_addr),
        .retire_rd_data_out(retire_rd_data)
    );

    function automatic [31:0] enc_i;
        input integer imm;
        input integer rs1;
        input integer funct3;
        input integer rd;
        input integer opcode;
        begin
            enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0],
                     opcode[6:0]};
        end
    endfunction

    function automatic [31:0] enc_r;
        input integer funct7;
        input integer rs2;
        input integer rs1;
        input integer funct3;
        input integer rd;
        begin
            enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0],
                     rd[4:0], 7'b0110011};
        end
    endfunction

    function automatic [31:0] enc_s;
        input integer imm;
        input integer rs2;
        input integer rs1;
        input integer funct3;
        begin
            enc_s = {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0],
                     imm[4:0], 7'b0100011};
        end
    endfunction

    function automatic [31:0] enc_b;
        input integer imm;
        input integer rs2;
        input integer rs1;
        input integer funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0],
                     funct3[2:0], imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    function automatic [31:0] enc_j;
        input integer imm;
        input integer rd;
        begin
            enc_j = {imm[20], imm[10:1], imm[11], imm[19:12],
                     rd[4:0], 7'b1101111};
        end
    endfunction

    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [7:0] data_mem [0:DMEM_BYTES-1];
    integer init_i;

    function automatic [31:0] read_imem_word;
        input integer word_index;
        begin
            if ((word_index >= 0) && (word_index < IMEM_WORDS))
                read_imem_word = imem[word_index];
            else
                read_imem_word = NOP;
        end
    endfunction

    function automatic [127:0] read_imem_line;
        input [31:0] byte_address;
        integer base_word;
        begin
            base_word = byte_address[31:2];
            read_imem_line = {read_imem_word(base_word + 3),
                              read_imem_word(base_word + 2),
                              read_imem_word(base_word + 1),
                              read_imem_word(base_word + 0)};
        end
    endfunction

    function automatic [31:0] read_data_word;
        input [31:0] byte_address;
        begin
            if (byte_address <= (DMEM_BYTES - 4))
                read_data_word = {data_mem[byte_address + 3],
                                  data_mem[byte_address + 2],
                                  data_mem[byte_address + 1],
                                  data_mem[byte_address + 0]};
            else
                read_data_word = 32'b0;
        end
    endfunction

    // Ordered, delayed instruction responses.  Keeping one response in flight
    // is sufficient to exercise line alignment and wrong-path response drain.
    reg        imem_pending;
    reg [31:0] imem_pending_addr;
    reg [2:0]  imem_delay;
    assign pm_req_ready = !imem_pending && !reset;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            imem_pending <= 1'b0;
            imem_pending_addr <= 32'b0;
            imem_delay <= 3'b0;
            pm_resp_valid <= 1'b0;
            pm_resp_data <= 128'b0;
        end
        else begin
            pm_resp_valid <= 1'b0;
            if (pm_req_valid && pm_req_ready) begin
                if (pm_req_addr[3:0] != 4'b0)
                    $fatal(1, "PM request is not 16-byte aligned: %08x",
                           pm_req_addr);
                imem_pending <= 1'b1;
                imem_pending_addr <= pm_req_addr;
                imem_delay <= 3'd2;
            end
            if (imem_pending) begin
                if (imem_delay != 0)
                    imem_delay <= imem_delay - 1'b1;
                else begin
                    imem_pending <= 1'b0;
                    pm_resp_valid <= 1'b1;
                    pm_resp_data <= read_imem_line(imem_pending_addr);
                end
            end
        end
    end

    // The direct DM model deliberately refuses every new request for two
    // cycles, then returns a response three cycles after acceptance.
    reg        dmem_arming;
    reg [1:0]  dmem_stall_count;
    reg        dmem_pending;
    reg [2:0]  dmem_delay;
    reg        held_write;
    reg [31:0] held_addr;
    reg [31:0] held_wdata;
    reg [3:0]  held_wstrb;
    integer cycle_count;
    integer read_accept_count;
    integer write_accept_count;
    integer backpressure_cycles;
    integer byte_i;

    wire any_dm_request = dm_req_rvalid || dm_req_wvalid;
    wire dm_accept_enable = dmem_arming && (dmem_stall_count == 0) &&
                            !dmem_pending;
    assign dm_req_rready = dm_accept_enable;
    assign dm_req_wready = dm_accept_enable;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dmem_arming <= 1'b0;
            dmem_stall_count <= 2'b0;
            dmem_pending <= 1'b0;
            dmem_delay <= 3'b0;
            held_write <= 1'b0;
            held_addr <= 32'b0;
            held_wdata <= 32'b0;
            held_wstrb <= 4'b0;
            dm_resp_rvalid <= 1'b0;
            dm_resp_rdata <= 32'b0;
            dm_resp_wvalid <= 1'b0;
            cycle_count <= 0;
            read_accept_count <= 0;
            write_accept_count <= 0;
            backpressure_cycles <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;
            dm_resp_rvalid <= 1'b0;
            dm_resp_wvalid <= 1'b0;

            if (dm_req_rvalid && dm_req_wvalid)
                $fatal(1, "simultaneous direct DM read and write requests");

            if (any_dm_request && !dmem_pending && !dmem_arming) begin
                dmem_arming <= 1'b1;
                dmem_stall_count <= 2'd2;
                held_write <= dm_req_wvalid;
                held_addr <= dm_req_addr;
                held_wdata <= dm_req_wdata;
                held_wstrb <= dm_req_wstrb;
            end
            else if (dmem_arming) begin
                if (!any_dm_request)
                    $fatal(1, "DM valid dropped before ready");
                if ((dm_req_wvalid !== held_write) ||
                    (dm_req_addr !== held_addr) ||
                    (held_write && ((dm_req_wdata !== held_wdata) ||
                                    (dm_req_wstrb !== held_wstrb))))
                    $fatal(1, "DM request payload changed under backpressure");
                if (dmem_stall_count != 0) begin
                    dmem_stall_count <= dmem_stall_count - 1'b1;
                    backpressure_cycles <= backpressure_cycles + 1;
                end
                else if ((dm_req_rvalid && dm_req_rready) ||
                         (dm_req_wvalid && dm_req_wready)) begin
                    dmem_arming <= 1'b0;
                    dmem_pending <= 1'b1;
                    dmem_delay <= 3'd3;
                    if (held_write) begin
                        write_accept_count <= write_accept_count + 1;
                        if ((held_addr != 32'd128) ||
                            (held_wstrb != 4'b1111) ||
                            (held_wdata != 32'd84))
                            $fatal(1, "unexpected store request addr=%08x strb=%x data=%08x",
                                   held_addr, held_wstrb, held_wdata);
                    end
                    else begin
                        read_accept_count <= read_accept_count + 1;
                        if (held_addr != 32'd128)
                            $fatal(1, "unexpected load request addr=%08x", held_addr);
                    end
                end
            end

            if (dmem_pending) begin
                if (dmem_delay != 0)
                    dmem_delay <= dmem_delay - 1'b1;
                else begin
                    dmem_pending <= 1'b0;
                    if (held_write) begin
                        for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1)
                            if (held_wstrb[byte_i])
                                data_mem[held_addr + byte_i] <=
                                    held_wdata[byte_i*8 +: 8];
                        dm_resp_wvalid <= 1'b1;
                    end
                    else begin
                        dm_resp_rdata <= read_data_word(held_addr);
                        dm_resp_rvalid <= 1'b1;
                    end
                end
            end

            if (any_dm_request && (dm_req_addr == 32'd132))
                $fatal(1, "wrong-path store reached the direct DM interface");
        end
    end

    reg [31:0] expected_pc [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_instr [0:EXPECTED_RETIRE-1];
    reg        expected_write [0:EXPECTED_RETIRE-1];
    reg [4:0]  expected_rd [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_data [0:EXPECTED_RETIRE-1];
    integer expected_fill;

    task automatic add_expected;
        input [31:0] pc;
        input [31:0] instr;
        input        writes;
        input [4:0]  rd;
        input [31:0] data;
        begin
            expected_pc[expected_fill] = pc;
            expected_instr[expected_fill] = instr;
            expected_write[expected_fill] = writes;
            expected_rd[expected_fill] = rd;
            expected_data[expected_fill] = data;
            expected_fill = expected_fill + 1;
        end
    endtask

    integer trace_index;
    integer dual_retire_cycles;
    reg pair_waw_seen;
    reg pair_war_seen;
    reg done;

    task automatic check_retire_lane;
        input integer lane;
        reg [31:0] got_pc;
        reg [31:0] got_instr;
        reg        got_write;
        reg [4:0]  got_rd;
        reg [31:0] got_data;
        begin
            got_pc = retire_pc[lane*32 +: 32];
            got_instr = retire_instr[lane*32 +: 32];
            got_write = retire_rd_write[lane];
            got_rd = retire_rd_addr[lane*5 +: 5];
            got_data = retire_rd_data[lane*32 +: 32];
            if (trace_index >= EXPECTED_RETIRE)
                $fatal(1, "unexpected retire lane=%0d pc=%08x instr=%08x",
                       lane, got_pc, got_instr);
            if ((got_pc !== expected_pc[trace_index]) ||
                (got_instr !== expected_instr[trace_index]))
                $fatal(1, "retire[%0d] mismatch pc=%08x/%08x instr=%08x/%08x",
                       trace_index, got_pc, expected_pc[trace_index], got_instr,
                       expected_instr[trace_index]);
            if (got_write !== expected_write[trace_index])
                $fatal(1, "retire[%0d] write flag mismatch", trace_index);
            if (got_write && ((got_rd !== expected_rd[trace_index]) ||
                              (got_data !== expected_data[trace_index])))
                $fatal(1, "retire[%0d] write mismatch rd=%0d/%0d data=%08x/%08x",
                       trace_index, got_rd, expected_rd[trace_index], got_data,
                       expected_data[trace_index]);
            trace_index = trace_index + 1;
            if (trace_index == EXPECTED_RETIRE)
                done = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            if (retire_valid[1] && !retire_valid[0])
                $fatal(1, "lane 1 retired without lane 0");
            if (retire_valid == 2'b11) begin
                dual_retire_cycles = dual_retire_cycles + 1;
                if ((retire_pc[31:0] == 32'd8) &&
                    (retire_pc[63:32] == 32'd12))
                    $fatal(1, "same-packet RAW pair retired as one issue bundle");
                if ((retire_pc[31:0] == 32'd16) &&
                    (retire_pc[63:32] == 32'd20))
                    pair_waw_seen = 1'b1;
                if ((retire_pc[31:0] == 32'd24) &&
                    (retire_pc[63:32] == 32'd28))
                    pair_war_seen = 1'b1;
            end
            if ((retire_valid[0] && (retire_instr[31:0] == FENCE)) ||
                (retire_valid[1] && (retire_instr[63:32] == FENCE))) begin
                if (!retire_valid[0] || retire_valid[1] ||
                    (retire_instr[31:0] != FENCE))
                    $fatal(1, "FENCE did not retire alone in lane 0");
            end
            if (retire_valid[0])
                check_retire_lane(0);
            if (retire_valid[1])
                check_retire_lane(1);
        end
    end

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        done = 1'b0;
        trace_index = 0;
        dual_retire_cycles = 0;
        pair_waw_seen = 1'b0;
        pair_war_seen = 1'b0;
        expected_fill = 0;

        for (init_i = 0; init_i < IMEM_WORDS; init_i = init_i + 1)
            imem[init_i] = NOP;
        for (init_i = 0; init_i < DMEM_BYTES; init_i = init_i + 1)
            data_mem[init_i] = 8'b0;

        imem[0]  = enc_i(5,  0, 3'b000, 1, 7'b0010011);
        imem[1]  = enc_i(7,  0, 3'b000, 2, 7'b0010011);
        imem[2]  = enc_r(0, 2, 1, 3'b000, 3);
        imem[3]  = enc_i(1,  3, 3'b000, 4, 7'b0010011);
        imem[4]  = enc_i(9,  0, 3'b000, 5, 7'b0010011);
        imem[5]  = enc_i(11, 0, 3'b000, 5, 7'b0010011);
        imem[6]  = enc_r(0, 1, 5, 3'b000, 6);
        imem[7]  = enc_i(20, 0, 3'b000, 1, 7'b0010011);
        imem[8]  = enc_i(99, 0, 3'b000, 0, 7'b0010011);
        imem[9]  = enc_r(1, 2, 3, 3'b000, 7);
        imem[10] = enc_r(1, 2, 7, 3'b100, 8);
        imem[11] = enc_r(1, 1, 7, 3'b110, 9);
        imem[12] = enc_s(128, 7, 0, 3'b010);
        imem[13] = enc_i(128, 0, 3'b010, 10, 7'b0000011);
        imem[14] = enc_b(12, 7, 10, 3'b000);
        imem[15] = enc_i(99, 0, 3'b000, 11, 7'b0010011);
        imem[16] = enc_s(132, 1, 0, 3'b010);
        imem[17] = enc_i(17, 0, 3'b000, 11, 7'b0010011);
        imem[18] = enc_j(8, 12);
        imem[19] = enc_i(99, 0, 3'b000, 13, 7'b0010011);
        imem[20] = enc_i(92, 0, 3'b000, 14, 7'b0010011);
        imem[21] = enc_i(0, 14, 3'b000, 15, 7'b1100111);
        imem[22] = enc_i(99, 0, 3'b000, 16, 7'b0010011);
        imem[23] = FENCE;
        imem[24] = enc_i(1, 0, 3'b000, 17, 7'b0010011);
        imem[25] = enc_i(2, 0, 3'b000, 18, 7'b0010011);
        imem[26] = enc_j(0, 0);

        add_expected(0,   imem[0],  1'b1, 5'd1,  32'd5);
        add_expected(4,   imem[1],  1'b1, 5'd2,  32'd7);
        add_expected(8,   imem[2],  1'b1, 5'd3,  32'd12);
        add_expected(12,  imem[3],  1'b1, 5'd4,  32'd13);
        add_expected(16,  imem[4],  1'b1, 5'd5,  32'd9);
        add_expected(20,  imem[5],  1'b1, 5'd5,  32'd11);
        add_expected(24,  imem[6],  1'b1, 5'd6,  32'd16);
        add_expected(28,  imem[7],  1'b1, 5'd1,  32'd20);
        add_expected(32,  imem[8],  1'b0, 5'd0,  32'b0);
        add_expected(36,  imem[9],  1'b1, 5'd7,  32'd84);
        add_expected(40,  imem[10], 1'b1, 5'd8,  32'd12);
        add_expected(44,  imem[11], 1'b1, 5'd9,  32'd4);
        add_expected(48,  imem[12], 1'b0, 5'd0,  32'b0);
        add_expected(52,  imem[13], 1'b1, 5'd10, 32'd84);
        add_expected(56,  imem[14], 1'b0, 5'd0,  32'b0);
        add_expected(68,  imem[17], 1'b1, 5'd11, 32'd17);
        add_expected(72,  imem[18], 1'b1, 5'd12, 32'd76);
        add_expected(80,  imem[20], 1'b1, 5'd14, 32'd92);
        add_expected(84,  imem[21], 1'b1, 5'd15, 32'd88);
        add_expected(92,  imem[23], 1'b0, 5'd0,  32'b0);
        add_expected(96,  imem[24], 1'b1, 5'd17, 32'd1);
        add_expected(100, imem[25], 1'b1, 5'd18, 32'd2);

        if (expected_fill != EXPECTED_RETIRE)
            $fatal(1, "internal expected trace size mismatch");

        repeat (5) @(posedge clk);
        reset <= 1'b0;

        fork
            begin
                wait (done);
            end
            begin
                repeat (5000) @(posedge clk);
                $fatal(1, "dual core timeout retired=%0d/%0d",
                       trace_index, EXPECTED_RETIRE);
            end
        join_any
        disable fork;
        @(negedge clk);

        if (dual_retire_cycles == 0)
            $fatal(1, "the fixed two-wide retirement path was never active");
        if (!pair_waw_seen || !pair_war_seen)
            $fatal(1, "legal WAW/WAR pairs were not preserved: waw=%0d war=%0d",
                   pair_waw_seen, pair_war_seen);
        if ((write_accept_count != 1) || (read_accept_count != 1))
            $fatal(1, "DM acceptance count mismatch writes=%0d reads=%0d",
                   write_accept_count, read_accept_count);
        if (backpressure_cycles < 4)
            $fatal(1, "DM backpressure path was not exercised");
        if (read_data_word(32'd128) != 32'd84)
            $fatal(1, "final direct memory state mismatch");

        $display("DUAL_CORE_TRACE PASS retired=%0d dual_cycles=%0d waw=1 war=1",
                 trace_index, dual_retire_cycles);
        $display("DUAL_CORE_MEMORY PASS reads=%0d writes=%0d backpressure_cycles=%0d",
                 read_accept_count, write_accept_count, backpressure_cycles);
        $display("DUAL_CORE_TEST PASS");
        $finish;
    end
endmodule
