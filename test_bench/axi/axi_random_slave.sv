`timescale 1ns/1ps
`include "axi_defs.vh"

// Deterministic pseudo-random AXI4 memory slave used only by the standalone
// subsystem test. It deliberately inserts address/data ready stalls and read/
// write response latency while keeping every VALID payload stable.
module axi_random_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 2,
    parameter int MEM_WORDS  = 1024,
    parameter logic [31:0] DATA_TAG = 32'h6000_0000,
    parameter logic [31:0] SEED = 32'h1ace_b00c
)(
    input  logic                         clk,
    input  logic                         reset,

    input  logic [ID_WIDTH-1:0]          s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  logic [7:0]                   s_axi_awlen,
    input  logic [2:0]                   s_axi_awsize,
    input  logic [1:0]                   s_axi_awburst,
    input  logic                         s_axi_awlock,
    input  logic [3:0]                   s_axi_awcache,
    input  logic [2:0]                   s_axi_awprot,
    input  logic [3:0]                   s_axi_awqos,
    input  logic                         s_axi_awvalid,
    output logic                         s_axi_awready,

    input  logic [DATA_WIDTH-1:0]        s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0]      s_axi_wstrb,
    input  logic                         s_axi_wlast,
    input  logic                         s_axi_wvalid,
    output logic                         s_axi_wready,

    output logic [ID_WIDTH-1:0]          s_axi_bid,
    output logic [1:0]                   s_axi_bresp,
    output logic                         s_axi_bvalid,
    input  logic                         s_axi_bready,

    input  logic [ID_WIDTH-1:0]          s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]        s_axi_araddr,
    input  logic [7:0]                   s_axi_arlen,
    input  logic [2:0]                   s_axi_arsize,
    input  logic [1:0]                   s_axi_arburst,
    input  logic                         s_axi_arlock,
    input  logic [3:0]                   s_axi_arcache,
    input  logic [2:0]                   s_axi_arprot,
    input  logic [3:0]                   s_axi_arqos,
    input  logic                         s_axi_arvalid,
    output logic                         s_axi_arready,

    output logic [ID_WIDTH-1:0]          s_axi_rid,
    output logic [DATA_WIDTH-1:0]        s_axi_rdata,
    output logic [1:0]                   s_axi_rresp,
    output logic                         s_axi_rlast,
    output logic                         s_axi_rvalid,
    input  logic                         s_axi_rready
);

    localparam int DATA_BYTES = DATA_WIDTH / 8;
    localparam logic [2:0] AXI_SIZE = $clog2(DATA_BYTES);

    logic [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];
    integer init_index;
    initial begin
        if (DATA_WIDTH != 32 || DATA_BYTES != 4) begin
            $fatal(1, "axi_random_slave requires DATA_WIDTH=32");
        end
        if (SEED == 0) begin
            $fatal(1, "axi_random_slave SEED must be non-zero");
        end
        for (init_index = 0; init_index < MEM_WORDS;
             init_index = init_index + 1) begin
            mem[init_index] = DATA_TAG + init_index;
        end
    end

    function automatic logic [31:0] lfsr_next(input logic [31:0] value);
        lfsr_next = {value[30:0],
                     value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    logic [31:0] lfsr_q;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            lfsr_q <= SEED;
        end
        else begin
            lfsr_q <= lfsr_next(lfsr_q);
        end
    end

    logic                         read_active_q;
    logic [ID_WIDTH-1:0]          read_id_q;
    logic [ADDR_WIDTH-1:0]        read_addr_q;
    logic [7:0]                   read_len_q;
    logic [7:0]                   read_beat_q;
    logic [2:0]                   read_size_q;
    logic [2:0]                   ar_wait_q;
    logic [2:0]                   r_wait_q;

    wire [ADDR_WIDTH-1:0] current_read_addr =
        read_addr_q + (read_beat_q << read_size_q);
    wire [ADDR_WIDTH-1:2] current_read_word = current_read_addr[ADDR_WIDTH-1:2];

    assign s_axi_arready = !read_active_q && !s_axi_rvalid &&
                           (ar_wait_q == 0) && lfsr_q[0];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            read_active_q <= 1'b0;
            read_id_q     <= '0;
            read_addr_q   <= '0;
            read_len_q    <= '0;
            read_beat_q   <= '0;
            read_size_q   <= '0;
            ar_wait_q     <= 3'd3;
            r_wait_q      <= '0;
            s_axi_rid     <= '0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= `AXI_RESP_OKAY;
            s_axi_rlast   <= 1'b0;
            s_axi_rvalid  <= 1'b0;
        end
        else begin
            if (!read_active_q && s_axi_arvalid && (ar_wait_q != 0)) begin
                ar_wait_q <= ar_wait_q - 1'b1;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                if (s_axi_arsize != AXI_SIZE ||
                    s_axi_arburst != `AXI_BURST_INCR || s_axi_arlock ||
                    ((s_axi_araddr & (DATA_BYTES - 1)) != 0) ||
                    (((s_axi_araddr >> 2) + s_axi_arlen) >= MEM_WORDS)) begin
                    $fatal(1, "random AXI slave received illegal AR");
                end
                read_active_q <= 1'b1;
                read_id_q     <= s_axi_arid;
                read_addr_q   <= s_axi_araddr;
                read_len_q    <= s_axi_arlen;
                read_beat_q   <= '0;
                read_size_q   <= s_axi_arsize;
                r_wait_q      <= {1'b0, lfsr_q[2:1]} + 1'b1;
            end
            else if (read_active_q) begin
                if (s_axi_rvalid) begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        if (s_axi_rlast) begin
                            read_active_q <= 1'b0;
                            read_beat_q   <= '0;
                            ar_wait_q     <= {1'b0, lfsr_q[4:3]} + 1'b1;
                        end
                        else begin
                            read_beat_q <= read_beat_q + 1'b1;
                            r_wait_q    <= {1'b0, lfsr_q[6:5]} + 1'b1;
                        end
                    end
                end
                else if (r_wait_q != 0) begin
                    r_wait_q <= r_wait_q - 1'b1;
                end
                else if (lfsr_q[7]) begin
                    if (current_read_word >= MEM_WORDS) begin
                        $fatal(1, "random AXI slave read index out of range");
                    end
                    s_axi_rid    <= read_id_q;
                    s_axi_rdata  <= mem[current_read_word];
                    s_axi_rresp  <= `AXI_RESP_OKAY;
                    s_axi_rlast  <= (read_beat_q == read_len_q);
                    s_axi_rvalid <= 1'b1;
                end
            end
        end
    end

    logic                         write_active_q;
    logic                         b_pending_q;
    logic [ID_WIDTH-1:0]          write_id_q;
    logic [ADDR_WIDTH-1:0]        write_addr_q;
    logic [7:0]                   write_len_q;
    logic [7:0]                   write_beat_q;
    logic [2:0]                   write_size_q;
    logic [2:0]                   aw_wait_q;
    logic [2:0]                   w_wait_q;
    logic [2:0]                   b_wait_q;
    integer byte_index;

    wire [ADDR_WIDTH-1:0] current_write_addr =
        write_addr_q + (write_beat_q << write_size_q);
    wire [ADDR_WIDTH-1:2] current_write_word = current_write_addr[ADDR_WIDTH-1:2];

    assign s_axi_awready = !write_active_q && !b_pending_q && !s_axi_bvalid &&
                           (aw_wait_q == 0) && lfsr_q[8];
    assign s_axi_wready = write_active_q && (w_wait_q == 0) && lfsr_q[9];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            write_active_q <= 1'b0;
            b_pending_q    <= 1'b0;
            write_id_q     <= '0;
            write_addr_q   <= '0;
            write_len_q    <= '0;
            write_beat_q   <= '0;
            write_size_q   <= '0;
            aw_wait_q      <= 3'd3;
            w_wait_q       <= '0;
            b_wait_q       <= '0;
            s_axi_bid      <= '0;
            s_axi_bresp    <= `AXI_RESP_OKAY;
            s_axi_bvalid   <= 1'b0;
        end
        else begin
            if (!write_active_q && !b_pending_q && !s_axi_bvalid &&
                s_axi_awvalid && (aw_wait_q != 0)) begin
                aw_wait_q <= aw_wait_q - 1'b1;
            end

            if (s_axi_awvalid && s_axi_awready) begin
                if (s_axi_awsize != AXI_SIZE ||
                    s_axi_awburst != `AXI_BURST_INCR || s_axi_awlock ||
                    ((s_axi_awaddr & (DATA_BYTES - 1)) != 0) ||
                    (((s_axi_awaddr >> 2) + s_axi_awlen) >= MEM_WORDS)) begin
                    $fatal(1, "random AXI slave received illegal AW");
                end
                write_active_q <= 1'b1;
                write_id_q     <= s_axi_awid;
                write_addr_q   <= s_axi_awaddr;
                write_len_q    <= s_axi_awlen;
                write_beat_q   <= '0;
                write_size_q   <= s_axi_awsize;
                w_wait_q       <= {1'b0, lfsr_q[11:10]} + 1'b1;
            end
            else if (write_active_q && s_axi_wvalid) begin
                if (w_wait_q != 0) begin
                    w_wait_q <= w_wait_q - 1'b1;
                end
                else if (s_axi_wready) begin
                    if (current_write_word >= MEM_WORDS) begin
                        $fatal(1, "random AXI slave write index out of range");
                    end
                    if (s_axi_wlast !== (write_beat_q == write_len_q)) begin
                        $fatal(1, "random AXI slave observed WLAST/AWLEN mismatch");
                    end
                    for (byte_index = 0; byte_index < DATA_BYTES;
                         byte_index = byte_index + 1) begin
                        if (s_axi_wstrb[byte_index]) begin
                            mem[current_write_word][byte_index*8 +: 8]
                                <= s_axi_wdata[byte_index*8 +: 8];
                        end
                    end
                    if (s_axi_wlast) begin
                        write_active_q <= 1'b0;
                        b_pending_q    <= 1'b1;
                        b_wait_q       <= {1'b0, lfsr_q[13:12]} + 1'b1;
                    end
                    else begin
                        write_beat_q <= write_beat_q + 1'b1;
                        w_wait_q     <= {1'b0, lfsr_q[15:14]} + 1'b1;
                    end
                end
            end

            if (s_axi_bvalid) begin
                if (s_axi_bready) begin
                    s_axi_bvalid <= 1'b0;
                    aw_wait_q    <= {1'b0, lfsr_q[17:16]} + 1'b1;
                end
            end
            else if (b_pending_q) begin
                if (b_wait_q != 0) begin
                    b_wait_q <= b_wait_q - 1'b1;
                end
                else if (lfsr_q[18]) begin
                    s_axi_bid    <= write_id_q;
                    s_axi_bresp  <= `AXI_RESP_OKAY;
                    s_axi_bvalid <= 1'b1;
                    b_pending_q  <= 1'b0;
                end
            end
        end
    end

    wire unused_inputs = ^{s_axi_awcache, s_axi_awprot, s_axi_awqos,
                           s_axi_arcache, s_axi_arprot, s_axi_arqos};

endmodule
