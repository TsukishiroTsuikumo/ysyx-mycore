`ifndef YSYX_AXI_MONITOR_SVH
`define YSYX_AXI_MONITOR_SVH

// Internal capture for the AXI4 W channel.  AXI4 has no WID, so complete W
// bursts are paired with AW transactions in AW acceptance order.
class axi_w_capture #(
    int unsigned DATA_WIDTH = 32,
    int unsigned USER_WIDTH = 1
);
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    bit [DATA_WIDTH-1:0] data_q[$];
    bit [STRB_WIDTH-1:0] strb_q[$];
    bit                  last_q[$];
    bit [USER_WIDTH-1:0] user_q[$];
    bit                  backpressure;
endclass

class axi_monitor #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_monitor;

    typedef axi_monitor #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;
    typedef axi_w_capture #(DATA_WIDTH, USER_WIDTH) w_capture_t;
    typedef virtual axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_vif_t;

    `uvm_component_param_utils(this_type)

    axi_vif_t vif;
    uvm_analysis_port #(txn_t) analysis_port;

    txn_t aw_q[$];
    txn_t write_response_q[$];
    txn_t read_q[$];
    w_capture_t completed_w_q[$];
    w_capture_t current_w;

    bit aw_stall_seen;
    bit ar_stall_seen;

    int unsigned aw_count;
    int unsigned w_burst_count;
    int unsigned b_count;
    int unsigned ar_count;
    int unsigned r_burst_count;

    bit require_quiescent_end;

    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
        aw_count = 0;
        w_burst_count = 0;
        b_count = 0;
        ar_count = 0;
        r_burst_count = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_MONITOR", "Failed to get axi_if virtual interface")
        end
        void'(uvm_config_db#(bit)::get(
            this, "", "require_quiescent_end", require_quiescent_end));
    endfunction

    function txn_t create_txn(string name);
        txn_t txn;
        txn = txn_t::type_id::create(name);
        if (txn == null) begin
            `uvm_fatal("AXI_MONITOR", "Failed to create AXI transaction")
        end
        return txn;
    endfunction

    function void clear_state();
        aw_q.delete();
        write_response_q.delete();
        read_q.delete();
        completed_w_q.delete();
        current_w = null;
        aw_stall_seen = 1'b0;
        ar_stall_seen = 1'b0;
    endfunction

    function int find_write_response(input bit [ID_WIDTH-1:0] id);
        foreach (write_response_q[i]) begin
            if (write_response_q[i].id == id) return i;
        end
        return -1;
    endfunction

    function int find_read(input bit [ID_WIDTH-1:0] id);
        foreach (read_q[i]) begin
            if (read_q[i].id == id) return i;
        end
        return -1;
    endfunction

    function void sample_aw();
        txn_t txn;

        if (vif.awvalid && !vif.awready) aw_stall_seen = 1'b1;

        if (vif.awvalid && vif.awready) begin
            txn = create_txn("write_txn");
            txn.direction       = AXI_WRITE;
            txn.id              = vif.awid;
            txn.addr            = vif.awaddr;
            txn.len             = vif.awlen;
            txn.size            = vif.awsize;
            txn.burst           = axi_burst_e'(vif.awburst);
            txn.lock            = vif.awlock;
            txn.cache           = vif.awcache;
            txn.prot            = vif.awprot;
            txn.qos             = vif.awqos;
            txn.region          = vif.awregion;
            txn.address_user    = vif.awuser;
            txn.owner           = vif.aw_owner;
            txn.aw_backpressure = aw_stall_seen;
            aw_stall_seen       = 1'b0;
            aw_q.push_back(txn);
            aw_count++;
        end
    endfunction

    function void sample_w();
        if (vif.wvalid && current_w == null) current_w = new();

        if (vif.wvalid && !vif.wready) current_w.backpressure = 1'b1;

        if (vif.wvalid && vif.wready) begin
            current_w.data_q.push_back(vif.wdata);
            current_w.strb_q.push_back(vif.wstrb);
            current_w.last_q.push_back(vif.wlast);
            current_w.user_q.push_back(vif.wuser);

            if (vif.wlast) begin
                completed_w_q.push_back(current_w);
                current_w = null;
                w_burst_count++;
            end
        end
    endfunction

    function void pair_write_channels();
        txn_t txn;
        w_capture_t data;
        int unsigned expected;

        while (aw_q.size() != 0 && completed_w_q.size() != 0) begin
            txn = aw_q.pop_front();
            data = completed_w_q.pop_front();

            txn.data_q = data.data_q;
            txn.strb_q = data.strb_q;
            txn.last_q = data.last_q;
            txn.data_user_q = data.user_q;
            txn.w_backpressure = data.backpressure;

            expected = txn.expected_beats();
            txn.beat_count_ok = (txn.data_q.size() == expected);
            txn.last_ok = txn.beat_count_ok &&
                          (txn.last_q.size() == txn.data_q.size()) &&
                          (txn.last_q.size() != 0) && txn.last_q[$];

            write_response_q.push_back(txn);
        end
    endfunction

    function void sample_b();
        int idx;
        txn_t txn;

        if (!vif.bvalid) return;

        idx = find_write_response(vif.bid);
        if (idx < 0) begin
            `uvm_error("AXI_MONITOR", $sformatf(
                "B response for unknown ID 0x%0x", vif.bid))
            return;
        end

        if (!vif.bready) write_response_q[idx].b_backpressure = 1'b1;

        if (vif.bready) begin
            txn = write_response_q[idx];
            write_response_q.delete(idx);
            txn.bresp = vif.bresp;
            txn.buser = vif.buser;
            analysis_port.write(txn);
            b_count++;
        end
    endfunction

    function void sample_ar();
        txn_t txn;

        if (vif.arvalid && !vif.arready) ar_stall_seen = 1'b1;

        if (vif.arvalid && vif.arready) begin
            txn = create_txn("read_txn");
            txn.direction       = AXI_READ;
            txn.id              = vif.arid;
            txn.addr            = vif.araddr;
            txn.len             = vif.arlen;
            txn.size            = vif.arsize;
            txn.burst           = axi_burst_e'(vif.arburst);
            txn.lock            = vif.arlock;
            txn.cache           = vif.arcache;
            txn.prot            = vif.arprot;
            txn.qos             = vif.arqos;
            txn.region          = vif.arregion;
            txn.address_user    = vif.aruser;
            txn.owner           = vif.ar_owner;
            txn.ar_backpressure = ar_stall_seen;
            ar_stall_seen       = 1'b0;
            read_q.push_back(txn);
            ar_count++;
        end
    endfunction

    function void sample_r();
        int idx;
        int unsigned expected;
        txn_t txn;

        if (!vif.rvalid) return;

        idx = find_read(vif.rid);
        if (idx < 0) begin
            `uvm_error("AXI_MONITOR", $sformatf(
                "R beat for unknown ID 0x%0x", vif.rid))
            return;
        end

        if (!vif.rready) read_q[idx].r_backpressure = 1'b1;

        if (vif.rready) begin
            read_q[idx].data_q.push_back(vif.rdata);
            read_q[idx].resp_q.push_back(vif.rresp);
            read_q[idx].last_q.push_back(vif.rlast);
            read_q[idx].data_user_q.push_back(vif.ruser);

            if (vif.rlast) begin
                txn = read_q[idx];
                read_q.delete(idx);
                expected = txn.expected_beats();
                txn.beat_count_ok = (txn.data_q.size() == expected);
                txn.last_ok = txn.beat_count_ok &&
                              (txn.last_q.size() == txn.data_q.size()) &&
                              (txn.last_q.size() != 0) && txn.last_q[$];
                analysis_port.write(txn);
                r_burst_count++;
            end
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.aclk);

            if (!vif.aresetn) begin
                clear_state();
                continue;
            end

            // Address and data channels are sampled before response channels so
            // a zero-latency test slave remains observable.
            sample_aw();
            sample_w();
            pair_write_channels();
            sample_ar();
            sample_b();
            sample_r();
        end
    endtask

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (aw_q.size() != 0 || completed_w_q.size() != 0 || current_w != null ||
            write_response_q.size() != 0 || read_q.size() != 0) begin
            if (require_quiescent_end) begin
                `uvm_error("AXI_MONITOR", $sformatf(
                    "incomplete AXI traffic aw=%0d w_complete=%0d w_partial=%0d b_pending=%0d r_pending=%0d",
                    aw_q.size(), completed_w_q.size(), current_w != null,
                    write_response_q.size(), read_q.size()))
            end
            else begin
                // Program tests stop after a target retirement count while the
                // frontend may legally have one speculative fetch outstanding.
                `uvm_info("AXI_MONITOR", $sformatf(
                    "end-of-test non-quiescent traffic ignored aw=%0d w_complete=%0d w_partial=%0d b_pending=%0d r_pending=%0d",
                    aw_q.size(), completed_w_q.size(), current_w != null,
                    write_response_q.size(), read_q.size()), UVM_LOW)
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_MONITOR", $sformatf(
            "AW=%0d W_BURST=%0d B=%0d AR=%0d R_BURST=%0d",
            aw_count, w_burst_count, b_count, ar_count, r_burst_count), UVM_LOW)
    endfunction

endclass

`endif
