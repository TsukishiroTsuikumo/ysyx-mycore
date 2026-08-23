`ifndef YSYX_AXI_MASTER_SEQUENCE_SVH
`define YSYX_AXI_MASTER_SEQUENCE_SVH

// Active-master regression sequence for the cache-line AXI subset.  In
// addition to the original read/write/read smoke, this sequence checks byte
// strobes, constrained-random addresses/delays, deterministic stress traffic,
// and injected read/write error responses.  The driver remains deliberately
// single-outstanding, matching the implemented cache adapters.
class axi_master_sequence #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_sequence #(
    axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    )
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned LINE_BEATS = 4;
    localparam int unsigned RANDOM_READS = 6;
    localparam int unsigned STRESS_WRITE_PAIRS = 3;
    localparam bit [31:0] INITIAL_DATA_TAG = 32'h6000_0000;
    localparam bit [31:0] WRITE_DATA_TAG   = 32'ha5a5_0000;
    localparam bit [31:0] PARTIAL_DATA_TAG = 32'h1122_3344;
    localparam bit [31:0] STRESS_DATA_TAG  = 32'h9000_0000;
    localparam bit [ADDR_WIDTH-1:0] ERROR_ADDR = 'h800;

    typedef axi_master_sequence #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;

    `uvm_object_param_utils(this_type)

    int unsigned completed_transactions;
    int unsigned completed_reads;
    int unsigned completed_writes;
    int unsigned check_count;
    int unsigned error_count;

    function new(string name = "axi_master_sequence");
        super.new(name);
        completed_transactions = 0;
        completed_reads = 0;
        completed_writes = 0;
        check_count = 0;
        error_count = 0;
    endfunction

    function void configure_line_item(
        txn_t item,
        input axi_direction_e direction,
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [ID_WIDTH-1:0] id,
        input bit [OWNER_WIDTH-1:0] owner,
        input int unsigned address_delay,
        input int unsigned beat_delay,
        input int unsigned response_delay
    );
        item.direction = direction;
        item.id = id;
        item.addr = addr;
        item.len = LINE_BEATS - 1;
        item.size = $clog2(STRB_WIDTH);
        item.burst = AXI_BURST_INCR;
        item.lock = 1'b0;
        item.cache = 4'b0011;
        item.prot = 3'b000;
        item.qos = 4'b0;
        item.region = 4'b0;
        item.address_user = '0;
        item.owner = owner;
        item.address_delay_cycles = address_delay;
        item.beat_delay_cycles = beat_delay;
        item.response_ready_delay_cycles = response_delay;
    endfunction

    function automatic bit [DATA_WIDTH-1:0] merge_strobe(
        input bit [DATA_WIDTH-1:0] original,
        input bit [DATA_WIDTH-1:0] update,
        input bit [STRB_WIDTH-1:0] strobe
    );
        bit [DATA_WIDTH-1:0] result;
        result = original;
        for (int unsigned byte_index = 0; byte_index < STRB_WIDTH;
             byte_index++) begin
            if (strobe[byte_index]) begin
                result[byte_index*8 +: 8] = update[byte_index*8 +: 8];
            end
        end
        return result;
    endfunction

    function void check_read_line(
        txn_t item,
        input bit [DATA_WIDTH-1:0] expected_data_q[$],
        input axi_resp_e expected_resp,
        input bit check_data
    );
        if (item.data_q.size() != LINE_BEATS ||
            item.resp_q.size() != LINE_BEATS ||
            item.last_q.size() != LINE_BEATS) begin
            error_count++;
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "read payload sizes data=%0d resp=%0d last=%0d expected=%0d",
                item.data_q.size(), item.resp_q.size(), item.last_q.size(),
                LINE_BEATS))
            return;
        end
        if (check_data && expected_data_q.size() != LINE_BEATS) begin
            error_count++;
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "expected read payload has %0d beats, expected %0d",
                expected_data_q.size(), LINE_BEATS))
            return;
        end

        foreach (item.data_q[beat]) begin
            check_count++;
            if (check_data && item.data_q[beat] !== expected_data_q[beat]) begin
                error_count++;
                `uvm_error("AXI_MASTER_SEQ", $sformatf(
                    "read data mismatch beat=%0d expected=0x%08x actual=0x%08x",
                    beat, expected_data_q[beat], item.data_q[beat]))
            end
            if (item.resp_q[beat] != expected_resp) begin
                error_count++;
                `uvm_error("AXI_MASTER_SEQ", $sformatf(
                    "read response mismatch beat=%0d expected=0x%0x actual=0x%0x",
                    beat, expected_resp, item.resp_q[beat]))
            end
            if (item.last_q[beat] !== (beat == (LINE_BEATS - 1))) begin
                error_count++;
                `uvm_error("AXI_MASTER_SEQ", $sformatf(
                    "read LAST mismatch beat=%0d last=%0d",
                    beat, item.last_q[beat]))
            end
        end
    endfunction

    task send_read_line(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [ID_WIDTH-1:0] id,
        input bit [OWNER_WIDTH-1:0] owner,
        input bit [DATA_WIDTH-1:0] expected_data_q[$],
        input axi_resp_e expected_resp,
        input bit check_data,
        input int unsigned address_delay,
        input int unsigned beat_delay,
        input int unsigned response_delay
    );
        txn_t item;

        item = txn_t::type_id::create("read_item");
        start_item(item);
        configure_line_item(item, AXI_READ, addr, id, owner,
                            address_delay, beat_delay, response_delay);
        finish_item(item);
        completed_transactions++;
        completed_reads++;
        check_read_line(item, expected_data_q, expected_resp, check_data);
    endtask

    task send_constrained_random_read();
        txn_t item;
        bit [DATA_WIDTH-1:0] expected_data_q[$];
        bit [DATA_WIDTH-1:0] expected_base;

        item = txn_t::type_id::create("random_read_item");
        start_item(item);
        if (!item.randomize() with {
            addr inside {[32'h0000_0300:32'h0000_03f0]};
            addr[3:0] == 4'b0000;
            id inside {0, 1};
            owner == id[0];
            address_delay_cycles inside {[0:3]};
            beat_delay_cycles inside {[0:3]};
            response_ready_delay_cycles inside {[1:4]};
        }) begin
            `uvm_fatal("AXI_MASTER_SEQ",
                "Failed to randomize bounded cache-line read")
        end
        configure_line_item(item, AXI_READ, item.addr, item.id, item.owner,
                            item.address_delay_cycles,
                            item.beat_delay_cycles,
                            item.response_ready_delay_cycles);
        finish_item(item);

        expected_base = INITIAL_DATA_TAG + (item.addr >> 2);
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
            expected_data_q.push_back(expected_base + beat);
        end
        completed_transactions++;
        completed_reads++;
        check_read_line(item, expected_data_q, AXI_RESP_OKAY, 1'b1);
    endtask

    task send_write_line(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [ID_WIDTH-1:0] id,
        input bit [OWNER_WIDTH-1:0] owner,
        input bit [DATA_WIDTH-1:0] data_base,
        input bit partial_strobes,
        input axi_resp_e expected_resp,
        input int unsigned address_delay,
        input int unsigned beat_delay,
        input int unsigned response_delay
    );
        txn_t item;
        bit [STRB_WIDTH-1:0] strobe;

        item = txn_t::type_id::create("write_item");
        start_item(item);
        configure_line_item(item, AXI_WRITE, addr, id, owner,
                            address_delay, beat_delay, response_delay);
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
            item.data_q.push_back(data_base +
                                  (partial_strobes ?
                                   (beat * 32'h1111_1111) : beat));
            strobe = partial_strobes ? ({{(STRB_WIDTH-1){1'b0}}, 1'b1} << beat) :
                                         {STRB_WIDTH{1'b1}};
            item.strb_q.push_back(strobe);
            item.data_user_q.push_back('0);
        end
        finish_item(item);
        completed_transactions++;
        completed_writes++;
        check_count++;
        if (item.bresp != expected_resp) begin
            error_count++;
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "write response mismatch expected=0x%0x actual=0x%0x",
                expected_resp, item.bresp))
        end
    endtask

    virtual task body();
        bit [DATA_WIDTH-1:0] expected_data_q[$];
        bit [DATA_WIDTH-1:0] initial_expected;
        bit [DATA_WIDTH-1:0] update_data;
        bit [STRB_WIDTH-1:0] update_strobe;
        bit [ADDR_WIDTH-1:0] stress_addr;
        bit [DATA_WIDTH-1:0] stress_data;

        if (DATA_WIDTH != 32 || STRB_WIDTH != 4 || ID_WIDTH < 2 ||
            OWNER_WIDTH < 1) begin
            `uvm_fatal("AXI_MASTER_SEQ",
                "Regression sequence requires 32-bit data, >=2 ID bits and an owner bit")
        end

        // Original read/write/read line smoke.
        initial_expected = INITIAL_DATA_TAG + ('h40 >> 2);
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++)
            expected_data_q.push_back(initial_expected + beat);
        send_read_line('h40, '0, '0, expected_data_q, AXI_RESP_OKAY,
                       1'b1, 1, 1, 2);

        send_write_line('h100, 'd1, 'd1, WRITE_DATA_TAG, 1'b0,
                        AXI_RESP_OKAY, 1, 1, 2);
        expected_data_q.delete();
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++)
            expected_data_q.push_back(WRITE_DATA_TAG + beat);
        send_read_line('h100, 'd1, 'd1, expected_data_q, AXI_RESP_OKAY,
                       1'b1, 1, 1, 2);

        // Full-line transfer with one distinct byte enabled per beat.
        send_write_line('h140, 'd1, 'd1, PARTIAL_DATA_TAG, 1'b1,
                        AXI_RESP_OKAY, 2, 2, 3);
        expected_data_q.delete();
        initial_expected = INITIAL_DATA_TAG + ('h140 >> 2);
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
            update_data = PARTIAL_DATA_TAG + (beat * 32'h1111_1111);
            update_strobe = (4'b0001 << beat);
            expected_data_q.push_back(merge_strobe(
                initial_expected + beat, update_data, update_strobe));
        end
        send_read_line('h140, 'd1, 'd1, expected_data_q, AXI_RESP_OKAY,
                       1'b1, 1, 1, 3);

        // Constrained-random aligned line reads.  The memory pattern makes the
        // expected result derivable from the randomized address.
        repeat (RANDOM_READS) send_constrained_random_read();

        // Deterministic write/read stress pairs keep a software oracle while
        // covering multiple lines and longer channel stall combinations.
        for (int unsigned pair = 0; pair < STRESS_WRITE_PAIRS; pair++) begin
            stress_addr = 'h400 + (pair * 'h40);
            stress_data = STRESS_DATA_TAG + (pair * 'h100);
            send_write_line(stress_addr, 'd1, 'd1, stress_data, 1'b0,
                            AXI_RESP_OKAY, pair, pair + 1, pair + 2);
            expected_data_q.delete();
            for (int unsigned beat = 0; beat < LINE_BEATS; beat++)
                expected_data_q.push_back(stress_data + beat);
            send_read_line(stress_addr, 'd1, 'd1, expected_data_q,
                           AXI_RESP_OKAY, 1'b1,
                           pair + 1, pair, pair + 2);
        end

        // The slave injects SLVERR on this line.  Data is intentionally not
        // checked, but all response beats, IDs and LAST placement still are.
        expected_data_q.delete();
        send_read_line(ERROR_ADDR, 'd1, 'd1, expected_data_q,
                       AXI_RESP_SLVERR, 1'b0, 3, 2, 4);
        send_write_line(ERROR_ADDR, 'd1, 'd1, 32'hdead_0000, 1'b0,
                        AXI_RESP_SLVERR, 3, 2, 4);

        if (completed_transactions != 19 || completed_reads != 13 ||
            completed_writes != 6 || check_count != 58 || error_count != 0) begin
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "sequence summary transactions=%0d reads=%0d writes=%0d checks=%0d errors=%0d",
                completed_transactions, completed_reads, completed_writes,
                check_count, error_count))
        end
        else begin
            `uvm_info("AXI_MASTER_SEQ", $sformatf(
                "transactions=%0d reads=%0d writes=%0d checks=%0d errors=%0d",
                completed_transactions, completed_reads, completed_writes,
                check_count, error_count), UVM_LOW)
        end
    endtask

endclass

`endif
