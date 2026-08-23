`ifndef YSYX_AXI_PROTOCOL_CHECKER_SV
`define YSYX_AXI_PROTOCOL_CHECKER_SV

`timescale 1ns/1ps

// Passive AXI4 protocol checker.  Bind or instantiate one checker per observed
// interface and compile Verilator with --assert.  SVA covers channel stability
// and request legality; procedural queues cover cross-channel ordering and
// LEN/LAST/ID relationships that are awkward to express portably in SVA.
module axi_protocol_checker #(
    parameter bit CHECK_FINAL_QUIESCENCE = 1'b0
)(
    axi_if.monitor axi
);

    localparam int unsigned DATA_BYTES = $bits(axi.wstrb);
    localparam int unsigned MAX_SIZE   = $clog2(DATA_BYTES);

    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;
    localparam logic [1:0] BURST_WRAP  = 2'b10;
    localparam logic [1:0] BURST_RSVD  = 2'b11;

    function automatic bit legal_wrap_len(input logic [7:0] len);
        return len == 8'd1 || len == 8'd3 || len == 8'd7 || len == 8'd15;
    endfunction

    function automatic bit legal_burst_len(
        input logic [1:0] burst,
        input logic [7:0] len
    );
        if (burst == BURST_INCR) return 1'b1;
        if (burst == BURST_WRAP) return legal_wrap_len(len);
        if (burst == BURST_FIXED) return len <= 8'd15;
        return 1'b0;
    endfunction

    function automatic bit crosses_4k(
        input longint unsigned addr,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst
    );
        longint unsigned transfer_bytes;
        longint unsigned low_addr;
        longint unsigned wrap_base;
        if (burst == BURST_FIXED) return 1'b0;
        transfer_bytes = (longint'(len) + 1) << size;
        low_addr = addr & 64'hfff;
        if (burst == BURST_WRAP) begin
            // A legal WRAP length makes transfer_bytes a power of two.  Check
            // the complete wrap window, rather than start+length, because the
            // latter would falsely reject a burst that wraps backwards within
            // the same 4-KiB region.
            wrap_base = low_addr & ~(transfer_bytes - 1);
            return (wrap_base + transfer_bytes) > 64'd4096;
        end
        return (low_addr + transfer_bytes) > 64'd4096;
    endfunction

    function automatic bit wrap_address_aligned(
        input longint unsigned addr,
        input logic [2:0] size,
        input logic [1:0] burst
    );
        longint unsigned byte_mask;
        if (burst != BURST_WRAP) return 1'b1;
        byte_mask = (64'd1 << size) - 1;
        return (addr & byte_mask) == 0;
    endfunction

    property p_aw_stable_when_stalled;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.awvalid && !axi.awready |=>
            axi.awvalid && $stable({axi.awid, axi.awaddr, axi.awlen,
                axi.awsize, axi.awburst, axi.awlock, axi.awcache,
                axi.awprot, axi.awqos, axi.awregion, axi.awuser,
                axi.aw_owner});
    endproperty

    property p_w_stable_when_stalled;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.wvalid && !axi.wready |=>
            axi.wvalid && $stable({axi.wdata, axi.wstrb, axi.wlast, axi.wuser});
    endproperty

    property p_b_stable_when_stalled;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.bvalid && !axi.bready |=>
            axi.bvalid && $stable({axi.bid, axi.bresp, axi.buser});
    endproperty

    property p_ar_stable_when_stalled;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.arvalid && !axi.arready |=>
            axi.arvalid && $stable({axi.arid, axi.araddr, axi.arlen,
                axi.arsize, axi.arburst, axi.arlock, axi.arcache,
                axi.arprot, axi.arqos, axi.arregion, axi.aruser,
                axi.ar_owner});
    endproperty

    property p_r_stable_when_stalled;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.rvalid && !axi.rready |=>
            axi.rvalid && $stable({axi.rid, axi.rdata, axi.rresp,
                                   axi.rlast, axi.ruser});
    endproperty

    property p_aw_legal;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.awvalid && axi.awready |->
            axi.awburst != BURST_RSVD &&
            axi.awsize <= MAX_SIZE &&
            legal_burst_len(axi.awburst, axi.awlen) &&
            !crosses_4k(axi.awaddr, axi.awlen, axi.awsize, axi.awburst) &&
            wrap_address_aligned(axi.awaddr, axi.awsize, axi.awburst) &&
            $unsigned(axi.aw_owner) <= 1;
    endproperty

    property p_ar_legal;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.arvalid && axi.arready |->
            axi.arburst != BURST_RSVD &&
            axi.arsize <= MAX_SIZE &&
            legal_burst_len(axi.arburst, axi.arlen) &&
            !crosses_4k(axi.araddr, axi.arlen, axi.arsize, axi.arburst) &&
            wrap_address_aligned(axi.araddr, axi.arsize, axi.arburst) &&
            $unsigned(axi.ar_owner) <= 1;
    endproperty

    property p_aw_payload_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.awvalid |-> !$isunknown({axi.awid, axi.awaddr, axi.awlen,
            axi.awsize, axi.awburst, axi.awlock, axi.awcache, axi.awprot,
            axi.awqos, axi.awregion, axi.awuser, axi.aw_owner});
    endproperty

    property p_w_payload_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.wvalid |-> !$isunknown({axi.wdata, axi.wstrb, axi.wlast, axi.wuser});
    endproperty

    property p_b_payload_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.bvalid |-> !$isunknown({axi.bid, axi.bresp, axi.buser});
    endproperty

    property p_ar_payload_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.arvalid |-> !$isunknown({axi.arid, axi.araddr, axi.arlen,
            axi.arsize, axi.arburst, axi.arlock, axi.arcache, axi.arprot,
            axi.arqos, axi.arregion, axi.aruser, axi.ar_owner});
    endproperty

    property p_r_payload_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        axi.rvalid |-> !$isunknown({axi.rid, axi.rdata, axi.rresp,
                                    axi.rlast, axi.ruser});
    endproperty

    property p_channel_controls_known;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        !$isunknown({axi.awvalid, axi.awready, axi.wvalid, axi.wready,
                     axi.bvalid, axi.bready, axi.arvalid, axi.arready,
                     axi.rvalid, axi.rready});
    endproperty

    a_aw_stable: assert property (p_aw_stable_when_stalled)
        else $error("AXI_PROTOCOL: AW payload changed while stalled");
    a_w_stable: assert property (p_w_stable_when_stalled)
        else $error("AXI_PROTOCOL: W payload changed while stalled");
    a_b_stable: assert property (p_b_stable_when_stalled)
        else $error("AXI_PROTOCOL: B payload changed while stalled");
    a_ar_stable: assert property (p_ar_stable_when_stalled)
        else $error("AXI_PROTOCOL: AR payload changed while stalled");
    a_r_stable: assert property (p_r_stable_when_stalled)
        else $error("AXI_PROTOCOL: R payload changed while stalled");
    a_aw_legal: assert property (p_aw_legal)
        else $error("AXI_PROTOCOL: illegal AW LEN/SIZE/BURST/owner or 4-KiB crossing");
    a_ar_legal: assert property (p_ar_legal)
        else $error("AXI_PROTOCOL: illegal AR LEN/SIZE/BURST/owner or 4-KiB crossing");
    a_aw_known: assert property (p_aw_payload_known)
        else $error("AXI_PROTOCOL: unknown AW payload");
    a_w_known: assert property (p_w_payload_known)
        else $error("AXI_PROTOCOL: unknown W payload");
    a_b_known: assert property (p_b_payload_known)
        else $error("AXI_PROTOCOL: unknown B payload");
    a_ar_known: assert property (p_ar_payload_known)
        else $error("AXI_PROTOCOL: unknown AR payload");
    a_r_known: assert property (p_r_payload_known)
        else $error("AXI_PROTOCOL: unknown R payload");
    a_controls_known: assert property (p_channel_controls_known)
        else $error("AXI_PROTOCOL: unknown VALID/READY control");

    typedef struct {
        longint unsigned id;
        int unsigned     expected_beats;
    } aw_desc_t;

    typedef struct {
        longint unsigned id;
        int unsigned     expected_beats;
        int unsigned     observed_beats;
    } read_desc_t;

    aw_desc_t aw_q[$];
    int unsigned completed_w_beats_q[$];
    longint unsigned b_pending_id_q[$];
    read_desc_t read_q[$];
    int unsigned current_w_beats;
    longint unsigned aw_handshake_count;
    longint unsigned w_handshake_count;
    longint unsigned b_handshake_count;
    longint unsigned ar_handshake_count;
    longint unsigned r_handshake_count;
    int unsigned procedural_error_count;

    integer found;
    aw_desc_t aw_desc;
    read_desc_t read_desc;
    int unsigned completed_beats;

    always @(posedge axi.aclk) begin
        if (!axi.aresetn) begin
            aw_q.delete();
            completed_w_beats_q.delete();
            b_pending_id_q.delete();
            read_q.delete();
            current_w_beats = 0;
            aw_handshake_count = 0;
            w_handshake_count = 0;
            b_handshake_count = 0;
            ar_handshake_count = 0;
            r_handshake_count = 0;
            procedural_error_count = 0;
        end
        else begin
            if (axi.awvalid && axi.awready) begin
                aw_handshake_count++;
                aw_desc.id = longint'(axi.awid);
                aw_desc.expected_beats = int'(axi.awlen) + 1;
                aw_q.push_back(aw_desc);
            end

            if (axi.wvalid && axi.wready) begin
                w_handshake_count++;
                current_w_beats++;
                if (axi.wlast) begin
                    completed_w_beats_q.push_back(current_w_beats);
                    current_w_beats = 0;
                end
            end

            while (aw_q.size() != 0 && completed_w_beats_q.size() != 0) begin
                aw_desc = aw_q.pop_front();
                completed_beats = completed_w_beats_q.pop_front();
                if (completed_beats != aw_desc.expected_beats) begin
                    procedural_error_count++;
                    $error("AXI_PROTOCOL: WLAST beat mismatch id=0x%0x expected=%0d observed=%0d",
                           aw_desc.id, aw_desc.expected_beats, completed_beats);
                end
                b_pending_id_q.push_back(aw_desc.id);
            end

            if (axi.bvalid && axi.bready) begin
                b_handshake_count++;
                found = -1;
                foreach (b_pending_id_q[i]) begin
                    if (found < 0 && b_pending_id_q[i] == longint'(axi.bid)) found = i;
                end
                if (found < 0) begin
                    procedural_error_count++;
                    $error("AXI_PROTOCOL: B response without completed AW/W burst id=0x%0x", axi.bid);
                end
                else begin
                    b_pending_id_q.delete(found);
                end
            end

            if (axi.arvalid && axi.arready) begin
                ar_handshake_count++;
                read_desc.id = longint'(axi.arid);
                read_desc.expected_beats = int'(axi.arlen) + 1;
                read_desc.observed_beats = 0;
                read_q.push_back(read_desc);
            end

            if (axi.rvalid && axi.rready) begin
                r_handshake_count++;
                found = -1;
                foreach (read_q[i]) begin
                    if (found < 0 && read_q[i].id == longint'(axi.rid)) found = i;
                end

                if (found < 0) begin
                    procedural_error_count++;
                    $error("AXI_PROTOCOL: R beat without outstanding AR id=0x%0x", axi.rid);
                end
                else begin
                    read_q[found].observed_beats++;
                    if (axi.rlast !==
                        (read_q[found].observed_beats == read_q[found].expected_beats)) begin
                        procedural_error_count++;
                        $error("AXI_PROTOCOL: RLAST beat mismatch id=0x%0x expected=%0d observed=%0d rlast=%0d",
                               axi.rid, read_q[found].expected_beats,
                               read_q[found].observed_beats, axi.rlast);
                    end
                    if (axi.rlast) read_q.delete(found);
                end
            end
        end
    end

    final begin
        $display("AXI_PROTOCOL_REPORT: AW=%0d W=%0d B=%0d AR=%0d R=%0d procedural_errors=%0d pending_aw=%0d pending_w=%0d pending_b=%0d pending_r=%0d",
                 aw_handshake_count, w_handshake_count, b_handshake_count,
                 ar_handshake_count, r_handshake_count,
                 procedural_error_count, aw_q.size(),
                 completed_w_beats_q.size(), b_pending_id_q.size(),
                 read_q.size());
        if (aw_q.size() != 0 || completed_w_beats_q.size() != 0 ||
            b_pending_id_q.size() != 0 || read_q.size() != 0 ||
            current_w_beats != 0) begin
            if (CHECK_FINAL_QUIESCENCE) begin
                $error("AXI_PROTOCOL: incomplete traffic at end aw=%0d w_complete=%0d w_partial_beats=%0d b_pending=%0d r_pending=%0d",
                       aw_q.size(), completed_w_beats_q.size(), current_w_beats,
                       b_pending_id_q.size(), read_q.size());
            end
            else begin
                $display("AXI_PROTOCOL_REPORT: non-quiescent end ignored because CHECK_FINAL_QUIESCENCE=0");
            end
        end
    end

endmodule

`endif
