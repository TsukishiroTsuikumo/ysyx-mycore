`ifndef YSYX_CACHE_DRIVER_SVH
`define YSYX_CACHE_DRIVER_SVH

class cache_driver extends uvm_driver #(cache_transaction);
    `uvm_component_utils(cache_driver)

    virtual cache_uvm_if vif;
    int unsigned completed_transactions;
    int unsigned ic_inflight_flush_drains;

    function new(string name = "cache_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_uvm_if)::get(this, "", "vif", vif))
            `uvm_fatal("CACHE_DRIVER", "cache_uvm_if was not configured")
    endfunction

    task automatic wait_ic_ready();
        int unsigned cycles = 0;
        do begin
            @(posedge vif.clk);
            cycles++;
            if (cycles > 1000) `uvm_fatal("CACHE_DRIVER", "ICache request timeout")
        end while (!vif.ic_cpu_req_ready);
    endtask

    task automatic wait_dc_read_ready();
        int unsigned cycles = 0;
        do begin
            @(posedge vif.clk);
            cycles++;
            if (cycles > 1000) `uvm_fatal("CACHE_DRIVER", "DCache read request timeout")
        end while (!vif.dc_cpu_read_ready);
    endtask

    task automatic wait_dc_write_ready();
        int unsigned cycles = 0;
        do begin
            @(posedge vif.clk);
            cycles++;
            if (cycles > 1000) `uvm_fatal("CACHE_DRIVER", "DCache write request timeout")
        end while (!vif.dc_cpu_write_ready);
    endtask

    function automatic bit [7:0] initial_byte(bit [31:0] address);
        bit [31:0] mixed;
        mixed = (address * 32'd29) ^ (address >> 3) ^ 32'h0000_005a;
        return mixed[7:0];
    endfunction

    function automatic bit [31:0] expected_word(bit [31:0] address);
        bit [31:0] value;
        for (int unsigned byte_index = 0; byte_index < 4; byte_index++)
            value[byte_index*8 +: 8] = initial_byte(address + byte_index);
        return value;
    endfunction

    function automatic bit [127:0] expected_line(bit [31:0] address);
        bit [127:0] value;
        bit [31:0] line_address;
        line_address = address & 32'hffff_fff0;
        for (int unsigned byte_index = 0; byte_index < 16; byte_index++)
            value[byte_index*8 +: 8] = initial_byte(line_address + byte_index);
        return value;
    endfunction

    task automatic drive_ic_inflight_flush(cache_transaction item);
        int unsigned cycles;
        int unsigned new_mem_requests;
        bit old_response_seen;
        bit new_cpu_accepted;

        cycles = 0;
        new_mem_requests = 0;
        old_response_seen = 1'b0;
        new_cpu_accepted = 1'b0;

        // Launch a guaranteed cold miss and wait until backing memory has
        // accepted it.  The memory model gives this address a long-latency
        // SLVERR response so flush is unquestionably in flight.
        @(negedge vif.clk);
        vif.ic_cpu_req_addr  <= item.addr;
        vif.ic_cpu_req_valid <= 1'b1;
        wait_ic_ready();
        vif.ic_cpu_req_valid <= 1'b0;

        do begin
            @(posedge vif.clk);
            cycles++;
            if (cycles > 1000)
                `uvm_fatal("CACHE_DRIVER", "in-flight flush old request timeout")
        end while (!(vif.ic_mem_req_valid && vif.ic_mem_req_ready));
        if (vif.ic_mem_req_addr !== {item.addr[31:4], 4'b0})
            `uvm_fatal("CACHE_DRIVER", "in-flight flush old line address mismatch")

        // Keep the replacement CPU request asserted across two sampled flush
        // cycles.  This also verifies that a repeated flush while already in
        // DRAIN cannot release the controller early.
        @(negedge vif.clk);
        vif.flush_request    <= 1'b1;
        vif.ic_cpu_req_addr  <= item.addr2;
        vif.ic_cpu_req_valid <= 1'b1;
        repeat (2) begin
            @(posedge vif.clk);
            if (vif.ic_cpu_req_ready || vif.ic_mem_req_valid ||
                vif.ic_cpu_resp_valid || vif.ic_fault_valid)
                `uvm_fatal("CACHE_DRIVER",
                    "ICache exposed activity while in-flight flush was asserted")
        end
        @(negedge vif.clk);
        vif.flush_request <= 1'b0;

        // Until the stale response arrives, DRAIN must reject the held CPU
        // request and emit no second memory request.  The stale SLVERR itself
        // must be swallowed without a CPU completion or fault sideband.
        cycles = 0;
        while (!old_response_seen) begin
            @(posedge vif.clk);
            cycles++;
            if (vif.ic_cpu_req_ready || vif.ic_mem_req_valid ||
                vif.ic_cpu_resp_valid || vif.ic_fault_valid)
                `uvm_fatal("CACHE_DRIVER",
                    "ICache released or completed before stale response drain")
            if (vif.ic_mem_resp_valid) begin
                if (vif.ic_mem_resp_code !== 2'b10)
                    `uvm_fatal("CACHE_DRIVER",
                        "in-flight flush stale response was not injected SLVERR")
                old_response_seen = 1'b1;
            end
            if (cycles > 1000)
                `uvm_fatal("CACHE_DRIVER", "in-flight flush drain timeout")
        end

        // The held replacement request may be accepted only after the drain
        // edge.  Its own miss must then generate exactly one request for the
        // replacement line, never reuse the stale response as refill data.
        cycles = 0;
        while (!new_cpu_accepted) begin
            @(posedge vif.clk);
            cycles++;
            if (vif.ic_cpu_resp_valid || vif.ic_fault_valid ||
                vif.ic_mem_req_valid)
                `uvm_fatal("CACHE_DRIVER",
                    "ICache produced replacement activity before CPU acceptance")
            if (vif.ic_cpu_req_ready)
                new_cpu_accepted = 1'b1;
            if (cycles > 1000)
                `uvm_fatal("CACHE_DRIVER",
                    "replacement CPU request was not accepted after drain")
        end
        @(negedge vif.clk);
        vif.ic_cpu_req_valid <= 1'b0;

        cycles = 0;
        while (new_mem_requests == 0) begin
            @(posedge vif.clk);
            cycles++;
            if (vif.ic_mem_req_valid && vif.ic_mem_req_ready) begin
                new_mem_requests++;
                if (vif.ic_mem_req_addr !== {item.addr2[31:4], 4'b0})
                    `uvm_fatal("CACHE_DRIVER",
                        "replacement miss issued the wrong line address")
            end
            if (vif.ic_cpu_resp_valid || vif.ic_fault_valid)
                `uvm_fatal("CACHE_DRIVER",
                    "replacement completed before its memory request")
            if (cycles > 1000)
                `uvm_fatal("CACHE_DRIVER", "replacement memory request timeout")
        end

        cycles = 0;
        while (!vif.ic_cpu_resp_valid) begin
            @(posedge vif.clk);
            cycles++;
            if (vif.ic_mem_req_valid && vif.ic_mem_req_ready)
                new_mem_requests++;
            if (vif.ic_fault_valid)
                `uvm_fatal("CACHE_DRIVER",
                    "stale fault escaped during replacement refill")
            if (cycles > 1000)
                `uvm_fatal("CACHE_DRIVER", "replacement refill timeout")
        end
        if (new_mem_requests != 1)
            `uvm_fatal("CACHE_DRIVER",
                "replacement generated an unexpected memory request count")
        item.rline = vif.ic_cpu_resp_data;
        item.rdata = item.rline[item.addr2[3:2]*32 +: 32];
        if (item.rline !== expected_line(item.addr2))
            `uvm_fatal("CACHE_DRIVER", $sformatf(
                "replacement line mismatch expected=0x%032x actual=0x%032x",
                expected_line(item.addr2), item.rline))
        if (item.rdata !== expected_word(item.addr2))
            `uvm_fatal("CACHE_DRIVER", $sformatf(
                "stale response polluted replacement line expected=0x%08x actual=0x%08x",
                expected_word(item.addr2), item.rdata))

        ic_inflight_flush_drains++;
    endtask

    virtual task run_phase(uvm_phase phase);
        cache_transaction item;

        vif.reset_request      <= 1'b0;
        vif.flush_request      <= 1'b0;
        vif.ic_cpu_req_valid   <= 1'b0;
        vif.ic_cpu_req_addr    <= '0;
        vif.dc_cpu_req_addr    <= '0;
        vif.dc_cpu_read_valid  <= 1'b0;
        vif.dc_cpu_write_valid <= 1'b0;
        vif.dc_cpu_write_strb  <= '0;
        vif.dc_cpu_write_data  <= '0;

        forever begin
            seq_item_port.get_next_item(item);
            while (vif.reset) @(posedge vif.clk);

            case (item.op)
                cache_transaction::IC_READ: begin
                    @(negedge vif.clk);
                    vif.ic_cpu_req_addr  <= item.addr;
                    vif.ic_cpu_req_valid <= 1'b1;
                    wait_ic_ready();
                    vif.ic_cpu_req_valid <= 1'b0;
                    do @(posedge vif.clk); while (!vif.ic_cpu_resp_valid);
                    item.rline = vif.ic_cpu_resp_data;
                    item.rdata = item.rline[item.addr[3:2]*32 +: 32];
                end
                cache_transaction::DC_READ: begin
                    @(negedge vif.clk);
                    vif.dc_cpu_req_addr   <= item.addr;
                    vif.dc_cpu_read_valid <= 1'b1;
                    wait_dc_read_ready();
                    vif.dc_cpu_read_valid <= 1'b0;
                    do @(posedge vif.clk); while (!vif.dc_cpu_read_resp_valid);
                    item.rdata = vif.dc_cpu_read_data;
                end
                cache_transaction::DC_WRITE: begin
                    @(negedge vif.clk);
                    vif.dc_cpu_req_addr    <= item.addr;
                    vif.dc_cpu_write_strb  <= item.wstrb;
                    vif.dc_cpu_write_data  <= item.wdata;
                    vif.dc_cpu_write_valid <= 1'b1;
                    wait_dc_write_ready();
                    vif.dc_cpu_write_valid <= 1'b0;
                    do @(posedge vif.clk); while (!vif.dc_cpu_write_resp_valid);
                end
                cache_transaction::CACHE_RESET: begin
                    @(negedge vif.clk);
                    vif.reset_request <= 1'b1;
                    repeat (4) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.reset_request <= 1'b0;
                    repeat (3) @(posedge vif.clk);
                end
                cache_transaction::IC_FLUSH: begin
                    @(negedge vif.clk);
                    vif.flush_request <= 1'b1;
                    repeat (2) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.flush_request <= 1'b0;
                    repeat (2) @(posedge vif.clk);
                end
                cache_transaction::IC_FLUSH_INFLIGHT: begin
                    drive_ic_inflight_flush(item);
                end
                cache_transaction::ID_CONCURRENT_READ: begin
                    bit ic_accepted;
                    bit dc_accepted;
                    bit ic_done;
                    bit dc_done;
                    int unsigned cycles;
                    ic_accepted = 1'b0;
                    dc_accepted = 1'b0;
                    ic_done = 1'b0;
                    dc_done = 1'b0;
                    cycles = 0;
                    @(negedge vif.clk);
                    vif.ic_cpu_req_addr   <= item.addr;
                    vif.dc_cpu_req_addr   <= item.addr2;
                    vif.ic_cpu_req_valid  <= 1'b1;
                    vif.dc_cpu_read_valid <= 1'b1;
                    while (!ic_accepted || !dc_accepted) begin
                        @(posedge vif.clk);
                        cycles++;
                        if (!ic_accepted && vif.ic_cpu_req_ready) begin
                            ic_accepted = 1'b1;
                            vif.ic_cpu_req_valid <= 1'b0;
                        end
                        if (!dc_accepted && vif.dc_cpu_read_ready) begin
                            dc_accepted = 1'b1;
                            vif.dc_cpu_read_valid <= 1'b0;
                        end
                        if (cycles > 1000)
                            `uvm_fatal("CACHE_DRIVER", "concurrent request timeout")
                    end
                    while (!ic_done || !dc_done) begin
                        @(posedge vif.clk);
                        cycles++;
                        if (vif.ic_cpu_resp_valid) ic_done = 1'b1;
                        if (vif.dc_cpu_read_resp_valid) dc_done = 1'b1;
                        if (cycles > 2000)
                            `uvm_fatal("CACHE_DRIVER", "concurrent response timeout")
                    end
                end
                default: `uvm_fatal("CACHE_DRIVER", "unknown cache transaction kind")
            endcase

            completed_transactions++;
            seq_item_port.item_done();
        end
    endtask
endclass

`endif
