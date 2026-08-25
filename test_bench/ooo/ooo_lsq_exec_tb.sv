`timescale 1ns/1ps

module ooo_lsq_exec_tb;

    logic clk;
    logic reset;
    logic flush;

    always #5 clk = ~clk;

    // Mul/div fixed-latency tracker.
    logic        m_start_valid;
    logic [6:0]  m_use_signal;
    logic [31:0] m_mul_result;
    logic [31:0] m_div_result;
    logic [2:0]  m_start_rob;
    logic [5:0]  m_start_pdst;
    logic        m_start_writes;
    wire         m_start_ready;
    wire         m_start_fire;
    wire         m_busy;
    wire         m_result_valid;
    logic        m_result_grant;
    wire [31:0]  m_result_value;
    wire [2:0]   m_result_rob;
    wire [5:0]   m_result_pdst;
    wire         m_result_writes;

    muldiv_tracker muldiv_tracker_inst (
        .clk                (clk),
        .reset              (reset),
        .flush_in           (flush),
        .start_valid_in     (m_start_valid),
        .start_use_signal_in(m_use_signal),
        .mul_result_in      (m_mul_result),
        .div_result_in      (m_div_result),
        .start_rob_in       (m_start_rob),
        .start_pdst_in      (m_start_pdst),
        .start_writes_in    (m_start_writes),
        .start_ready_out    (m_start_ready),
        .start_fire_out     (m_start_fire),
        .busy_out           (m_busy),
        .result_valid_out   (m_result_valid),
        .result_grant_in    (m_result_grant),
        .result_value_out   (m_result_value),
        .result_rob_out     (m_result_rob),
        .result_pdst_out    (m_result_pdst),
        .result_writes_out  (m_result_writes)
    );

    // Two-lane CDB arbiter.
    logic load_valid;
    logic muldiv_valid;
    logic int0_valid;
    logic int1_valid;
    wire cdb0_valid;
    wire [2:0] cdb0_rob;
    wire cdb0_writes;
    wire [5:0] cdb0_pdst;
    wire [31:0] cdb0_value;
    wire cdb0_control;
    wire [31:0] cdb0_target;
    wire cdb0_mispredict;
    wire cdb1_valid;
    wire [2:0] cdb1_rob;
    wire cdb1_writes;
    wire [5:0] cdb1_pdst;
    wire [31:0] cdb1_value;
    wire cdb1_control;
    wire [31:0] cdb1_target;
    wire cdb1_mispredict;
    wire load_grant;
    wire muldiv_grant;
    wire int0_grant;
    wire int1_grant;

    cdb_arbiter cdb_arbiter_inst (
        .load_valid       (load_valid),
        .load_rob         (3'd1),
        .load_writes      (1'b1),
        .load_pdst        (6'd33),
        .load_value       (32'h1111_1111),
        .load_control     (1'b0),
        .load_target      (32'h0000_0100),
        .load_mispredict  (1'b0),
        .muldiv_valid     (muldiv_valid),
        .muldiv_rob       (3'd2),
        .muldiv_writes    (1'b1),
        .muldiv_pdst      (6'd34),
        .muldiv_value     (32'h2222_2222),
        .muldiv_control   (1'b0),
        .muldiv_target    (32'h0000_0200),
        .muldiv_mispredict(1'b0),
        .int0_valid       (int0_valid),
        .int0_rob         (3'd3),
        .int0_writes      (1'b1),
        .int0_pdst        (6'd35),
        .int0_value       (32'h3333_3333),
        .int0_control     (1'b1),
        .int0_target      (32'h0000_0300),
        .int0_mispredict  (1'b1),
        .int1_valid       (int1_valid),
        .int1_rob         (3'd4),
        .int1_writes      (1'b1),
        .int1_pdst        (6'd36),
        .int1_value       (32'h4444_4444),
        .int1_control     (1'b0),
        .int1_target      (32'h0000_0400),
        .int1_mispredict  (1'b0),
        .cdb0_valid       (cdb0_valid),
        .cdb0_rob         (cdb0_rob),
        .cdb0_writes      (cdb0_writes),
        .cdb0_pdst        (cdb0_pdst),
        .cdb0_value       (cdb0_value),
        .cdb0_control     (cdb0_control),
        .cdb0_target      (cdb0_target),
        .cdb0_mispredict  (cdb0_mispredict),
        .cdb1_valid       (cdb1_valid),
        .cdb1_rob         (cdb1_rob),
        .cdb1_writes      (cdb1_writes),
        .cdb1_pdst        (cdb1_pdst),
        .cdb1_value       (cdb1_value),
        .cdb1_control     (cdb1_control),
        .cdb1_target      (cdb1_target),
        .cdb1_mispredict  (cdb1_mispredict),
        .load_grant       (load_grant),
        .muldiv_grant     (muldiv_grant),
        .int0_grant       (int0_grant),
        .int1_grant       (int1_grant)
    );

    // Load result formatter.
    logic [2:0]  ext_lsu_op;
    logic [31:0] ext_raw_data;
    wire [31:0]  ext_value;

    load_extender load_extender_inst (
        .lsu_op_in  (ext_lsu_op),
        .raw_data_in(ext_raw_data),
        .value_out  (ext_value)
    );

    // Eight-entry LSQ and split data-memory channel.
    logic [1:0] dispatch_count;
    logic       dispatch0_enable;
    logic       dispatch0_is_store;
    logic [63:0] dispatch0_seq;
    logic [2:0] dispatch0_rob;
    logic [5:0] dispatch0_pdst;
    logic       dispatch0_writes;
    logic [2:0] dispatch0_lsu_op;
    logic       dispatch1_enable;
    logic       dispatch1_is_store;
    logic [63:0] dispatch1_seq;
    logic [2:0] dispatch1_rob;
    logic [5:0] dispatch1_pdst;
    logic       dispatch1_writes;
    logic [2:0] dispatch1_lsu_op;
    wire [2:0] alloc_index0;
    wire [2:0] alloc_index1;
    wire [3:0] free_count;

    logic       agu_capture_valid;
    logic [2:0] agu_capture_index;
    logic [31:0] agu_addr;
    logic [31:0] agu_wdata;
    logic [3:0] agu_wstrb;
    logic [2:0] agu_lsu_op;

    logic       rob_head_valid;
    logic [2:0] rob_head_tag;
    logic       rob_head_is_store;
    logic       barrier_valid;
    logic [63:0] barrier_seq;

    wire [31:0] dm_req_addr;
    wire        dm_req_rvalid;
    logic       dm_req_rready;
    logic       dm_resp_rvalid;
    logic [31:0] dm_resp_rdata;
    wire        dm_req_wvalid;
    logic       dm_req_wready;
    wire [3:0]  dm_req_wstrb;
    wire [31:0] dm_req_wdata;
    logic       dm_resp_wvalid;

    wire        load_result_valid;
    logic       load_result_grant;
    wire [2:0]  load_result_rob;
    wire [5:0]  load_result_pdst;
    wire        load_result_writes;
    wire [31:0] load_result_value;
    wire        store_complete_valid;
    wire [2:0]  store_complete_rob;
    wire        memory_idle;

    lsq lsq_inst (
        .clk                       (clk),
        .reset                     (reset),
        .flush_in                  (flush),
        .dispatch_count_in         (dispatch_count),
        .dispatch0_enable_in       (dispatch0_enable),
        .dispatch0_is_store_in     (dispatch0_is_store),
        .dispatch0_seq_in          (dispatch0_seq),
        .dispatch0_rob_in          (dispatch0_rob),
        .dispatch0_pdst_in         (dispatch0_pdst),
        .dispatch0_writes_in       (dispatch0_writes),
        .dispatch0_lsu_op_in       (dispatch0_lsu_op),
        .dispatch1_enable_in       (dispatch1_enable),
        .dispatch1_is_store_in     (dispatch1_is_store),
        .dispatch1_seq_in          (dispatch1_seq),
        .dispatch1_rob_in          (dispatch1_rob),
        .dispatch1_pdst_in         (dispatch1_pdst),
        .dispatch1_writes_in       (dispatch1_writes),
        .dispatch1_lsu_op_in       (dispatch1_lsu_op),
        .alloc_index0_out          (alloc_index0),
        .alloc_index1_out          (alloc_index1),
        .free_count_out            (free_count),
        .agu_capture_valid_in      (agu_capture_valid),
        .agu_capture_index_in      (agu_capture_index),
        .agu_addr_in               (agu_addr),
        .agu_wdata_in              (agu_wdata),
        .agu_wstrb_in              (agu_wstrb),
        .agu_lsu_op_in             (agu_lsu_op),
        .rob_head_valid_in         (rob_head_valid),
        .rob_head_tag_in           (rob_head_tag),
        .rob_head_is_store_in      (rob_head_is_store),
        .barrier_valid_in          (barrier_valid),
        .barrier_seq_in            (barrier_seq),
        .dm_req_addr_out           (dm_req_addr),
        .dm_req_rvalid_out         (dm_req_rvalid),
        .dm_req_rready_in          (dm_req_rready),
        .dm_resp_rvalid_in         (dm_resp_rvalid),
        .dm_resp_rdata_in          (dm_resp_rdata),
        .dm_req_wvalid_out         (dm_req_wvalid),
        .dm_req_wready_in          (dm_req_wready),
        .dm_req_wstrb_out          (dm_req_wstrb),
        .dm_req_wdata_out          (dm_req_wdata),
        .dm_resp_wvalid_in         (dm_resp_wvalid),
        .load_result_valid_out     (load_result_valid),
        .load_result_grant_in      (load_result_grant),
        .load_result_rob_out       (load_result_rob),
        .load_result_pdst_out      (load_result_pdst),
        .load_result_writes_out    (load_result_writes),
        .load_result_value_out     (load_result_value),
        .store_complete_valid_out  (store_complete_valid),
        .store_complete_rob_out    (store_complete_rob),
        .memory_idle_out           (memory_idle)
    );

    // This invariant is the regression target for the ROB-head store fix.
    // A younger load must not even be prepared while the store remains head.
    always @(posedge clk) begin
        if (!flush && rob_head_valid && rob_head_is_store && dm_req_rvalid)
            $fatal(1, "young load prepared while a store is ROB head");
    end

    task automatic dispatch_one_load(
        input  [63:0] seq_value,
        input  [2:0]  rob_tag,
        input  [5:0]  pdst,
        input  [2:0]  lsu_op,
        output [2:0]  index
    );
        begin
            @(negedge clk);
            dispatch_count = 2'd1;
            dispatch0_enable = 1'b1;
            dispatch0_is_store = 1'b0;
            dispatch0_seq = seq_value;
            dispatch0_rob = rob_tag;
            dispatch0_pdst = pdst;
            dispatch0_writes = 1'b1;
            dispatch0_lsu_op = lsu_op;
            #1 index = alloc_index0;
            @(posedge clk);
            #1;
            @(negedge clk);
            dispatch_count = 2'd0;
            dispatch0_enable = 1'b0;
        end
    endtask

    task automatic dispatch_two_loads(
        input  [63:0] sequence0,
        input  [2:0]  rob_tag0,
        input  [5:0]  pdst0,
        input  [63:0] sequence1,
        input  [2:0]  rob_tag1,
        input  [5:0]  pdst1,
        output [2:0]  index0,
        output [2:0]  index1
    );
        begin
            @(negedge clk);
            dispatch_count = 2'd2;
            dispatch0_enable = 1'b1;
            dispatch0_is_store = 1'b0;
            dispatch0_seq = sequence0;
            dispatch0_rob = rob_tag0;
            dispatch0_pdst = pdst0;
            dispatch0_writes = 1'b1;
            dispatch0_lsu_op = 3'b010;
            dispatch1_enable = 1'b1;
            dispatch1_is_store = 1'b0;
            dispatch1_seq = sequence1;
            dispatch1_rob = rob_tag1;
            dispatch1_pdst = pdst1;
            dispatch1_writes = 1'b1;
            dispatch1_lsu_op = 3'b010;
            #1;
            index0 = alloc_index0;
            index1 = alloc_index1;
            if (index0 == index1)
                $fatal(1, "dual load dispatch received duplicate LSQ index");
            @(posedge clk);
            #1;
            @(negedge clk);
            dispatch_count = 2'd0;
            dispatch0_enable = 1'b0;
            dispatch1_enable = 1'b0;
        end
    endtask

    task automatic dispatch_store_and_load(
        input  [63:0] store_sequence,
        input  [2:0]  store_rob,
        input  [63:0] load_sequence,
        input  [2:0]  load_rob,
        output [2:0]  store_index,
        output [2:0]  load_index
    );
        begin
            @(negedge clk);
            dispatch_count = 2'd2;
            dispatch0_enable = 1'b1;
            dispatch0_is_store = 1'b1;
            dispatch0_seq = store_sequence;
            dispatch0_rob = store_rob;
            dispatch0_pdst = 6'b0;
            dispatch0_writes = 1'b0;
            dispatch0_lsu_op = 3'b111;
            dispatch1_enable = 1'b1;
            dispatch1_is_store = 1'b0;
            dispatch1_seq = load_sequence;
            dispatch1_rob = load_rob;
            dispatch1_pdst = 6'd39;
            dispatch1_writes = 1'b1;
            dispatch1_lsu_op = 3'b010;
            #1;
            store_index = alloc_index0;
            load_index = alloc_index1;
            if (store_index == load_index)
                $fatal(1, "store/load dispatch received duplicate LSQ index");
            @(posedge clk);
            #1;
            @(negedge clk);
            dispatch_count = 2'd0;
            dispatch0_enable = 1'b0;
            dispatch1_enable = 1'b0;
        end
    endtask

    task automatic capture_address(
        input [2:0]  index,
        input [31:0] address,
        input [31:0] write_data,
        input [3:0]  write_strobe,
        input [2:0]  lsu_op
    );
        begin
            @(negedge clk);
            agu_capture_valid = 1'b1;
            agu_capture_index = index;
            agu_addr = address;
            agu_wdata = write_data;
            agu_wstrb = write_strobe;
            agu_lsu_op = lsu_op;
            @(posedge clk);
            #1;
            @(negedge clk);
            agu_capture_valid = 1'b0;
        end
    endtask

    task automatic grant_load_result;
        begin
            @(negedge clk);
            load_result_grant = 1'b1;
            @(posedge clk);
            #1;
            if (load_result_valid)
                $fatal(1, "load result did not clear after grant");
            @(negedge clk);
            load_result_grant = 1'b0;
        end
    endtask

    integer latency_cycle;
    integer hold_cycle;
    logic [2:0] saved_index0;
    logic [2:0] saved_index1;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        flush = 1'b0;

        m_start_valid = 1'b0;
        m_use_signal = 7'b0;
        m_mul_result = 32'b0;
        m_div_result = 32'b0;
        m_start_rob = 3'b0;
        m_start_pdst = 6'b0;
        m_start_writes = 1'b0;
        m_result_grant = 1'b0;

        load_valid = 1'b0;
        muldiv_valid = 1'b0;
        int0_valid = 1'b0;
        int1_valid = 1'b0;
        ext_lsu_op = 3'b0;
        ext_raw_data = 32'b0;

        dispatch_count = 2'b0;
        dispatch0_enable = 1'b0;
        dispatch0_is_store = 1'b0;
        dispatch0_seq = 64'b0;
        dispatch0_rob = 3'b0;
        dispatch0_pdst = 6'b0;
        dispatch0_writes = 1'b0;
        dispatch0_lsu_op = 3'b0;
        dispatch1_enable = 1'b0;
        dispatch1_is_store = 1'b0;
        dispatch1_seq = 64'b0;
        dispatch1_rob = 3'b0;
        dispatch1_pdst = 6'b0;
        dispatch1_writes = 1'b0;
        dispatch1_lsu_op = 3'b0;
        agu_capture_valid = 1'b0;
        agu_capture_index = 3'b0;
        agu_addr = 32'b0;
        agu_wdata = 32'b0;
        agu_wstrb = 4'b0;
        agu_lsu_op = 3'b0;
        rob_head_valid = 1'b0;
        rob_head_tag = 3'b0;
        rob_head_is_store = 1'b0;
        barrier_valid = 1'b0;
        barrier_seq = 64'b0;
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        dm_resp_rdata = 32'b0;
        dm_req_wready = 1'b0;
        dm_resp_wvalid = 1'b0;
        load_result_grant = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        #1;
        if ((free_count !== 4'd8) || !memory_idle)
            $fatal(1, "LSQ reset state is incorrect");

        // All five load extension modes.
        ext_raw_data = 32'h0000_0080;
        ext_lsu_op = 3'b000;
        #1;
        if (ext_value !== 32'hffff_ff80)
            $fatal(1, "LB extension failed");
        ext_lsu_op = 3'b011;
        #1;
        if (ext_value !== 32'h0000_0080)
            $fatal(1, "LBU extension failed");
        ext_raw_data = 32'h0000_8001;
        ext_lsu_op = 3'b001;
        #1;
        if (ext_value !== 32'hffff_8001)
            $fatal(1, "LH extension failed");
        ext_lsu_op = 3'b100;
        #1;
        if (ext_value !== 32'h0000_8001)
            $fatal(1, "LHU extension failed");
        ext_raw_data = 32'h89ab_cdef;
        ext_lsu_op = 3'b010;
        #1;
        if (ext_value !== 32'h89ab_cdef)
            $fatal(1, "LW formatting failed");

        // CDB priority: load > M > int0 > int1, with two grants maximum.
        load_valid = 1'b1;
        muldiv_valid = 1'b1;
        int0_valid = 1'b1;
        int1_valid = 1'b1;
        #1;
        if (!cdb0_valid || !cdb1_valid || (cdb0_rob !== 3'd1) ||
            !cdb0_writes || (cdb0_pdst !== 6'd33) ||
            (cdb0_value !== 32'h1111_1111) || cdb0_control ||
            (cdb0_target !== 32'h0000_0100) || cdb0_mispredict ||
            (cdb1_rob !== 3'd2) || !cdb1_writes ||
            (cdb1_pdst !== 6'd34) ||
            (cdb1_value !== 32'h2222_2222) || cdb1_control ||
            (cdb1_target !== 32'h0000_0200) || cdb1_mispredict ||
            !load_grant || !muldiv_grant || int0_grant || int1_grant)
            $fatal(1, "CDB load/M priority failed");
        load_valid = 1'b0;
        #1;
        if (!cdb0_valid || !cdb1_valid || (cdb0_rob !== 3'd2) ||
            (cdb1_rob !== 3'd3) || !muldiv_grant || !int0_grant ||
            load_grant || int1_grant)
            $fatal(1, "CDB M/int0 priority failed");
        muldiv_valid = 1'b0;
        #1;
        if (!cdb0_valid || !cdb1_valid || (cdb0_rob !== 3'd3) ||
            (cdb1_rob !== 3'd4) || !int0_grant || !int1_grant ||
            load_grant || muldiv_grant)
            $fatal(1, "CDB int0/int1 priority failed");
        int0_valid = 1'b0;
        #1;
        if (!cdb0_valid || cdb1_valid || (cdb0_rob !== 3'd4) ||
            !int1_grant)
            $fatal(1, "CDB single int1 selection failed");
        int1_valid = 1'b0;

        // M metadata and value appear after exactly twelve rising edges.
        @(negedge clk);
        m_use_signal = 7'b0001000;
        m_mul_result = 32'h1357_9bdf;
        m_div_result = 32'hdead_beef;
        m_start_rob = 3'd5;
        m_start_pdst = 6'd40;
        m_start_writes = 1'b1;
        m_start_valid = 1'b1;
        #1;
        if (!m_start_ready || !m_start_fire)
            $fatal(1, "M tracker rejected an idle start");
        @(posedge clk);
        #1;
        if (!m_busy || m_result_valid)
            $fatal(1, "M tracker start state failed");
        @(negedge clk);
        m_start_valid = 1'b0;
        for (latency_cycle = 1; latency_cycle <= 11;
             latency_cycle = latency_cycle + 1) begin
            @(posedge clk);
            #1;
            if (m_result_valid)
                $fatal(1, "M result was early at cycle %0d", latency_cycle);
        end
        @(posedge clk);
        #1;
        if (!m_result_valid || !m_busy ||
            (m_result_value !== 32'h1357_9bdf) ||
            (m_result_rob !== 3'd5) || (m_result_pdst !== 6'd40) ||
            !m_result_writes)
            $fatal(1, "M result timing or metadata failed");
        for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
            @(posedge clk);
            #1;
            if (!m_result_valid ||
                (m_result_value !== 32'h1357_9bdf))
                $fatal(1, "M result was not held for grant");
        end
        @(negedge clk);
        m_result_grant = 1'b1;
        @(posedge clk);
        #1;
        if (m_result_valid || m_busy)
            $fatal(1, "M result did not clear after grant");
        @(negedge clk);
        m_result_grant = 1'b0;

        // Load request must hold through memory backpressure.  Acceptance and
        // response may occur together, and the formatted result must hold.
        dispatch_one_load(64'd1, 3'd1, 6'd33, 3'b000, saved_index0);
        capture_address(saved_index0, 32'h0000_0040,
                        32'b0, 4'b0, 3'b000);
        @(posedge clk);
        #1;
        if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0040))
            $fatal(1, "backpressured load request was not prepared");
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0040) ||
                memory_idle)
                $fatal(1, "load request did not hold under backpressure");
        end
        @(negedge clk);
        dm_req_rready = 1'b1;
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'h0000_0080;
        @(posedge clk);
        #1;
        if (!load_result_valid || (load_result_rob !== 3'd1) ||
            (load_result_pdst !== 6'd33) || !load_result_writes ||
            (load_result_value !== 32'hffff_ff80))
            $fatal(1, "same-cycle load acceptance/response failed");
        @(negedge clk);
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!load_result_valid || memory_idle)
                $fatal(1, "load result was not held for CDB grant");
        end
        grant_load_result();
        if (free_count !== 4'd8)
            $fatal(1, "completed load did not release its LSQ entry");

        // Loads execute in program order even if the younger address arrives
        // first.  The old load must complete and be granted before the young
        // request can be prepared.
        dispatch_two_loads(64'd10, 3'd2, 6'd34,
                           64'd11, 3'd3, 6'd35,
                           saved_index0, saved_index1);
        capture_address(saved_index1, 32'h0000_0110,
                        32'b0, 4'b0, 3'b010);
        repeat (3) begin
            @(posedge clk);
            #1;
            if (dm_req_rvalid)
                $fatal(1, "younger load bypassed an older load");
        end
        capture_address(saved_index0, 32'h0000_0100,
                        32'b0, 4'b0, 3'b010);
        @(posedge clk);
        #1;
        if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0100))
            $fatal(1, "oldest load was not selected first");
        @(negedge clk);
        dm_req_rready = 1'b1;
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'haaaa_0001;
        @(posedge clk);
        #1;
        if (!load_result_valid || (load_result_rob !== 3'd2) ||
            (load_result_value !== 32'haaaa_0001))
            $fatal(1, "oldest load completion failed");
        @(negedge clk);
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        grant_load_result();
        @(posedge clk);
        #1;
        if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0110))
            $fatal(1, "younger load did not follow the older load");
        @(negedge clk);
        dm_req_rready = 1'b1;
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'hbbbb_0002;
        @(posedge clk);
        #1;
        if (!load_result_valid || (load_result_rob !== 3'd3) ||
            (load_result_value !== 32'hbbbb_0002))
            $fatal(1, "younger load completion failed");
        @(negedge clk);
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        grant_load_result();

        // An older control/FENCE barrier blocks a ready load.
        dispatch_one_load(64'd21, 3'd4, 6'd36, 3'b010, saved_index0);
        barrier_valid = 1'b1;
        barrier_seq = 64'd20;
        capture_address(saved_index0, 32'h0000_0200,
                        32'b0, 4'b0, 3'b010);
        repeat (3) begin
            @(posedge clk);
            #1;
            if (dm_req_rvalid)
                $fatal(1, "load bypassed an older control barrier");
        end
        @(negedge clk);
        barrier_valid = 1'b0;
        @(posedge clk);
        #1;
        if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0200))
            $fatal(1, "load did not issue after barrier removal");
        @(negedge clk);
        dm_req_rready = 1'b1;
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'hcccc_0003;
        @(posedge clk);
        #1;
        if (!load_result_valid || (load_result_rob !== 3'd4))
            $fatal(1, "post-barrier load completion failed");
        @(negedge clk);
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        grant_load_result();

        // An older store blocks the younger load.  A store may issue only as
        // ROB head.  Keep the head indication asserted after its response to
        // exercise the retirement window fixed in lsq.v.
        dispatch_store_and_load(64'd30, 3'd5, 64'd31, 3'd6,
                                saved_index0, saved_index1);
        rob_head_valid = 1'b1;
        rob_head_is_store = 1'b1;
        rob_head_tag = 3'd5;
        capture_address(saved_index1, 32'h0000_0310,
                        32'b0, 4'b0, 3'b010);
        repeat (3) begin
            @(posedge clk);
            #1;
            if (dm_req_rvalid || dm_req_wvalid)
                $fatal(1, "memory request escaped before head-store address");
        end
        capture_address(saved_index0, 32'h0000_0300,
                        32'ha5a5_5a5a, 4'b1100, 3'b111);
        @(posedge clk);
        #1;
        if (!dm_req_wvalid || dm_req_rvalid ||
            (dm_req_addr !== 32'h0000_0300) ||
            (dm_req_wdata !== 32'ha5a5_5a5a) ||
            (dm_req_wstrb !== 4'b1100))
            $fatal(1, "ROB-head store request failed");
        @(posedge clk);
        #1;
        if (!dm_req_wvalid || dm_req_rvalid)
            $fatal(1, "head store request did not hold for acceptance");
        @(negedge clk);
        dm_req_wready = 1'b1;
        dm_resp_wvalid = 1'b1;
        @(posedge clk);
        #1;
        if (!store_complete_valid || (store_complete_rob !== 3'd5) ||
            (free_count !== 4'd7))
            $fatal(1, "ROB-head store completion failed");
        @(negedge clk);
        dm_req_wready = 1'b0;
        dm_resp_wvalid = 1'b0;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (dm_req_rvalid || dm_req_wvalid)
                $fatal(1, "young load prepared before head store retired");
        end
        @(negedge clk);
        rob_head_valid = 1'b0;
        rob_head_is_store = 1'b0;
        @(posedge clk);
        #1;
        if (!dm_req_rvalid || (dm_req_addr !== 32'h0000_0310))
            $fatal(1, "young load did not issue after store retirement");
        @(negedge clk);
        dm_req_rready = 1'b1;
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'hdddd_0004;
        @(posedge clk);
        #1;
        if (!load_result_valid || (load_result_rob !== 3'd6))
            $fatal(1, "load after older store did not complete");
        @(negedge clk);
        dm_req_rready = 1'b0;
        dm_resp_rvalid = 1'b0;
        grant_load_result();

        // Flush cancels an unaccepted request immediately.
        dispatch_one_load(64'd40, 3'd7, 6'd41, 3'b010, saved_index0);
        capture_address(saved_index0, 32'h0000_0400,
                        32'b0, 4'b0, 3'b010);
        @(posedge clk);
        #1;
        if (!dm_req_rvalid)
            $fatal(1, "flush-cancel request was not prepared");
        @(negedge clk);
        flush = 1'b1;
        #1;
        if (dm_req_rvalid)
            $fatal(1, "flush did not suppress an unaccepted request");
        @(posedge clk);
        #1;
        if (!memory_idle || load_result_valid || (free_count !== 4'd8))
            $fatal(1, "flush did not cancel unaccepted request state");
        @(negedge clk);
        flush = 1'b0;

        // Once accepted, a flushed request remains non-idle until its late
        // response is drained and dropped.  No architectural result may leak.
        dispatch_one_load(64'd41, 3'd0, 6'd42, 3'b010, saved_index0);
        capture_address(saved_index0, 32'h0000_0410,
                        32'b0, 4'b0, 3'b010);
        @(posedge clk);
        #1;
        if (!dm_req_rvalid)
            $fatal(1, "flush-drain request was not prepared");
        @(negedge clk);
        dm_req_rready = 1'b1;
        @(posedge clk);
        #1;
        if (memory_idle || dm_req_rvalid)
            $fatal(1, "accepted load did not enter outstanding state");
        @(negedge clk);
        dm_req_rready = 1'b0;
        flush = 1'b1;
        @(posedge clk);
        #1;
        if (memory_idle || load_result_valid || (free_count !== 4'd8))
            $fatal(1, "flush failed to preserve response-drain state");
        @(negedge clk);
        flush = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            if (memory_idle || load_result_valid)
                $fatal(1, "flushed request stopped waiting for drain");
        end
        @(negedge clk);
        dm_resp_rvalid = 1'b1;
        dm_resp_rdata = 32'hffff_ffff;
        @(posedge clk);
        #1;
        if (!memory_idle || load_result_valid || store_complete_valid ||
            (free_count !== 4'd8))
            $fatal(1, "late flushed response was not drained and dropped");
        @(negedge clk);
        dm_resp_rvalid = 1'b0;

        $display("OOO_LSQ_EXEC_TEST PASS");
        $finish;
    end

endmodule
