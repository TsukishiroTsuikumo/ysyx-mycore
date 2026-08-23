`ifndef YSYX_AXI_MASTER_SEQUENCE_SVH
`define YSYX_AXI_MASTER_SEQUENCE_SVH

// Directed active-master smoke sequence.  It verifies an initialized line,
// writes another complete line, and reads the line back through the same AXI
// agent.  Instruction/data owner and ID mappings match the cache subsystem.
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
    localparam bit [31:0] INITIAL_DATA_TAG = 32'h6000_0000;
    localparam bit [31:0] WRITE_DATA_TAG   = 32'ha5a5_0000;

    typedef axi_master_sequence #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;

    `uvm_object_param_utils(this_type)

    int unsigned completed_transactions;
    int unsigned check_count;
    int unsigned error_count;

    function new(string name = "axi_master_sequence");
        super.new(name);
        completed_transactions = 0;
        check_count = 0;
        error_count = 0;
    endfunction

    function void configure_line_item(
        txn_t item,
        input axi_direction_e direction,
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [ID_WIDTH-1:0] id,
        input bit [OWNER_WIDTH-1:0] owner
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
        item.address_delay_cycles = 1;
        item.beat_delay_cycles = 1;
        item.response_ready_delay_cycles = 2;
    endfunction

    function void check_read_line(
        txn_t item,
        input bit [DATA_WIDTH-1:0] expected_base
    );
        bit [DATA_WIDTH-1:0] expected_data;

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

        foreach (item.data_q[beat]) begin
            expected_data = expected_base + beat;
            check_count++;
            if (item.data_q[beat] !== expected_data) begin
                error_count++;
                `uvm_error("AXI_MASTER_SEQ", $sformatf(
                    "read data mismatch beat=%0d expected=0x%08x actual=0x%08x",
                    beat, expected_data, item.data_q[beat]))
            end
            if (item.resp_q[beat] != AXI_RESP_OKAY) begin
                error_count++;
                `uvm_error("AXI_MASTER_SEQ", $sformatf(
                    "read response error beat=%0d resp=0x%0x",
                    beat, item.resp_q[beat]))
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
        input bit [DATA_WIDTH-1:0] expected_base
    );
        txn_t item;

        item = txn_t::type_id::create("read_item");
        start_item(item);
        configure_line_item(item, AXI_READ, addr, id, owner);
        finish_item(item);
        completed_transactions++;
        check_read_line(item, expected_base);
    endtask

    task send_write_line(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [ID_WIDTH-1:0] id,
        input bit [OWNER_WIDTH-1:0] owner
    );
        txn_t item;
        int unsigned beat;

        item = txn_t::type_id::create("write_item");
        start_item(item);
        configure_line_item(item, AXI_WRITE, addr, id, owner);
        for (beat = 0; beat < LINE_BEATS; beat++) begin
            item.data_q.push_back(WRITE_DATA_TAG + beat);
            item.strb_q.push_back({STRB_WIDTH{1'b1}});
            item.data_user_q.push_back('0);
        end
        finish_item(item);
        completed_transactions++;
        check_count++;
        if (item.bresp != AXI_RESP_OKAY) begin
            error_count++;
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "write response error resp=0x%0x", item.bresp))
        end
    endtask

    virtual task body();
        bit [ADDR_WIDTH-1:0] initial_read_addr;
        bit [ADDR_WIDTH-1:0] write_addr;
        bit [DATA_WIDTH-1:0] initial_expected;

        if (DATA_WIDTH != 32 || STRB_WIDTH != 4) begin
            `uvm_fatal("AXI_MASTER_SEQ", "Smoke sequence requires 32-bit AXI data")
        end

        initial_read_addr = 'h40;
        write_addr = 'h100;
        initial_expected = INITIAL_DATA_TAG + (initial_read_addr >> 2);

        send_read_line(initial_read_addr, '0, '0, initial_expected);
        send_write_line(write_addr, {{(ID_WIDTH-1){1'b0}}, 1'b1},
                        {{(OWNER_WIDTH-1){1'b0}}, 1'b1});
        send_read_line(write_addr, {{(ID_WIDTH-1){1'b0}}, 1'b1},
                       {{(OWNER_WIDTH-1){1'b0}}, 1'b1}, WRITE_DATA_TAG);

        if (completed_transactions != 3 || check_count != 9 ||
            error_count != 0) begin
            `uvm_error("AXI_MASTER_SEQ", $sformatf(
                "sequence summary transactions=%0d checks=%0d errors=%0d",
                completed_transactions, check_count, error_count))
        end
        else begin
            `uvm_info("AXI_MASTER_SEQ", $sformatf(
                "transactions=%0d checks=%0d errors=%0d",
                completed_transactions, check_count, error_count), UVM_LOW)
        end
    endtask

endclass

`endif
