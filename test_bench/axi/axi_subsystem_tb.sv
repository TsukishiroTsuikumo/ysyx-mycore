`timescale 1ns/1ps
`include "axi_defs.vh"

module axi_subsystem_tb;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 2;
    localparam int LINE_BYTES = 16;
    localparam int LINE_WIDTH = LINE_BYTES * 8;
    localparam logic [31:0] RANDOM_TAG = 32'h6000_0000;

    logic clk;
    logic reset;

    initial clk = 1'b0;
    always #1 clk = ~clk;

    initial begin : watchdog
        repeat (50000) @(posedge clk);
        $fatal(1, "AXI subsystem test timed out");
    end

    function automatic logic [LINE_WIDTH-1:0] pack_line(
        input logic [31:0] word0,
        input logic [31:0] word1,
        input logic [31:0] word2,
        input logic [31:0] word3
    );
        pack_line = {word3, word2, word1, word0};
    endfunction

    function automatic logic [LINE_WIDTH-1:0] tagged_line(
        input logic [31:0] address
    );
        integer beat;
        begin
            tagged_line = '0;
            for (beat = 0; beat < 4; beat = beat + 1) begin
                tagged_line[beat*32 +: 32] =
                    RANDOM_TAG + (address >> 2) + beat;
            end
        end
    endfunction

    // ---------------------------------------------------------------------
    // Complete cache-line/decoder/RAM subsystem instance.
    // ---------------------------------------------------------------------
    logic                  sys_ic_req_valid;
    wire                   sys_ic_req_ready;
    logic [31:0]           sys_ic_req_addr;
    wire                   sys_ic_resp_valid;
    wire [LINE_WIDTH-1:0]  sys_ic_resp_data;
    wire [1:0]             sys_ic_resp_resp;

    logic                  sys_dc_rreq_valid;
    wire                   sys_dc_rreq_ready;
    logic [31:0]           sys_dc_rreq_addr;
    wire                   sys_dc_rresp_valid;
    wire [LINE_WIDTH-1:0]  sys_dc_rresp_data;
    wire [1:0]             sys_dc_rresp_resp;

    logic                  sys_dc_wreq_valid;
    wire                   sys_dc_wreq_ready;
    logic [31:0]           sys_dc_wreq_addr;
    logic [LINE_WIDTH-1:0] sys_dc_wreq_data;
    wire                   sys_dc_wresp_valid;
    wire [1:0]             sys_dc_wresp_resp;

    cache_axi_memory_system #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .MEM_WIDTH  (12),
        .MEM_BYTES  (4096),
        .RAM_BASE   (32'h8000_0000),
        .RAM_MASK   (32'hffff_f000),
        .MMIO_BASE  (32'h1000_0000),
        .MMIO_MASK  (32'hffff_f000)
    ) u_subsystem (
        .clk            (clk),
        .reset          (reset),
        .ic_req_rvalid  (sys_ic_req_valid),
        .ic_req_rready  (sys_ic_req_ready),
        .ic_req_raddr   (sys_ic_req_addr),
        .ic_resp_rvalid (sys_ic_resp_valid),
        .ic_resp_rdata  (sys_ic_resp_data),
        .ic_resp_rresp  (sys_ic_resp_resp),
        .dc_req_rvalid  (sys_dc_rreq_valid),
        .dc_req_rready  (sys_dc_rreq_ready),
        .dc_req_raddr   (sys_dc_rreq_addr),
        .dc_resp_rvalid (sys_dc_rresp_valid),
        .dc_resp_rdata  (sys_dc_rresp_data),
        .dc_resp_rresp  (sys_dc_rresp_resp),
        .dc_req_wvalid  (sys_dc_wreq_valid),
        .dc_req_wready  (sys_dc_wreq_ready),
        .dc_req_waddr   (sys_dc_wreq_addr),
        .dc_req_wdata   (sys_dc_wreq_data),
        .dc_resp_wvalid (sys_dc_wresp_valid),
        .dc_resp_wresp  (sys_dc_wresp_resp)
    );

    integer sys_ram_read_beats;
    integer sys_ram_write_beats;
    integer sys_ram_read_beat_in_burst;
    integer sys_ram_write_beat_in_burst;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sys_ram_read_beats          <= 0;
            sys_ram_write_beats         <= 0;
            sys_ram_read_beat_in_burst  <= 0;
            sys_ram_write_beat_in_burst <= 0;
        end
        else begin
            if (u_subsystem.ram_axi_rvalid &&
                u_subsystem.ram_axi_rready) begin
                if (u_subsystem.ram_axi_rlast !==
                    (sys_ram_read_beat_in_burst == 3)) begin
                    $fatal(1, "RAM RLAST mismatch at beat %0d",
                           sys_ram_read_beat_in_burst);
                end
                sys_ram_read_beats <= sys_ram_read_beats + 1;
                if (u_subsystem.ram_axi_rlast) begin
                    sys_ram_read_beat_in_burst <= 0;
                end
                else begin
                    sys_ram_read_beat_in_burst <=
                        sys_ram_read_beat_in_burst + 1;
                end
            end
            if (u_subsystem.ram_axi_wvalid &&
                u_subsystem.ram_axi_wready) begin
                if (u_subsystem.ram_axi_wlast !==
                    (sys_ram_write_beat_in_burst == 3)) begin
                    $fatal(1, "RAM WLAST mismatch at beat %0d",
                           sys_ram_write_beat_in_burst);
                end
                sys_ram_write_beats <= sys_ram_write_beats + 1;
                if (u_subsystem.ram_axi_wlast) begin
                    sys_ram_write_beat_in_burst <= 0;
                end
                else begin
                    sys_ram_write_beat_in_burst <=
                        sys_ram_write_beat_in_burst + 1;
                end
            end
        end
    end

    task automatic apply_reset;
        begin
            @(negedge clk);
            reset = 1'b1;
            repeat (4) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic preload_system_line(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] data
    );
        begin
            u_subsystem.write_word(address + 32'd0, data[31:0]);
            u_subsystem.write_word(address + 32'd4, data[63:32]);
            u_subsystem.write_word(address + 32'd8, data[95:64]);
            u_subsystem.write_word(address + 32'd12, data[127:96]);
        end
    endtask

    task automatic system_icache_read(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] expected_data,
        input logic [1:0] expected_resp,
        input integer expected_ram_beats
    );
        integer start_beats;
        begin
            start_beats = sys_ram_read_beats;
            @(negedge clk);
            sys_ic_req_addr  = address;
            sys_ic_req_valid = 1'b1;
            while (!(sys_ic_req_valid && sys_ic_req_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            sys_ic_req_valid = 1'b0;
            while (!sys_ic_resp_valid) begin
                @(negedge clk);
            end
            if (sys_ic_resp_resp !== expected_resp) begin
                $fatal(1, "ICache response mismatch at %08x: expected %0d got %0d",
                       address, expected_resp, sys_ic_resp_resp);
            end
            if (sys_ic_resp_data !== expected_data) begin
                $fatal(1, "ICache data mismatch at %08x: expected %032x got %032x",
                       address, expected_data, sys_ic_resp_data);
            end
            if ((sys_ram_read_beats - start_beats) != expected_ram_beats) begin
                $fatal(1, "ICache RAM beat count at %08x: expected %0d got %0d",
                       address, expected_ram_beats,
                       sys_ram_read_beats - start_beats);
            end
            @(negedge clk);
        end
    endtask

    task automatic system_dcache_read(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] expected_data,
        input logic [1:0] expected_resp,
        input integer expected_ram_beats
    );
        integer start_beats;
        begin
            start_beats = sys_ram_read_beats;
            @(negedge clk);
            sys_dc_rreq_addr  = address;
            sys_dc_rreq_valid = 1'b1;
            while (!(sys_dc_rreq_valid && sys_dc_rreq_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            sys_dc_rreq_valid = 1'b0;
            while (!sys_dc_rresp_valid) begin
                @(negedge clk);
            end
            if (sys_dc_rresp_resp !== expected_resp) begin
                $fatal(1, "DCache read response mismatch at %08x: expected %0d got %0d",
                       address, expected_resp, sys_dc_rresp_resp);
            end
            if (sys_dc_rresp_data !== expected_data) begin
                $fatal(1, "DCache read data mismatch at %08x: expected %032x got %032x",
                       address, expected_data, sys_dc_rresp_data);
            end
            if ((sys_ram_read_beats - start_beats) != expected_ram_beats) begin
                $fatal(1, "DCache RAM read beats at %08x: expected %0d got %0d",
                       address, expected_ram_beats,
                       sys_ram_read_beats - start_beats);
            end
            @(negedge clk);
        end
    endtask

    task automatic system_dcache_write(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] data,
        input logic [1:0] expected_resp,
        input integer expected_ram_beats
    );
        integer start_beats;
        begin
            start_beats = sys_ram_write_beats;
            @(negedge clk);
            sys_dc_wreq_addr  = address;
            sys_dc_wreq_data  = data;
            sys_dc_wreq_valid = 1'b1;
            while (!(sys_dc_wreq_valid && sys_dc_wreq_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            sys_dc_wreq_valid = 1'b0;
            while (!sys_dc_wresp_valid) begin
                @(negedge clk);
            end
            if (sys_dc_wresp_resp !== expected_resp) begin
                $fatal(1, "DCache write response mismatch at %08x: expected %0d got %0d",
                       address, expected_resp, sys_dc_wresp_resp);
            end
            if ((sys_ram_write_beats - start_beats) != expected_ram_beats) begin
                $fatal(1, "DCache RAM write beats at %08x: expected %0d got %0d",
                       address, expected_ram_beats,
                       sys_ram_write_beats - start_beats);
            end
            @(negedge clk);
        end
    endtask

    task automatic system_simultaneous_reads(
        input logic [31:0] ic_address,
        input logic [LINE_WIDTH-1:0] ic_expected,
        input logic [31:0] dc_address,
        input logic [LINE_WIDTH-1:0] dc_expected
    );
        integer start_beats;
        integer response_order;
        bit ic_seen;
        bit dc_seen;
        begin
            start_beats = sys_ram_read_beats;
            response_order = 0;
            ic_seen = 1'b0;
            dc_seen = 1'b0;
            @(negedge clk);
            sys_ic_req_addr   = ic_address;
            sys_dc_rreq_addr  = dc_address;
            sys_ic_req_valid  = 1'b1;
            sys_dc_rreq_valid = 1'b1;
            @(posedge clk);
            if (!sys_ic_req_ready || !sys_dc_rreq_ready) begin
                $fatal(1, "simultaneous cache-line requests were not accepted");
            end
            @(negedge clk);
            sys_ic_req_valid  = 1'b0;
            sys_dc_rreq_valid = 1'b0;

            while (!ic_seen || !dc_seen) begin
                @(negedge clk);
                if (sys_ic_resp_valid) begin
                    if (ic_seen) begin
                        $fatal(1, "duplicate ICache line response");
                    end
                    if ((sys_ic_resp_resp != `AXI_RESP_OKAY) ||
                        (sys_ic_resp_data !== ic_expected)) begin
                        $fatal(1, "simultaneous ICache response mismatch");
                    end
                    if (response_order != 0) begin
                        $fatal(1, "read arbiter did not grant source 0 first after reset");
                    end
                    response_order = response_order + 1;
                    ic_seen = 1'b1;
                end
                if (sys_dc_rresp_valid) begin
                    if (dc_seen) begin
                        $fatal(1, "duplicate DCache line response");
                    end
                    if ((sys_dc_rresp_resp != `AXI_RESP_OKAY) ||
                        (sys_dc_rresp_data !== dc_expected)) begin
                        $fatal(1, "simultaneous DCache response mismatch");
                    end
                    response_order = response_order + 1;
                    dc_seen = 1'b1;
                end
            end
            if ((sys_ram_read_beats - start_beats) != 8) begin
                $fatal(1, "simultaneous reads expected 8 RAM beats, got %0d",
                       sys_ram_read_beats - start_beats);
            end
            @(negedge clk);
        end
    endtask

    // ---------------------------------------------------------------------
    // Direct adapter/arbiter path.  A mux selects one target at a time so all
    // three blocks see the same seeded, randomized AXI slave implementation.
    // ---------------------------------------------------------------------
    localparam logic [1:0] TARGET_IC  = 2'd0;
    localparam logic [1:0] TARGET_DC  = 2'd1;
    localparam logic [1:0] TARGET_ARB = 2'd2;
    logic [1:0] random_target;

    logic                 direct_ic_req_valid;
    wire                  direct_ic_req_ready;
    logic [31:0]          direct_ic_req_addr;
    wire                  direct_ic_resp_valid;
    wire [LINE_WIDTH-1:0] direct_ic_resp_data;
    wire [1:0]            direct_ic_resp_resp;
    wire [1:0]            ic_arid;
    wire [31:0]           ic_araddr;
    wire [7:0]            ic_arlen;
    wire [2:0]            ic_arsize;
    wire [1:0]            ic_arburst;
    wire                  ic_arlock;
    wire [3:0]            ic_arcache;
    wire [2:0]            ic_arprot;
    wire [3:0]            ic_arqos;
    wire                  ic_arvalid;
    wire                  ic_arready;
    wire [1:0]            ic_rid;
    wire [31:0]           ic_rdata;
    wire [1:0]            ic_rresp;
    wire                  ic_rlast;
    wire                  ic_rvalid;
    wire                  ic_rready;

    icache_axi_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .AXI_ID     (2'd0)
    ) u_direct_icache (
        .clk             (clk),
        .reset           (reset),
        .line_req_valid  (direct_ic_req_valid),
        .line_req_ready  (direct_ic_req_ready),
        .line_req_addr   (direct_ic_req_addr),
        .line_resp_valid (direct_ic_resp_valid),
        .line_resp_data  (direct_ic_resp_data),
        .line_resp_resp  (direct_ic_resp_resp),
        .m_axi_arid      (ic_arid),
        .m_axi_araddr    (ic_araddr),
        .m_axi_arlen     (ic_arlen),
        .m_axi_arsize    (ic_arsize),
        .m_axi_arburst   (ic_arburst),
        .m_axi_arlock    (ic_arlock),
        .m_axi_arcache   (ic_arcache),
        .m_axi_arprot    (ic_arprot),
        .m_axi_arqos     (ic_arqos),
        .m_axi_arvalid   (ic_arvalid),
        .m_axi_arready   (ic_arready),
        .m_axi_rid       (ic_rid),
        .m_axi_rdata     (ic_rdata),
        .m_axi_rresp     (ic_rresp),
        .m_axi_rlast     (ic_rlast),
        .m_axi_rvalid    (ic_rvalid),
        .m_axi_rready    (ic_rready)
    );

    logic                 direct_dc_rreq_valid;
    wire                  direct_dc_rreq_ready;
    logic [31:0]          direct_dc_rreq_addr;
    wire                  direct_dc_rresp_valid;
    wire [LINE_WIDTH-1:0] direct_dc_rresp_data;
    wire [1:0]            direct_dc_rresp_resp;
    logic                 direct_dc_wreq_valid;
    wire                  direct_dc_wreq_ready;
    logic [31:0]          direct_dc_wreq_addr;
    logic [LINE_WIDTH-1:0] direct_dc_wreq_data;
    wire                  direct_dc_wresp_valid;
    wire [1:0]            direct_dc_wresp_resp;

    wire [1:0]  dc_awid;
    wire [31:0] dc_awaddr;
    wire [7:0]  dc_awlen;
    wire [2:0]  dc_awsize;
    wire [1:0]  dc_awburst;
    wire        dc_awlock;
    wire [3:0]  dc_awcache;
    wire [2:0]  dc_awprot;
    wire [3:0]  dc_awqos;
    wire        dc_awvalid;
    wire        dc_awready;
    wire [31:0] dc_wdata;
    wire [3:0]  dc_wstrb;
    wire        dc_wlast;
    wire        dc_wvalid;
    wire        dc_wready;
    wire [1:0]  dc_bid;
    wire [1:0]  dc_bresp;
    wire        dc_bvalid;
    wire        dc_bready;
    wire [1:0]  dc_arid;
    wire [31:0] dc_araddr;
    wire [7:0]  dc_arlen;
    wire [2:0]  dc_arsize;
    wire [1:0]  dc_arburst;
    wire        dc_arlock;
    wire [3:0]  dc_arcache;
    wire [2:0]  dc_arprot;
    wire [3:0]  dc_arqos;
    wire        dc_arvalid;
    wire        dc_arready;
    wire [1:0]  dc_rid;
    wire [31:0] dc_rdata;
    wire [1:0]  dc_rresp;
    wire        dc_rlast;
    wire        dc_rvalid;
    wire        dc_rready;

    dcache_axi_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LINE_BYTES (LINE_BYTES),
        .AXI_ID     (2'd1)
    ) u_direct_dcache (
        .clk              (clk),
        .reset            (reset),
        .line_rreq_valid  (direct_dc_rreq_valid),
        .line_rreq_ready  (direct_dc_rreq_ready),
        .line_rreq_addr   (direct_dc_rreq_addr),
        .line_rresp_valid (direct_dc_rresp_valid),
        .line_rresp_data  (direct_dc_rresp_data),
        .line_rresp_resp  (direct_dc_rresp_resp),
        .line_wreq_valid  (direct_dc_wreq_valid),
        .line_wreq_ready  (direct_dc_wreq_ready),
        .line_wreq_addr   (direct_dc_wreq_addr),
        .line_wreq_data   (direct_dc_wreq_data),
        .line_wresp_valid (direct_dc_wresp_valid),
        .line_wresp_resp  (direct_dc_wresp_resp),
        .m_axi_awid       (dc_awid),
        .m_axi_awaddr     (dc_awaddr),
        .m_axi_awlen      (dc_awlen),
        .m_axi_awsize     (dc_awsize),
        .m_axi_awburst    (dc_awburst),
        .m_axi_awlock     (dc_awlock),
        .m_axi_awcache    (dc_awcache),
        .m_axi_awprot     (dc_awprot),
        .m_axi_awqos      (dc_awqos),
        .m_axi_awvalid    (dc_awvalid),
        .m_axi_awready    (dc_awready),
        .m_axi_wdata      (dc_wdata),
        .m_axi_wstrb      (dc_wstrb),
        .m_axi_wlast      (dc_wlast),
        .m_axi_wvalid     (dc_wvalid),
        .m_axi_wready     (dc_wready),
        .m_axi_bid        (dc_bid),
        .m_axi_bresp      (dc_bresp),
        .m_axi_bvalid     (dc_bvalid),
        .m_axi_bready     (dc_bready),
        .m_axi_arid       (dc_arid),
        .m_axi_araddr     (dc_araddr),
        .m_axi_arlen      (dc_arlen),
        .m_axi_arsize     (dc_arsize),
        .m_axi_arburst    (dc_arburst),
        .m_axi_arlock     (dc_arlock),
        .m_axi_arcache    (dc_arcache),
        .m_axi_arprot     (dc_arprot),
        .m_axi_arqos      (dc_arqos),
        .m_axi_arvalid    (dc_arvalid),
        .m_axi_arready    (dc_arready),
        .m_axi_rid        (dc_rid),
        .m_axi_rdata      (dc_rdata),
        .m_axi_rresp      (dc_rresp),
        .m_axi_rlast      (dc_rlast),
        .m_axi_rvalid     (dc_rvalid),
        .m_axi_rready     (dc_rready)
    );

    logic [1:0]  arb_s0_arid;
    logic [31:0] arb_s0_araddr;
    logic [7:0]  arb_s0_arlen;
    logic [2:0]  arb_s0_arsize;
    logic [1:0]  arb_s0_arburst;
    logic        arb_s0_arlock;
    logic [3:0]  arb_s0_arcache;
    logic [2:0]  arb_s0_arprot;
    logic [3:0]  arb_s0_arqos;
    logic        arb_s0_arvalid;
    wire         arb_s0_arready;
    wire [1:0]   arb_s0_rid;
    wire [31:0]  arb_s0_rdata;
    wire [1:0]   arb_s0_rresp;
    wire         arb_s0_rlast;
    wire         arb_s0_rvalid;
    logic        arb_s0_rready;

    logic [1:0]  arb_s1_arid;
    logic [31:0] arb_s1_araddr;
    logic [7:0]  arb_s1_arlen;
    logic [2:0]  arb_s1_arsize;
    logic [1:0]  arb_s1_arburst;
    logic        arb_s1_arlock;
    logic [3:0]  arb_s1_arcache;
    logic [2:0]  arb_s1_arprot;
    logic [3:0]  arb_s1_arqos;
    logic        arb_s1_arvalid;
    wire         arb_s1_arready;
    wire [1:0]   arb_s1_rid;
    wire [31:0]  arb_s1_rdata;
    wire [1:0]   arb_s1_rresp;
    wire         arb_s1_rlast;
    wire         arb_s1_rvalid;
    logic        arb_s1_rready;

    wire [1:0]   arb_arid;
    wire [31:0]  arb_araddr;
    wire [7:0]   arb_arlen;
    wire [2:0]   arb_arsize;
    wire [1:0]   arb_arburst;
    wire         arb_arlock;
    wire [3:0]   arb_arcache;
    wire [2:0]   arb_arprot;
    wire [3:0]   arb_arqos;
    wire         arb_arvalid;
    wire         arb_arready;
    wire [1:0]   arb_rid;
    wire [31:0]  arb_rdata;
    wire [1:0]   arb_rresp;
    wire         arb_rlast;
    wire         arb_rvalid;
    wire         arb_rready;

    axi_read_arbiter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_direct_arbiter (
        .clk            (clk),
        .reset          (reset),
        .s0_axi_arid    (arb_s0_arid),
        .s0_axi_araddr  (arb_s0_araddr),
        .s0_axi_arlen   (arb_s0_arlen),
        .s0_axi_arsize  (arb_s0_arsize),
        .s0_axi_arburst (arb_s0_arburst),
        .s0_axi_arlock  (arb_s0_arlock),
        .s0_axi_arcache (arb_s0_arcache),
        .s0_axi_arprot  (arb_s0_arprot),
        .s0_axi_arqos   (arb_s0_arqos),
        .s0_axi_arvalid (arb_s0_arvalid),
        .s0_axi_arready (arb_s0_arready),
        .s0_axi_rid     (arb_s0_rid),
        .s0_axi_rdata   (arb_s0_rdata),
        .s0_axi_rresp   (arb_s0_rresp),
        .s0_axi_rlast   (arb_s0_rlast),
        .s0_axi_rvalid  (arb_s0_rvalid),
        .s0_axi_rready  (arb_s0_rready),
        .s1_axi_arid    (arb_s1_arid),
        .s1_axi_araddr  (arb_s1_araddr),
        .s1_axi_arlen   (arb_s1_arlen),
        .s1_axi_arsize  (arb_s1_arsize),
        .s1_axi_arburst (arb_s1_arburst),
        .s1_axi_arlock  (arb_s1_arlock),
        .s1_axi_arcache (arb_s1_arcache),
        .s1_axi_arprot  (arb_s1_arprot),
        .s1_axi_arqos   (arb_s1_arqos),
        .s1_axi_arvalid (arb_s1_arvalid),
        .s1_axi_arready (arb_s1_arready),
        .s1_axi_rid     (arb_s1_rid),
        .s1_axi_rdata   (arb_s1_rdata),
        .s1_axi_rresp   (arb_s1_rresp),
        .s1_axi_rlast   (arb_s1_rlast),
        .s1_axi_rvalid  (arb_s1_rvalid),
        .s1_axi_rready  (arb_s1_rready),
        .m_axi_arid     (arb_arid),
        .m_axi_araddr   (arb_araddr),
        .m_axi_arlen    (arb_arlen),
        .m_axi_arsize   (arb_arsize),
        .m_axi_arburst  (arb_arburst),
        .m_axi_arlock   (arb_arlock),
        .m_axi_arcache  (arb_arcache),
        .m_axi_arprot   (arb_arprot),
        .m_axi_arqos    (arb_arqos),
        .m_axi_arvalid  (arb_arvalid),
        .m_axi_arready  (arb_arready),
        .m_axi_rid      (arb_rid),
        .m_axi_rdata    (arb_rdata),
        .m_axi_rresp    (arb_rresp),
        .m_axi_rlast    (arb_rlast),
        .m_axi_rvalid   (arb_rvalid),
        .m_axi_rready   (arb_rready)
    );

    // Shared randomized slave bus.
    wire [1:0]  rnd_awid;
    wire [31:0] rnd_awaddr;
    wire [7:0]  rnd_awlen;
    wire [2:0]  rnd_awsize;
    wire [1:0]  rnd_awburst;
    wire        rnd_awlock;
    wire [3:0]  rnd_awcache;
    wire [2:0]  rnd_awprot;
    wire [3:0]  rnd_awqos;
    wire        rnd_awvalid;
    wire        rnd_awready;
    wire [31:0] rnd_wdata;
    wire [3:0]  rnd_wstrb;
    wire        rnd_wlast;
    wire        rnd_wvalid;
    wire        rnd_wready;
    wire [1:0]  rnd_bid;
    wire [1:0]  rnd_bresp;
    wire        rnd_bvalid;
    wire        rnd_bready;
    wire [1:0]  rnd_arid;
    wire [31:0] rnd_araddr;
    wire [7:0]  rnd_arlen;
    wire [2:0]  rnd_arsize;
    wire [1:0]  rnd_arburst;
    wire        rnd_arlock;
    wire [3:0]  rnd_arcache;
    wire [2:0]  rnd_arprot;
    wire [3:0]  rnd_arqos;
    wire        rnd_arvalid;
    wire        rnd_arready;
    wire [1:0]  rnd_rid;
    wire [31:0] rnd_rdata;
    wire [1:0]  rnd_rresp;
    wire        rnd_rlast;
    wire        rnd_rvalid;
    wire        rnd_rready;

    // Response-side backpressure belongs to the AXI master.  The adapters
    // themselves consume responses whenever active, so this harness inserts
    // a transparent gate: the slave and passive checker see true B/R stalls,
    // while the adapter only sees a response on the cycle it is accepted.
    logic [31:0] response_lfsr_q;
    logic        read_response_seen_q;
    logic        write_response_seen_q;
    logic        read_response_release_q;
    logic        write_response_release_q;
    logic [2:0]  read_response_hold_q;
    logic [2:0]  write_response_hold_q;

    function automatic logic [31:0] response_lfsr_next(
        input logic [31:0] value
    );
        response_lfsr_next = {value[30:0],
                              value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    wire allow_read_response = read_response_release_q;
    wire allow_write_response = write_response_release_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            response_lfsr_q       <= 32'h3141_5926;
            read_response_seen_q  <= 1'b0;
            write_response_seen_q <= 1'b0;
            read_response_release_q  <= 1'b0;
            write_response_release_q <= 1'b0;
            read_response_hold_q  <= '0;
            write_response_hold_q <= '0;
        end
        else begin
            response_lfsr_q <= response_lfsr_next(response_lfsr_q);

            if (!read_response_seen_q && rnd_rvalid) begin
                read_response_seen_q <= 1'b1;
                read_response_hold_q <= 3'd2;
                read_response_release_q <= 1'b0;
            end
            else if (read_response_hold_q != 0) begin
                read_response_hold_q <= read_response_hold_q - 1'b1;
            end
            else if (read_response_seen_q && !read_response_release_q &&
                     response_lfsr_q[0]) begin
                read_response_release_q <= 1'b1;
            end
            if (rnd_rvalid && rnd_rready) begin
                read_response_seen_q <= 1'b0;
                read_response_hold_q <= '0;
                read_response_release_q <= 1'b0;
            end

            if (!write_response_seen_q && rnd_bvalid) begin
                write_response_seen_q <= 1'b1;
                write_response_hold_q <= 3'd2;
                write_response_release_q <= 1'b0;
            end
            else if (write_response_hold_q != 0) begin
                write_response_hold_q <= write_response_hold_q - 1'b1;
            end
            else if (write_response_seen_q && !write_response_release_q &&
                     response_lfsr_q[1]) begin
                write_response_release_q <= 1'b1;
            end
            if (rnd_bvalid && rnd_bready) begin
                write_response_seen_q <= 1'b0;
                write_response_hold_q <= '0;
                write_response_release_q <= 1'b0;
            end
        end
    end

    assign rnd_awid    = (random_target == TARGET_DC) ? dc_awid : 2'b0;
    assign rnd_awaddr  = (random_target == TARGET_DC) ? dc_awaddr : 32'b0;
    assign rnd_awlen   = (random_target == TARGET_DC) ? dc_awlen : 8'b0;
    assign rnd_awsize  = (random_target == TARGET_DC) ? dc_awsize : 3'b0;
    assign rnd_awburst = (random_target == TARGET_DC) ? dc_awburst : 2'b0;
    assign rnd_awlock  = (random_target == TARGET_DC) ? dc_awlock : 1'b0;
    assign rnd_awcache = (random_target == TARGET_DC) ? dc_awcache : 4'b0;
    assign rnd_awprot  = (random_target == TARGET_DC) ? dc_awprot : 3'b0;
    assign rnd_awqos   = (random_target == TARGET_DC) ? dc_awqos : 4'b0;
    assign rnd_awvalid = (random_target == TARGET_DC) && dc_awvalid;
    assign dc_awready  = (random_target == TARGET_DC) && rnd_awready;

    assign rnd_wdata   = (random_target == TARGET_DC) ? dc_wdata : 32'b0;
    assign rnd_wstrb   = (random_target == TARGET_DC) ? dc_wstrb : 4'b0;
    assign rnd_wlast   = (random_target == TARGET_DC) && dc_wlast;
    assign rnd_wvalid  = (random_target == TARGET_DC) && dc_wvalid;
    assign dc_wready   = (random_target == TARGET_DC) && rnd_wready;
    assign dc_bid      = rnd_bid;
    assign dc_bresp    = rnd_bresp;
    assign dc_bvalid   = (random_target == TARGET_DC) && rnd_bvalid &&
                         allow_write_response;
    assign rnd_bready  = (random_target == TARGET_DC) && dc_bready &&
                         allow_write_response;

    assign rnd_arid = (random_target == TARGET_IC)  ? ic_arid :
                      (random_target == TARGET_DC)  ? dc_arid : arb_arid;
    assign rnd_araddr = (random_target == TARGET_IC) ? ic_araddr :
                        (random_target == TARGET_DC) ? dc_araddr : arb_araddr;
    assign rnd_arlen = (random_target == TARGET_IC) ? ic_arlen :
                       (random_target == TARGET_DC) ? dc_arlen : arb_arlen;
    assign rnd_arsize = (random_target == TARGET_IC) ? ic_arsize :
                        (random_target == TARGET_DC) ? dc_arsize : arb_arsize;
    assign rnd_arburst = (random_target == TARGET_IC) ? ic_arburst :
                         (random_target == TARGET_DC) ? dc_arburst : arb_arburst;
    assign rnd_arlock = (random_target == TARGET_IC) ? ic_arlock :
                        (random_target == TARGET_DC) ? dc_arlock : arb_arlock;
    assign rnd_arcache = (random_target == TARGET_IC) ? ic_arcache :
                         (random_target == TARGET_DC) ? dc_arcache : arb_arcache;
    assign rnd_arprot = (random_target == TARGET_IC) ? ic_arprot :
                        (random_target == TARGET_DC) ? dc_arprot : arb_arprot;
    assign rnd_arqos = (random_target == TARGET_IC) ? ic_arqos :
                       (random_target == TARGET_DC) ? dc_arqos : arb_arqos;
    assign rnd_arvalid = (random_target == TARGET_IC)  ? ic_arvalid :
                         (random_target == TARGET_DC)  ? dc_arvalid : arb_arvalid;

    assign ic_arready  = (random_target == TARGET_IC) && rnd_arready;
    assign dc_arready  = (random_target == TARGET_DC) && rnd_arready;
    assign arb_arready = (random_target == TARGET_ARB) && rnd_arready;
    assign ic_rid      = rnd_rid;
    assign ic_rdata    = rnd_rdata;
    assign ic_rresp    = rnd_rresp;
    assign ic_rlast    = rnd_rlast;
    assign ic_rvalid   = (random_target == TARGET_IC) && rnd_rvalid &&
                         allow_read_response;
    assign dc_rid      = rnd_rid;
    assign dc_rdata    = rnd_rdata;
    assign dc_rresp    = rnd_rresp;
    assign dc_rlast    = rnd_rlast;
    assign dc_rvalid   = (random_target == TARGET_DC) && rnd_rvalid &&
                         allow_read_response;
    assign arb_rid     = rnd_rid;
    assign arb_rdata   = rnd_rdata;
    assign arb_rresp   = rnd_rresp;
    assign arb_rlast   = rnd_rlast;
    assign arb_rvalid  = (random_target == TARGET_ARB) && rnd_rvalid &&
                         allow_read_response;
    assign rnd_rready  = (random_target == TARGET_IC)  ? ic_rready &&
                                                        allow_read_response :
                         (random_target == TARGET_DC)  ? dc_rready &&
                                                        allow_read_response :
                                                        arb_rready &&
                                                        allow_read_response;

    axi_random_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .MEM_WORDS (1024),
        .DATA_TAG  (RANDOM_TAG),
        .SEED      (32'h5eed_cafe)
    ) u_random_slave (
        .clk           (clk),
        .reset         (reset),
        .s_axi_awid    (rnd_awid),
        .s_axi_awaddr  (rnd_awaddr),
        .s_axi_awlen   (rnd_awlen),
        .s_axi_awsize  (rnd_awsize),
        .s_axi_awburst (rnd_awburst),
        .s_axi_awlock  (rnd_awlock),
        .s_axi_awcache (rnd_awcache),
        .s_axi_awprot  (rnd_awprot),
        .s_axi_awqos   (rnd_awqos),
        .s_axi_awvalid (rnd_awvalid),
        .s_axi_awready (rnd_awready),
        .s_axi_wdata   (rnd_wdata),
        .s_axi_wstrb   (rnd_wstrb),
        .s_axi_wlast   (rnd_wlast),
        .s_axi_wvalid  (rnd_wvalid),
        .s_axi_wready  (rnd_wready),
        .s_axi_bid     (rnd_bid),
        .s_axi_bresp   (rnd_bresp),
        .s_axi_bvalid  (rnd_bvalid),
        .s_axi_bready  (rnd_bready),
        .s_axi_arid    (rnd_arid),
        .s_axi_araddr  (rnd_araddr),
        .s_axi_arlen   (rnd_arlen),
        .s_axi_arsize  (rnd_arsize),
        .s_axi_arburst (rnd_arburst),
        .s_axi_arlock  (rnd_arlock),
        .s_axi_arcache (rnd_arcache),
        .s_axi_arprot  (rnd_arprot),
        .s_axi_arqos   (rnd_arqos),
        .s_axi_arvalid (rnd_arvalid),
        .s_axi_arready (rnd_arready),
        .s_axi_rid     (rnd_rid),
        .s_axi_rdata   (rnd_rdata),
        .s_axi_rresp   (rnd_rresp),
        .s_axi_rlast   (rnd_rlast),
        .s_axi_rvalid  (rnd_rvalid),
        .s_axi_rready  (rnd_rready)
    );

    axi_test_checker #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .ID_WIDTH       (ID_WIDTH),
        .CHECK_READ     (1'b1),
        .CHECK_WRITE    (1'b1),
        .CHECK_FIXED_ID (1'b0)
    ) u_random_checker (
        .clk     (clk),
        .reset   (reset),
        .awid    (rnd_awid),
        .awaddr  (rnd_awaddr),
        .awlen   (rnd_awlen),
        .awsize  (rnd_awsize),
        .awburst (rnd_awburst),
        .awlock  (rnd_awlock),
        .awcache (rnd_awcache),
        .awprot  (rnd_awprot),
        .awqos   (rnd_awqos),
        .awvalid (rnd_awvalid),
        .awready (rnd_awready),
        .wdata   (rnd_wdata),
        .wstrb   (rnd_wstrb),
        .wlast   (rnd_wlast),
        .wvalid  (rnd_wvalid),
        .wready  (rnd_wready),
        .bid     (rnd_bid),
        .bresp   (rnd_bresp),
        .bvalid  (rnd_bvalid),
        .bready  (rnd_bready),
        .arid    (rnd_arid),
        .araddr  (rnd_araddr),
        .arlen   (rnd_arlen),
        .arsize  (rnd_arsize),
        .arburst (rnd_arburst),
        .arlock  (rnd_arlock),
        .arcache (rnd_arcache),
        .arprot  (rnd_arprot),
        .arqos   (rnd_arqos),
        .arvalid (rnd_arvalid),
        .arready (rnd_arready),
        .rid     (rnd_rid),
        .rdata   (rnd_rdata),
        .rresp   (rnd_rresp),
        .rlast   (rnd_rlast),
        .rvalid  (rnd_rvalid),
        .rready  (rnd_rready)
    );

    always @(posedge clk) begin
        if (!reset) begin
            if (ic_arvalid && (ic_arid != 2'd0)) begin
                $fatal(1, "ICache adapter emitted wrong AXI ID");
            end
            if ((dc_arvalid && (dc_arid != 2'd1)) ||
                (dc_awvalid && (dc_awid != 2'd1))) begin
                $fatal(1, "DCache adapter emitted wrong AXI ID");
            end
        end
    end

    logic arb_s0_r_stalled_q;
    logic arb_s1_r_stalled_q;
    logic [36:0] arb_s0_r_payload_q;
    logic [36:0] arb_s1_r_payload_q;
    wire [36:0] arb_s0_r_payload =
        {arb_s0_rid, arb_s0_rdata, arb_s0_rresp, arb_s0_rlast};
    wire [36:0] arb_s1_r_payload =
        {arb_s1_rid, arb_s1_rdata, arb_s1_rresp, arb_s1_rlast};

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            arb_s0_r_stalled_q <= 1'b0;
            arb_s1_r_stalled_q <= 1'b0;
            arb_s0_r_payload_q <= '0;
            arb_s1_r_payload_q <= '0;
        end
        else begin
            if (arb_s0_r_stalled_q &&
                (!arb_s0_rvalid ||
                 (arb_s0_r_payload !== arb_s0_r_payload_q))) begin
                $fatal(1, "arbiter source 0 R payload changed while stalled");
            end
            if (arb_s1_r_stalled_q &&
                (!arb_s1_rvalid ||
                 (arb_s1_r_payload !== arb_s1_r_payload_q))) begin
                $fatal(1, "arbiter source 1 R payload changed while stalled");
            end
            arb_s0_r_stalled_q <= arb_s0_rvalid && !arb_s0_rready;
            arb_s1_r_stalled_q <= arb_s1_rvalid && !arb_s1_rready;
            if (arb_s0_rvalid && !arb_s0_rready) begin
                arb_s0_r_payload_q <= arb_s0_r_payload;
            end
            if (arb_s1_rvalid && !arb_s1_rready) begin
                arb_s1_r_payload_q <= arb_s1_r_payload;
            end
        end
    end

    task automatic direct_icache_read(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] expected_data
    );
        begin
            @(negedge clk);
            direct_ic_req_addr  = address;
            direct_ic_req_valid = 1'b1;
            while (!(direct_ic_req_valid && direct_ic_req_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            direct_ic_req_valid = 1'b0;
            while (!direct_ic_resp_valid) begin
                @(negedge clk);
            end
            if ((direct_ic_resp_resp != `AXI_RESP_OKAY) ||
                (direct_ic_resp_data !== expected_data)) begin
                $fatal(1, "direct randomized ICache read mismatch at %08x",
                       address);
            end
            @(negedge clk);
        end
    endtask

    task automatic direct_dcache_write(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            direct_dc_wreq_addr  = address;
            direct_dc_wreq_data  = data;
            direct_dc_wreq_valid = 1'b1;
            while (!(direct_dc_wreq_valid && direct_dc_wreq_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            direct_dc_wreq_valid = 1'b0;
            while (!direct_dc_wresp_valid) begin
                @(negedge clk);
            end
            if (direct_dc_wresp_resp != `AXI_RESP_OKAY) begin
                $fatal(1, "direct randomized DCache write failed at %08x",
                       address);
            end
            @(negedge clk);
        end
    endtask

    task automatic direct_dcache_read(
        input logic [31:0] address,
        input logic [LINE_WIDTH-1:0] expected_data
    );
        begin
            @(negedge clk);
            direct_dc_rreq_addr  = address;
            direct_dc_rreq_valid = 1'b1;
            while (!(direct_dc_rreq_valid && direct_dc_rreq_ready)) begin
                @(posedge clk);
            end
            @(negedge clk);
            direct_dc_rreq_valid = 1'b0;
            while (!direct_dc_rresp_valid) begin
                @(negedge clk);
            end
            if ((direct_dc_rresp_resp != `AXI_RESP_OKAY) ||
                (direct_dc_rresp_data !== expected_data)) begin
                $fatal(1, "direct randomized DCache read mismatch at %08x",
                       address);
            end
            @(negedge clk);
        end
    endtask

    task automatic direct_arbiter_reads;
        integer source0_beat;
        integer source1_beat;
        integer completed;
        begin
            source0_beat = 0;
            source1_beat = 0;
            completed = 0;

            @(negedge clk);
            arb_s0_arid    = 2'd0;
            arb_s0_araddr  = 32'h0000_0200;
            arb_s0_arlen   = 8'd3;
            arb_s0_arsize  = 3'd2;
            arb_s0_arburst = `AXI_BURST_INCR;
            arb_s0_arlock  = 1'b0;
            arb_s0_arcache = 4'b0011;
            arb_s0_arprot  = 3'b000;
            arb_s0_arqos   = 4'b0000;
            arb_s0_arvalid = 1'b1;
            arb_s1_arid    = 2'd1;
            arb_s1_araddr  = 32'h0000_0240;
            arb_s1_arlen   = 8'd3;
            arb_s1_arsize  = 3'd2;
            arb_s1_arburst = `AXI_BURST_INCR;
            arb_s1_arlock  = 1'b0;
            arb_s1_arcache = 4'b0011;
            arb_s1_arprot  = 3'b000;
            arb_s1_arqos   = 4'b0000;
            arb_s1_arvalid = 1'b1;
            arb_s0_rready  = 1'b0;
            arb_s1_rready  = 1'b0;

            fork
                begin
                    while (!(arb_s0_arvalid && arb_s0_arready)) begin
                        @(posedge clk);
                    end
                    @(negedge clk);
                    arb_s0_arvalid = 1'b0;
                end
                begin
                    while (!(arb_s1_arvalid && arb_s1_arready)) begin
                        @(posedge clk);
                    end
                    @(negedge clk);
                    arb_s1_arvalid = 1'b0;
                end
                begin
                    while (!(arb_s0_rvalid || arb_s1_rvalid)) begin
                        @(posedge clk);
                    end
                    // Hold RREADY low for multiple cycles.  The passive
                    // checker proves that RVALID and all payload bits hold.
                    repeat (3) @(posedge clk);
                    @(negedge clk);
                    arb_s0_rready = 1'b1;
                    arb_s1_rready = 1'b1;
                end
                begin
                    while (completed < 2) begin
                        @(posedge clk);
                        if (arb_s0_rvalid && arb_s0_rready) begin
                            if ((arb_s0_rid != 2'd0) ||
                                (arb_s0_rresp != `AXI_RESP_OKAY) ||
                                (arb_s0_rdata !==
                                 (RANDOM_TAG + (32'h200 >> 2) + source0_beat)) ||
                                (arb_s0_rlast !== (source0_beat == 3))) begin
                                $fatal(1, "arbiter source 0 response mismatch at beat %0d",
                                       source0_beat);
                            end
                            if (arb_s0_rlast) begin
                                if (completed != 0) begin
                                    $fatal(1, "arbiter source 0 lost reset priority");
                                end
                                completed = completed + 1;
                            end
                            source0_beat = source0_beat + 1;
                        end
                        if (arb_s1_rvalid && arb_s1_rready) begin
                            if ((arb_s1_rid != 2'd1) ||
                                (arb_s1_rresp != `AXI_RESP_OKAY) ||
                                (arb_s1_rdata !==
                                 (RANDOM_TAG + (32'h240 >> 2) + source1_beat)) ||
                                (arb_s1_rlast !== (source1_beat == 3))) begin
                                $fatal(1, "arbiter source 1 response mismatch at beat %0d",
                                       source1_beat);
                            end
                            if (arb_s1_rlast) begin
                                if (completed != 1) begin
                                    $fatal(1, "arbiter source 1 completed out of order");
                                end
                                completed = completed + 1;
                            end
                            source1_beat = source1_beat + 1;
                        end
                    end
                end
            join

            if ((source0_beat != 4) || (source1_beat != 4)) begin
                $fatal(1, "arbiter did not return four beats per source");
            end
            @(negedge clk);
            arb_s0_rready = 1'b0;
            arb_s1_rready = 1'b0;
        end
    endtask

    initial begin : test_sequence
        logic [LINE_WIDTH-1:0] sys_ic_line;
        logic [LINE_WIDTH-1:0] sys_dc_line;
        logic [LINE_WIDTH-1:0] sys_write_line;
        logic [LINE_WIDTH-1:0] sys_boundary_line;
        logic [LINE_WIDTH-1:0] direct_write_line;

        reset = 1'b1;
        random_target = TARGET_IC;

        sys_ic_req_valid  = 1'b0;
        sys_ic_req_addr   = '0;
        sys_dc_rreq_valid = 1'b0;
        sys_dc_rreq_addr  = '0;
        sys_dc_wreq_valid = 1'b0;
        sys_dc_wreq_addr  = '0;
        sys_dc_wreq_data  = '0;

        direct_ic_req_valid  = 1'b0;
        direct_ic_req_addr   = '0;
        direct_dc_rreq_valid = 1'b0;
        direct_dc_rreq_addr  = '0;
        direct_dc_wreq_valid = 1'b0;
        direct_dc_wreq_addr  = '0;
        direct_dc_wreq_data  = '0;

        arb_s0_arid    = '0;
        arb_s0_araddr  = '0;
        arb_s0_arlen   = 8'd3;
        arb_s0_arsize  = 3'd2;
        arb_s0_arburst = `AXI_BURST_INCR;
        arb_s0_arlock  = 1'b0;
        arb_s0_arcache = 4'b0011;
        arb_s0_arprot  = 3'b000;
        arb_s0_arqos   = 4'b0000;
        arb_s0_arvalid = 1'b0;
        arb_s0_rready  = 1'b0;
        arb_s1_arid    = '0;
        arb_s1_araddr  = '0;
        arb_s1_arlen   = 8'd3;
        arb_s1_arsize  = 3'd2;
        arb_s1_arburst = `AXI_BURST_INCR;
        arb_s1_arlock  = 1'b0;
        arb_s1_arcache = 4'b0011;
        arb_s1_arprot  = 3'b000;
        arb_s1_arqos   = 4'b0000;
        arb_s1_arvalid = 1'b0;
        arb_s1_rready  = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // Baseline subsystem reads: each request must become one four-beat
        // RAM burst and retain the little-endian line packing used by caches.
        sys_ic_line = pack_line(32'h1020_3040, 32'h5060_7080,
                                32'h90a0_b0c0, 32'hd0e0_f001);
        sys_dc_line = pack_line(32'h1357_9bdf, 32'h2468_ace0,
                                32'hdead_beef, 32'hc001_d00d);
        preload_system_line(32'h8000_0100, sys_ic_line);
        preload_system_line(32'h8000_0140, sys_dc_line);
        system_icache_read(32'h8000_0100, sys_ic_line,
                           `AXI_RESP_OKAY, 4);
        system_dcache_read(32'h8000_0140, sys_dc_line,
                           `AXI_RESP_OKAY, 4);

        // Dirty-line writeback followed by a read proves AW/W/B pairing and
        // that every one of the four words was committed to RAM.
        sys_write_line = pack_line(32'h0123_4567, 32'h89ab_cdef,
                                   32'h55aa_aa55, 32'h8000_0001);
        system_dcache_write(32'h8000_0180, sys_write_line,
                            `AXI_RESP_OKAY, 4);
        system_dcache_read(32'h8000_0180, sys_write_line,
                           `AXI_RESP_OKAY, 4);

        // Reset restores deterministic source-0 arbitration priority without
        // clearing RAM. Both adapters accept a request in the same cycle.
        apply_reset();
        system_simultaneous_reads(32'h8000_0100, sys_ic_line,
                                  32'h8000_0140, sys_dc_line);

        // The final complete line inside the 4 KiB RAM succeeds. The first
        // line beyond it, the reserved MMIO window, and an unrelated hole all
        // complete as DECERR and must never reach the RAM slave.
        sys_boundary_line = pack_line(32'h0bad_f00d, 32'hfeed_face,
                                      32'h7654_3210, 32'hffff_0000);
        preload_system_line(32'h8000_0ff0, sys_boundary_line);
        system_icache_read(32'h8000_0ff0, sys_boundary_line,
                           `AXI_RESP_OKAY, 4);
        system_icache_read(32'h8000_1000, '0,
                           `AXI_RESP_DECERR, 0);
        system_dcache_read(32'h1000_0000, '0,
                           `AXI_RESP_DECERR, 0);
        system_icache_read(32'h2000_0000, '0,
                           `AXI_RESP_DECERR, 0);
        system_dcache_write(32'h1000_0000, sys_write_line,
                            `AXI_RESP_DECERR, 0);

        // Direct ICache adapter against deterministic randomized ARREADY and
        // RVALID latency. The forced address wait makes VALID stability
        // coverage non-vacuous.
        random_target = TARGET_IC;
        apply_reset();
        direct_icache_read(32'h0000_0100, tagged_line(32'h0000_0100));
        if ((u_random_checker.read_burst_count != 1) ||
            (u_random_checker.ar_stall_count == 0) ||
            (u_random_checker.r_stall_count == 0)) begin
            $fatal(1, "randomized ICache protocol/stall coverage missing");
        end

        // Direct DCache write then read through randomized AWREADY, WREADY,
        // response latency, and ARREADY. Readback checks all data beats.
        random_target = TARGET_DC;
        apply_reset();
        direct_write_line = pack_line(32'ha5a5_0001, 32'h5a5a_0002,
                                      32'hffff_0003, 32'h0000_0004);
        direct_dcache_write(32'h0000_0180, direct_write_line);
        direct_dcache_read(32'h0000_0180, direct_write_line);
        if ((u_random_checker.write_burst_count != 1) ||
            (u_random_checker.read_burst_count != 1) ||
            (u_random_checker.aw_stall_count == 0) ||
            (u_random_checker.w_stall_count == 0) ||
            (u_random_checker.b_stall_count == 0) ||
            (u_random_checker.ar_stall_count == 0) ||
            (u_random_checker.r_stall_count == 0)) begin
            $fatal(1, "randomized DCache protocol/stall coverage missing");
        end

        // Direct arbiter contention plus explicit RREADY backpressure checks
        // route locking, reset priority, ID preservation, and stable RVALID.
        random_target = TARGET_ARB;
        apply_reset();
        direct_arbiter_reads();
        if ((u_random_checker.read_burst_count != 2) ||
            (u_random_checker.ar_stall_count == 0) ||
            (u_random_checker.r_stall_count == 0)) begin
            $fatal(1, "randomized arbiter protocol/stall coverage missing");
        end

        @(negedge clk);
        if (u_random_checker.read_outstanding_q ||
            u_random_checker.write_outstanding_q ||
            u_random_slave.read_active_q || u_random_slave.write_active_q ||
            u_random_slave.b_pending_q || rnd_arvalid || rnd_awvalid ||
            rnd_wvalid || rnd_rvalid || rnd_bvalid ||
            arb_s0_arvalid || arb_s1_arvalid ||
            read_response_seen_q || write_response_seen_q ||
            read_response_release_q || write_response_release_q ||
            !direct_ic_req_ready || !direct_dc_rreq_ready ||
            !direct_dc_wreq_ready || (u_direct_arbiter.state_q != 2'd0) ||
            !sys_ic_req_ready || !sys_dc_rreq_ready ||
            !sys_dc_wreq_ready) begin
            $fatal(1, "test ended with a pending AXI/cache transaction");
        end

        $display("AXI_SUBSYSTEM_TEST PASS");
        $finish;
    end

endmodule
