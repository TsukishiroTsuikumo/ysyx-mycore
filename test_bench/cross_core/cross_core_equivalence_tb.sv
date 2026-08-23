`timescale 1ns/1ps

// One shared RV32IM program is executed by four independently elaborated
// implementations.  CORE_KIND selects the stable scalar pipeline, the
// width-one/width-two configurations of mycore_dual, or the bounded OoO core.
// Every run is checked record-by-record against the same DPI C model and emits
// a canonical summary derived only from DUT-observed architectural state.
module cross_core_equivalence_tb #(
    parameter integer CORE_KIND = 0
);
    localparam integer CORE_STABLE = 0;
    localparam integer CORE_DUAL_1 = 1;
    localparam integer CORE_DUAL_2 = 2;
    localparam integer CORE_OOO    = 3;
    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_BYTES = 256;
    localparam integer TRACE_DEPTH = 64;
    localparam integer EXPECTED_RETIRE_COUNT = 10;
    localparam integer EXPECTED_MEMORY_COUNT = 2;
    localparam logic [31:0] NOP = 32'h0000_0013;
    localparam logic [31:0] FENCE = 32'h0000_000f;
    localparam logic [31:0] JAL_HALT = 32'h0000_006f;
    localparam logic [31:0] HALT_PC = 32'd40;
    localparam logic [63:0] HASH_SEED = 64'hcbf2_9ce4_8422_2325;

    `include "cmodel_dpi.svh"

    logic clk;
    logic reset;
    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [7:0] data_mem [0:DMEM_BYTES-1];

    wire [1:0] norm_retire_valid;
    wire [1:0][31:0] norm_retire_pc;
    wire [1:0][31:0] norm_retire_instr;
    wire [1:0] norm_commit_valid;
    wire [1:0][4:0] norm_rd_addr;
    wire [1:0][31:0] norm_rd_data;
    wire [31:0] norm_arch_regs [0:31];

    wire mem_req_valid;
    wire mem_req_write;
    wire [31:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    wire [3:0] mem_req_wstrb;
    wire mem_req_ready;
    logic mem_resp_valid;
    logic mem_resp_write;
    logic [31:0] mem_resp_rdata;

    function automatic string implementation_name;
        begin
            case (CORE_KIND)
                CORE_STABLE: implementation_name = "stable";
                CORE_DUAL_1: implementation_name = "dual1";
                CORE_DUAL_2: implementation_name = "dual2";
                CORE_OOO:    implementation_name = "ooo";
                default:     implementation_name = "invalid";
            endcase
        end
    endfunction

    function automatic logic [31:0] read_imem_word(input integer word_index);
        begin
            if ((word_index >= 0) && (word_index < IMEM_WORDS))
                read_imem_word = imem[word_index];
            else
                read_imem_word = NOP;
        end
    endfunction

    function automatic logic [127:0] read_imem_line(
        input logic [31:0] byte_addr
    );
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

    function automatic logic [31:0] read_data_word(
        input logic [31:0] byte_addr
    );
        begin
            if (byte_addr <= (DMEM_BYTES - 4))
                read_data_word = {data_mem[byte_addr+3],
                                  data_mem[byte_addr+2],
                                  data_mem[byte_addr+1],
                                  data_mem[byte_addr]};
            else
                read_data_word = 32'b0;
        end
    endfunction

    function automatic logic [63:0] hash_mix(
        input logic [63:0] hash_value,
        input logic [63:0] item
    );
        begin
            hash_mix = (hash_value ^ item) * 64'h0000_0100_0000_01b3;
        end
    endfunction

    function automatic logic [63:0] hash_retire_record(
        input logic [63:0] hash_value,
        input logic [31:0] pc,
        input logic [31:0] instr,
        input logic commit,
        input logic [4:0] rd,
        input logic [31:0] data
    );
        logic [63:0] mixed;
        begin
            mixed = hash_mix(hash_value, {pc, instr});
            mixed = hash_mix(mixed,
                {26'b0, commit, commit ? rd : 5'b0,
                 commit ? data : 32'b0});
            hash_retire_record = mixed;
        end
    endfunction

    function automatic logic [63:0] hash_memory_record(
        input logic [63:0] hash_value,
        input logic is_write,
        input logic [31:0] addr,
        input logic [3:0] wstrb,
        input logic [31:0] wdata,
        input logic [31:0] rdata
    );
        logic [63:0] mixed;
        begin
            mixed = hash_mix(hash_value,
                {26'b0, is_write, !is_write,
                 is_write ? wstrb : 4'b0, addr});
            mixed = hash_mix(mixed, is_write ? {32'b0, wdata}
                                             : {32'b0, rdata});
            hash_memory_record = mixed;
        end
    endfunction

    generate
        if (CORE_KIND == CORE_STABLE) begin : gen_stable
            wire pm_req_valid;
            wire [31:0] pm_req_addr;
            wire pm_req_ready;
            wire pm_resp_valid;
            wire [31:0] pm_resp_data;
            logic pm_pending_valid;
            logic [31:0] pm_pending_addr;

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

            mycore stable_dut (
                .clk(clk), .reset(reset),
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
                .dm_resp_wvalid_in(dm_resp_wvalid)
            );

            assign pm_req_ready = !reset;
            assign pm_resp_valid = pm_pending_valid;
            assign pm_resp_data = read_imem_word(pm_pending_addr[31:2]);
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

            assign mem_req_valid = dm_req_rvalid || dm_req_wvalid;
            assign mem_req_write = dm_req_wvalid;
            assign mem_req_addr = dm_req_addr;
            assign mem_req_wdata = dm_req_wdata;
            assign mem_req_wstrb = dm_req_wstrb;
            assign dm_req_rready = mem_req_ready;
            assign dm_req_wready = mem_req_ready;
            assign dm_resp_rvalid = mem_resp_valid && !mem_resp_write;
            assign dm_resp_wvalid = mem_resp_valid && mem_resp_write;
            assign dm_resp_rdata = mem_resp_rdata;

            assign norm_retire_valid = {1'b0, stable_dut.retire_valid};
            assign norm_retire_pc = {32'b0, stable_dut.PC_mem_wb};
            assign norm_retire_instr = {32'b0, stable_dut.instr_mem_wb};
            assign norm_commit_valid = {1'b0, stable_dut.commit_valid};
            assign norm_rd_addr = {5'b0, stable_dut.rd_addr_wb};
            assign norm_rd_data = {32'b0, stable_dut.w1_in_wb};
            for (genvar reg_index = 0; reg_index < 32;
                 reg_index = reg_index + 1) begin : gen_arch_regs
                assign norm_arch_regs[reg_index] =
                    stable_dut.regfile.reg_val[reg_index];
            end

            always @(posedge clk) begin
                if (!reset && dm_req_rvalid && dm_req_wvalid)
                    $fatal(1, "stable issued simultaneous read/write requests");
            end
        end
        else if ((CORE_KIND == CORE_DUAL_1) ||
                 (CORE_KIND == CORE_DUAL_2)) begin : gen_dual
            localparam integer DUAL_WIDTH =
                (CORE_KIND == CORE_DUAL_1) ? 1 : 2;
            wire pm_req_valid;
            wire [31:0] pm_req_addr;
            wire pm_req_ready;
            wire pm_resp_valid;
            wire [127:0] pm_resp_data;
            logic pm_pending_valid;
            logic [31:0] pm_pending_addr;
            wire [1:0] pm_resp_code = 2'b00;

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
            wire [31:0] arch_regs [0:31];

            mycore_dual #(
                .ISSUE_WIDTH(DUAL_WIDTH),
                .FETCH_DEPTH(8),
                .COUNTER_WIDTH(64),
                .RESET_PC(32'h0000_0000)
            ) dual_dut (
                .clk(clk), .reset(reset),
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
                .arch_regfile_out(arch_regs),
                .perf_cycle_count(),
                .perf_issued_instr_count(),
                .perf_retired_instr_count(),
                .perf_dual_issue_cycle_count(),
                .perf_dual_retire_cycle_count(),
                .perf_frontend_empty_cycle_count(),
                .perf_data_hazard_stall_cycle_count(),
                .perf_memory_stall_cycle_count(),
                .perf_pair_serialize_cycle_count()
            );

            assign pm_req_ready = !reset;
            assign pm_resp_valid = pm_pending_valid;
            assign pm_resp_data = read_imem_line(pm_pending_addr);
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

            assign mem_req_valid = dm_req_rvalid || dm_req_wvalid;
            assign mem_req_write = dm_req_wvalid;
            assign mem_req_addr = dm_req_addr;
            assign mem_req_wdata = dm_req_wdata;
            assign mem_req_wstrb = dm_req_wstrb;
            assign dm_req_rready = mem_req_ready;
            assign dm_req_wready = mem_req_ready;
            assign dm_resp_rvalid = mem_resp_valid && !mem_resp_write;
            assign dm_resp_wvalid = mem_resp_valid && mem_resp_write;
            assign dm_resp_rdata = mem_resp_rdata;

            assign norm_retire_valid = retire_valid;
            assign norm_retire_pc = retire_pc;
            assign norm_retire_instr = retire_instr;
            assign norm_commit_valid = commit_valid;
            assign norm_rd_addr = commit_rd_addr;
            assign norm_rd_data = commit_rd_data;
            for (genvar reg_index = 0; reg_index < 32;
                 reg_index = reg_index + 1) begin : gen_arch_regs
                assign norm_arch_regs[reg_index] = arch_regs[reg_index];
            end

            always @(posedge clk) begin
                if (!reset && dm_req_rvalid && dm_req_wvalid)
                    $fatal(1, "dual issued simultaneous read/write requests");
            end
        end
        else if (CORE_KIND == CORE_OOO) begin : gen_ooo
            wire imem_req_valid;
            wire [31:0] imem_req_addr;
            wire imem_req_ready;
            logic imem_resp_valid;
            logic [63:0] imem_resp_data;
            logic imem_pending_valid;
            logic [31:0] imem_pending_addr;
            wire dmem_req_valid;
            wire dmem_req_write;
            wire [31:0] dmem_req_addr;
            wire [31:0] dmem_req_wdata;
            wire [3:0] dmem_req_wstrb;
            wire [1:0] retire_valid;
            wire [1:0][31:0] retire_pc;
            wire [1:0][31:0] retire_instr;
            wire [1:0] retire_rd_write;
            wire [1:0][4:0] retire_rd_addr;
            wire [1:0][31:0] retire_rd_data;
            wire [31:0] arch_regs [0:31];

            ooo_core #(
                .ROB_DEPTH(8),
                .RS_DEPTH(12),
                .LSQ_DEPTH(8),
                .PRF_COUNT(48),
                .M_LATENCY(8)
            ) ooo_dut (
                .clk(clk), .reset(reset),
                .imem_req_valid_out(imem_req_valid),
                .imem_req_addr_out(imem_req_addr),
                .imem_req_ready_in(imem_req_ready),
                .imem_resp_valid_in(imem_resp_valid),
                .imem_resp_data_in(imem_resp_data),
                .dmem_req_valid_out(dmem_req_valid),
                .dmem_req_ready_in(mem_req_ready),
                .dmem_req_write_out(dmem_req_write),
                .dmem_req_addr_out(dmem_req_addr),
                .dmem_req_wdata_out(dmem_req_wdata),
                .dmem_req_wstrb_out(dmem_req_wstrb),
                .dmem_resp_valid_in(mem_resp_valid),
                .dmem_resp_rdata_in(mem_resp_rdata),
                .dmem_resp_error_in(1'b0),
                .retire_valid_out(retire_valid),
                .retire_pc_out(retire_pc),
                .retire_instr_out(retire_instr),
                .retire_rd_write_out(retire_rd_write),
                .retire_rd_addr_out(retire_rd_addr),
                .retire_rd_data_out(retire_rd_data),
                .arch_regfile_out(arch_regs),
                .rob_occupancy_out(),
                .cycle_count_out(),
                .retired_count_out(),
                .ooo_completion_count_out(),
                .rob_full_cycle_count_out(),
                .load_block_cycle_count_out(),
                .branch_recovery_count_out(),
                .memory_fault_sticky_out()
            );

            assign imem_req_ready = !reset;
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    imem_pending_valid <= 1'b0;
                    imem_pending_addr <= 32'b0;
                    imem_resp_valid <= 1'b0;
                    imem_resp_data <= 64'b0;
                end
                else begin
                    imem_resp_valid <= imem_pending_valid;
                    if (imem_pending_valid)
                        imem_resp_data <= {
                            read_imem_word((imem_pending_addr >> 2) + 1),
                            read_imem_word(imem_pending_addr >> 2)};
                    imem_pending_valid <=
                        imem_req_valid && imem_req_ready;
                    if (imem_req_valid && imem_req_ready)
                        imem_pending_addr <= imem_req_addr;
                end
            end

            assign mem_req_valid = dmem_req_valid;
            assign mem_req_write = dmem_req_write;
            assign mem_req_addr = dmem_req_addr;
            assign mem_req_wdata = dmem_req_wdata;
            assign mem_req_wstrb = dmem_req_wstrb;
            assign norm_retire_valid = retire_valid;
            assign norm_retire_pc = retire_pc;
            assign norm_retire_instr = retire_instr;
            assign norm_commit_valid = retire_rd_write;
            assign norm_rd_addr = retire_rd_addr;
            assign norm_rd_data = retire_rd_data;
            for (genvar reg_index = 0; reg_index < 32;
                 reg_index = reg_index + 1) begin : gen_arch_regs
                assign norm_arch_regs[reg_index] = arch_regs[reg_index];
            end
        end
        else begin : gen_invalid
            initial $fatal(1, "CORE_KIND must be 0, 1, 2 or 3");
            assign mem_req_valid = 1'b0;
            assign mem_req_write = 1'b0;
            assign mem_req_addr = 32'b0;
            assign mem_req_wdata = 32'b0;
            assign mem_req_wstrb = 4'b0;
            assign norm_retire_valid = 2'b0;
            assign norm_retire_pc = '0;
            assign norm_retire_instr = '0;
            assign norm_commit_valid = 2'b0;
            assign norm_rd_addr = '0;
            assign norm_rd_data = '0;
            for (genvar reg_index = 0; reg_index < 32;
                 reg_index = reg_index + 1) begin : gen_arch_regs
                assign norm_arch_regs[reg_index] = 32'b0;
            end
        end
    endgenerate

    logic mem_pending;
    logic [2:0] mem_delay;
    logic mem_pending_write;
    logic [31:0] mem_pending_addr;
    logic [31:0] mem_pending_wdata;
    logic [3:0] mem_pending_wstrb;
    assign mem_req_ready = !reset && !mem_pending;

    logic expected_mem_write [0:TRACE_DEPTH-1];
    logic [31:0] expected_mem_addr [0:TRACE_DEPTH-1];
    logic [3:0] expected_mem_wstrb [0:TRACE_DEPTH-1];
    logic [31:0] expected_mem_wdata [0:TRACE_DEPTH-1];
    logic [31:0] expected_mem_rdata [0:TRACE_DEPTH-1];
    integer expected_mem_count;
    integer actual_mem_index;
    logic [63:0] actual_memtrace_hash;
    integer mem_byte;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_pending <= 1'b0;
            mem_delay <= 3'b0;
            mem_pending_write <= 1'b0;
            mem_pending_addr <= 32'b0;
            mem_pending_wdata <= 32'b0;
            mem_pending_wstrb <= 4'b0;
            mem_resp_valid <= 1'b0;
            mem_resp_write <= 1'b0;
            mem_resp_rdata <= 32'b0;
            actual_mem_index = 0;
            actual_memtrace_hash = HASH_SEED;
        end
        else begin
            mem_resp_valid <= 1'b0;
            if (mem_req_valid && mem_req_ready) begin
                if (actual_mem_index >= expected_mem_count)
                    $fatal(1, "%s produced an extra memory request",
                           implementation_name());
                if (mem_req_write !==
                    expected_mem_write[actual_mem_index])
                    $fatal(1, "%s memory[%0d] kind mismatch",
                           implementation_name(), actual_mem_index);
                if (mem_req_addr !== expected_mem_addr[actual_mem_index])
                    $fatal(1,
                        "%s memory[%0d] address got=%08x expected=%08x",
                        implementation_name(), actual_mem_index,
                        mem_req_addr, expected_mem_addr[actual_mem_index]);
                if (mem_req_write) begin
                    if (mem_req_wstrb !==
                        expected_mem_wstrb[actual_mem_index])
                        $fatal(1, "%s memory[%0d] strobe mismatch",
                               implementation_name(), actual_mem_index);
                    if (mem_req_wdata !==
                        expected_mem_wdata[actual_mem_index])
                        $fatal(1, "%s memory[%0d] write data mismatch",
                               implementation_name(), actual_mem_index);
                end
                else if (read_data_word(mem_req_addr) !==
                         expected_mem_rdata[actual_mem_index])
                    $fatal(1, "%s memory[%0d] read data mismatch",
                           implementation_name(), actual_mem_index);

                actual_memtrace_hash = hash_memory_record(
                    actual_memtrace_hash, mem_req_write, mem_req_addr,
                    mem_req_wstrb, mem_req_wdata,
                    read_data_word(mem_req_addr));
                actual_mem_index = actual_mem_index + 1;
                mem_pending <= 1'b1;
                mem_delay <= 3'd2;
                mem_pending_write <= mem_req_write;
                mem_pending_addr <= mem_req_addr;
                mem_pending_wdata <= mem_req_wdata;
                mem_pending_wstrb <= mem_req_wstrb;
            end

            if (mem_pending) begin
                if (mem_delay != 0)
                    mem_delay <= mem_delay - 1'b1;
                else begin
                    mem_pending <= 1'b0;
                    mem_resp_valid <= 1'b1;
                    mem_resp_write <= mem_pending_write;
                    mem_resp_rdata <= read_data_word(mem_pending_addr);
                    if (mem_pending_write) begin
                        for (mem_byte = 0; mem_byte < 4;
                             mem_byte = mem_byte + 1) begin
                            if (mem_pending_wstrb[mem_byte] &&
                                ((mem_pending_addr + mem_byte) < DMEM_BYTES))
                                data_mem[mem_pending_addr + mem_byte] <=
                                    mem_pending_wdata[(mem_byte * 8) +: 8];
                        end
                    end
                end
            end
        end
    end

    logic [31:0] expected_pc [0:TRACE_DEPTH-1];
    logic [31:0] expected_instr [0:TRACE_DEPTH-1];
    logic expected_commit [0:TRACE_DEPTH-1];
    logic [4:0] expected_rd [0:TRACE_DEPTH-1];
    logic [31:0] expected_rd_data [0:TRACE_DEPTH-1];
    logic [31:0] expected_arch_regs [0:31];
    logic [7:0] expected_data_mem [0:DMEM_BYTES-1];
    integer expected_count;
    integer actual_index;
    integer expected_fence_count;
    integer actual_fence_count;
    logic trace_complete;
    logic [63:0] expected_reg_hash;
    logic [63:0] expected_memory_hash;
    logic [63:0] expected_retire_hash;
    logic [63:0] expected_memtrace_hash;
    logic [63:0] actual_retire_hash;

    task automatic build_reference_oracle;
        integer word_index;
        integer reg_index;
        integer byte_index;
        integer ok;
        integer halt_seen;
        int unsigned oracle_pc;
        int unsigned oracle_instr;
        int unsigned oracle_commit;
        int unsigned oracle_rd;
        int unsigned oracle_rd_data;
        int unsigned oracle_addr;
        int unsigned oracle_is_read;
        int unsigned oracle_rdata;
        int unsigned oracle_is_write;
        int unsigned oracle_wstrb;
        int unsigned oracle_wdata;
        int unsigned oracle_byte;
        begin
            if (!cmodel_init_empty())
                $fatal(1, "%s C model initialization failed",
                       implementation_name());
            for (word_index = 0; word_index < IMEM_WORDS;
                 word_index = word_index + 1)
                cmodel_imem_write32(word_index * 4, imem[word_index]);

            expected_count = 0;
            expected_mem_count = 0;
            expected_fence_count = 0;
            expected_retire_hash = HASH_SEED;
            expected_memtrace_hash = HASH_SEED;
            halt_seen = 0;
            while (!halt_seen && (expected_count < TRACE_DEPTH)) begin
                ok = cmodel_step(
                    oracle_pc, oracle_instr, oracle_commit, oracle_rd,
                    oracle_rd_data, oracle_addr, oracle_is_read,
                    oracle_rdata, oracle_is_write, oracle_wstrb,
                    oracle_wdata);
                if (!ok)
                    $fatal(1, "%s C model step failed",
                           implementation_name());
                if ((oracle_pc == HALT_PC) &&
                    (oracle_instr == JAL_HALT)) begin
                    halt_seen = 1;
                end
                else begin
                    if (oracle_instr == FENCE)
                        expected_fence_count = expected_fence_count + 1;
                    expected_pc[expected_count] = oracle_pc;
                    expected_instr[expected_count] = oracle_instr;
                    expected_commit[expected_count] =
                        oracle_commit[0] && (oracle_rd[4:0] != 5'b0);
                    expected_rd[expected_count] = oracle_rd[4:0];
                    expected_rd_data[expected_count] = oracle_rd_data;
                    expected_retire_hash = hash_retire_record(
                        expected_retire_hash, oracle_pc, oracle_instr,
                        expected_commit[expected_count], oracle_rd[4:0],
                        oracle_rd_data);
                    expected_count = expected_count + 1;

                    if (oracle_is_read || oracle_is_write) begin
                        expected_mem_write[expected_mem_count] =
                            oracle_is_write[0];
                        expected_mem_addr[expected_mem_count] = oracle_addr;
                        expected_mem_wstrb[expected_mem_count] =
                            oracle_wstrb[3:0];
                        expected_mem_wdata[expected_mem_count] = oracle_wdata;
                        expected_mem_rdata[expected_mem_count] = oracle_rdata;
                        expected_memtrace_hash = hash_memory_record(
                            expected_memtrace_hash, oracle_is_write[0],
                            oracle_addr, oracle_wstrb[3:0], oracle_wdata,
                            oracle_rdata);
                        expected_mem_count = expected_mem_count + 1;
                    end
                end
            end
            if (!halt_seen)
                $fatal(1, "%s C model did not reach halt",
                       implementation_name());
            if (expected_count != EXPECTED_RETIRE_COUNT)
                $fatal(1, "%s C model retired %0d, expected %0d",
                       implementation_name(), expected_count,
                       EXPECTED_RETIRE_COUNT);
            if (expected_mem_count != EXPECTED_MEMORY_COUNT)
                $fatal(1, "%s C model memory count %0d, expected %0d",
                       implementation_name(), expected_mem_count,
                       EXPECTED_MEMORY_COUNT);
            if (expected_fence_count != 1)
                $fatal(1, "%s C model FENCE count %0d, expected 1",
                       implementation_name(), expected_fence_count);

            expected_reg_hash = HASH_SEED;
            for (reg_index = 0; reg_index < 32;
                 reg_index = reg_index + 1) begin
                expected_arch_regs[reg_index] = cmodel_get_reg(reg_index);
                expected_reg_hash = hash_mix(expected_reg_hash,
                    {27'b0, reg_index[4:0],
                     expected_arch_regs[reg_index]});
            end
            expected_memory_hash = HASH_SEED;
            for (byte_index = 0; byte_index < DMEM_BYTES;
                 byte_index = byte_index + 1) begin
                oracle_byte = cmodel_mem_peek8(byte_index);
                expected_data_mem[byte_index] = oracle_byte[7:0];
                expected_memory_hash = hash_mix(expected_memory_hash,
                    {24'b0, byte_index[31:0], oracle_byte[7:0]});
            end
            $display(
                "CROSS_CORE_ORACLE PASS impl=%s retired=%0d memory_ops=%0d fence=%0d regs=%016x memory=%016x retire=%016x memtrace=%016x",
                implementation_name(), expected_count, expected_mem_count,
                expected_fence_count, expected_reg_hash, expected_memory_hash,
                expected_retire_hash, expected_memtrace_hash);
        end
    endtask

    task automatic check_retire_lane(input integer lane);
        integer index;
        logic actual_commit;
        begin
            if ((norm_retire_pc[lane] == HALT_PC) &&
                (norm_retire_instr[lane] == JAL_HALT))
                return;
            index = actual_index;
            if (index >= expected_count)
                $fatal(1, "%s produced extra retirement pc=%08x instr=%08x",
                       implementation_name(), norm_retire_pc[lane],
                       norm_retire_instr[lane]);
            actual_commit = norm_commit_valid[lane] &&
                            (norm_rd_addr[lane] != 5'b0);
            if (norm_retire_pc[lane] !== expected_pc[index])
                $fatal(1, "%s retire[%0d] PC got=%08x expected=%08x",
                       implementation_name(), index, norm_retire_pc[lane],
                       expected_pc[index]);
            if (norm_retire_instr[lane] !== expected_instr[index])
                $fatal(1,
                    "%s retire[%0d] instruction got=%08x expected=%08x",
                    implementation_name(), index, norm_retire_instr[lane],
                    expected_instr[index]);
            if (actual_commit !== expected_commit[index])
                $fatal(1, "%s retire[%0d] commit mismatch",
                       implementation_name(), index);
            if (actual_commit) begin
                if (norm_rd_addr[lane] !== expected_rd[index])
                    $fatal(1, "%s retire[%0d] rd mismatch",
                           implementation_name(), index);
                if (norm_rd_data[lane] !== expected_rd_data[index])
                    $fatal(1, "%s retire[%0d] data mismatch",
                           implementation_name(), index);
            end
            actual_retire_hash = hash_retire_record(
                actual_retire_hash, norm_retire_pc[lane],
                norm_retire_instr[lane], actual_commit,
                norm_rd_addr[lane], norm_rd_data[lane]);
            if (norm_retire_instr[lane] == FENCE)
                actual_fence_count = actual_fence_count + 1;
            actual_index = actual_index + 1;
            if (actual_index == expected_count)
                trace_complete = 1'b1;
        end
    endtask

    integer lane;
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            actual_index = 0;
            actual_fence_count = 0;
            actual_retire_hash = HASH_SEED;
            trace_complete = 1'b0;
        end
        else begin
            if (norm_retire_valid[1] && !norm_retire_valid[0])
                $fatal(1, "%s lane1 retired without lane0",
                       implementation_name());
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (norm_retire_valid[lane])
                    check_retire_lane(lane);
            end
        end
    end

    integer init_index;
    integer timeout_cycles;
    integer final_index;
    logic [63:0] actual_reg_hash;
    logic [63:0] actual_memory_hash;
    initial begin
        if ((CORE_KIND < CORE_STABLE) || (CORE_KIND > CORE_OOO))
            $fatal(1, "CORE_KIND must be 0, 1, 2 or 3");
        clk = 1'b0;
        reset = 1'b1;
        for (init_index = 0; init_index < IMEM_WORDS;
             init_index = init_index + 1)
            imem[init_index] = NOP;
        for (init_index = 0; init_index < DMEM_BYTES;
             init_index = init_index + 1)
            data_mem[init_index] = 8'b0;
        $readmemh("test_bench/programs/cross_core_rv32im.mem", imem, 0, 10);

        repeat (5) @(posedge clk);
        @(negedge clk);
        build_reference_oracle();
        reset = 1'b0;

        timeout_cycles = 0;
        while (!trace_complete && (timeout_cycles < 3000)) begin
            @(negedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!trace_complete)
            $fatal(1, "%s timeout retired=%0d/%0d",
                   implementation_name(), actual_index, expected_count);
        repeat (5) @(negedge clk);
        #1;

        if (actual_mem_index != expected_mem_count)
            $fatal(1, "%s memory trace incomplete got=%0d expected=%0d",
                   implementation_name(), actual_mem_index,
                   expected_mem_count);
        if (actual_fence_count != expected_fence_count)
            $fatal(1, "%s retired %0d FENCE instructions, expected %0d",
                   implementation_name(), actual_fence_count,
                   expected_fence_count);
        if (actual_retire_hash !== expected_retire_hash)
            $fatal(1, "%s retirement hash mismatch",
                   implementation_name());
        if (actual_memtrace_hash !== expected_memtrace_hash)
            $fatal(1, "%s memory trace hash mismatch",
                   implementation_name());

        actual_reg_hash = HASH_SEED;
        for (final_index = 0; final_index < 32;
             final_index = final_index + 1) begin
            if (norm_arch_regs[final_index] !==
                expected_arch_regs[final_index])
                $fatal(1, "%s final x%0d got=%08x expected=%08x",
                       implementation_name(), final_index,
                       norm_arch_regs[final_index],
                       expected_arch_regs[final_index]);
            actual_reg_hash = hash_mix(actual_reg_hash,
                {27'b0, final_index[4:0], norm_arch_regs[final_index]});
        end
        actual_memory_hash = HASH_SEED;
        for (final_index = 0; final_index < DMEM_BYTES;
             final_index = final_index + 1) begin
            if (data_mem[final_index] !== expected_data_mem[final_index])
                $fatal(1, "%s final memory[%0d] got=%02x expected=%02x",
                       implementation_name(), final_index,
                       data_mem[final_index],
                       expected_data_mem[final_index]);
            actual_memory_hash = hash_mix(actual_memory_hash,
                {24'b0, final_index[31:0], data_mem[final_index]});
        end
        if ((actual_reg_hash !== expected_reg_hash) ||
            (actual_memory_hash !== expected_memory_hash))
            $fatal(1, "%s final state hash mismatch",
                   implementation_name());

        $display(
            "CROSS_CORE_STATE PASS impl=%s regs=32 memory_bytes=%0d retired=%0d memory_ops=%0d fence=%0d",
            implementation_name(), DMEM_BYTES, actual_index,
            actual_mem_index, actual_fence_count);
        $display(
            "CROSS_CORE_SUMMARY impl=%s regs=%016x memory=%016x retire=%016x memtrace=%016x retired=%0d memory_ops=%0d fence=%0d",
            implementation_name(), actual_reg_hash, actual_memory_hash,
            actual_retire_hash, actual_memtrace_hash, actual_index,
            actual_mem_index, actual_fence_count);
        $finish;
    end

    always #5 clk = ~clk;
endmodule
