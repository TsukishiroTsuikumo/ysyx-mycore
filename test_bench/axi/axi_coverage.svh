`ifndef YSYX_AXI_COVERAGE_SVH
`define YSYX_AXI_COVERAGE_SVH

// Explicit-bin functional coverage.  This deliberately avoids covergroup so
// the same component works on Verilator builds whose covergroup support differs
// from commercial simulators.  The counters are still semantic coverage bins
// and can be made test gates through the require_* configuration bits.
class axi_coverage #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_subscriber #(
    axi_transaction #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH)
);

    typedef axi_coverage #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;

    `uvm_component_param_utils(this_type)

    localparam int AW_CH = 0;
    localparam int W_CH  = 1;
    localparam int B_CH  = 2;
    localparam int AR_CH = 3;
    localparam int R_CH  = 4;
    localparam int CACHE_LINE_LEN  = 3; // Four 32-bit beats = 16 bytes.
    localparam int CACHE_LINE_SIZE = $clog2(DATA_WIDTH / 8);
    localparam bit [ADDR_WIDTH-1:0] EXPECTED_SLVERR_ADDR = 'h800;
    localparam bit [ADDR_WIDTH-1:0] EXPECTED_DECERR_ADDR = 'h900;

    longint unsigned total_read;
    longint unsigned total_write;
    // Transaction hit counts and actual VALID&&!READY cycle counts are kept
    // separately.  This prevents a one-cycle boolean hit from masquerading as
    // meaningful channel stress.
    longint unsigned channel_backpressure_hits[0:4];
    longint unsigned channel_stall_cycles[0:4];
    longint unsigned read_len_hits[0:255];
    longint unsigned write_len_hits[0:255];
    longint unsigned read_size_hits[0:7];
    longint unsigned write_size_hits[0:7];
    longint unsigned read_burst_hits[0:3];
    longint unsigned write_burst_hits[0:3];
    longint unsigned read_resp_hits[0:3];
    longint unsigned write_resp_hits[0:3];
    longint unsigned read_response_txn_hits[0:3];
    longint unsigned write_response_txn_hits[0:3];
    longint unsigned read_owner_hits[int unsigned];
    longint unsigned write_owner_hits[int unsigned];
    longint unsigned read_last_hits[0:1];
    longint unsigned write_last_hits[0:1];
    longint unsigned read_beat_count_hits[0:1];
    longint unsigned write_beat_count_hits[0:1];
    longint unsigned read_owner_burst_hits[int unsigned][int unsigned];
    longint unsigned write_owner_burst_hits[int unsigned][int unsigned];
    longint unsigned cache_line_read_ok;
    longint unsigned cache_line_write_ok;
    longint unsigned cache_line_shape_errors;
    longint unsigned response_error_count;
    longint unsigned unexpected_response_error_count;
    longint unsigned expected_read_error_ok;
    longint unsigned expected_write_error_ok;
    longint unsigned expected_read_slverr_ok;
    longint unsigned expected_read_decerr_ok;
    longint unsigned expected_write_slverr_ok;
    longint unsigned expected_write_decerr_ok;
    longint unsigned partial_write_ok;
    longint unsigned full_strobe_write_ok;
    longint unsigned single_byte_strobe_write_ok;
    longint unsigned multi_byte_strobe_write_ok;
    longint unsigned zero_strobe_write_ok;
    longint unsigned owner_id_errors;
    int unsigned acceptance_errors;

    bit require_backpressure_coverage;
    bit require_owner_coverage;
    bit require_last_error_coverage;
    bit require_cache_line_traffic;
    bit require_error_response_coverage;
    bit require_partial_strobe_coverage;
    bit require_random_stress_coverage;

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        total_read = 0;
        total_write = 0;
        foreach (channel_backpressure_hits[i]) channel_backpressure_hits[i] = 0;
        foreach (channel_stall_cycles[i]) channel_stall_cycles[i] = 0;
        foreach (read_len_hits[i]) read_len_hits[i] = 0;
        foreach (write_len_hits[i]) write_len_hits[i] = 0;
        foreach (read_size_hits[i]) read_size_hits[i] = 0;
        foreach (write_size_hits[i]) write_size_hits[i] = 0;
        foreach (read_burst_hits[i]) read_burst_hits[i] = 0;
        foreach (write_burst_hits[i]) write_burst_hits[i] = 0;
        foreach (read_resp_hits[i]) read_resp_hits[i] = 0;
        foreach (write_resp_hits[i]) write_resp_hits[i] = 0;
        foreach (read_response_txn_hits[i]) read_response_txn_hits[i] = 0;
        foreach (write_response_txn_hits[i]) write_response_txn_hits[i] = 0;
        foreach (read_last_hits[i]) read_last_hits[i] = 0;
        foreach (write_last_hits[i]) write_last_hits[i] = 0;
        foreach (read_beat_count_hits[i]) read_beat_count_hits[i] = 0;
        foreach (write_beat_count_hits[i]) write_beat_count_hits[i] = 0;
        cache_line_read_ok = 0;
        cache_line_write_ok = 0;
        cache_line_shape_errors = 0;
        response_error_count = 0;
        unexpected_response_error_count = 0;
        expected_read_error_ok = 0;
        expected_write_error_ok = 0;
        expected_read_slverr_ok = 0;
        expected_read_decerr_ok = 0;
        expected_write_slverr_ok = 0;
        expected_write_decerr_ok = 0;
        partial_write_ok = 0;
        full_strobe_write_ok = 0;
        single_byte_strobe_write_ok = 0;
        multi_byte_strobe_write_ok = 0;
        zero_strobe_write_ok = 0;
        owner_id_errors = 0;
        acceptance_errors = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(bit)::get(
            this, "", "require_backpressure_coverage", require_backpressure_coverage));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_owner_coverage", require_owner_coverage));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_last_error_coverage", require_last_error_coverage));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_cache_line_traffic",
            require_cache_line_traffic));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_error_response_coverage",
            require_error_response_coverage));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_partial_strobe_coverage",
            require_partial_strobe_coverage));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_random_stress_coverage",
            require_random_stress_coverage));
    endfunction

    function automatic int unsigned strobe_popcount(
        input bit [DATA_WIDTH/8-1:0] strobe
    );
        int unsigned count;
        count = 0;
        foreach (strobe[i]) count += strobe[i];
        return count;
    endfunction

    function longint unsigned protocol_error_count();
        return cache_line_shape_errors + owner_id_errors +
               unexpected_response_error_count;
    endfunction

    virtual function void write(txn_t txn);
        int unsigned owner_idx;
        int unsigned burst_idx;
        bit line_shape_ok;
        bit response_ok;
        bit expected_error_txn;
        bit expected_error_resp_ok;
        bit partial_strobe;
        bit full_strobe;
        bit single_byte_strobe;
        bit multi_byte_strobe;
        bit zero_strobe;
        bit read_response_uniform;
        bit [1:0] expected_error_resp;
        bit [1:0] observed_read_resp;
        int unsigned strobe_ones;

        if (txn == null) begin
            `uvm_error("AXI_COVERAGE", "Received null transaction")
            return;
        end

        owner_idx = int'(txn.owner);
        burst_idx = int'(txn.burst);
        line_shape_ok = (txn.len == CACHE_LINE_LEN) &&
                        (txn.size == CACHE_LINE_SIZE) &&
                        (txn.burst == AXI_BURST_INCR) &&
                        txn.last_ok && txn.beat_count_ok;
        response_ok = 1'b1;
        expected_error_txn = require_error_response_coverage &&
                             ((txn.addr == EXPECTED_SLVERR_ADDR) ||
                              (require_random_stress_coverage &&
                               (txn.addr == EXPECTED_DECERR_ADDR)));
        expected_error_resp = (txn.addr == EXPECTED_DECERR_ADDR) ?
                              AXI_RESP_DECERR : AXI_RESP_SLVERR;
        expected_error_resp_ok = 1'b1;
        partial_strobe = 1'b0;
        full_strobe = 1'b0;
        single_byte_strobe = 1'b0;
        multi_byte_strobe = 1'b0;
        zero_strobe = 1'b0;
        read_response_uniform = 1'b1;
        observed_read_resp = AXI_RESP_OKAY;

        if (txn.direction == AXI_WRITE) begin
            total_write++;
            write_owner_hits[owner_idx]++;
            write_len_hits[txn.len]++;
            write_size_hits[txn.size]++;
            write_burst_hits[burst_idx]++;
            write_resp_hits[txn.bresp]++;
            write_response_txn_hits[txn.bresp]++;
            write_last_hits[txn.last_ok]++;
            write_beat_count_hits[txn.beat_count_ok]++;
            write_owner_burst_hits[owner_idx][burst_idx]++;

            foreach (txn.strb_q[i]) begin
                strobe_ones = strobe_popcount(txn.strb_q[i]);
                if (strobe_ones == 0) zero_strobe = 1'b1;
                else if (strobe_ones == 1) begin
                    single_byte_strobe = 1'b1;
                    partial_strobe = 1'b1;
                end
                else if (strobe_ones == (DATA_WIDTH/8))
                    full_strobe = 1'b1;
                else begin
                    multi_byte_strobe = 1'b1;
                    partial_strobe = 1'b1;
                end
            end
            // Required strobe bins describe writes that were actually
            // accepted by the test memory.  Error-response writes are sampled
            // for response coverage but cannot satisfy data-shape gates.
            if (txn.bresp == AXI_RESP_OKAY) begin
                if (partial_strobe) partial_write_ok++;
                if (full_strobe) full_strobe_write_ok++;
                if (single_byte_strobe) single_byte_strobe_write_ok++;
                if (multi_byte_strobe) multi_byte_strobe_write_ok++;
                if (zero_strobe) zero_strobe_write_ok++;
            end

            if (txn.aw_stall_cycles != 0) channel_backpressure_hits[AW_CH]++;
            if (txn.w_stall_cycles != 0)  channel_backpressure_hits[W_CH]++;
            if (txn.b_stall_cycles != 0)  channel_backpressure_hits[B_CH]++;
            channel_stall_cycles[AW_CH] += txn.aw_stall_cycles;
            channel_stall_cycles[W_CH]  += txn.w_stall_cycles;
            channel_stall_cycles[B_CH]  += txn.b_stall_cycles;

            if ((txn.owner != 1) || (txn.id != 1)) owner_id_errors++;

            response_ok = (txn.bresp == AXI_RESP_OKAY);
            if (!response_ok) response_error_count++;
            expected_error_resp_ok = (txn.bresp == expected_error_resp);
            if (expected_error_txn) begin
                if (expected_error_resp_ok) begin
                    expected_write_error_ok++;
                    if (expected_error_resp == AXI_RESP_SLVERR)
                        expected_write_slverr_ok++;
                    else
                        expected_write_decerr_ok++;
                end
                else
                    unexpected_response_error_count++;
            end
            else if (!response_ok) begin
                unexpected_response_error_count++;
            end
            if (line_shape_ok && response_ok)
                cache_line_write_ok++;
            else if (!line_shape_ok)
                cache_line_shape_errors++;
        end
        else begin
            total_read++;
            read_owner_hits[owner_idx]++;
            read_len_hits[txn.len]++;
            read_size_hits[txn.size]++;
            read_burst_hits[burst_idx]++;
            foreach (txn.resp_q[i]) begin
                read_resp_hits[txn.resp_q[i]]++;
                if (i == 0) observed_read_resp = txn.resp_q[i];
                else if (txn.resp_q[i] != observed_read_resp)
                    read_response_uniform = 1'b0;
                if (txn.resp_q[i] != AXI_RESP_OKAY) response_ok = 1'b0;
                if (txn.resp_q[i] != expected_error_resp)
                    expected_error_resp_ok = 1'b0;
            end
            if ((txn.resp_q.size() != 0) && read_response_uniform)
                read_response_txn_hits[observed_read_resp]++;
            read_last_hits[txn.last_ok]++;
            read_beat_count_hits[txn.beat_count_ok]++;
            read_owner_burst_hits[owner_idx][burst_idx]++;

            if (txn.ar_stall_cycles != 0) channel_backpressure_hits[AR_CH]++;
            if (txn.r_stall_cycles != 0)  channel_backpressure_hits[R_CH]++;
            channel_stall_cycles[AR_CH] += txn.ar_stall_cycles;
            channel_stall_cycles[R_CH]  += txn.r_stall_cycles;

            if (!(((txn.owner == 0) && (txn.id == 0)) ||
                  ((txn.owner == 1) && (txn.id == 1)))) begin
                owner_id_errors++;
            end

            if (!response_ok) response_error_count++;
            if (expected_error_txn) begin
                if (expected_error_resp_ok && read_response_uniform &&
                    (txn.resp_q.size() == txn.expected_beats())) begin
                    expected_read_error_ok++;
                    if (expected_error_resp == AXI_RESP_SLVERR)
                        expected_read_slverr_ok++;
                    else
                        expected_read_decerr_ok++;
                end
                else
                    unexpected_response_error_count++;
            end
            else if (!response_ok) begin
                unexpected_response_error_count++;
            end
            if (line_shape_ok && response_ok)
                cache_line_read_ok++;
            else if (!line_shape_ok)
                cache_line_shape_errors++;
        end
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (require_backpressure_coverage) begin
            foreach (channel_backpressure_hits[i]) begin
                if (channel_backpressure_hits[i] == 0) begin
                    `uvm_error("AXI_COVERAGE", $sformatf(
                        "missing backpressure coverage on channel index %0d (AW=0 W=1 B=2 AR=3 R=4)", i))
                end
            end
        end

        if (require_owner_coverage) begin
            if (!read_owner_hits.exists(0))
                `uvm_error("AXI_COVERAGE", "missing instruction-owner read coverage")
            if (!read_owner_hits.exists(1))
                `uvm_error("AXI_COVERAGE", "missing data-owner read coverage")
            if (!write_owner_hits.exists(1))
                `uvm_error("AXI_COVERAGE", "missing data-owner write coverage")
        end

        // Error bins are useful in negative protocol tests but are not required
        // for ordinary smoke/regression tests unless explicitly requested.
        if (require_last_error_coverage) begin
            if (read_last_hits[0] == 0 || write_last_hits[0] == 0)
                `uvm_error("AXI_COVERAGE", "missing malformed LAST negative-test coverage")
        end

        // End-to-end cache/program tests enable this gate. It turns the passive
        // observer into an automatic acceptance path without requiring an
        // active AXI driver: at least one complete line read must be seen, all
        // shared-bus requests must be four-beat line bursts, and responses must
        // be successful.
        if (require_cache_line_traffic) begin
            if (total_read == 0 || cache_line_read_ok == 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE",
                    "no complete successful cache-line read observed")
            end
            if (cache_line_shape_errors != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "observed %0d transaction(s) with invalid line LEN/SIZE/BURST/LAST",
                    cache_line_shape_errors))
            end
            if (unexpected_response_error_count != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "observed %0d unexpected/missing response-error transaction(s)",
                    unexpected_response_error_count))
            end
            if (owner_id_errors != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "observed %0d transaction(s) with invalid owner/ID mapping",
                    owner_id_errors))
            end
            if (require_error_response_coverage &&
                (expected_read_error_ok == 0 ||
                 expected_write_error_ok == 0)) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "missing expected SLVERR coverage read=%0d write=%0d",
                    expected_read_error_ok, expected_write_error_ok))
            end
            if (require_partial_strobe_coverage && partial_write_ok == 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE",
                    "missing partial-write strobe coverage")
            end
        end

        if (require_random_stress_coverage) begin
            if (total_read != 32 || total_write != 32) begin
                acceptance_errors++;
                `uvm_error("AXI_RANDOM_COVERAGE", $sformatf(
                    "expected exactly 32 reads and 32 writes, got read=%0d write=%0d",
                    total_read, total_write))
            end
            if (!read_owner_hits.exists(0) || read_owner_hits[0] < 8 ||
                !read_owner_hits.exists(1) || read_owner_hits[1] < 8) begin
                acceptance_errors++;
                `uvm_error("AXI_RANDOM_COVERAGE", $sformatf(
                    "owner-read minimum missed I=%0d D=%0d",
                    read_owner_hits.exists(0) ? read_owner_hits[0] : 0,
                    read_owner_hits.exists(1) ? read_owner_hits[1] : 0))
            end
            foreach (channel_backpressure_hits[i]) begin
                if (channel_backpressure_hits[i] < 4 ||
                    channel_stall_cycles[i] < 8) begin
                    acceptance_errors++;
                    `uvm_error("AXI_RANDOM_COVERAGE", $sformatf(
                        "channel %0d backpressure below threshold txns=%0d cycles=%0d",
                        i, channel_backpressure_hits[i],
                        channel_stall_cycles[i]))
                end
            end
            if (full_strobe_write_ok == 0 ||
                single_byte_strobe_write_ok == 0 ||
                multi_byte_strobe_write_ok == 0 ||
                zero_strobe_write_ok == 0) begin
                acceptance_errors++;
                `uvm_error("AXI_RANDOM_COVERAGE", $sformatf(
                    "strobe bins missing full=%0d single=%0d multi=%0d zero=%0d",
                    full_strobe_write_ok, single_byte_strobe_write_ok,
                    multi_byte_strobe_write_ok, zero_strobe_write_ok))
            end
            if (read_response_txn_hits[AXI_RESP_OKAY] == 0 ||
                write_response_txn_hits[AXI_RESP_OKAY] == 0 ||
                expected_read_slverr_ok == 0 ||
                expected_read_decerr_ok == 0 ||
                expected_write_slverr_ok == 0 ||
                expected_write_decerr_ok == 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ERROR_RESPONSE_COVERAGE", $sformatf(
                    "response bins missing r_ok=%0d w_ok=%0d r_slverr=%0d r_decerr=%0d w_slverr=%0d w_decerr=%0d",
                    read_response_txn_hits[AXI_RESP_OKAY],
                    write_response_txn_hits[AXI_RESP_OKAY],
                    expected_read_slverr_ok, expected_read_decerr_ok,
                    expected_write_slverr_ok, expected_write_decerr_ok))
            end
            if (protocol_error_count() != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_RANDOM_COVERAGE", $sformatf(
                    "protocol/shape/owner error count=%0d",
                    protocol_error_count()))
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_COVERAGE", $sformatf(
            "READ=%0d WRITE=%0d BP_AW=%0d BP_W=%0d BP_B=%0d BP_AR=%0d BP_R=%0d I_RD=%0d D_RD=%0d D_WR=%0d LAST_RD_OK=%0d LAST_RD_ERR=%0d LAST_WR_OK=%0d LAST_WR_ERR=%0d",
            total_read, total_write,
            channel_backpressure_hits[AW_CH], channel_backpressure_hits[W_CH],
            channel_backpressure_hits[B_CH], channel_backpressure_hits[AR_CH],
            channel_backpressure_hits[R_CH],
            read_owner_hits.exists(0) ? read_owner_hits[0] : 0,
            read_owner_hits.exists(1) ? read_owner_hits[1] : 0,
            write_owner_hits.exists(1) ? write_owner_hits[1] : 0,
            read_last_hits[1], read_last_hits[0],
            write_last_hits[1], write_last_hits[0]), UVM_LOW)

        if (require_random_stress_coverage) begin
            `uvm_info("AXI_RANDOM_BP", $sformatf(
                "AW_TXNS=%0d AW_CYCLES=%0d W_TXNS=%0d W_CYCLES=%0d B_TXNS=%0d B_CYCLES=%0d AR_TXNS=%0d AR_CYCLES=%0d R_TXNS=%0d R_CYCLES=%0d",
                channel_backpressure_hits[AW_CH], channel_stall_cycles[AW_CH],
                channel_backpressure_hits[W_CH], channel_stall_cycles[W_CH],
                channel_backpressure_hits[B_CH], channel_stall_cycles[B_CH],
                channel_backpressure_hits[AR_CH], channel_stall_cycles[AR_CH],
                channel_backpressure_hits[R_CH], channel_stall_cycles[R_CH]),
                UVM_LOW)
        end

        if (require_cache_line_traffic) begin
            `uvm_info("AXI_ACCEPTANCE", $sformatf(
                "status=%s line_read_ok=%0d line_write_ok=%0d shape_errors=%0d response_errors=%0d unexpected_response_errors=%0d expected_read_error_ok=%0d expected_write_error_ok=%0d partial_write_ok=%0d owner_id_errors=%0d",
                (acceptance_errors == 0) ? "PASS" : "FAIL",
                cache_line_read_ok, cache_line_write_ok,
                cache_line_shape_errors, response_error_count,
                unexpected_response_error_count,
                expected_read_error_ok, expected_write_error_ok,
                partial_write_ok,
                owner_id_errors), UVM_LOW)
        end
    endfunction

endclass

`endif
