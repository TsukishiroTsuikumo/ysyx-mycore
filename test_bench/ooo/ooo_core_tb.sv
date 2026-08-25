`timescale 1ns/1ps

// Public-interface acceptance gate for the bounded OoO evolution of mycore.
// No implementation hierarchy below `mycore` is observed: ordering comes
// from the flat retirement bus and OoO progress comes from the split DM bus.
module ooo_core_tb;
    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_BYTES = 512;
    localparam integer EXPECTED_RETIRE = 29;
    localparam [31:0] NOP   = 32'h0000_0013;
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

    // Ordered 128-bit PM line responses with one outstanding transaction.
    reg        imem_pending;
    reg [31:0] imem_pending_addr;
    reg [2:0]  imem_delay;
    reg        mul_retired;
    reg        fetched_under_m_stall;
    assign pm_req_ready = !imem_pending && !reset;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            imem_pending <= 1'b0;
            imem_pending_addr <= 32'b0;
            imem_delay <= 3'b0;
            pm_resp_valid <= 1'b0;
            pm_resp_data <= 128'b0;
            fetched_under_m_stall <= 1'b0;
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
                if (!mul_retired && (pm_req_addr >= 32'd32))
                    fetched_under_m_stall <= 1'b1;
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

    // DM deliberately holds ready low for two cycles and then delays the
    // response.  This checks valid/payload stability as well as LSQ ordering.
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
    integer load80_accept_count;
    integer backpressure_cycles;
    integer byte_i;
    reg younger_load_before_mul_retire;
    reg older_sequence_retired;
    reg store_retired;
    reg fence_retired;

    wire any_dm_request = dm_req_rvalid || dm_req_wvalid;
    wire dm_accept_enable = dmem_arming && (dmem_stall_count == 0) &&
                            !dmem_pending;
    assign dm_req_rready = dm_accept_enable;
    assign dm_req_wready = dm_accept_enable;

    function automatic retire_has_pc;
        input [31:0] pc;
        begin
            retire_has_pc = (retire_valid[0] && (retire_pc[31:0] == pc)) ||
                            (retire_valid[1] && (retire_pc[63:32] == pc));
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mul_retired <= 1'b0;
            older_sequence_retired <= 1'b0;
            store_retired <= 1'b0;
            fence_retired <= 1'b0;
        end
        else begin
            if (retire_has_pc(32'd8))
                mul_retired <= 1'b1;
            if (retire_has_pc(32'd56))
                older_sequence_retired <= 1'b1;
            if (retire_has_pc(32'd60))
                store_retired <= 1'b1;
            if (retire_has_pc(32'd112))
                fence_retired <= 1'b1;
        end
    end

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
            load80_accept_count <= 0;
            backpressure_cycles <= 0;
            younger_load_before_mul_retire <= 1'b0;
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
                        if ((held_addr != 32'd80) ||
                            (held_wstrb != 4'b1111) ||
                            (held_wdata != 32'd42))
                            $fatal(1, "unexpected store addr=%08x strb=%x data=%08x",
                                   held_addr, held_wstrb, held_wdata);
                        if (!older_sequence_retired)
                            $fatal(1, "store became externally visible before reaching ROB head");
                    end
                    else begin
                        read_accept_count <= read_accept_count + 1;
                        if (held_addr == 32'd64) begin
                            if (mul_retired || retire_has_pc(32'd8))
                                $fatal(1, "young load did not issue before older M retired");
                            younger_load_before_mul_retire <= 1'b1;
                        end
                        else if (held_addr == 32'd80) begin
                            load80_accept_count <= load80_accept_count + 1;
                            if (load80_accept_count == 0) begin
                                if (!store_retired)
                                    $fatal(1, "load passed an older unretired store");
                            end
                            else if (!fence_retired)
                                $fatal(1, "post-FENCE load issued before FENCE retirement");
                        end
                        else
                            $fatal(1, "unexpected load address %08x", held_addr);
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

            if (any_dm_request && ((dm_req_addr == 32'd84) ||
                                   (dm_req_addr == 32'd88) ||
                                   (dm_req_addr == 32'd92)))
                $fatal(1, "wrong-path memory request reached DM addr=%08x",
                       dm_req_addr);
        end
    end

    reg [31:0] expected_pc [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_instr [0:EXPECTED_RETIRE-1];
    reg        expected_write [0:EXPECTED_RETIRE-1];
    reg [4:0]  expected_rd [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_data [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_arch [0:31];
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
    integer m_head_stall_cycles;
    reg m_head_window;
    reg pair_waw_seen;
    reg pair_war_seen;
    reg pair_raw_seen;
    reg fence_seen;
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
                $fatal(1, "unexpected retire lane=%0d pc=%08x", lane, got_pc);
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
            if (retire_valid == 2'b11)
                dual_retire_cycles = dual_retire_cycles + 1;
            // Exact trace checking proves the first member already retired.
            // These markers do not require a particular completion/commit
            // alignment for the dependency pair itself.
            if (retire_has_pc(32'd36))
                pair_waw_seen = 1'b1;
            if (retire_has_pc(32'd44))
                pair_war_seen = 1'b1;
            if (retire_has_pc(32'd52))
                pair_raw_seen = 1'b1;
            if (m_head_window) begin
                if (retire_has_pc(32'd8))
                    m_head_window = 1'b0;
                else begin
                    if (retire_valid != 2'b00)
                        $fatal(1, "younger instruction retired around blocked older M");
                    m_head_stall_cycles = m_head_stall_cycles + 1;
                end
            end
            if (retire_has_pc(32'd4))
                m_head_window = 1'b1;
            if ((retire_valid[0] && (retire_instr[31:0] == FENCE)) ||
                (retire_valid[1] && (retire_instr[63:32] == FENCE))) begin
                if (!retire_valid[0] || retire_valid[1] ||
                    (retire_instr[31:0] != FENCE))
                    $fatal(1, "FENCE did not retire alone in lane 0");
                fence_seen = 1'b1;
            end
            if (retire_valid[0])
                check_retire_lane(0);
            if (retire_valid[1])
                check_retire_lane(1);
        end
    end

    reg [31:0] got_arch;
    integer arch_i;
    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        done = 1'b0;
        trace_index = 0;
        dual_retire_cycles = 0;
        m_head_stall_cycles = 0;
        m_head_window = 1'b0;
        pair_waw_seen = 1'b0;
        pair_war_seen = 1'b0;
        pair_raw_seen = 1'b0;
        fence_seen = 1'b0;
        expected_fill = 0;

        for (init_i = 0; init_i < IMEM_WORDS; init_i = init_i + 1)
            imem[init_i] = NOP;
        for (init_i = 0; init_i < DMEM_BYTES; init_i = init_i + 1)
            data_mem[init_i] = 8'b0;
        for (init_i = 0; init_i < 32; init_i = init_i + 1)
            expected_arch[init_i] = 32'b0;

        data_mem[64] = 8'h78;
        data_mem[65] = 8'h56;
        data_mem[66] = 8'h34;
        data_mem[67] = 8'h12;

        imem[0]  = enc_i(6,   0, 3'b000, 1,  7'b0010011);
        imem[1]  = enc_i(7,   0, 3'b000, 2,  7'b0010011);
        imem[2]  = enc_r(1, 2, 1, 3'b000, 3);                // MUL
        imem[3]  = enc_i(64,  0, 3'b010, 4,  7'b0000011);   // young LW
        imem[4]  = enc_i(1,   0, 3'b000, 10, 7'b0010011);
        imem[5]  = enc_i(2,   0, 3'b000, 11, 7'b0010011);
        imem[6]  = enc_i(3,   0, 3'b000, 12, 7'b0010011);
        imem[7]  = enc_i(4,   0, 3'b000, 13, 7'b0010011);
        imem[8]  = enc_i(9,   0, 3'b000, 5,  7'b0010011);
        imem[9]  = enc_i(11,  0, 3'b000, 5,  7'b0010011);   // pair WAW
        imem[10] = enc_r(0, 20, 5, 3'b000, 6);              // old x20
        imem[11] = enc_i(200, 0, 3'b000, 20, 7'b0010011);   // pair WAR
        imem[12] = enc_r(0, 1, 6, 3'b000, 7);
        imem[13] = enc_i(1,   7, 3'b000, 8,  7'b0010011);   // pair RAW
        imem[14] = enc_i(99,  0, 3'b000, 0,  7'b0010011);   // x0
        imem[15] = enc_s(80,  3, 0, 3'b010);
        imem[16] = enc_i(80,  0, 3'b010, 9,  7'b0000011);
        imem[17] = enc_b(12,  3, 9, 3'b000);                // -> 80
        imem[18] = enc_i(99,  0, 3'b000, 21, 7'b0010011);   // wrong
        imem[19] = enc_s(84,  1, 0, 3'b010);                // wrong
        imem[20] = enc_i(7,   0, 3'b000, 21, 7'b0010011);
        imem[21] = enc_j(8, 22);                            // -> 92
        imem[22] = enc_i(88,  0, 3'b010, 23, 7'b0000011);   // wrong
        imem[23] = enc_i(8,   0, 3'b000, 23, 7'b0010011);
        imem[24] = enc_i(112, 0, 3'b000, 24, 7'b0010011);
        imem[25] = enc_i(0,  24, 3'b000, 25, 7'b1100111);   // -> 112
        imem[26] = enc_i(66,  0, 3'b000, 26, 7'b0010011);   // wrong
        imem[27] = enc_s(92,  1, 0, 3'b010);                // wrong
        imem[28] = FENCE;
        imem[29] = enc_i(80,  0, 3'b010, 29, 7'b0000011);
        imem[30] = enc_i(1,   0, 3'b000, 27, 7'b0010011);
        imem[31] = enc_i(2,   0, 3'b000, 28, 7'b0010011);
        imem[32] = enc_i(144, 0, 3'b000, 30, 7'b0010011);
        imem[33] = enc_i(0, 30, 3'b000, 0, 7'b1100111);    // JALR x0 -> 144
        imem[34] = enc_i(99, 0, 3'b000, 31, 7'b0010011);   // wrong
        imem[35] = enc_s(96, 1, 0, 3'b010);                // wrong
        imem[36] = enc_j(0, 0);

        add_expected(0,   imem[0],  1'b1, 5'd1,  32'd6);
        add_expected(4,   imem[1],  1'b1, 5'd2,  32'd7);
        add_expected(8,   imem[2],  1'b1, 5'd3,  32'd42);
        add_expected(12,  imem[3],  1'b1, 5'd4,  32'h1234_5678);
        add_expected(16,  imem[4],  1'b1, 5'd10, 32'd1);
        add_expected(20,  imem[5],  1'b1, 5'd11, 32'd2);
        add_expected(24,  imem[6],  1'b1, 5'd12, 32'd3);
        add_expected(28,  imem[7],  1'b1, 5'd13, 32'd4);
        add_expected(32,  imem[8],  1'b1, 5'd5,  32'd9);
        add_expected(36,  imem[9],  1'b1, 5'd5,  32'd11);
        add_expected(40,  imem[10], 1'b1, 5'd6,  32'd111);
        add_expected(44,  imem[11], 1'b1, 5'd20, 32'd200);
        add_expected(48,  imem[12], 1'b1, 5'd7,  32'd117);
        add_expected(52,  imem[13], 1'b1, 5'd8,  32'd118);
        // Report the decoded rd intent for x0 on the stable retirement bus;
        // the PRF/RAT checks below still require x0 to remain immutable.
        add_expected(56,  imem[14], 1'b1, 5'd0,  32'b0);
        add_expected(60,  imem[15], 1'b0, 5'd0,  32'b0);
        add_expected(64,  imem[16], 1'b1, 5'd9,  32'd42);
        add_expected(68,  imem[17], 1'b0, 5'd0,  32'b0);
        add_expected(80,  imem[20], 1'b1, 5'd21, 32'd7);
        add_expected(84,  imem[21], 1'b1, 5'd22, 32'd88);
        add_expected(92,  imem[23], 1'b1, 5'd23, 32'd8);
        add_expected(96,  imem[24], 1'b1, 5'd24, 32'd112);
        add_expected(100, imem[25], 1'b1, 5'd25, 32'd104);
        add_expected(112, imem[28], 1'b0, 5'd0,  32'b0);
        add_expected(116, imem[29], 1'b1, 5'd29, 32'd42);
        add_expected(120, imem[30], 1'b1, 5'd27, 32'd1);
        add_expected(124, imem[31], 1'b1, 5'd28, 32'd2);
        add_expected(128, imem[32], 1'b1, 5'd30, 32'd144);
        // JALR must still use adder mode when the architectural destination
        // is x0; only the physical-write intent is suppressed.
        add_expected(132, imem[33], 1'b1, 5'd0,  32'b0);

        expected_arch[1]  = 32'd6;
        expected_arch[2]  = 32'd7;
        expected_arch[3]  = 32'd42;
        expected_arch[4]  = 32'h1234_5678;
        expected_arch[5]  = 32'd11;
        expected_arch[6]  = 32'd111;
        expected_arch[7]  = 32'd117;
        expected_arch[8]  = 32'd118;
        expected_arch[9]  = 32'd42;
        expected_arch[10] = 32'd1;
        expected_arch[11] = 32'd2;
        expected_arch[12] = 32'd3;
        expected_arch[13] = 32'd4;
        expected_arch[20] = 32'd200;
        expected_arch[21] = 32'd7;
        expected_arch[22] = 32'd88;
        expected_arch[23] = 32'd8;
        expected_arch[24] = 32'd112;
        expected_arch[25] = 32'd104;
        expected_arch[27] = 32'd1;
        expected_arch[28] = 32'd2;
        expected_arch[29] = 32'd42;
        expected_arch[30] = 32'd144;

        if (expected_fill != EXPECTED_RETIRE)
            $fatal(1, "internal expected trace size mismatch");

        repeat (5) @(posedge clk);
        @(negedge clk);
        dut.write_arch_reg(5'd20, 32'd100);
        reset = 1'b0;

        fork
            begin
                wait (done);
            end
            begin
                repeat (8000) @(posedge clk);
                $fatal(1, "OoO core timeout retired=%0d/%0d",
                       trace_index, EXPECTED_RETIRE);
            end
        join_any
        disable fork;
        @(negedge clk);

        if (!younger_load_before_mul_retire)
            $fatal(1, "no public OoO evidence: young load missed M window");
        if (!fetched_under_m_stall || (m_head_stall_cycles < 8))
            $fatal(1, "ROB pressure window missing fetch=%0d stalled=%0d",
                   fetched_under_m_stall, m_head_stall_cycles);
        if (dual_retire_cycles == 0)
            $fatal(1, "bounded OoO core never retired two instructions");
        if (!pair_waw_seen || !pair_war_seen || !pair_raw_seen)
            $fatal(1, "rename pair coverage missing raw=%0d waw=%0d war=%0d",
                   pair_raw_seen, pair_waw_seen, pair_war_seen);
        if (!fence_seen)
            $fatal(1, "FENCE was not observed at retirement");
        if ((write_accept_count != 1) || (read_accept_count != 3) ||
            (load80_accept_count != 2))
            $fatal(1, "DM acceptance mismatch writes=%0d reads=%0d load80=%0d",
                   write_accept_count, read_accept_count, load80_accept_count);
        if (backpressure_cycles < 8)
            $fatal(1, "DM backpressure path was not exercised");
        if (read_data_word(32'd80) != 32'd42)
            $fatal(1, "final direct memory state mismatch");

        for (arch_i = 0; arch_i < 32; arch_i = arch_i + 1) begin
            dut.read_arch_reg(arch_i, got_arch);
            if (got_arch !== expected_arch[arch_i])
                $fatal(1, "architectural x%0d mismatch got=%08x expected=%08x",
                       arch_i, got_arch, expected_arch[arch_i]);
        end

        $display("OOO_CORE_ORDER PASS retired=%0d dual_cycles=%0d raw=1 waw=1 war=1",
                 trace_index, dual_retire_cycles);
        $display("OOO_CORE_PROGRESS PASS young_load_before_mul=1 rob_stall=%0d",
                 m_head_stall_cycles);
        $display("OOO_CORE_MEMORY PASS reads=%0d writes=%0d backpressure=%0d",
                 read_accept_count, write_accept_count, backpressure_cycles);
        $display("OOO_CORE_TEST PASS");
        $finish;
    end
endmodule
