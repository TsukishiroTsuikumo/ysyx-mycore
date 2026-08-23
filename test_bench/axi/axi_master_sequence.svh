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
        bit [ADDR_WIDTH-1:0] random_addr;
        bit [ID_WIDTH-1:0] random_id;
        bit [OWNER_WIDTH-1:0] random_owner;
        int unsigned address_delay;
        int unsigned beat_delay;
        int unsigned response_delay;

        item = txn_t::type_id::create("random_read_item");
        start_item(item);
        // Generate random values inside explicit legal bounds without relying
        // on an external SAT solver.  This keeps the regression runnable in
        // the stock Verilator container while retaining randomized traffic.
        random_addr = 32'h0000_0300 + ($urandom_range(15, 0) << 4);
        random_id = $urandom_range(1, 0);
        random_owner = random_id[0];
        address_delay = $urandom_range(3, 0);
        beat_delay = $urandom_range(3, 0);
        response_delay = $urandom_range(4, 1);
        configure_line_item(item, AXI_READ, random_addr, random_id,
                            random_owner, address_delay, beat_delay,
                            response_delay);
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

// Reproducible, solver-free stress sequence for the implemented cache-line
// subset.  The PRNG controls ordering, addresses, data, strobes and all master
// timing knobs.  A small number of choices are deliberately forced into bins
// so every seed satisfies the advertised minimum coverage contract while all
// remaining choices still vary with AXI_RANDOM_SEED.
class axi_random_stress_sequence #(
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
    localparam int unsigned MEM_WORDS = 1024;
    localparam int unsigned TOTAL_TRANSACTIONS = 64;
    localparam int unsigned REQUIRED_READS = 32;
    localparam int unsigned REQUIRED_WRITES = 32;
    localparam bit [31:0] INITIAL_DATA_TAG = 32'h6000_0000;
    localparam bit [ADDR_WIDTH-1:0] SLVERR_ADDR = 'h800;
    localparam bit [ADDR_WIDTH-1:0] DECERR_ADDR = 'h900;
    localparam int unsigned STROBE_FULL = 0;
    localparam int unsigned STROBE_SINGLE = 1;
    localparam int unsigned STROBE_MULTI = 2;
    localparam int unsigned STROBE_ZERO = 3;

    typedef axi_random_stress_sequence #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;

    `uvm_object_param_utils(this_type)

    int unsigned random_seed;
    int unsigned prng_state;
    int unsigned completed_transactions;
    int unsigned completed_reads;
    int unsigned completed_writes;
    int unsigned check_count;
    int unsigned error_count;
    int unsigned paired_readbacks;
    int unsigned error_write_unchanged;
    int unsigned successful_write_count;
    longint unsigned address_delay_bucket_hits[0:2];
    longint unsigned beat_delay_bucket_hits[0:2];
    longint unsigned response_delay_bucket_hits[0:2];
    bit [DATA_WIDTH-1:0] expected_mem[0:MEM_WORDS-1];
    bit [ADDR_WIDTH-1:0] used_okay_addr_q[$];
    bit [ADDR_WIDTH-1:0] pending_addr_q[$];
    axi_resp_e pending_resp_q[$];
    int unsigned pending_pair_index_q[$];
    bit pending_error_contract_q[$];

    function new(string name = "axi_random_stress_sequence");
        super.new(name);
        random_seed = 32'h51a7_2026;
        prng_state = random_seed;
        completed_transactions = 0;
        completed_reads = 0;
        completed_writes = 0;
        check_count = 0;
        error_count = 0;
        paired_readbacks = 0;
        error_write_unchanged = 0;
        successful_write_count = 0;
        foreach (address_delay_bucket_hits[i])
            address_delay_bucket_hits[i] = 0;
        foreach (beat_delay_bucket_hits[i])
            beat_delay_bucket_hits[i] = 0;
        foreach (response_delay_bucket_hits[i])
            response_delay_bucket_hits[i] = 0;
    endfunction

    function int unsigned next_random();
        int unsigned value;
        value = prng_state;
        value ^= (value << 13);
        value ^= (value >> 17);
        value ^= (value << 5);
        if (value == 0) value = 32'h6d2b_79f5;
        prng_state = value;
        return value;
    endfunction

    function int unsigned delay_bucket(input int unsigned delay_cycles);
        if (delay_cycles == 0) return 0;
        if (delay_cycles <= 3) return 1;
        return 2;
    endfunction

    function int unsigned random_delay_in_bucket(input int unsigned bucket);
        case (bucket)
            0: return 0;
            1: return 1 + (next_random() % 3);
            default: return 4 + (next_random() % 4);
        endcase
    endfunction

    function int unsigned choose_delay(
        input int unsigned transaction_index,
        input int unsigned control_index
    );
        int unsigned chosen_bucket;
        int unsigned value;
        // Stagger the first three transactions so each independent timing
        // control observes zero, short (1..3) and long (4..7) delays.
        if (transaction_index < 3)
            chosen_bucket = (transaction_index + control_index) % 3;
        else
            chosen_bucket = next_random() % 3;
        value = random_delay_in_bucket(chosen_bucket);
        case (control_index)
            0: address_delay_bucket_hits[delay_bucket(value)]++;
            1: beat_delay_bucket_hits[delay_bucket(value)]++;
            default: response_delay_bucket_hits[delay_bucket(value)]++;
        endcase
        return value;
    endfunction

    function bit [ADDR_WIDTH-1:0] choose_random_line_addr();
        int unsigned line_index;
        do begin
            // 0x100..0xfe0, always 16-byte aligned and wholly below 4 KiB.
            line_index = 16 + (next_random() % 239);
        end while ((line_index == (SLVERR_ADDR >> 4)) ||
                   (line_index == (DECERR_ADDR >> 4)));
        return (line_index << 4);
    endfunction

    function bit okay_addr_already_used(
        input bit [ADDR_WIDTH-1:0] candidate
    );
        foreach (used_okay_addr_q[i]) begin
            if (used_okay_addr_q[i] == candidate) return 1'b1;
        end
        return 1'b0;
    endfunction

    function bit [ADDR_WIDTH-1:0] choose_unique_okay_line_addr();
        bit [ADDR_WIDTH-1:0] candidate;
        do candidate = choose_random_line_addr();
        while (okay_addr_already_used(candidate));
        used_okay_addr_q.push_back(candidate);
        return candidate;
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
        int unsigned random_value;
        item.direction = direction;
        item.id = id;
        item.addr = addr;
        item.len = LINE_BEATS - 1;
        item.size = $clog2(STRB_WIDTH);
        item.burst = AXI_BURST_INCR;
        item.lock = 1'b0;
        random_value = next_random();
        item.cache = random_value;
        random_value = next_random();
        item.prot = random_value;
        random_value = next_random();
        item.qos = random_value;
        item.region = '0;
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
            if (strobe[byte_index])
                result[byte_index*8 +: 8] = update[byte_index*8 +: 8];
        end
        return result;
    endfunction

    function bit [STRB_WIDTH-1:0] choose_strobe(
        input int unsigned strobe_mode
    );
        int unsigned selection;
        bit [STRB_WIDTH-1:0] result;
        selection = next_random();
        result = '0;
        case (strobe_mode)
            STROBE_FULL: return {STRB_WIDTH{1'b1}};
            STROBE_SINGLE: begin
                result[selection % STRB_WIDTH] = 1'b1;
                return result;
            end
            STROBE_MULTI: begin
                case (selection % 6)
                    0: return 4'b0011;
                    1: return 4'b0110;
                    2: return 4'b1100;
                    3: return 4'b1001;
                    4: return 4'b0111;
                    default: return 4'b1110;
                endcase
            end
            default: return '0;
        endcase
    endfunction

    task send_paired_read(
        input int unsigned transaction_index,
        input int unsigned read_index,
        input bit [ADDR_WIDTH-1:0] addr,
        input axi_resp_e expected_resp,
        input int unsigned pair_index,
        input bit check_error_write_unchanged
    );
        txn_t item;
        bit [ID_WIDTH-1:0] id;
        bit [OWNER_WIDTH-1:0] owner;
        bit transaction_ok;
        int unsigned word_index;
        int unsigned address_delay;
        int unsigned beat_delay;
        int unsigned response_delay;

        // The 30 successful readbacks alone guarantee at least eight reads
        // from each owner; error-contract reads keep a seed-driven owner.
        if (!check_error_write_unchanged && pair_index < 8)
            owner = '0;
        else if (!check_error_write_unchanged && pair_index < 16)
            owner = 'd1;
        else
            owner = next_random() & 1;
        id = owner[0] ? 'd1 : 'd0;
        address_delay = choose_delay(transaction_index, 0);
        // This knob is not consumed by the R channel, but remains seeded on
        // every item.  Only write-side values populate beat-delay bins.
        beat_delay = next_random() % 8;
        response_delay = choose_delay(transaction_index, 2);

        item = txn_t::type_id::create($sformatf("paired_read_%0d", read_index));
        start_item(item);
        configure_line_item(item, AXI_READ, addr, id, owner,
                            address_delay, beat_delay, response_delay);
        finish_item(item);

        transaction_ok = 1'b1;
        if (item.data_q.size() != LINE_BEATS ||
            item.resp_q.size() != LINE_BEATS ||
            item.last_q.size() != LINE_BEATS) begin
            transaction_ok = 1'b0;
            error_count++;
            `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                "read payload size mismatch index=%0d data=%0d resp=%0d last=%0d",
                read_index, item.data_q.size(), item.resp_q.size(),
                item.last_q.size()))
        end
        else begin
            word_index = addr >> 2;
            for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
                check_count++;
                if (item.resp_q[beat] != expected_resp) begin
                    transaction_ok = 1'b0;
                    error_count++;
                    `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                        "read response mismatch index=%0d beat=%0d expected=%0x actual=%0x",
                        read_index, beat, expected_resp, item.resp_q[beat]))
                end
                if (item.last_q[beat] !== (beat == (LINE_BEATS - 1))) begin
                    transaction_ok = 1'b0;
                    error_count++;
                    `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                        "read LAST mismatch index=%0d beat=%0d last=%0d",
                        read_index, beat, item.last_q[beat]))
                end
                // For error responses AXI does not generally define useful
                // read data.  This comparison intentionally verifies the
                // standalone test slave's stronger contract: an error write
                // must not mutate its backing memory, and its paired error
                // read returns the unchanged four data beats.
                if (item.data_q[beat] !== expected_mem[word_index + beat]) begin
                    transaction_ok = 1'b0;
                    error_count++;
                    `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                        "paired read data mismatch index=%0d beat=%0d expected=%08x actual=%08x",
                        read_index, beat, expected_mem[word_index + beat],
                        item.data_q[beat]))
                end
            end
        end

        if (transaction_ok) begin
            if (check_error_write_unchanged)
                error_write_unchanged++;
            else
                paired_readbacks++;
        end
        completed_transactions++;
        completed_reads++;
    endtask

    task send_random_write(
        input int unsigned transaction_index,
        input int unsigned write_index
    );
        txn_t item;
        bit [ADDR_WIDTH-1:0] addr;
        bit [DATA_WIDTH-1:0] data;
        bit [STRB_WIDTH-1:0] strobe;
        axi_resp_e expected_resp;
        bit check_error_contract;
        int unsigned strobe_mode;
        int unsigned pair_index;
        int unsigned word_index;
        int unsigned address_delay;
        int unsigned beat_delay;
        int unsigned response_delay;

        if (write_index == 0) begin
            addr = SLVERR_ADDR;
            expected_resp = AXI_RESP_SLVERR;
            check_error_contract = 1'b1;
            pair_index = 0;
        end
        else if (write_index == 1) begin
            addr = DECERR_ADDR;
            expected_resp = AXI_RESP_DECERR;
            check_error_contract = 1'b1;
            pair_index = 1;
        end
        else begin
            pair_index = write_index - 2;
            addr = choose_unique_okay_line_addr();
            expected_resp = AXI_RESP_OKAY;
            check_error_contract = 1'b0;
        end
        // Error writes deliberately attempt a full-line mutation with data
        // distinct from the pre-write image.  Their paired reads therefore
        // prove that an error response suppressed a real write, rather than
        // passing vacuously because the random strobe happened to be zero.
        // Only successful writes can satisfy required WSTRB bins.  The first
        // four successful writes deterministically hit full/single/multi/zero;
        // later successful writes remain seed-driven.
        if (check_error_contract)
            strobe_mode = STROBE_FULL;
        else if (pair_index < 4)
            strobe_mode = pair_index;
        else
            strobe_mode = next_random() % 4;
        address_delay = choose_delay(transaction_index, 0);
        // Force the first three *writes* across the three delay ranges.  This
        // makes the bin guarantee independent of the randomized R/W ordering.
        beat_delay = choose_delay(write_index, 1);
        response_delay = choose_delay(transaction_index, 2);

        item = txn_t::type_id::create($sformatf("random_write_%0d", write_index));
        start_item(item);
        configure_line_item(item, AXI_WRITE, addr, 'd1, 'd1,
                            address_delay, beat_delay, response_delay);
        word_index = addr >> 2;
        for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
            if (check_error_contract)
                data = ~expected_mem[word_index + beat];
            else
                data = next_random();
            strobe = choose_strobe(strobe_mode);
            item.data_q.push_back(data);
            item.strb_q.push_back(strobe);
            item.data_user_q.push_back('0);
        end
        finish_item(item);

        check_count++;
        if (item.bresp != expected_resp) begin
            error_count++;
            `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                "write response mismatch index=%0d expected=%0x actual=%0x",
                write_index, expected_resp, item.bresp))
        end
        if (expected_resp == AXI_RESP_OKAY) begin
            for (int unsigned beat = 0; beat < LINE_BEATS; beat++) begin
                expected_mem[word_index + beat] = merge_strobe(
                    expected_mem[word_index + beat], item.data_q[beat],
                    item.strb_q[beat]);
            end
            if (item.bresp == AXI_RESP_OKAY) successful_write_count++;
        end

        // A read becomes schedulable only after the corresponding write and
        // B response have completed.  Parallel queues form one dependency-safe
        // pending descriptor and each entry is removed exactly once.
        pending_addr_q.push_back(addr);
        pending_resp_q.push_back(expected_resp);
        pending_pair_index_q.push_back(pair_index);
        pending_error_contract_q.push_back(check_error_contract);
        completed_transactions++;
        completed_writes++;
    endtask

    virtual task body();
        int unsigned read_index;
        int unsigned write_index;
        int unsigned choice;
        int unsigned pending_index;
        bit [ADDR_WIDTH-1:0] pending_addr;
        axi_resp_e pending_resp;
        int unsigned pending_pair_index;
        bit pending_error_contract;

        if (DATA_WIDTH != 32 || STRB_WIDTH != 4 || ID_WIDTH < 2 ||
            OWNER_WIDTH < 1) begin
            `uvm_fatal("AXI_RANDOM_SEQ",
                "Random stress requires 32-bit data, >=2 ID bits and an owner bit")
        end

        void'($value$plusargs("AXI_RANDOM_SEED=%h", random_seed));
        if (random_seed == 0) begin
            `uvm_fatal("AXI_RANDOM_SEQ", "AXI_RANDOM_SEED must be non-zero")
        end
        prng_state = random_seed;
        $display("AXI_RANDOM_SEED seed=0x%08x", random_seed);

        for (int unsigned word = 0; word < MEM_WORDS; word++)
            expected_mem[word] = INITIAL_DATA_TAG + word;

        read_index = 0;
        write_index = 0;
        for (int unsigned transaction_index = 0;
             transaction_index < TOTAL_TRANSACTIONS; transaction_index++) begin
            // A pending read exists only after its write has completed.  The
            // seed chooses between another write and one randomly selected
            // dependency-ready read; boundary conditions force progress.
            choice = next_random() & 1;
            if ((write_index < REQUIRED_WRITES) &&
                ((pending_addr_q.size() == 0) || (choice != 0))) begin
                send_random_write(transaction_index, write_index);
                write_index++;
            end
            else begin
                pending_index = next_random() % pending_addr_q.size();
                pending_addr = pending_addr_q[pending_index];
                pending_resp = pending_resp_q[pending_index];
                pending_pair_index = pending_pair_index_q[pending_index];
                pending_error_contract =
                    pending_error_contract_q[pending_index];
                pending_addr_q.delete(pending_index);
                pending_resp_q.delete(pending_index);
                pending_pair_index_q.delete(pending_index);
                pending_error_contract_q.delete(pending_index);
                send_paired_read(transaction_index, read_index, pending_addr,
                                 pending_resp, pending_pair_index,
                                 pending_error_contract);
                read_index++;
            end
        end

        if (completed_transactions != TOTAL_TRANSACTIONS ||
            completed_reads != REQUIRED_READS ||
            completed_writes != REQUIRED_WRITES ||
            successful_write_count != 30 || used_okay_addr_q.size() != 30 ||
            paired_readbacks != 30 || error_write_unchanged != 2 ||
            pending_addr_q.size() != 0 || pending_resp_q.size() != 0 ||
            pending_pair_index_q.size() != 0 ||
            pending_error_contract_q.size() != 0 || error_count != 0) begin
            error_count++;
            `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                "summary txns=%0d reads=%0d writes=%0d successful_writes=%0d unique_addrs=%0d paired_readbacks=%0d error_write_unchanged=%0d pending=%0d checks=%0d errors=%0d",
                completed_transactions, completed_reads, completed_writes,
                successful_write_count, used_okay_addr_q.size(),
                paired_readbacks, error_write_unchanged,
                pending_addr_q.size(), check_count, error_count))
        end
        foreach (address_delay_bucket_hits[i]) begin
            if (address_delay_bucket_hits[i] == 0 ||
                beat_delay_bucket_hits[i] == 0 ||
                response_delay_bucket_hits[i] == 0) begin
                error_count++;
                `uvm_error("AXI_RANDOM_SEQ", $sformatf(
                    "delay bucket %0d missing addr=%0d beat=%0d response=%0d",
                    i, address_delay_bucket_hits[i],
                    beat_delay_bucket_hits[i],
                    response_delay_bucket_hits[i]))
            end
        end
    endtask

endclass

`endif
