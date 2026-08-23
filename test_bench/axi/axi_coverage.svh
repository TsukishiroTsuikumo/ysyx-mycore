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

    longint unsigned total_read;
    longint unsigned total_write;
    longint unsigned channel_backpressure_hits[0:4];
    longint unsigned read_len_hits[0:255];
    longint unsigned write_len_hits[0:255];
    longint unsigned read_size_hits[0:7];
    longint unsigned write_size_hits[0:7];
    longint unsigned read_burst_hits[0:3];
    longint unsigned write_burst_hits[0:3];
    longint unsigned read_resp_hits[0:3];
    longint unsigned write_resp_hits[0:3];
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
    longint unsigned owner_id_errors;
    int unsigned acceptance_errors;

    bit require_backpressure_coverage;
    bit require_owner_coverage;
    bit require_last_error_coverage;
    bit require_cache_line_traffic;

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        total_read = 0;
        total_write = 0;
        foreach (channel_backpressure_hits[i]) channel_backpressure_hits[i] = 0;
        foreach (read_len_hits[i]) read_len_hits[i] = 0;
        foreach (write_len_hits[i]) write_len_hits[i] = 0;
        foreach (read_size_hits[i]) read_size_hits[i] = 0;
        foreach (write_size_hits[i]) write_size_hits[i] = 0;
        foreach (read_burst_hits[i]) read_burst_hits[i] = 0;
        foreach (write_burst_hits[i]) write_burst_hits[i] = 0;
        foreach (read_resp_hits[i]) read_resp_hits[i] = 0;
        foreach (write_resp_hits[i]) write_resp_hits[i] = 0;
        foreach (read_last_hits[i]) read_last_hits[i] = 0;
        foreach (write_last_hits[i]) write_last_hits[i] = 0;
        foreach (read_beat_count_hits[i]) read_beat_count_hits[i] = 0;
        foreach (write_beat_count_hits[i]) write_beat_count_hits[i] = 0;
        cache_line_read_ok = 0;
        cache_line_write_ok = 0;
        cache_line_shape_errors = 0;
        response_error_count = 0;
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
    endfunction

    virtual function void write(txn_t txn);
        int unsigned owner_idx;
        int unsigned burst_idx;
        bit line_shape_ok;
        bit response_ok;

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

        if (txn.direction == AXI_WRITE) begin
            total_write++;
            write_owner_hits[owner_idx]++;
            write_len_hits[txn.len]++;
            write_size_hits[txn.size]++;
            write_burst_hits[burst_idx]++;
            write_resp_hits[txn.bresp]++;
            write_last_hits[txn.last_ok]++;
            write_beat_count_hits[txn.beat_count_ok]++;
            write_owner_burst_hits[owner_idx][burst_idx]++;

            if (txn.aw_backpressure) channel_backpressure_hits[AW_CH]++;
            if (txn.w_backpressure)  channel_backpressure_hits[W_CH]++;
            if (txn.b_backpressure)  channel_backpressure_hits[B_CH]++;

            if ((txn.owner != 1) || (txn.id != 1)) owner_id_errors++;

            response_ok = (txn.bresp == AXI_RESP_OKAY);
            if (!response_ok) response_error_count++;
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
                if (txn.resp_q[i] != AXI_RESP_OKAY) response_ok = 1'b0;
            end
            read_last_hits[txn.last_ok]++;
            read_beat_count_hits[txn.beat_count_ok]++;
            read_owner_burst_hits[owner_idx][burst_idx]++;

            if (txn.ar_backpressure) channel_backpressure_hits[AR_CH]++;
            if (txn.r_backpressure)  channel_backpressure_hits[R_CH]++;

            if (!(((txn.owner == 0) && (txn.id == 0)) ||
                  ((txn.owner == 1) && (txn.id == 1)))) begin
                owner_id_errors++;
            end

            if (!response_ok) response_error_count++;
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
            if (response_error_count != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "observed %0d transaction(s) with non-OKAY response",
                    response_error_count))
            end
            if (owner_id_errors != 0) begin
                acceptance_errors++;
                `uvm_error("AXI_ACCEPTANCE", $sformatf(
                    "observed %0d transaction(s) with invalid owner/ID mapping",
                    owner_id_errors))
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

        if (require_cache_line_traffic) begin
            `uvm_info("AXI_ACCEPTANCE", $sformatf(
                "status=%s line_read_ok=%0d line_write_ok=%0d shape_errors=%0d response_errors=%0d owner_id_errors=%0d",
                (acceptance_errors == 0) ? "PASS" : "FAIL",
                cache_line_read_ok, cache_line_write_ok,
                cache_line_shape_errors, response_error_count,
                owner_id_errors), UVM_LOW)
        end
    endfunction

endclass

`endif
