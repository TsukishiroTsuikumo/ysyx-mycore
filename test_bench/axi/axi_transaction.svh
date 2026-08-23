`ifndef YSYX_AXI_TRANSACTION_SVH
`define YSYX_AXI_TRANSACTION_SVH

typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
} axi_direction_e;

typedef enum bit [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10,
    AXI_BURST_RSVD  = 2'b11
} axi_burst_e;

typedef enum bit [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
} axi_resp_e;

class axi_transaction #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_sequence_item;

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;

    rand axi_direction_e          direction;
    rand bit [ID_WIDTH-1:0]       id;
    rand bit [ADDR_WIDTH-1:0]     addr;
    rand bit [7:0]                len;
    rand bit [2:0]                size;
    rand axi_burst_e              burst;
    rand bit                      lock;
    rand bit [3:0]                cache;
    rand bit [2:0]                prot;
    rand bit [3:0]                qos;
    rand bit [3:0]                region;
    rand bit [USER_WIDTH-1:0]     address_user;
    rand bit [OWNER_WIDTH-1:0]    owner;

    bit [DATA_WIDTH-1:0] data_q[$];
    bit [STRB_WIDTH-1:0] strb_q[$];
    bit [1:0]            resp_q[$];
    bit                  last_q[$];
    bit [USER_WIDTH-1:0] data_user_q[$];

    bit [1:0]            bresp;
    bit [USER_WIDTH-1:0] buser;

    // Master-driver timing controls.  Keeping these controls on the sequence
    // item makes directed and constrained-random sequences able to request
    // channel stalls without baking a policy into the reusable driver.
    int unsigned address_delay_cycles;
    int unsigned beat_delay_cycles;
    int unsigned response_ready_delay_cycles;

    // Per-transaction observations used by the explicit coverage subscriber.
    bit aw_backpressure;
    bit w_backpressure;
    bit b_backpressure;
    bit ar_backpressure;
    bit r_backpressure;
    bit last_ok;
    bit beat_count_ok;

    `uvm_object_param_utils(this_type)

    constraint legal_size_c {
        size <= $clog2(STRB_WIDTH);
    }

    constraint legal_burst_c {
        burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
        if (burst != AXI_BURST_INCR) len <= 8'd15;
        if (burst == AXI_BURST_WRAP) len inside {8'd1, 8'd3, 8'd7, 8'd15};
    }

    function new(string name = "axi_transaction");
        super.new(name);
        last_ok = 1'b1;
        beat_count_ok = 1'b1;
        address_delay_cycles = 0;
        beat_delay_cycles = 0;
        response_ready_delay_cycles = 0;
    endfunction

    function int unsigned expected_beats();
        return int'(len) + 1;
    endfunction

    function void clear_payload();
        data_q.delete();
        strb_q.delete();
        resp_q.delete();
        last_q.delete();
        data_user_q.delete();
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "%s owner=%0d id=0x%0x addr=0x%0x len=%0d size=%0d burst=%0d beats=%0d last_ok=%0d beat_count_ok=%0d resp=0x%0x delays=%0d/%0d/%0d",
            (direction == AXI_WRITE) ? "WRITE" : "READ",
            owner, id, addr, len, size, burst, data_q.size(),
            last_ok, beat_count_ok,
            (direction == AXI_WRITE && resp_q.size() == 0) ? bresp :
                ((resp_q.size() == 0) ? AXI_RESP_OKAY : resp_q[$]),
            address_delay_cycles, beat_delay_cycles,
            response_ready_delay_cycles)
        ;
    endfunction

endclass

`endif
