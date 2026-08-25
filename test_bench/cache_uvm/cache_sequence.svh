`ifndef YSYX_CACHE_SEQUENCE_SVH
`define YSYX_CACHE_SEQUENCE_SVH

class cache_sequence extends uvm_sequence #(cache_transaction);
    `uvm_object_utils(cache_sequence)
    int unsigned completed_operations;

    function new(string name = "cache_sequence");
        super.new(name);
    endfunction

    task automatic send_item(
        bit [2:0] op,
        bit [31:0] address = 0,
        bit [3:0] strobe = 0,
        bit [31:0] data = 0,
        bit [31:0] second_address = 0
    );
        cache_transaction item;
        item = cache_transaction::type_id::create("item");
        start_item(item);
        item.op = op;
        item.addr = address;
        item.addr2 = second_address;
        item.wstrb = strobe;
        item.wdata = data;
        finish_item(item);
        completed_operations++;
    endtask

    task body();
        bit [3:0] masks[8];

        // ICache: cold refill, resident hit, explicit flush invalidation,
        // consecutive misses, clean fill-age replacement, and non-allocating
        // SLVERR/DECERR responses.
        send_item(cache_transaction::IC_READ, 32'h0000_0000);
        send_item(cache_transaction::IC_READ, 32'h0000_0004);
        send_item(cache_transaction::IC_FLUSH);
        send_item(cache_transaction::IC_READ, 32'h0000_0004);
        send_item(cache_transaction::IC_READ, 32'h0000_0004);
        // Abort an accepted miss while its injected SLVERR response is still
        // outstanding.  The second address is held at the CPU interface during
        // drain and must be accepted/refilled only after the stale response is
        // discarded.
        send_item(cache_transaction::IC_FLUSH_INFLIGHT,
                  32'h0000_0750, 4'b0, 32'b0, 32'h0000_0760);
        send_item(cache_transaction::IC_READ, 32'h0000_0100);
        send_item(cache_transaction::IC_READ, 32'h0000_0200);
        send_item(cache_transaction::IC_READ, 32'h0000_0300);
        send_item(cache_transaction::IC_READ, 32'h0000_0400);
        send_item(cache_transaction::IC_READ, 32'h0000_0800);
        send_item(cache_transaction::IC_READ, 32'h0000_0800);
        send_item(cache_transaction::IC_READ, 32'h0000_0900);
        send_item(cache_transaction::IC_READ, 32'h0000_0900);

        // Reset is independently checked as a cache-invalidation path.  The
        // backing memory model intentionally retains its contents.
        send_item(cache_transaction::CACHE_RESET);
        send_item(cache_transaction::IC_READ, 32'h0000_0004);

        // Both cache controllers become outstanding together.  The line
        // memory responder accepts and services both channels in parallel.
        send_item(cache_transaction::ID_CONCURRENT_READ,
                  32'h0000_0550, 4'b0, 32'b0, 32'h0000_0650);

        // DCache read miss/hit.
        send_item(cache_transaction::DC_READ, 32'h0000_0040);
        send_item(cache_transaction::DC_READ, 32'h0000_0040);

        // All supported byte-mask classes followed immediately by a read,
        // making every mask an independently checked RAW dependency.
        masks[0] = 4'b0001;
        masks[1] = 4'b0010;
        masks[2] = 4'b0100;
        masks[3] = 4'b1000;
        masks[4] = 4'b0011;
        masks[5] = 4'b1100;
        masks[6] = 4'b1111;
        masks[7] = 4'b0000;
        for (int unsigned i = 0; i < 8; i++) begin
            send_item(cache_transaction::DC_WRITE, 32'h0000_0044,
                      masks[i], 32'h1020_3040 ^ (32'h1111_1111 * i));
            send_item(cache_transaction::DC_READ, 32'h0000_0044);
        end

        // Write allocate and a cross-line read (offset 13).
        send_item(cache_transaction::DC_WRITE, 32'h0000_0180,
                  4'b1111, 32'h89ab_cdef);
        send_item(cache_transaction::DC_READ, 32'h0000_0180);
        send_item(cache_transaction::DC_READ, 32'h0000_070d);

        // Five dirty lines mapped to one set force a successful writeback;
        // refetching the oldest line proves the backing-store update.
        send_item(cache_transaction::DC_WRITE, 32'h0000_0120,
                  4'b1111, 32'h1200_0001);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0220,
                  4'b1111, 32'h2200_0002);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0320,
                  4'b1111, 32'h3200_0003);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0420,
                  4'b1111, 32'h4200_0004);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0520,
                  4'b1111, 32'h5200_0005);
        send_item(cache_transaction::DC_READ, 32'h0000_0120);

        // Repeated refill error proves failed reads do not allocate.
        send_item(cache_transaction::DC_READ, 32'h0000_0a00);
        send_item(cache_transaction::DC_READ, 32'h0000_0a00);

        // The first dirty line in this set is configured to reject writeback.
        // The fifth allocation aborts; the old line must remain resident.
        send_item(cache_transaction::DC_WRITE, 32'h0000_0b00,
                  4'b1111, 32'hb00b_0001);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0c00,
                  4'b1111, 32'hc00c_0002);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0d00,
                  4'b1111, 32'hd00d_0003);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0e00,
                  4'b1111, 32'he00e_0004);
        send_item(cache_transaction::DC_WRITE, 32'h0000_0f00,
                  4'b1111, 32'hf00f_0005);
        send_item(cache_transaction::DC_READ, 32'h0000_0b00);
    endtask
endclass

`endif
