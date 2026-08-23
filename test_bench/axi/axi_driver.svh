`ifndef YSYX_AXI_DRIVER_SVH
`define YSYX_AXI_DRIVER_SVH

// Single-outstanding AXI4 master driver.  Address, data and response channels
// use independent VALID/READY handshakes, but a sequence item is completed
// only after its complete B or R response has been observed.  This conservative
// policy is sufficient for cache-line traffic and makes response data directly
// available to the originating sequence item.
class axi_driver #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_driver #(
    axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    )
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    typedef axi_driver #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;
    typedef virtual axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_vif_t;

    `uvm_component_param_utils(this_type)

    axi_vif_t vif;
    int unsigned completed_read_count;
    int unsigned completed_write_count;

    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
        completed_read_count = 0;
        completed_write_count = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_DRIVER", "Failed to get axi_if virtual interface")
        end
    endfunction

    task drive_idle();
        vif.awid     <= '0;
        vif.awaddr   <= '0;
        vif.awlen    <= '0;
        vif.awsize   <= '0;
        vif.awburst  <= AXI_BURST_INCR;
        vif.awlock   <= 1'b0;
        vif.awcache  <= '0;
        vif.awprot   <= '0;
        vif.awqos    <= '0;
        vif.awregion <= '0;
        vif.awuser   <= '0;
        vif.aw_owner <= '0;
        vif.awvalid  <= 1'b0;

        vif.wdata  <= '0;
        vif.wstrb  <= '0;
        vif.wlast  <= 1'b0;
        vif.wuser  <= '0;
        vif.wvalid <= 1'b0;
        vif.bready <= 1'b0;

        vif.arid     <= '0;
        vif.araddr   <= '0;
        vif.arlen    <= '0;
        vif.arsize   <= '0;
        vif.arburst  <= AXI_BURST_INCR;
        vif.arlock   <= 1'b0;
        vif.arcache  <= '0;
        vif.arprot   <= '0;
        vif.arqos    <= '0;
        vif.arregion <= '0;
        vif.aruser   <= '0;
        vif.ar_owner <= '0;
        vif.arvalid  <= 1'b0;
        vif.rready   <= 1'b0;
    endtask

    task wait_for_reset_release();
        while (vif.aresetn !== 1'b1) @(posedge vif.aclk);
    endtask

    task wait_driver_cycles(input int unsigned cycles);
        repeat (cycles) @(posedge vif.aclk);
    endtask

    task drive_aw(txn_t item);
        wait_driver_cycles(item.address_delay_cycles);
        @(negedge vif.aclk);
        vif.awid     <= item.id;
        vif.awaddr   <= item.addr;
        vif.awlen    <= item.len;
        vif.awsize   <= item.size;
        vif.awburst  <= item.burst;
        vif.awlock   <= item.lock;
        vif.awcache  <= item.cache;
        vif.awprot   <= item.prot;
        vif.awqos    <= item.qos;
        vif.awregion <= item.region;
        vif.awuser   <= item.address_user;
        vif.aw_owner <= item.owner;
        vif.awvalid  <= 1'b1;

        do @(posedge vif.aclk); while (!vif.awready);

        @(negedge vif.aclk);
        vif.awvalid <= 1'b0;
    endtask

    task drive_w(txn_t item);
        int unsigned beat;
        bit [USER_WIDTH-1:0] beat_user;

        for (beat = 0; beat < item.expected_beats(); beat++) begin
            wait_driver_cycles(item.beat_delay_cycles);
            beat_user = (item.data_user_q.size() == item.expected_beats()) ?
                        item.data_user_q[beat] : '0;

            @(negedge vif.aclk);
            vif.wdata  <= item.data_q[beat];
            vif.wstrb  <= item.strb_q[beat];
            vif.wlast  <= (beat == (item.expected_beats() - 1));
            vif.wuser  <= beat_user;
            vif.wvalid <= 1'b1;

            do @(posedge vif.aclk); while (!vif.wready);

            @(negedge vif.aclk);
            vif.wvalid <= 1'b0;
            vif.wlast  <= 1'b0;
        end
    endtask

    task collect_b(txn_t item);
        do @(posedge vif.aclk); while (!vif.bvalid);
        wait_driver_cycles(item.response_ready_delay_cycles);

        @(negedge vif.aclk);
        vif.bready <= 1'b1;
        do @(posedge vif.aclk); while (!vif.bvalid);

        item.bresp = vif.bresp;
        item.buser = vif.buser;
        if (vif.bid !== item.id) begin
            `uvm_error("AXI_DRIVER", $sformatf(
                "BID mismatch expected=0x%0x actual=0x%0x", item.id, vif.bid))
        end

        @(negedge vif.aclk);
        vif.bready <= 1'b0;
    endtask

    task drive_ar(txn_t item);
        wait_driver_cycles(item.address_delay_cycles);
        @(negedge vif.aclk);
        vif.arid     <= item.id;
        vif.araddr   <= item.addr;
        vif.arlen    <= item.len;
        vif.arsize   <= item.size;
        vif.arburst  <= item.burst;
        vif.arlock   <= item.lock;
        vif.arcache  <= item.cache;
        vif.arprot   <= item.prot;
        vif.arqos    <= item.qos;
        vif.arregion <= item.region;
        vif.aruser   <= item.address_user;
        vif.ar_owner <= item.owner;
        vif.arvalid  <= 1'b1;

        do @(posedge vif.aclk); while (!vif.arready);

        @(negedge vif.aclk);
        vif.arvalid <= 1'b0;
    endtask

    task collect_r(txn_t item);
        int unsigned beat;
        bit expected_last;

        item.clear_payload();
        for (beat = 0; beat < item.expected_beats(); beat++) begin
            do @(posedge vif.aclk); while (!vif.rvalid);
            wait_driver_cycles(item.response_ready_delay_cycles);

            @(negedge vif.aclk);
            vif.rready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.rvalid);

            expected_last = (beat == (item.expected_beats() - 1));
            item.data_q.push_back(vif.rdata);
            item.resp_q.push_back(vif.rresp);
            item.last_q.push_back(vif.rlast);
            item.data_user_q.push_back(vif.ruser);

            if (vif.rid !== item.id) begin
                `uvm_error("AXI_DRIVER", $sformatf(
                    "RID mismatch beat=%0d expected=0x%0x actual=0x%0x",
                    beat, item.id, vif.rid))
            end
            if (vif.rlast !== expected_last) begin
                `uvm_error("AXI_DRIVER", $sformatf(
                    "RLAST mismatch beat=%0d expected=%0d actual=%0d",
                    beat, expected_last, vif.rlast))
            end

            @(negedge vif.aclk);
            vif.rready <= 1'b0;
        end

        item.beat_count_ok = (item.data_q.size() == item.expected_beats());
        item.last_ok = item.beat_count_ok && (item.last_q.size() != 0) &&
                       item.last_q[$];
    endtask

    task drive_write(txn_t item);
        if ((item.data_q.size() != item.expected_beats()) ||
            (item.strb_q.size() != item.expected_beats())) begin
            `uvm_fatal("AXI_DRIVER", $sformatf(
                "write payload mismatch beats=%0d data=%0d strb=%0d",
                item.expected_beats(), item.data_q.size(), item.strb_q.size()))
        end
        if ((item.data_user_q.size() != 0) &&
            (item.data_user_q.size() != item.expected_beats())) begin
            `uvm_fatal("AXI_DRIVER", $sformatf(
                "write USER payload mismatch beats=%0d user=%0d",
                item.expected_beats(), item.data_user_q.size()))
        end

        drive_aw(item);
        drive_w(item);
        collect_b(item);
        completed_write_count++;
    endtask

    task drive_read(txn_t item);
        drive_ar(item);
        collect_r(item);
        completed_read_count++;
    endtask

    virtual task run_phase(uvm_phase phase);
        txn_t item;

        drive_idle();
        forever begin
            seq_item_port.get_next_item(item);
            if (item == null) begin
                `uvm_fatal("AXI_DRIVER", "Received null sequence item")
            end

            wait_for_reset_release();
            if (item.direction == AXI_WRITE)
                drive_write(item);
            else
                drive_read(item);

            seq_item_port.item_done();
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_DRIVER", $sformatf(
            "completed reads=%0d writes=%0d",
            completed_read_count, completed_write_count), UVM_LOW)
    endfunction

endclass

`endif
