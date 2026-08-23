`timescale 1ns/1ps

// Direct, self-checking cache verification.  This testbench intentionally
// drives the CPU-side and line-memory-side cache interfaces without a core or
// AXI adapter in between, so every cache hit, miss, refill, writeback, and
// fault is attributable to the cache controller under test.
module cache_directed_tb;

    localparam integer LINE_BYTES = 16;
    localparam integer LINE_WIDTH = LINE_BYTES * 8;
    localparam integer MAX_WAIT_CYCLES = 200;

    // Required semantic coverage.  These are explicit executable bins rather
    // than simulator-dependent covergroups, so every CI environment enforces
    // the same contract.
    localparam integer COV_IC_OFFSET_0          = 0;
    localparam integer COV_IC_OFFSET_4          = 1;
    localparam integer COV_IC_OFFSET_8          = 2;
    localparam integer COV_IC_OFFSET_12         = 3;
    localparam integer COV_IC_COLD_REFILL       = 4;
    localparam integer COV_IC_SAME_LINE_HIT     = 5;
    localparam integer COV_IC_CLEAN_REPLACE     = 6;
    localparam integer COV_IC_RESET_INVALIDATE  = 7;
    localparam integer COV_IC_REQ_BACKPRESSURE  = 8;
    localparam integer COV_IC_RESPONSE_DELAY    = 9;
    localparam integer COV_IC_SLVERR             = 10;
    localparam integer COV_IC_DECERR             = 11;

    localparam integer COV_DC_READ_HIT           = 12;
    localparam integer COV_DC_WRITE_HIT          = 13;
    localparam integer COV_DC_READ_REFILL        = 14;
    localparam integer COV_DC_WRITE_ALLOCATE     = 15;
    localparam integer COV_DC_CLEAN_REPLACE      = 16;
    localparam integer COV_DC_DIRTY_WRITEBACK    = 17;
    localparam integer COV_DC_WSTRB_0001         = 18;
    localparam integer COV_DC_WSTRB_0010         = 19;
    localparam integer COV_DC_WSTRB_0100         = 20;
    localparam integer COV_DC_WSTRB_1000         = 21;
    localparam integer COV_DC_WSTRB_0011         = 22;
    localparam integer COV_DC_WSTRB_1100         = 23;
    localparam integer COV_DC_WSTRB_1111         = 24;
    localparam integer COV_DC_CROSS_OFFSET_13    = 25;
    localparam integer COV_DC_CROSS_OFFSET_14    = 26;
    localparam integer COV_DC_CROSS_OFFSET_15    = 27;
    localparam integer COV_DC_REFILL_BACKPRESSURE = 28;
    localparam integer COV_DC_WB_BACKPRESSURE    = 29;
    localparam integer COV_DC_PARTIAL_RAW        = 30;
    localparam integer COV_DC_READ_SLVERR        = 31;
    localparam integer COV_DC_READ_DECERR        = 32;
    localparam integer COV_DC_WB_SLVERR          = 33;
    localparam integer COV_DC_WB_DECERR          = 34;
    localparam integer COV_DC_WB_RETAINS_DIRTY   = 35;
    localparam integer CACHE_REQUIRED_BINS        = 36;
    localparam [CACHE_REQUIRED_BINS-1:0] CACHE_REQUIRED_MASK =
        {CACHE_REQUIRED_BINS{1'b1}};

    reg clk;
    reg reset;

    integer check_count;
    integer error_count;
    integer ic_mem_read_count;
    integer dc_mem_read_count;
    integer dc_mem_write_count;
    integer coverage_hit_count;
    reg [CACHE_REQUIRED_BINS-1:0] coverage_hit;
    reg [CACHE_REQUIRED_BINS-1:0] coverage_missing;

    // ICache CPU interface.
    reg         ic_cpu_req_valid;
    reg  [31:0] ic_cpu_req_addr;
    wire        ic_cpu_req_ready;
    wire        ic_cpu_resp_valid;
    wire [31:0] ic_cpu_resp_data;

    // ICache line-memory interface.
    wire                  ic_mem_req_valid;
    reg                   ic_mem_req_ready;
    wire [31:0]           ic_mem_req_addr;
    reg                   ic_mem_resp_valid;
    reg  [LINE_WIDTH-1:0] ic_mem_resp_data;
    reg  [1:0]            ic_mem_resp_resp;
    wire                  ic_fault_valid;
    wire [31:0]           ic_fault_addr;
    wire [1:0]            ic_fault_resp;

    // DCache CPU interface.
    reg  [31:0] dc_cpu_req_addr;
    reg         dc_cpu_read_valid;
    wire        dc_cpu_read_ready;
    wire        dc_cpu_read_resp_valid;
    wire [31:0] dc_cpu_read_resp_data;
    reg         dc_cpu_write_valid;
    wire        dc_cpu_write_ready;
    reg  [3:0]  dc_cpu_write_strb;
    reg  [31:0] dc_cpu_write_data;
    wire        dc_cpu_write_resp_valid;

    // DCache line-memory interface.
    wire                  dc_mem_read_valid;
    reg                   dc_mem_read_ready;
    wire [31:0]           dc_mem_read_addr;
    reg                   dc_mem_read_resp_valid;
    reg  [LINE_WIDTH-1:0] dc_mem_read_resp_data;
    reg  [1:0]            dc_mem_read_resp_resp;
    wire                  dc_mem_write_valid;
    reg                   dc_mem_write_ready;
    wire [31:0]           dc_mem_write_addr;
    wire [LINE_WIDTH-1:0] dc_mem_write_data;
    reg                   dc_mem_write_resp_valid;
    reg  [1:0]            dc_mem_write_resp_resp;
    wire                  dc_fault_valid;
    wire                  dc_fault_is_write;
    wire [31:0]           dc_fault_addr;
    wire [1:0]            dc_fault_resp;

    Icache u_icache (
        .clk               (clk),
        .reset             (reset),
        .pm_req_valid_in   (ic_cpu_req_valid),
        .pm_req_addr_in    (ic_cpu_req_addr),
        .pm_req_ready_out  (ic_cpu_req_ready),
        .pm_resp_valid_out (ic_cpu_resp_valid),
        .pm_resp_data_out  (ic_cpu_resp_data),
        .ic_req_rvalid     (ic_mem_req_valid),
        .ic_req_rready     (ic_mem_req_ready),
        .ic_req_raddr      (ic_mem_req_addr),
        .ic_resp_rvalid    (ic_mem_resp_valid),
        .ic_resp_rdata     (ic_mem_resp_data),
        .ic_resp_rresp     (ic_mem_resp_resp),
        .ic_fault_valid    (ic_fault_valid),
        .ic_fault_addr     (ic_fault_addr),
        .ic_fault_resp     (ic_fault_resp)
    );

    Dcache u_dcache (
        .clk                (clk),
        .reset              (reset),
        .dm_req_addr_in     (dc_cpu_req_addr),
        .dm_req_rvalid_in   (dc_cpu_read_valid),
        .dm_req_rready_in   (dc_cpu_read_ready),
        .dm_resp_rvalid_out (dc_cpu_read_resp_valid),
        .dm_resp_rdata_out  (dc_cpu_read_resp_data),
        .dm_req_wvalid_in   (dc_cpu_write_valid),
        .dm_req_wready_out  (dc_cpu_write_ready),
        .dm_req_wstrb_in    (dc_cpu_write_strb),
        .dm_req_wdata_in    (dc_cpu_write_data),
        .dm_resp_wready_out (dc_cpu_write_resp_valid),
        .dc_req_rvalid      (dc_mem_read_valid),
        .dc_req_rready      (dc_mem_read_ready),
        .dc_req_raddr       (dc_mem_read_addr),
        .dc_resp_rvalid     (dc_mem_read_resp_valid),
        .dc_resp_rdata      (dc_mem_read_resp_data),
        .dc_resp_rresp      (dc_mem_read_resp_resp),
        .dc_req_wvalid      (dc_mem_write_valid),
        .dc_req_wready      (dc_mem_write_ready),
        .dc_req_waddr       (dc_mem_write_addr),
        .dc_req_wdata       (dc_mem_write_data),
        .dc_resp_wvalid     (dc_mem_write_resp_valid),
        .dc_resp_wresp      (dc_mem_write_resp_resp),
        .dc_fault_valid     (dc_fault_valid),
        .dc_fault_is_write  (dc_fault_is_write),
        .dc_fault_addr      (dc_fault_addr),
        .dc_fault_resp      (dc_fault_resp)
    );

    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end

    // Independent watchdog: a protocol bug must fail instead of hanging CI.
    initial begin
        repeat (10000) @(posedge clk);
        $fatal(1, "CACHE_DIRECTED_TIMEOUT: exceeded 10000 cycles");
    end

    function automatic [7:0] model_byte(input [31:0] address);
        begin
            model_byte = address[7:0] ^ address[15:8] ^
                         address[23:16] ^ 8'ha5;
        end
    endfunction

    function automatic [LINE_WIDTH-1:0] model_line(input [31:0] line_addr);
        reg [LINE_WIDTH-1:0] value;
        integer byte_index;
        begin
            value = {LINE_WIDTH{1'b0}};
            for (byte_index = 0; byte_index < LINE_BYTES;
                 byte_index = byte_index + 1) begin
                value[byte_index*8 +: 8] = model_byte(line_addr + byte_index);
            end
            model_line = value;
        end
    endfunction

    function automatic [31:0] model_word(input [31:0] address);
        reg [31:0] value;
        integer byte_index;
        begin
            value = 32'b0;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                value[byte_index*8 +: 8] = model_byte(address + byte_index);
            end
            model_word = value;
        end
    endfunction

    function automatic [31:0] line_word(
        input [LINE_WIDTH-1:0] line,
        input [3:0]            byte_offset
    );
        reg [31:0] value;
        integer byte_index;
        begin
            value = 32'b0;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                if (byte_offset + byte_index < LINE_BYTES) begin
                    value[byte_index*8 +: 8] =
                        line[(byte_offset + byte_index)*8 +: 8];
                end
            end
            line_word = value;
        end
    endfunction

    function automatic integer count_ones(
        input [CACHE_REQUIRED_BINS-1:0] value
    );
        integer bit_index;
        begin
            count_ones = 0;
            for (bit_index = 0; bit_index < CACHE_REQUIRED_BINS;
                 bit_index = bit_index + 1) begin
                if (value[bit_index]) begin
                    count_ones = count_ones + 1;
                end
            end
        end
    endfunction

    function automatic [LINE_WIDTH-1:0] patch_line_word(
        input [LINE_WIDTH-1:0] line,
        input [3:0]            byte_offset,
        input [3:0]            write_strb,
        input [31:0]           write_data
    );
        reg [LINE_WIDTH-1:0] value;
        integer byte_index;
        begin
            value = line;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                if (write_strb[byte_index] &&
                    (byte_offset + byte_index < LINE_BYTES)) begin
                    value[(byte_offset + byte_index)*8 +: 8] =
                        write_data[byte_index*8 +: 8];
                end
            end
            patch_line_word = value;
        end
    endfunction

    task automatic check_true(input reg condition, input string label);
        begin
            check_count = check_count + 1;
            if (condition !== 1'b1) begin
                error_count = error_count + 1;
                $error("CACHE_CHECK_FAIL: %s", label);
            end
        end
    endtask

    task automatic cover_true(
        input integer bin_index,
        input reg     condition,
        input string  label
    );
        begin
            check_count = check_count + 1;
            if (condition !== 1'b1) begin
                error_count = error_count + 1;
                $error("CACHE_COVERAGE_CHECK_FAIL: bin=%0d %s",
                       bin_index, label);
            end
            else begin
                coverage_hit[bin_index] = 1'b1;
            end
        end
    endtask

    task automatic check_word(
        input [31:0] actual,
        input [31:0] expected,
        input string label
    );
        begin
            check_count = check_count + 1;
            if (actual !== expected) begin
                error_count = error_count + 1;
                $error("CACHE_CHECK_FAIL: %s actual=0x%08x expected=0x%08x",
                       label, actual, expected);
            end
        end
    endtask

    task automatic check_line(
        input [LINE_WIDTH-1:0] actual,
        input [LINE_WIDTH-1:0] expected,
        input string label
    );
        begin
            check_count = check_count + 1;
            if (actual !== expected) begin
                error_count = error_count + 1;
                $error("CACHE_CHECK_FAIL: %s actual=0x%032x expected=0x%032x",
                       label, actual, expected);
            end
        end
    endtask

    task automatic apply_reset();
        begin
            @(negedge clk);
            ic_cpu_req_valid = 1'b0;
            ic_cpu_req_addr = 32'b0;
            ic_mem_req_ready = 1'b0;
            ic_mem_resp_valid = 1'b0;
            ic_mem_resp_data = {LINE_WIDTH{1'b0}};
            ic_mem_resp_resp = 2'b00;

            dc_cpu_req_addr = 32'b0;
            dc_cpu_read_valid = 1'b0;
            dc_cpu_write_valid = 1'b0;
            dc_cpu_write_strb = 4'b0;
            dc_cpu_write_data = 32'b0;
            dc_mem_read_ready = 1'b0;
            dc_mem_read_resp_valid = 1'b0;
            dc_mem_read_resp_data = {LINE_WIDTH{1'b0}};
            dc_mem_read_resp_resp = 2'b00;
            dc_mem_write_ready = 1'b0;
            dc_mem_write_resp_valid = 1'b0;
            dc_mem_write_resp_resp = 2'b00;

            reset = 1'b1;
            repeat (4) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic ic_cpu_read(
        input  [31:0] address,
        input         allow_line_request,
        output [31:0] data,
        output        fault_seen,
        output [31:0] fault_address,
        output [1:0]  fault_response
    );
        integer wait_cycles;
        reg accepted;
        reg response_seen;
        begin
            data = 32'b0;
            fault_seen = 1'b0;
            fault_address = 32'b0;
            fault_response = 2'b00;
            accepted = 1'b0;

            @(negedge clk);
            ic_cpu_req_addr = address;
            ic_cpu_req_valid = 1'b1;

            wait_cycles = 0;
            while (!accepted && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                accepted = ic_cpu_req_valid && ic_cpu_req_ready;
                wait_cycles = wait_cycles + 1;
            end
            if (!accepted) begin
                $fatal(1, "ICACHE_CPU_TIMEOUT: request 0x%08x not accepted",
                       address);
            end

            @(negedge clk);
            ic_cpu_req_valid = 1'b0;

            response_seen = 1'b0;
            wait_cycles = 0;
            while (!response_seen && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                if (!allow_line_request && ic_mem_req_valid) begin
                    $fatal(1,
                           "ICACHE_UNEXPECTED_MISS: hit address 0x%08x requested line 0x%08x",
                           address, ic_mem_req_addr);
                end
                if (ic_cpu_resp_valid) begin
                    data = ic_cpu_resp_data;
                    response_seen = 1'b1;
                    #1;
                    fault_seen = ic_fault_valid;
                    fault_address = ic_fault_addr;
                    fault_response = ic_fault_resp;
                end
                wait_cycles = wait_cycles + 1;
            end
            if (!response_seen) begin
                $fatal(1, "ICACHE_CPU_TIMEOUT: request 0x%08x has no response",
                       address);
            end
        end
    endtask

    task automatic ic_service_read(
        input [31:0] expected_line_addr,
        input [1:0]  response_code,
        input integer stall_cycles,
        input integer response_delay
    );
        integer wait_cycles;
        integer cycle_index;
        reg [31:0] held_addr;
        begin
            ic_mem_req_ready = 1'b0;
            wait_cycles = 0;
            while (!ic_mem_req_valid && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!ic_mem_req_valid) begin
                $fatal(1, "ICACHE_MEM_TIMEOUT: expected line request 0x%08x",
                       expected_line_addr);
            end

            held_addr = ic_mem_req_addr;
            check_word(held_addr, expected_line_addr,
                       "ICache line request address");
            for (cycle_index = 0; cycle_index < stall_cycles;
                 cycle_index = cycle_index + 1) begin
                @(posedge clk);
                check_true(ic_mem_req_valid,
                           "ICache request remains valid while stalled");
                check_word(ic_mem_req_addr, held_addr,
                           "ICache request address remains stable while stalled");
            end

            @(negedge clk);
            ic_mem_req_ready = 1'b1;
            @(posedge clk);
            check_true(ic_mem_req_valid && ic_mem_req_ready,
                       "ICache memory request handshake");
            ic_mem_read_count = ic_mem_read_count + 1;
            @(negedge clk);
            ic_mem_req_ready = 1'b0;

            repeat (response_delay) @(posedge clk);
            @(negedge clk);
            ic_mem_resp_data = model_line(expected_line_addr);
            ic_mem_resp_resp = response_code;
            ic_mem_resp_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ic_mem_resp_valid = 1'b0;
            ic_mem_resp_data = {LINE_WIDTH{1'b0}};
            ic_mem_resp_resp = 2'b00;
        end
    endtask

    task automatic dc_cpu_read(
        input  [31:0] address,
        input         allow_line_request,
        output [31:0] data,
        output        fault_seen,
        output        fault_write,
        output [31:0] fault_address,
        output [1:0]  fault_response
    );
        integer wait_cycles;
        reg accepted;
        reg response_seen;
        begin
            data = 32'b0;
            fault_seen = 1'b0;
            fault_write = 1'b0;
            fault_address = 32'b0;
            fault_response = 2'b00;
            accepted = 1'b0;

            @(negedge clk);
            dc_cpu_req_addr = address;
            dc_cpu_read_valid = 1'b1;
            dc_cpu_write_valid = 1'b0;

            wait_cycles = 0;
            while (!accepted && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                accepted = dc_cpu_read_valid && dc_cpu_read_ready;
                wait_cycles = wait_cycles + 1;
            end
            if (!accepted) begin
                $fatal(1, "DCACHE_CPU_TIMEOUT: read 0x%08x not accepted",
                       address);
            end

            @(negedge clk);
            dc_cpu_read_valid = 1'b0;

            response_seen = 1'b0;
            wait_cycles = 0;
            while (!response_seen && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                if (!allow_line_request &&
                    (dc_mem_read_valid || dc_mem_write_valid)) begin
                    $fatal(1,
                           "DCACHE_UNEXPECTED_MISS: hit address 0x%08x accessed line memory",
                           address);
                end
                if (dc_cpu_read_resp_valid) begin
                    data = dc_cpu_read_resp_data;
                    response_seen = 1'b1;
                    #1;
                    fault_seen = dc_fault_valid;
                    fault_write = dc_fault_is_write;
                    fault_address = dc_fault_addr;
                    fault_response = dc_fault_resp;
                end
                wait_cycles = wait_cycles + 1;
            end
            if (!response_seen) begin
                $fatal(1, "DCACHE_CPU_TIMEOUT: read 0x%08x has no response",
                       address);
            end
        end
    endtask

    task automatic dc_cpu_write(
        input [31:0] address,
        input [3:0]  write_strb,
        input [31:0] write_data,
        input        allow_line_request,
        output       fault_seen,
        output       fault_write,
        output [31:0] fault_address,
        output [1:0]  fault_response
    );
        integer wait_cycles;
        reg accepted;
        reg response_seen;
        begin
            fault_seen = 1'b0;
            fault_write = 1'b0;
            fault_address = 32'b0;
            fault_response = 2'b00;
            accepted = 1'b0;

            @(negedge clk);
            dc_cpu_req_addr = address;
            dc_cpu_write_strb = write_strb;
            dc_cpu_write_data = write_data;
            dc_cpu_read_valid = 1'b0;
            dc_cpu_write_valid = 1'b1;

            wait_cycles = 0;
            while (!accepted && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                accepted = dc_cpu_write_valid && dc_cpu_write_ready;
                wait_cycles = wait_cycles + 1;
            end
            if (!accepted) begin
                $fatal(1, "DCACHE_CPU_TIMEOUT: write 0x%08x not accepted",
                       address);
            end

            @(negedge clk);
            dc_cpu_write_valid = 1'b0;

            response_seen = 1'b0;
            wait_cycles = 0;
            while (!response_seen && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                if (!allow_line_request &&
                    (dc_mem_read_valid || dc_mem_write_valid)) begin
                    $fatal(1,
                           "DCACHE_UNEXPECTED_MISS: write hit address 0x%08x accessed line memory",
                           address);
                end
                if (dc_cpu_write_resp_valid) begin
                    response_seen = 1'b1;
                    #1;
                    fault_seen = dc_fault_valid;
                    fault_write = dc_fault_is_write;
                    fault_address = dc_fault_addr;
                    fault_response = dc_fault_resp;
                end
                wait_cycles = wait_cycles + 1;
            end
            if (!response_seen) begin
                $fatal(1, "DCACHE_CPU_TIMEOUT: write 0x%08x has no response",
                       address);
            end
        end
    endtask

    task automatic dc_service_read(
        input [31:0] expected_line_addr,
        input [1:0]  response_code,
        input integer stall_cycles,
        input integer response_delay
    );
        integer wait_cycles;
        integer cycle_index;
        reg [31:0] held_addr;
        begin
            dc_mem_read_ready = 1'b0;
            wait_cycles = 0;
            while (!dc_mem_read_valid && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!dc_mem_read_valid) begin
                $fatal(1, "DCACHE_MEM_TIMEOUT: expected read line 0x%08x",
                       expected_line_addr);
            end

            held_addr = dc_mem_read_addr;
            check_word(held_addr, expected_line_addr,
                       "DCache refill request address");
            for (cycle_index = 0; cycle_index < stall_cycles;
                 cycle_index = cycle_index + 1) begin
                @(posedge clk);
                check_true(dc_mem_read_valid,
                           "DCache refill request remains valid while stalled");
                check_word(dc_mem_read_addr, held_addr,
                           "DCache refill address remains stable while stalled");
            end

            @(negedge clk);
            dc_mem_read_ready = 1'b1;
            @(posedge clk);
            check_true(dc_mem_read_valid && dc_mem_read_ready,
                       "DCache refill request handshake");
            dc_mem_read_count = dc_mem_read_count + 1;
            @(negedge clk);
            dc_mem_read_ready = 1'b0;

            repeat (response_delay) @(posedge clk);
            @(negedge clk);
            dc_mem_read_resp_data = model_line(expected_line_addr);
            dc_mem_read_resp_resp = response_code;
            dc_mem_read_resp_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            dc_mem_read_resp_valid = 1'b0;
            dc_mem_read_resp_data = {LINE_WIDTH{1'b0}};
            dc_mem_read_resp_resp = 2'b00;
        end
    endtask

    task automatic dc_service_writeback(
        input [31:0] expected_line_addr,
        input [LINE_WIDTH-1:0] expected_line_data,
        input [1:0]  response_code,
        input integer stall_cycles,
        input integer response_delay
    );
        integer wait_cycles;
        integer cycle_index;
        reg [31:0] held_addr;
        reg [LINE_WIDTH-1:0] held_data;
        begin
            dc_mem_write_ready = 1'b0;
            wait_cycles = 0;
            while (!dc_mem_write_valid && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!dc_mem_write_valid) begin
                $fatal(1, "DCACHE_MEM_TIMEOUT: expected writeback line 0x%08x",
                       expected_line_addr);
            end

            held_addr = dc_mem_write_addr;
            held_data = dc_mem_write_data;
            check_word(held_addr, expected_line_addr,
                       "DCache writeback address");
            check_line(held_data, expected_line_data,
                       "DCache writeback data");
            for (cycle_index = 0; cycle_index < stall_cycles;
                 cycle_index = cycle_index + 1) begin
                @(posedge clk);
                check_true(dc_mem_write_valid,
                           "DCache writeback remains valid while stalled");
                check_word(dc_mem_write_addr, held_addr,
                           "DCache writeback address remains stable while stalled");
                check_line(dc_mem_write_data, held_data,
                           "DCache writeback data remains stable while stalled");
            end

            @(negedge clk);
            dc_mem_write_ready = 1'b1;
            @(posedge clk);
            check_true(dc_mem_write_valid && dc_mem_write_ready,
                       "DCache writeback request handshake");
            dc_mem_write_count = dc_mem_write_count + 1;
            @(negedge clk);
            dc_mem_write_ready = 1'b0;

            repeat (response_delay) @(posedge clk);
            @(negedge clk);
            dc_mem_write_resp_resp = response_code;
            dc_mem_write_resp_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            dc_mem_write_resp_valid = 1'b0;
            dc_mem_write_resp_resp = 2'b00;
        end
    endtask

    task automatic dc_mask_hit_case(
        input [31:0]           address,
        input [3:0]            write_strb,
        input [31:0]           write_data,
        input integer          coverage_bin,
        input string           mask_name,
        inout [LINE_WIDTH-1:0] expected_line
    );
        reg [31:0] data;
        reg [31:0] expected_word;
        reg fault_seen;
        reg fault_write;
        reg [31:0] fault_address;
        reg [1:0] fault_response;
        integer reads_before;
        integer writes_before;
        integer errors_before;
        reg scenario_ok;
        begin
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;

            dc_cpu_write(address, write_strb, write_data, 1'b0,
                         fault_seen, fault_write, fault_address,
                         fault_response);
            check_true(!fault_seen,
                       $sformatf("DCache WSTRB %s write hit has no fault",
                                 mask_name));
            expected_line = patch_line_word(expected_line, address[3:0],
                                            write_strb, write_data);
            expected_word = line_word(expected_line, address[3:0]);
            dc_cpu_read(address, 1'b0, data, fault_seen, fault_write,
                        fault_address, fault_response);
            check_word(data, expected_word,
                       $sformatf("DCache WSTRB %s immediate RAW readback",
                                 mask_name));
            check_true(!fault_seen,
                       $sformatf("DCache WSTRB %s readback has no fault",
                                 mask_name));
            check_true(dc_mem_read_count == reads_before &&
                       dc_mem_write_count == writes_before,
                       $sformatf("DCache WSTRB %s stays internal",
                                 mask_name));

            scenario_ok = (error_count == errors_before);
            cover_true(coverage_bin, scenario_ok,
                       $sformatf("DCache WSTRB %s", mask_name));
            cover_true(COV_DC_WRITE_HIT, scenario_ok,
                       "DCache CPU write hit");
            if (write_strb != 4'b1111) begin
                cover_true(COV_DC_PARTIAL_RAW, scenario_ok,
                           "DCache partial-write immediate RAW");
            end
        end
    endtask

    task automatic run_icache_tests();
        reg [31:0] data;
        reg fault_seen;
        reg [31:0] fault_address;
        reg [1:0] fault_response;
        reg scenario_ok;
        integer reads_before;
        integer errors_before;
        begin
            $display("ICACHE_DIRECTED_TEST: begin");
            apply_reset();

            // Cold miss plus request-channel backpressure and delayed memory
            // response. The memory response interface has no ready signal, so
            // latency rather than response-channel backpressure is checked.
            reads_before = ic_mem_read_count;
            errors_before = error_count;
            fork
                ic_cpu_read(32'h0000_0100, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_0100, 2'b00, 3, 2);
            join
            check_word(data, model_word(32'h0000_0100),
                       "ICache cold miss/refill data at offset 0");
            check_true(!fault_seen, "ICache successful refill has no fault");
            check_true(ic_mem_read_count == reads_before + 1,
                       "ICache cold miss issues exactly one line request");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_OFFSET_0, scenario_ok, "ICache offset 0");
            cover_true(COV_IC_COLD_REFILL, scenario_ok,
                       "ICache cold refill");
            cover_true(COV_IC_REQ_BACKPRESSURE, scenario_ok,
                       "ICache request backpressure and stable payload");
            cover_true(COV_IC_RESPONSE_DELAY, scenario_ok,
                       "ICache delayed line response");

            // All four architecturally aligned instruction offsets in the
            // resident line must hit without another line request.
            reads_before = ic_mem_read_count;
            errors_before = error_count;
            ic_cpu_read(32'h0000_0104, 1'b0, data, fault_seen,
                        fault_address, fault_response);
            check_word(data, model_word(32'h0000_0104),
                       "ICache same-line hit at offset 4");
            check_true(!fault_seen, "ICache offset 4 hit has no fault");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_OFFSET_4, scenario_ok, "ICache offset 4");
            cover_true(COV_IC_SAME_LINE_HIT, scenario_ok,
                       "ICache same-line hit");

            errors_before = error_count;
            ic_cpu_read(32'h0000_0108, 1'b0, data, fault_seen,
                        fault_address, fault_response);
            check_word(data, model_word(32'h0000_0108),
                       "ICache same-line hit at offset 8");
            check_true(!fault_seen, "ICache offset 8 hit has no fault");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_OFFSET_8, scenario_ok, "ICache offset 8");

            errors_before = error_count;
            ic_cpu_read(32'h0000_010c, 1'b0, data, fault_seen,
                        fault_address, fault_response);
            check_word(data, model_word(32'h0000_010c),
                       "ICache last aligned word at offset 12");
            check_true(!fault_seen, "ICache offset 12 hit has no fault");
            check_true(ic_mem_read_count == reads_before,
                       "ICache same-line hits issue no line request");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_OFFSET_12, scenario_ok, "ICache offset 12");

            // The first aligned word of the adjacent line must refill it.
            fork
                ic_cpu_read(32'h0000_0110, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_0110, 2'b00, 1, 1);
            join
            check_word(data, model_word(32'h0000_0110),
                       "ICache adjacent-line boundary refill data");

            // Five same-set clean lines force a fill-age replacement. A retry
            // of the first line proves that it was the clean victim.
            apply_reset();
            fork
                ic_cpu_read(32'h0000_1000, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1000, 2'b00, 0, 1);
            join
            check_word(data, model_word(32'h0000_1000),
                       "ICache fill-age line A");
            fork
                ic_cpu_read(32'h0000_1100, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1100, 2'b00, 0, 1);
            join
            fork
                ic_cpu_read(32'h0000_1200, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1200, 2'b00, 0, 1);
            join
            fork
                ic_cpu_read(32'h0000_1300, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1300, 2'b00, 0, 1);
            join
            errors_before = error_count;
            reads_before = ic_mem_read_count;
            fork
                ic_cpu_read(32'h0000_1400, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1400, 2'b00, 0, 1);
            join
            check_word(data, model_word(32'h0000_1400),
                       "ICache clean replacement line E");
            fork
                ic_cpu_read(32'h0000_1000, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_1000, 2'b00, 0, 1);
            join
            check_word(data, model_word(32'h0000_1000),
                       "ICache fill-age victim refills on retry");
            check_true(ic_mem_read_count == reads_before + 2,
                       "ICache clean replacement and victim retry refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_CLEAN_REPLACE, scenario_ok,
                       "ICache age-based clean replacement");

            // ICache has no explicit flush port; reset is its invalidation
            // mechanism. Fill a line, reset, then require a second refill.
            apply_reset();
            fork
                ic_cpu_read(32'h0000_3000, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_3000, 2'b00, 0, 1);
            join
            apply_reset();
            errors_before = error_count;
            reads_before = ic_mem_read_count;
            fork
                ic_cpu_read(32'h0000_3000, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_3000, 2'b00, 0, 1);
            join
            check_true(ic_mem_read_count == reads_before + 1,
                       "ICache reset invalidates resident line");
            check_word(data, model_word(32'h0000_3000),
                       "ICache refill after reset invalidation");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_RESET_INVALIDATE, scenario_ok,
                       "ICache reset invalidation");

            // SLVERR completes with a NOP/fault and cannot allocate the line.
            apply_reset();
            errors_before = error_count;
            fork
                ic_cpu_read(32'h0000_0204, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_0200, 2'b10, 2, 1);
            join
            check_word(data, 32'h0000_0013,
                       "ICache SLVERR returns architectural NOP");
            check_true(fault_seen, "ICache SLVERR asserts fault");
            check_word(fault_address, 32'h0000_0200,
                       "ICache SLVERR reports aligned line address");
            check_true(fault_response == 2'b10,
                       "ICache preserves SLVERR response code");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_SLVERR, scenario_ok, "ICache SLVERR");

            reads_before = ic_mem_read_count;
            fork
                ic_cpu_read(32'h0000_0204, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_0200, 2'b00, 0, 1);
            join
            check_true(ic_mem_read_count == reads_before + 1,
                       "ICache SLVERR does not allocate a line");
            check_word(data, model_word(32'h0000_0204),
                       "ICache retry after SLVERR refills successfully");

            // DECERR follows the same non-allocating diagnostic path.
            errors_before = error_count;
            fork
                ic_cpu_read(32'h0000_2408, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_2400, 2'b11, 1, 2);
            join
            check_word(data, 32'h0000_0013,
                       "ICache DECERR returns architectural NOP");
            check_true(fault_seen, "ICache DECERR asserts fault");
            check_word(fault_address, 32'h0000_2400,
                       "ICache DECERR reports aligned line address");
            check_true(fault_response == 2'b11,
                       "ICache preserves DECERR response code");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_IC_DECERR, scenario_ok, "ICache DECERR");

            reads_before = ic_mem_read_count;
            fork
                ic_cpu_read(32'h0000_2408, 1'b1, data, fault_seen,
                            fault_address, fault_response);
                ic_service_read(32'h0000_2400, 2'b00, 0, 1);
            join
            check_true(ic_mem_read_count == reads_before + 1,
                       "ICache DECERR does not allocate a line");
            check_word(data, model_word(32'h0000_2408),
                       "ICache retry after DECERR refills successfully");
            check_true(!fault_seen, "ICache successful retry has no fault");

            $display("ICACHE_DIRECTED_TEST: PASS memory_reads=%0d",
                     ic_mem_read_count);
        end
    endtask

    task automatic run_dcache_tests();
        reg [31:0] data;
        reg fault_seen;
        reg fault_write;
        reg [31:0] fault_address;
        reg [1:0] fault_response;
        reg [31:0] expected_word;
        reg [LINE_WIDTH-1:0] expected_dirty_line;
        reg [LINE_WIDTH-1:0] expected_mask_line;
        reg scenario_ok;
        integer reads_before;
        integer writes_before;
        integer errors_before;
        begin
            $display("DCACHE_DIRECTED_TEST: begin");
            apply_reset();

            // Cold read miss/refill with request backpressure, followed by a
            // same-line CPU read hit.
            reads_before = dc_mem_read_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_0100, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0100, 2'b00, 3, 2);
            join
            check_word(data, model_word(32'h0000_0100),
                       "DCache cold read miss/refill data");
            check_true(!fault_seen, "DCache successful refill has no fault");
            check_true(dc_mem_read_count == reads_before + 1,
                       "DCache cold read issues exactly one refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_READ_REFILL, scenario_ok,
                       "DCache read miss/refill");
            cover_true(COV_DC_REFILL_BACKPRESSURE, scenario_ok,
                       "DCache refill backpressure and stable address");

            reads_before = dc_mem_read_count;
            errors_before = error_count;
            dc_cpu_read(32'h0000_0104, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, model_word(32'h0000_0104),
                       "DCache read hit data");
            check_true(!fault_seen, "DCache read hit has no fault");
            check_true(dc_mem_read_count == reads_before,
                       "DCache read hit issues no refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_READ_HIT, scenario_ok, "DCache CPU read hit");

            // Make the first same-set line dirty, then fill the remaining
            // ways. The fifth line evicts the oldest filled dirty line.
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            dc_cpu_write(32'h0000_0100, 4'b0101, 32'hccbb_aa99,
                         1'b0, fault_seen, fault_write,
                         fault_address, fault_response);
            check_true(!fault_seen, "DCache write hit has no fault");
            check_true(dc_mem_read_count == reads_before &&
                       dc_mem_write_count == writes_before,
                       "DCache write hit stays internal");
            expected_word = model_word(32'h0000_0100);
            expected_word[7:0] = 8'h99;
            expected_word[23:16] = 8'hbb;
            dc_cpu_read(32'h0000_0100, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, expected_word,
                       "DCache initial partial write RAW readback");

            fork
                dc_cpu_read(32'h0000_0200, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0200, 2'b00, 0, 1);
            join
            check_word(data, model_word(32'h0000_0200),
                       "DCache same-set fill 1");
            fork
                dc_cpu_read(32'h0000_0300, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0300, 2'b00, 1, 1);
            join
            check_word(data, model_word(32'h0000_0300),
                       "DCache same-set fill 2");
            fork
                dc_cpu_read(32'h0000_0400, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0400, 2'b00, 0, 1);
            join
            check_word(data, model_word(32'h0000_0400),
                       "DCache same-set fill 3");

            expected_dirty_line = patch_line_word(
                model_line(32'h0000_0100), 4'd0, 4'b0101,
                32'hccbb_aa99);
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_0500, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                begin
                    dc_service_writeback(32'h0000_0100,
                                         expected_dirty_line,
                                         2'b00, 3, 2);
                    dc_service_read(32'h0000_0500, 2'b00, 2, 1);
                end
            join
            check_word(data, model_word(32'h0000_0500),
                       "DCache fill-age dirty replacement refill data");
            check_true(!fault_seen,
                       "DCache fill-age dirty replacement has no fault");
            check_true(dc_mem_write_count == writes_before + 1,
                       "DCache dirty replacement issues one writeback");
            check_true(dc_mem_read_count == reads_before + 1,
                       "DCache dirty replacement issues one refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_DIRTY_WRITEBACK, scenario_ok,
                       "DCache fill-age dirty writeback");
            cover_true(COV_DC_WB_BACKPRESSURE, scenario_ok,
                       "DCache writeback backpressure and stable payload");

            // Fill four clean same-set lines and require the fifth miss to
            // replace one without issuing a writeback.
            apply_reset();
            fork
                dc_cpu_read(32'h0000_2000, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_2000, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_2100, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_2100, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_2200, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_2200, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_2300, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_2300, 2'b00, 0, 1);
            join
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_2400, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_2400, 2'b00, 1, 1);
            join
            check_word(data, model_word(32'h0000_2400),
                       "DCache clean replacement data");
            check_true(dc_mem_read_count == reads_before + 1 &&
                       dc_mem_write_count == writes_before,
                       "DCache clean replacement has no writeback");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_CLEAN_REPLACE, scenario_ok,
                       "DCache clean replacement");

            // Exercise every required CPU byte-enable pattern on a resident
            // line. Every write is followed immediately by a readback.
            apply_reset();
            fork
                dc_cpu_read(32'h0000_6000, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_6000, 2'b00, 0, 1);
            join
            expected_mask_line = model_line(32'h0000_6000);
            dc_mask_hit_case(32'h0000_6000, 4'b0001, 32'h1122_3344,
                             COV_DC_WSTRB_0001, "0001",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_6004, 4'b0010, 32'h5566_7788,
                             COV_DC_WSTRB_0010, "0010",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_6008, 4'b0100, 32'h99aa_bbcc,
                             COV_DC_WSTRB_0100, "0100",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_600c, 4'b1000, 32'hddee_ff00,
                             COV_DC_WSTRB_1000, "1000",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_6000, 4'b0011, 32'h1020_3040,
                             COV_DC_WSTRB_0011, "0011",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_6004, 4'b1100, 32'h5060_7080,
                             COV_DC_WSTRB_1100, "1100",
                             expected_mask_line);
            dc_mask_hit_case(32'h0000_6008, 4'b1111, 32'h90a0_b0c0,
                             COV_DC_WSTRB_1111, "1111",
                             expected_mask_line);

            // Cold offset-13 cross-line read refills both lines. Offsets 14
            // and 15 then reuse both resident lines, covering every crossing
            // offset and the little-endian merge positions.
            apply_reset();
            reads_before = dc_mem_read_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_080d, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                begin
                    dc_service_read(32'h0000_0800, 2'b00, 1, 1);
                    dc_service_read(32'h0000_0810, 2'b00, 2, 1);
                end
            join
            check_word(data, model_word(32'h0000_080d),
                       "DCache cross-line offset 13 merge");
            check_true(!fault_seen &&
                       dc_mem_read_count == reads_before + 2,
                       "DCache offset 13 refills both lines");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_CROSS_OFFSET_13, scenario_ok,
                       "DCache cross-line read offset 13");

            reads_before = dc_mem_read_count;
            errors_before = error_count;
            dc_cpu_read(32'h0000_080e, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, model_word(32'h0000_080e),
                       "DCache cross-line offset 14 merge");
            check_true(!fault_seen && dc_mem_read_count == reads_before,
                       "DCache offset 14 hits both lines");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_CROSS_OFFSET_14, scenario_ok,
                       "DCache cross-line read offset 14");

            errors_before = error_count;
            dc_cpu_read(32'h0000_080f, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, model_word(32'h0000_080f),
                       "DCache cross-line offset 15 merge");
            check_true(!fault_seen && dc_mem_read_count == reads_before,
                       "DCache offset 15 hits both lines");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_CROSS_OFFSET_15, scenario_ok,
                       "DCache cross-line read offset 15");

            // Read SLVERR: zero completion, sideband metadata, and no line
            // allocation, proven by a successful retry refill.
            apply_reset();
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_0904, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0900, 2'b10, 2, 1);
            join
            check_word(data, 32'b0, "DCache read SLVERR returns zero data");
            check_true(fault_seen && !fault_write,
                       "DCache read SLVERR reports read fault");
            check_word(fault_address, 32'h0000_0900,
                       "DCache read SLVERR fault address");
            check_true(fault_response == 2'b10,
                       "DCache read SLVERR response code");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_READ_SLVERR, scenario_ok,
                       "DCache read SLVERR");
            reads_before = dc_mem_read_count;
            fork
                dc_cpu_read(32'h0000_0904, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0900, 2'b00, 0, 1);
            join
            check_true(dc_mem_read_count == reads_before + 1,
                       "DCache read SLVERR does not allocate a line");
            check_word(data, model_word(32'h0000_0904),
                       "DCache read retry after SLVERR");

            // Read DECERR follows the same non-allocating fault path.
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_0944, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0940, 2'b11, 1, 2);
            join
            check_word(data, 32'b0, "DCache read DECERR returns zero data");
            check_true(fault_seen && !fault_write,
                       "DCache read DECERR reports read fault");
            check_word(fault_address, 32'h0000_0940,
                       "DCache read DECERR fault address");
            check_true(fault_response == 2'b11,
                       "DCache read DECERR response code");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_READ_DECERR, scenario_ok,
                       "DCache read DECERR");
            reads_before = dc_mem_read_count;
            fork
                dc_cpu_read(32'h0000_0944, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0940, 2'b00, 0, 1);
            join
            check_true(dc_mem_read_count == reads_before + 1,
                       "DCache read DECERR does not allocate a line");
            check_word(data, model_word(32'h0000_0944),
                       "DCache read retry after DECERR");

            // Build the oldest line through write allocate, then reject its
            // eviction with SLVERR. The failed dirty line must remain present.
            apply_reset();
            reads_before = dc_mem_read_count;
            errors_before = error_count;
            fork
                dc_cpu_write(32'h0000_0a00, 4'b1111, 32'h1234_5678,
                             1'b1, fault_seen, fault_write,
                             fault_address, fault_response);
                dc_service_read(32'h0000_0a00, 2'b00, 0, 1);
            join
            check_true(!fault_seen &&
                       dc_mem_read_count == reads_before + 1,
                       "DCache write-allocate miss completes after refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_WRITE_ALLOCATE, scenario_ok,
                       "DCache write allocate");
            fork
                dc_cpu_read(32'h0000_0b00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0b00, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_0c00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0c00, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_0d00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_0d00, 2'b00, 0, 1);
            join

            expected_dirty_line = patch_line_word(
                model_line(32'h0000_0a00), 4'd0, 4'b1111,
                32'h1234_5678);
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_0e00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_writeback(32'h0000_0a00,
                                     expected_dirty_line,
                                     2'b10, 2, 1);
            join
            check_word(data, 32'b0,
                       "DCache writeback SLVERR returns zero read data");
            check_true(fault_seen && fault_write,
                       "DCache writeback SLVERR reports write fault");
            check_word(fault_address, 32'h0000_0a00,
                       "DCache writeback SLVERR fault address");
            check_true(fault_response == 2'b10,
                       "DCache writeback SLVERR response code");
            check_true(dc_mem_write_count == writes_before + 1,
                       "DCache failing SLVERR writeback handshakes once");
            check_true(dc_mem_read_count == reads_before,
                       "DCache SLVERR writeback suppresses replacement refill");
            check_true(!dc_mem_read_valid,
                       "DCache SLVERR writeback returns controller to idle");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_WB_SLVERR, scenario_ok,
                       "DCache writeback SLVERR");

            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;
            dc_cpu_read(32'h0000_0a00, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, 32'h1234_5678,
                       "DCache failed writeback retains dirty line data");
            check_true(!fault_seen &&
                       dc_mem_read_count == reads_before &&
                       dc_mem_write_count == writes_before,
                       "DCache failed writeback line remains an internal hit");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_WB_RETAINS_DIRTY, scenario_ok,
                       "DCache failed writeback retains original dirty line");

            // Repeat the dirty fill-age failure with DECERR.
            apply_reset();
            fork
                dc_cpu_write(32'h0000_1a00, 4'b1111, 32'h89ab_cdef,
                             1'b1, fault_seen, fault_write,
                             fault_address, fault_response);
                dc_service_read(32'h0000_1a00, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_1b00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_1b00, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_1c00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_1c00, 2'b00, 0, 1);
            join
            fork
                dc_cpu_read(32'h0000_1d00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_read(32'h0000_1d00, 2'b00, 0, 1);
            join
            expected_dirty_line = patch_line_word(
                model_line(32'h0000_1a00), 4'd0, 4'b1111,
                32'h89ab_cdef);
            reads_before = dc_mem_read_count;
            writes_before = dc_mem_write_count;
            errors_before = error_count;
            fork
                dc_cpu_read(32'h0000_1e00, 1'b1, data, fault_seen,
                            fault_write, fault_address, fault_response);
                dc_service_writeback(32'h0000_1a00,
                                     expected_dirty_line,
                                     2'b11, 1, 2);
            join
            check_word(data, 32'b0,
                       "DCache writeback DECERR returns zero read data");
            check_true(fault_seen && fault_write,
                       "DCache writeback DECERR reports write fault");
            check_word(fault_address, 32'h0000_1a00,
                       "DCache writeback DECERR fault address");
            check_true(fault_response == 2'b11,
                       "DCache writeback DECERR response code");
            check_true(dc_mem_write_count == writes_before + 1,
                       "DCache failing DECERR writeback handshakes once");
            check_true(dc_mem_read_count == reads_before,
                       "DCache DECERR writeback suppresses replacement refill");
            scenario_ok = (error_count == errors_before);
            cover_true(COV_DC_WB_DECERR, scenario_ok,
                       "DCache writeback DECERR");

            // The DECERR victim is retained too; this check is deliberately
            // redundant with the SLVERR retention bin to close both paths.
            dc_cpu_read(32'h0000_1a00, 1'b0, data, fault_seen,
                        fault_write, fault_address, fault_response);
            check_word(data, 32'h89ab_cdef,
                       "DCache DECERR writeback retains dirty line data");
            check_true(!fault_seen,
                       "DCache DECERR retained-line hit has no fault");

            $display("DCACHE_DIRECTED_TEST: PASS memory_reads=%0d writebacks=%0d",
                     dc_mem_read_count, dc_mem_write_count);
        end
    endtask

    initial begin
        reset = 1'b1;
        check_count = 0;
        error_count = 0;
        ic_mem_read_count = 0;
        dc_mem_read_count = 0;
        dc_mem_write_count = 0;
        coverage_hit_count = 0;
        coverage_hit = {CACHE_REQUIRED_BINS{1'b0}};
        coverage_missing = CACHE_REQUIRED_MASK;

        ic_cpu_req_valid = 1'b0;
        ic_cpu_req_addr = 32'b0;
        ic_mem_req_ready = 1'b0;
        ic_mem_resp_valid = 1'b0;
        ic_mem_resp_data = {LINE_WIDTH{1'b0}};
        ic_mem_resp_resp = 2'b00;

        dc_cpu_req_addr = 32'b0;
        dc_cpu_read_valid = 1'b0;
        dc_cpu_write_valid = 1'b0;
        dc_cpu_write_strb = 4'b0;
        dc_cpu_write_data = 32'b0;
        dc_mem_read_ready = 1'b0;
        dc_mem_read_resp_valid = 1'b0;
        dc_mem_read_resp_data = {LINE_WIDTH{1'b0}};
        dc_mem_read_resp_resp = 2'b00;
        dc_mem_write_ready = 1'b0;
        dc_mem_write_resp_valid = 1'b0;
        dc_mem_write_resp_resp = 2'b00;

        run_icache_tests();
        run_dcache_tests();

        if (error_count != 0) begin
            $fatal(1,
                   "CACHE_DIRECTED_ACCEPTANCE status=FAIL checks=%0d errors=%0d",
                   check_count, error_count);
        end
        coverage_hit_count = count_ones(coverage_hit);
        coverage_missing = CACHE_REQUIRED_MASK & ~coverage_hit;
        if (coverage_missing != {CACHE_REQUIRED_BINS{1'b0}}) begin
            $fatal(1,
                   "CACHE_COVERAGE status=FAIL required=%0d hit=%0d missing=0x%09x",
                   CACHE_REQUIRED_BINS, coverage_hit_count,
                   coverage_missing);
        end
        $display("CACHE_COVERAGE status=PASS required=%0d hit=%0d missing=0",
                 CACHE_REQUIRED_BINS, coverage_hit_count);
        $display("CACHE_DIRECTED_ACCEPTANCE status=PASS checks=%0d ic_reads=%0d dc_reads=%0d dc_writebacks=%0d",
                 check_count, ic_mem_read_count, dc_mem_read_count,
                 dc_mem_write_count);
        $finish;
    end

endmodule
