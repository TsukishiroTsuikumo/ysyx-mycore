`timescale 1ns/1ps

// End-to-end bounded OoO smoke test:
// the one mycore instance -> real ICache/DCache -> AXI fabric -> AXI RAM.
module ooo_system_tb;
    localparam integer EXPECTED_RETIRE = 14;
    localparam [31:0] NOP = 32'h0000_0013;

    reg clk;
    reg reset;

    wire [31:0] core_dm_addr;
    wire        core_dm_rvalid;
    wire        core_dm_wvalid;
    wire        core_dm_rready;
    wire        core_dm_wready;

    wire [1:0]  retire_valid;
    wire [63:0] retire_pc;
    wire [63:0] retire_instr;
    wire [1:0]  retire_rd_write;
    wire [9:0]  retire_rd_addr;
    wire [63:0] retire_rd_data;

    wire        bus_fault_valid;
    wire        bus_fault_is_write;
    wire [31:0] bus_fault_addr;
    wire [1:0]  bus_fault_resp;

    wire [1:0]  mon_axi_awid;
    wire [31:0] mon_axi_awaddr;
    wire        mon_axi_awvalid;
    wire        mon_axi_awready;
    wire [31:0] mon_axi_wdata;
    wire [3:0]  mon_axi_wstrb;
    wire        mon_axi_wlast;
    wire        mon_axi_wvalid;
    wire        mon_axi_wready;
    wire [1:0]  mon_axi_bid;
    wire [1:0]  mon_axi_bresp;
    wire        mon_axi_bvalid;
    wire        mon_axi_bready;
    wire [1:0]  mon_axi_arid;
    wire [31:0] mon_axi_araddr;
    wire        mon_axi_arvalid;
    wire        mon_axi_arready;
    wire [1:0]  mon_axi_rid;
    wire [31:0] mon_axi_rdata;
    wire [1:0]  mon_axi_rresp;
    wire        mon_axi_rlast;
    wire        mon_axi_rvalid;
    wire        mon_axi_rready;

    mycore_system #(
        .ICACHE_WAY_NUM(2),
        .ICACHE_SET_NUM(2),
        .DCACHE_WAY_NUM(2),
        .DCACHE_SET_NUM(2),
        .MEM_WIDTH(12),
        .MEM_BYTES(4096)
    ) dut (
        .clk(clk),
        .reset(reset),
        .use_cache(1'b1),

        .pm_req_valid_out(),
        .pm_req_addr_out(),
        .pm_req_ready_in(1'b0),
        .pm_resp_valid_in(1'b0),
        .pm_resp_data_in(128'b0),

        .dm_req_addr_out(core_dm_addr),
        .dm_req_rvalid_out(core_dm_rvalid),
        .dm_req_rready_in(1'b0),
        .dm_resp_rvalid_in(1'b0),
        .dm_resp_rdata_in(32'b0),
        .dm_req_wvalid_out(core_dm_wvalid),
        .dm_req_wready_in(1'b0),
        .dm_req_wstrb_out(),
        .dm_req_wdata_out(),
        .dm_resp_wvalid_in(1'b0),

        .retire_valid_out(retire_valid),
        .retire_pc_out(retire_pc),
        .retire_instr_out(retire_instr),
        .retire_rd_write_out(retire_rd_write),
        .retire_rd_addr_out(retire_rd_addr),
        .retire_rd_data_out(retire_rd_data),

        .bus_fault_valid_out(bus_fault_valid),
        .bus_fault_is_write_out(bus_fault_is_write),
        .bus_fault_addr_out(bus_fault_addr),
        .bus_fault_resp_out(bus_fault_resp),

        .mon_core_pm_req_ready(),
        .mon_core_pm_resp_valid(),
        .mon_core_pm_resp_data(),
        .mon_core_dm_req_rready(core_dm_rready),
        .mon_core_dm_resp_rvalid(),
        .mon_core_dm_resp_rdata(),
        .mon_core_dm_req_wready(core_dm_wready),
        .mon_core_dm_resp_wvalid(),

        .mon_axi_awid(mon_axi_awid),
        .mon_axi_awaddr(mon_axi_awaddr),
        .mon_axi_awlen(),
        .mon_axi_awsize(),
        .mon_axi_awburst(),
        .mon_axi_awlock(),
        .mon_axi_awcache(),
        .mon_axi_awprot(),
        .mon_axi_awqos(),
        .mon_axi_awvalid(mon_axi_awvalid),
        .mon_axi_awready(mon_axi_awready),
        .mon_axi_wdata(mon_axi_wdata),
        .mon_axi_wstrb(mon_axi_wstrb),
        .mon_axi_wlast(mon_axi_wlast),
        .mon_axi_wvalid(mon_axi_wvalid),
        .mon_axi_wready(mon_axi_wready),
        .mon_axi_bid(mon_axi_bid),
        .mon_axi_bresp(mon_axi_bresp),
        .mon_axi_bvalid(mon_axi_bvalid),
        .mon_axi_bready(mon_axi_bready),
        .mon_axi_arid(mon_axi_arid),
        .mon_axi_araddr(mon_axi_araddr),
        .mon_axi_arlen(),
        .mon_axi_arsize(),
        .mon_axi_arburst(),
        .mon_axi_arlock(),
        .mon_axi_arcache(),
        .mon_axi_arprot(),
        .mon_axi_arqos(),
        .mon_axi_arvalid(mon_axi_arvalid),
        .mon_axi_arready(mon_axi_arready),
        .mon_axi_rid(mon_axi_rid),
        .mon_axi_rdata(mon_axi_rdata),
        .mon_axi_rresp(mon_axi_rresp),
        .mon_axi_rlast(mon_axi_rlast),
        .mon_axi_rvalid(mon_axi_rvalid),
        .mon_axi_rready(mon_axi_rready)
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

    reg [31:0] program_mem [0:63];
    reg [31:0] expected_pc [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_instr [0:EXPECTED_RETIRE-1];
    reg        expected_write [0:EXPECTED_RETIRE-1];
    reg [4:0]  expected_rd [0:EXPECTED_RETIRE-1];
    reg [31:0] expected_data [0:EXPECTED_RETIRE-1];
    integer expected_fill;
    integer init_i;

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
    integer icache_axi_reads;
    integer dcache_axi_reads;
    integer dcache_axi_writes;
    integer dcache_axi_write_beats;
    integer dcache_axi_write_responses;
    reg d_read_0200;
    reg d_read_0400;
    reg d_read_0420;
    reg d_read_0440;
    reg mul_retired;
    reg young_load_seen_before_mul;
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
                $fatal(1, "unexpected system retire lane=%0d pc=%08x", lane,
                       got_pc);
            if ((got_pc !== expected_pc[trace_index]) ||
                (got_instr !== expected_instr[trace_index]) ||
                (got_write !== expected_write[trace_index]))
                $fatal(1, "system retire[%0d] mismatch pc=%08x/%08x instr=%08x/%08x",
                       trace_index, got_pc, expected_pc[trace_index], got_instr,
                       expected_instr[trace_index]);
            if (got_write && ((got_rd !== expected_rd[trace_index]) ||
                              (got_data !== expected_data[trace_index])))
                $fatal(1, "system retire[%0d] write mismatch rd=%0d/%0d data=%08x/%08x",
                       trace_index, got_rd, expected_rd[trace_index], got_data,
                       expected_data[trace_index]);
            trace_index = trace_index + 1;
            if (trace_index == EXPECTED_RETIRE)
                done = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            mul_retired <= 1'b0;
        end
        else begin
            if (bus_fault_valid)
                $fatal(1, "unexpected integrated bus fault write=%0d addr=%08x resp=%x",
                       bus_fault_is_write, bus_fault_addr, bus_fault_resp);
            if (retire_valid[1] && !retire_valid[0])
                $fatal(1, "integrated lane 1 retired without lane 0");
            if (retire_valid == 2'b11)
                dual_retire_cycles = dual_retire_cycles + 1;
            if ((retire_valid[0] && (retire_pc[31:0] == 32'd8)) ||
                (retire_valid[1] && (retire_pc[63:32] == 32'd8)))
                mul_retired <= 1'b1;
            if (core_dm_rvalid && (core_dm_addr == 32'h0000_0200) &&
                !mul_retired)
                young_load_seen_before_mul = 1'b1;
            if (core_dm_wvalid && (core_dm_addr == 32'h0000_0444))
                $fatal(1, "wrong-path system store reached DCache");
            if (retire_valid[0])
                check_retire_lane(0);
            if (retire_valid[1])
                check_retire_lane(1);

            if (mon_axi_arvalid && mon_axi_arready) begin
                if (mon_axi_arid == 2'd0)
                    icache_axi_reads = icache_axi_reads + 1;
                else if (mon_axi_arid == 2'd1) begin
                    dcache_axi_reads = dcache_axi_reads + 1;
                    case (mon_axi_araddr)
                        32'h0000_0200: begin
                            if (d_read_0200) $fatal(1, "duplicate DCache fill 0x200");
                            d_read_0200 = 1'b1;
                        end
                        32'h0000_0400: begin
                            if (d_read_0400) $fatal(1, "duplicate DCache fill 0x400");
                            d_read_0400 = 1'b1;
                        end
                        32'h0000_0420: begin
                            if (d_read_0420) $fatal(1, "duplicate DCache fill 0x420");
                            d_read_0420 = 1'b1;
                        end
                        32'h0000_0440: begin
                            if (d_read_0440) $fatal(1, "duplicate DCache fill 0x440");
                            d_read_0440 = 1'b1;
                        end
                        default:
                            $fatal(1, "unexpected DCache AXI read %08x",
                                   mon_axi_araddr);
                    endcase
                end
                else
                    $fatal(1, "unknown AXI read owner ID %0d", mon_axi_arid);
            end
            if (mon_axi_awvalid && mon_axi_awready) begin
                dcache_axi_writes = dcache_axi_writes + 1;
                if (mon_axi_awid != 2'd1)
                    $fatal(1, "DCache write used owner ID %0d", mon_axi_awid);
                if ((mon_axi_awaddr != 32'h0000_0400) &&
                    (mon_axi_awaddr != 32'h0000_0420))
                    $fatal(1, "unexpected dirty writeback %08x", mon_axi_awaddr);
            end
            if (mon_axi_wvalid && mon_axi_wready)
                dcache_axi_write_beats = dcache_axi_write_beats + 1;
            if (mon_axi_bvalid && mon_axi_bready) begin
                dcache_axi_write_responses = dcache_axi_write_responses + 1;
                if ((mon_axi_bid != 2'd1) || (mon_axi_bresp != 2'b00))
                    $fatal(1, "dirty write response id=%0d resp=%x",
                           mon_axi_bid, mon_axi_bresp);
            end
            if (mon_axi_rvalid && mon_axi_rready) begin
                if (mon_axi_rresp != 2'b00)
                    $fatal(1, "integrated AXI read returned error %x",
                           mon_axi_rresp);
                if ((mon_axi_rid != 2'd0) && (mon_axi_rid != 2'd1))
                    $fatal(1, "integrated AXI read returned owner ID %0d",
                           mon_axi_rid);
            end
        end
    end

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        done = 1'b0;
        trace_index = 0;
        dual_retire_cycles = 0;
        icache_axi_reads = 0;
        dcache_axi_reads = 0;
        dcache_axi_writes = 0;
        dcache_axi_write_beats = 0;
        dcache_axi_write_responses = 0;
        d_read_0200 = 1'b0;
        d_read_0400 = 1'b0;
        d_read_0420 = 1'b0;
        d_read_0440 = 1'b0;
        mul_retired = 1'b0;
        young_load_seen_before_mul = 1'b0;
        expected_fill = 0;

        for (init_i = 0; init_i < 64; init_i = init_i + 1)
            program_mem[init_i] = NOP;

        program_mem[0]  = enc_i(6,    0, 3'b000, 1,  7'b0010011);
        program_mem[1]  = enc_i(7,    0, 3'b000, 2,  7'b0010011);
        program_mem[2]  = enc_r(1, 2, 1, 3'b000, 3);                 // MUL
        program_mem[3]  = enc_i(512,  0, 3'b010, 4,  7'b0000011);   // young LW
        program_mem[4]  = enc_i(1,    0, 3'b000, 5,  7'b0010011);
        program_mem[5]  = enc_i(2,    0, 3'b000, 6,  7'b0010011);
        program_mem[6]  = enc_s(1024, 3, 0, 3'b010);
        program_mem[7]  = enc_i(1024, 0, 3'b010, 7,  7'b0000011);
        program_mem[8]  = enc_s(1056, 2, 0, 3'b010);
        program_mem[9]  = enc_i(1056, 0, 3'b010, 8,  7'b0000011);
        program_mem[10] = enc_s(1088, 1, 0, 3'b010);
        program_mem[11] = enc_i(1088, 0, 3'b010, 9,  7'b0000011);
        program_mem[12] = enc_b(12, 1, 9, 3'b000);                  // -> 60
        program_mem[13] = enc_i(99,   0, 3'b000, 10, 7'b0010011);  // wrong
        program_mem[14] = enc_s(1092, 1, 0, 3'b010);               // wrong
        program_mem[15] = enc_i(5,    0, 3'b000, 10, 7'b0010011);
        program_mem[16] = enc_j(0, 0);

        add_expected(0,  program_mem[0],  1'b1, 5'd1,  32'd6);
        add_expected(4,  program_mem[1],  1'b1, 5'd2,  32'd7);
        add_expected(8,  program_mem[2],  1'b1, 5'd3,  32'd42);
        add_expected(12, program_mem[3],  1'b1, 5'd4,  32'd9);
        add_expected(16, program_mem[4],  1'b1, 5'd5,  32'd1);
        add_expected(20, program_mem[5],  1'b1, 5'd6,  32'd2);
        add_expected(24, program_mem[6],  1'b0, 5'd0,  32'b0);
        add_expected(28, program_mem[7],  1'b1, 5'd7,  32'd42);
        add_expected(32, program_mem[8],  1'b0, 5'd0,  32'b0);
        add_expected(36, program_mem[9],  1'b1, 5'd8,  32'd7);
        add_expected(40, program_mem[10], 1'b0, 5'd0,  32'b0);
        add_expected(44, program_mem[11], 1'b1, 5'd9,  32'd6);
        add_expected(48, program_mem[12], 1'b0, 5'd0,  32'b0);
        add_expected(60, program_mem[15], 1'b1, 5'd10, 32'd5);

        if (expected_fill != EXPECTED_RETIRE)
            $fatal(1, "internal integrated trace size mismatch");

        // The RAM's own initial block completes at time zero.  Program/data
        // preload uses the stable system task while reset keeps traffic idle.
        #1;
        for (init_i = 0; init_i < 64; init_i = init_i + 1)
            dut.write_word(init_i * 4, program_mem[init_i]);
        dut.write_word(32'h0000_0200, 32'd9);

        repeat (5) @(posedge clk);
        reset <= 1'b0;

        fork
            begin
                wait (done);
            end
            begin
                repeat (20000) @(posedge clk);
                $fatal(1, "OoO system timeout retired=%0d/%0d",
                       trace_index, EXPECTED_RETIRE);
            end
        join_any
        disable fork;
        @(negedge clk);

        if (bus_fault_valid)
            $fatal(1, "sticky bus fault set at completion");
        if (dual_retire_cycles == 0)
            $fatal(1, "integrated OoO system never dual-retired");
        if (!young_load_seen_before_mul)
            $fatal(1, "integrated M/young-load overlap was not observed");
        if (icache_axi_reads == 0)
            $fatal(1, "no ICache AXI owner-ID-0 read observed");
        if ((dcache_axi_reads != 4) || !d_read_0200 || !d_read_0400 ||
            !d_read_0420 || !d_read_0440)
            $fatal(1, "DCache refill coverage mismatch count=%0d seen=%b%b%b%b",
                   dcache_axi_reads, d_read_0200, d_read_0400,
                   d_read_0420, d_read_0440);
        if ((dcache_axi_writes == 0) ||
            (dcache_axi_write_beats < 4) ||
            (dcache_axi_write_responses == 0))
            $fatal(1, "dirty eviction missing aw=%0d w=%0d b=%0d",
                   dcache_axi_writes, dcache_axi_write_beats,
                   dcache_axi_write_responses);

        $display("OOO_SYSTEM_TRACE PASS retired=%0d dual_cycles=%0d",
                 trace_index, dual_retire_cycles);
        $display("OOO_SYSTEM_AXI PASS ic_reads=%0d dc_reads=%0d dc_writes=%0d beats=%0d",
                 icache_axi_reads, dcache_axi_reads, dcache_axi_writes,
                 dcache_axi_write_beats);
        $display("OOO_SYSTEM_TEST PASS");
        $finish;
    end
endmodule
