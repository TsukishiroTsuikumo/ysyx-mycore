`ifndef YSYX_CACHE_SCOREBOARD_SVH
`define YSYX_CACHE_SCOREBOARD_SVH

class cache_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cache_scoreboard)

    uvm_analysis_imp #(cache_transaction, cache_scoreboard) analysis_export;
    localparam int unsigned MEM_BYTES = 4096;
    bit [7:0] ref_mem [0:MEM_BYTES-1];

    bit [31:0] expected_ic_q[$];
    bit [31:0] expected_dc_addr_q[$];
    bit [2:0] expected_dc_op_q[$];
    bit [2:0] expected_control_q[$];

    int unsigned completed_transactions;
    int unsigned read_checks;
    int unsigned writes;
    int unsigned controls;
    int unsigned data_errors;
    int unsigned order_errors;

    int unsigned ic_hits, ic_misses, ic_consecutive_misses;
    int unsigned ic_same_set_misses;
    int unsigned ic_flush_invalidations, ic_reset_invalidations;
    int unsigned ic_inflight_flushes;
    int unsigned ic_slverr, ic_decerr;
    int unsigned dc_read_hits, dc_read_misses;
    int unsigned dc_write_hits, dc_write_misses;
    int unsigned dc_dirty_writebacks, dc_writeback_errors;
    int unsigned dc_dirty_retained, dc_refill_errors;
    int unsigned dc_raw_checks, dc_crossline_reads;
    int unsigned dc_writeback_refetches;
    bit [7:0] wstrb_bins;

    bit previous_ic_miss;
    bit await_flush_refill;
    bit await_reset_refill;
    bit last_was_dc_write;
    bit [31:0] last_dc_write_addr;

    function new(string name = "cache_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    function automatic bit [7:0] initial_byte(bit [31:0] address);
        bit [31:0] mixed;
        mixed = (address * 32'd29) ^ (address >> 3) ^ 32'h0000_005a;
        return mixed[7:0];
    endfunction

    function automatic bit [31:0] expected_word(bit [31:0] address);
        bit [31:0] value;
        if (address + 3 >= MEM_BYTES)
            `uvm_fatal("CACHE_SCOREBOARD", "reference read outside memory")
        for (int unsigned i = 0; i < 4; i++)
            value[i*8 +: 8] = ref_mem[address+i];
        return value;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int unsigned i = 0; i < MEM_BYTES; i++)
            ref_mem[i] = initial_byte(i);
        load_expected_order();
    endfunction

    function void push_dc(bit [2:0] op, bit [31:0] address);
        expected_dc_op_q.push_back(op);
        expected_dc_addr_q.push_back(address);
    endfunction

    function void load_expected_order();
        bit [3:0] masks[8];
        expected_ic_q.push_back(32'h0000_0000);
        expected_ic_q.push_back(32'h0000_0004);
        expected_ic_q.push_back(32'h0000_0004);
        expected_ic_q.push_back(32'h0000_0004);
        expected_ic_q.push_back(32'h0000_0760);
        expected_ic_q.push_back(32'h0000_0100);
        expected_ic_q.push_back(32'h0000_0200);
        expected_ic_q.push_back(32'h0000_0300);
        expected_ic_q.push_back(32'h0000_0400);
        expected_ic_q.push_back(32'h0000_0800);
        expected_ic_q.push_back(32'h0000_0800);
        expected_ic_q.push_back(32'h0000_0900);
        expected_ic_q.push_back(32'h0000_0900);
        expected_ic_q.push_back(32'h0000_0004);
        expected_ic_q.push_back(32'h0000_0550);

        expected_control_q.push_back(cache_transaction::IC_FLUSH);
        expected_control_q.push_back(cache_transaction::IC_FLUSH);
        expected_control_q.push_back(cache_transaction::CACHE_RESET);

        push_dc(cache_transaction::DC_READ, 32'h0000_0650);
        push_dc(cache_transaction::DC_READ, 32'h0000_0040);
        push_dc(cache_transaction::DC_READ, 32'h0000_0040);
        masks[0] = 4'b0001;
        masks[1] = 4'b0010;
        masks[2] = 4'b0100;
        masks[3] = 4'b1000;
        masks[4] = 4'b0011;
        masks[5] = 4'b1100;
        masks[6] = 4'b1111;
        masks[7] = 4'b0000;
        for (int unsigned i = 0; i < 8; i++) begin
            push_dc(cache_transaction::DC_WRITE, 32'h0000_0044);
            push_dc(cache_transaction::DC_READ, 32'h0000_0044);
        end
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0180);
        push_dc(cache_transaction::DC_READ, 32'h0000_0180);
        push_dc(cache_transaction::DC_READ, 32'h0000_070d);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0120);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0220);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0320);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0420);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0520);
        push_dc(cache_transaction::DC_READ, 32'h0000_0120);
        push_dc(cache_transaction::DC_READ, 32'h0000_0a00);
        push_dc(cache_transaction::DC_READ, 32'h0000_0a00);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0b00);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0c00);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0d00);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0e00);
        push_dc(cache_transaction::DC_WRITE, 32'h0000_0f00);
        push_dc(cache_transaction::DC_READ, 32'h0000_0b00);
    endfunction

    function void check_order(cache_transaction t);
        bit [31:0] expected_addr;
        bit [2:0] expected_op;
        case (t.op)
            cache_transaction::IC_READ: begin
                if (expected_ic_q.size() == 0) begin
                    order_errors++;
                    `uvm_error("CACHE_ORDER", "unexpected ICache completion")
                end
                else begin
                    expected_addr = expected_ic_q.pop_front();
                    if (expected_addr != t.addr) begin
                        order_errors++;
                        `uvm_error("CACHE_ORDER", $sformatf(
                            "ICache order mismatch expected=0x%08x actual=0x%08x",
                            expected_addr, t.addr))
                    end
                end
            end
            cache_transaction::DC_READ, cache_transaction::DC_WRITE: begin
                if (expected_dc_addr_q.size() == 0 || expected_dc_op_q.size() == 0) begin
                    order_errors++;
                    `uvm_error("CACHE_ORDER", "unexpected DCache completion")
                end
                else begin
                    expected_addr = expected_dc_addr_q.pop_front();
                    expected_op = expected_dc_op_q.pop_front();
                    if (expected_addr != t.addr || expected_op != t.op) begin
                        order_errors++;
                        `uvm_error("CACHE_ORDER", $sformatf(
                            "DCache order mismatch expected op=%0d addr=0x%08x actual op=%0d addr=0x%08x",
                            expected_op, expected_addr, t.op, t.addr))
                    end
                end
            end
            cache_transaction::IC_FLUSH, cache_transaction::CACHE_RESET: begin
                if (expected_control_q.size() == 0) begin
                    order_errors++;
                    `uvm_error("CACHE_ORDER", "unexpected cache control completion")
                end
                else begin
                    expected_op = expected_control_q.pop_front();
                    if (expected_op != t.op) begin
                        order_errors++;
                        `uvm_error("CACHE_ORDER", "cache control order mismatch")
                    end
                end
            end
            default: begin
                order_errors++;
                `uvm_error("CACHE_ORDER", "unknown monitored operation")
            end
        endcase
    endfunction

    function void check_read(cache_transaction t);
        bit [31:0] expected;
        if (t.fault) begin
            expected = (t.op == cache_transaction::IC_READ) ?
                       32'h0000_0013 : 32'h0000_0000;
        end
        else expected = expected_word(t.addr);
        read_checks++;
        if (t.rdata !== expected) begin
            data_errors++;
            `uvm_error("CACHE_DATA", $sformatf(
                "read mismatch op=%0d addr=0x%08x expected=0x%08x actual=0x%08x fault=%0d",
                t.op, t.addr, expected, t.rdata, t.fault))
        end
    endfunction

    function void write(cache_transaction t);
        bit miss;
        completed_transactions++;
        check_order(t);

        if (t.op == cache_transaction::IC_FLUSH) begin
            controls++;
            if ((t.addr == 32'h0000_0750) &&
                (t.mem_read_count == 1))
                ic_inflight_flushes++;
            await_flush_refill = 1'b1;
            previous_ic_miss = 1'b0;
            return;
        end
        if (t.op == cache_transaction::CACHE_RESET) begin
            controls++;
            await_reset_refill = 1'b1;
            previous_ic_miss = 1'b0;
            last_was_dc_write = 1'b0;
            return;
        end

        if (t.op == cache_transaction::IC_READ) begin
            check_read(t);
            miss = (t.mem_read_count != 0);
            if (miss) ic_misses++; else ic_hits++;
            if (miss && previous_ic_miss) ic_consecutive_misses++;
            previous_ic_miss = miss;
            if (miss && !t.fault && t.addr[7:4] == 4'h0)
                ic_same_set_misses++;
            if (await_flush_refill) begin
                if (miss && !t.fault) ic_flush_invalidations++;
                await_flush_refill = 1'b0;
            end
            if (await_reset_refill) begin
                if (miss && !t.fault) ic_reset_invalidations++;
                await_reset_refill = 1'b0;
            end
            if (t.fault && t.response_code == 2'b10) ic_slverr++;
            if (t.fault && t.response_code == 2'b11) ic_decerr++;
            last_was_dc_write = 1'b0;
            return;
        end

        previous_ic_miss = 1'b0;
        if (t.op == cache_transaction::DC_READ) begin
            check_read(t);
            miss = (t.mem_read_count != 0);
            if (miss) dc_read_misses++; else dc_read_hits++;
            if (last_was_dc_write && last_dc_write_addr == t.addr && !t.fault)
                dc_raw_checks++;
            if (t.addr[3:0] > 4'd12 && !t.fault)
                dc_crossline_reads++;
            if (t.fault && !t.fault_is_writeback)
                dc_refill_errors++;
            if (t.addr == 32'h0000_0120 && !t.fault && miss)
                dc_writeback_refetches++;
            if (t.addr == 32'h0000_0b00 && !t.fault && !miss)
                dc_dirty_retained++;
            if (t.mem_write_count != 0 && !t.fault)
                dc_dirty_writebacks++;
            if (t.fault_is_writeback)
                dc_writeback_errors++;
            last_was_dc_write = 1'b0;
            return;
        end

        if (t.op == cache_transaction::DC_WRITE) begin
            writes++;
            miss = (t.mem_read_count != 0 || t.mem_write_count != 0);
            if (miss) dc_write_misses++; else dc_write_hits++;
            case (t.wstrb)
                4'b0001: wstrb_bins[0] = 1'b1;
                4'b0010: wstrb_bins[1] = 1'b1;
                4'b0100: wstrb_bins[2] = 1'b1;
                4'b1000: wstrb_bins[3] = 1'b1;
                4'b0011: wstrb_bins[4] = 1'b1;
                4'b1100: wstrb_bins[5] = 1'b1;
                4'b1111: wstrb_bins[6] = 1'b1;
                4'b0000: wstrb_bins[7] = 1'b1;
                default: ;
            endcase
            if (!t.fault) begin
                for (int unsigned i = 0; i < 4; i++)
                    if (t.wstrb[i]) ref_mem[t.addr+i] = t.wdata[i*8 +: 8];
            end
            if (t.mem_write_count != 0 && !t.fault)
                dc_dirty_writebacks++;
            if (t.fault_is_writeback)
                dc_writeback_errors++;
            last_was_dc_write = !t.fault;
            last_dc_write_addr = t.addr;
            return;
        end
    endfunction

    function bit queues_empty();
        return expected_ic_q.size() == 0 && expected_dc_addr_q.size() == 0 &&
               expected_dc_op_q.size() == 0 && expected_control_q.size() == 0;
    endfunction
endclass

`endif
