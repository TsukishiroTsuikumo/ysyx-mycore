`timescale 1ns/1ps
`include "axi_defs.vh"

// Byte-addressed AXI4 RAM used by the cache subsystem and simulation tests.
// The implemented transfer subset is aligned, full-width INCR bursts. Invalid
// requests are drained and completed with SLVERR without modifying memory.
module axi_ram_slave #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2,
    parameter integer MEM_WIDTH  = 24,
    parameter integer MEM_BYTES  = (1 << MEM_WIDTH),
    parameter [ADDR_WIDTH-1:0] BASE_ADDR = {ADDR_WIDTH{1'b0}}
)(
    input                               clk,
    input                               reset,

    input      [ID_WIDTH-1:0]           s_axi_awid,
    input      [ADDR_WIDTH-1:0]         s_axi_awaddr,
    input      [7:0]                    s_axi_awlen,
    input      [2:0]                    s_axi_awsize,
    input      [1:0]                    s_axi_awburst,
    input                               s_axi_awlock,
    input      [3:0]                    s_axi_awcache,
    input      [2:0]                    s_axi_awprot,
    input      [3:0]                    s_axi_awqos,
    input                               s_axi_awvalid,
    output                              s_axi_awready,

    input      [DATA_WIDTH-1:0]         s_axi_wdata,
    input      [DATA_WIDTH/8-1:0]       s_axi_wstrb,
    input                               s_axi_wlast,
    input                               s_axi_wvalid,
    output                              s_axi_wready,

    output     [ID_WIDTH-1:0]           s_axi_bid,
    output     [1:0]                    s_axi_bresp,
    output                              s_axi_bvalid,
    input                               s_axi_bready,

    input      [ID_WIDTH-1:0]           s_axi_arid,
    input      [ADDR_WIDTH-1:0]         s_axi_araddr,
    input      [7:0]                    s_axi_arlen,
    input      [2:0]                    s_axi_arsize,
    input      [1:0]                    s_axi_arburst,
    input                               s_axi_arlock,
    input      [3:0]                    s_axi_arcache,
    input      [2:0]                    s_axi_arprot,
    input      [3:0]                    s_axi_arqos,
    input                               s_axi_arvalid,
    output                              s_axi_arready,

    output     [ID_WIDTH-1:0]           s_axi_rid,
    output     [DATA_WIDTH-1:0]         s_axi_rdata,
    output     [1:0]                    s_axi_rresp,
    output                              s_axi_rlast,
    output                              s_axi_rvalid,
    input                               s_axi_rready
);

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE = $clog2(DATA_BYTES);

    reg [7:0] mem [0:MEM_BYTES-1];

    function request_valid;
        input [ADDR_WIDTH-1:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        reg [63:0] byte_count;
        reg [63:0] absolute_address;
        reg [63:0] base_address;
        reg [63:0] memory_limit;
        reg [63:0] last_address;
        begin
            byte_count = ({56'b0, length} + 64'd1) << size;
            absolute_address = {32'b0, address};
            base_address = {32'b0, BASE_ADDR};
            memory_limit = base_address + MEM_BYTES;
            last_address = absolute_address + byte_count - 64'd1;

            request_valid = 1'b1;
            if (size != AXI_SIZE) begin
                request_valid = 1'b0;
            end
            if (burst != `AXI_BURST_INCR) begin
                request_valid = 1'b0;
            end
            if ((address & (DATA_BYTES - 1)) != 0) begin
                request_valid = 1'b0;
            end
            if ((last_address < absolute_address) ||
                (last_address[63:ADDR_WIDTH] != 0) ||
                (absolute_address < base_address) ||
                (last_address >= memory_limit)) begin
                request_valid = 1'b0;
            end
            if (({52'b0, address[11:0]} + byte_count) > 64'd4096) begin
                request_valid = 1'b0;
            end
        end
    endfunction

    function [ADDR_WIDTH-1:0] beat_address;
        input [ADDR_WIDTH-1:0] base_address;
        input [7:0] beat_index;
        input [2:0] size;
        begin
            beat_address = base_address +
                           ({{(ADDR_WIDTH-8){1'b0}}, beat_index} << size);
        end
    endfunction

    function [DATA_WIDTH-1:0] read_data;
        input [ADDR_WIDTH-1:0] address;
        integer byte_index;
        reg [ADDR_WIDTH-1:0] relative_address;
        begin
            relative_address = address - BASE_ADDR;
            read_data = {DATA_WIDTH{1'b0}};
            for (byte_index = 0; byte_index < DATA_BYTES;
                 byte_index = byte_index + 1) begin
                read_data[byte_index*8 +: 8] =
                    mem[relative_address + byte_index];
            end
        end
    endfunction

`ifndef SYNTHESIS
    task write_byte;
        input [31:0] address;
        input [7:0] data;
        begin
            if ((address < BASE_ADDR) ||
                ({32'b0, address} >= ({32'b0, BASE_ADDR} + MEM_BYTES))) begin
                $display("Error: write_byte address out of bounds: %h", address);
            end
            else begin
                mem[address - BASE_ADDR] = data;
            end
        end
    endtask

    task write_word;
        input [31:0] address;
        input [31:0] data;
        begin
            write_byte(address + 0, data[7:0]);
            write_byte(address + 1, data[15:8]);
            write_byte(address + 2, data[23:16]);
            write_byte(address + 3, data[31:24]);
        end
    endtask

    task load_word_image;
        input [255*8:1] file_name;
        integer fd;
        integer code;
        integer word_addr;
        reg [31:0] word_data;
        reg [1023:0] line;
        begin
            fd = $fopen(file_name, "r");
            if (fd == 0) begin
                $display("Error: Failed to open memory image: %0s", file_name);
            end
            else begin
                word_addr = 0;
                while (!$feof(fd)) begin
                    code = $fscanf(fd, "%h", word_data);
                    if (code == 1) begin
                        write_word(BASE_ADDR + (word_addr << 2), word_data);
                        word_addr = word_addr + 1;
                    end
                    else begin
                        code = $fgets(line, fd);
                    end
                end
                $fclose(fd);
                $display("AXI RAM: loaded %0d 32-bit words from %0s",
                         word_addr, file_name);
            end
        end
    endtask

    reg [255*8:1] memfile = "program.mem";
    reg [251*8:1] tmp_memfile;
    reg [255*8:1] exact_memfile;
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < MEM_BYTES; init_idx = init_idx + 4) begin
            mem[init_idx + 0] = 8'h13;
            mem[init_idx + 1] = 8'h00;
            mem[init_idx + 2] = 8'h00;
            mem[init_idx + 3] = 8'h00;
        end

        if ($value$plusargs("MEM=%s", tmp_memfile)) begin
            memfile = {tmp_memfile, ".mem"};
            load_word_image(memfile);
        end
        else if ($value$plusargs("MEM_FILE=%s", exact_memfile)) begin
            load_word_image(exact_memfile);
        end
    end
`endif

    // Read channel state.
    reg read_active_q;
    reg read_error_q;
    reg [ID_WIDTH-1:0] read_id_q;
    reg [ADDR_WIDTH-1:0] read_addr_q;
    reg [7:0] read_len_q;
    reg [7:0] read_beat_q;
    reg [2:0] read_size_q;
    reg [DATA_WIDTH-1:0] read_data_q;

    assign s_axi_arready = !read_active_q;
    assign s_axi_rid     = read_id_q;
    assign s_axi_rdata   = read_data_q;
    assign s_axi_rresp   = read_error_q
                           ? `AXI_RESP_SLVERR
                           : `AXI_RESP_OKAY;
    assign s_axi_rlast   = read_active_q && (read_beat_q == read_len_q);
    assign s_axi_rvalid  = read_active_q;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_active_q <= 1'b0;
            read_error_q  <= 1'b0;
            read_id_q     <= {ID_WIDTH{1'b0}};
            read_addr_q   <= {ADDR_WIDTH{1'b0}};
            read_len_q    <= 8'b0;
            read_beat_q   <= 8'b0;
            read_size_q   <= 3'b0;
            read_data_q   <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_active_q <= 1'b1;
                read_error_q  <= !request_valid(s_axi_araddr, s_axi_arlen,
                                                s_axi_arsize,
                                                s_axi_arburst);
                read_id_q     <= s_axi_arid;
                read_addr_q   <= s_axi_araddr;
                read_len_q    <= s_axi_arlen;
                read_beat_q   <= 8'b0;
                read_size_q   <= s_axi_arsize;
                read_data_q   <= request_valid(s_axi_araddr, s_axi_arlen,
                                               s_axi_arsize,
                                               s_axi_arburst)
                                 ? read_data(s_axi_araddr)
                                 : {DATA_WIDTH{1'b0}};
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    read_active_q <= 1'b0;
                    read_beat_q   <= 8'b0;
                end
                else begin
                    read_beat_q <= read_beat_q + 1'b1;
                    read_data_q <= read_error_q
                                   ? {DATA_WIDTH{1'b0}}
                                   : read_data(beat_address(
                                         read_addr_q,
                                         read_beat_q + 1'b1,
                                         read_size_q));
                end
            end
        end
    end

    // Write channel state.
    reg write_active_q;
    reg write_resp_valid_q;
    reg write_request_error_q;
    reg write_protocol_error_q;
    reg [ID_WIDTH-1:0] write_id_q;
    reg [ADDR_WIDTH-1:0] write_addr_q;
    reg [7:0] write_len_q;
    // The ninth bit represents the first beat beyond AWLEN=255. Keeping it
    // prevents a malformed burst without WLAST from wrapping and writing the
    // beginning of memory again while it is drained.
    reg [8:0] write_beat_q;
    reg [2:0] write_size_q;
    reg [1:0] write_resp_q;

    wire write_last_expected =
        (write_beat_q == {1'b0, write_len_q});
    wire write_last_mismatch = (s_axi_wlast != write_last_expected);
    wire [ADDR_WIDTH-1:0] current_write_addr =
        beat_address(write_addr_q, write_beat_q[7:0], write_size_q);

    assign s_axi_awready = !write_active_q && !write_resp_valid_q;
    assign s_axi_wready  = write_active_q;
    assign s_axi_bid     = write_id_q;
    assign s_axi_bresp   = write_resp_q;
    assign s_axi_bvalid  = write_resp_valid_q;

    integer write_byte_index;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_active_q         <= 1'b0;
            write_resp_valid_q     <= 1'b0;
            write_request_error_q  <= 1'b0;
            write_protocol_error_q <= 1'b0;
            write_id_q             <= {ID_WIDTH{1'b0}};
            write_addr_q           <= {ADDR_WIDTH{1'b0}};
            write_len_q            <= 8'b0;
            write_beat_q           <= 9'b0;
            write_size_q           <= 3'b0;
            write_resp_q           <= `AXI_RESP_OKAY;
        end
        else begin
            if (s_axi_bvalid && s_axi_bready) begin
                write_resp_valid_q <= 1'b0;
            end

            if (s_axi_awvalid && s_axi_awready) begin
                write_active_q         <= 1'b1;
                write_request_error_q  <= !request_valid(
                                            s_axi_awaddr,
                                            s_axi_awlen,
                                            s_axi_awsize,
                                            s_axi_awburst);
                write_protocol_error_q <= 1'b0;
                write_id_q             <= s_axi_awid;
                write_addr_q           <= s_axi_awaddr;
                write_len_q            <= s_axi_awlen;
                write_beat_q           <= 9'b0;
                write_size_q           <= s_axi_awsize;
                write_resp_q           <= `AXI_RESP_OKAY;
            end
            else if (s_axi_wvalid && s_axi_wready) begin
                if (!write_request_error_q &&
                    (write_beat_q <= {1'b0, write_len_q})) begin
                    for (write_byte_index = 0;
                         write_byte_index < DATA_BYTES;
                         write_byte_index = write_byte_index + 1) begin
                        if (s_axi_wstrb[write_byte_index]) begin
                            mem[(current_write_addr - BASE_ADDR) +
                                write_byte_index]
                                <= s_axi_wdata[write_byte_index*8 +: 8];
                        end
                    end
                end

                if (write_last_mismatch) begin
                    write_protocol_error_q <= 1'b1;
                end

                if (s_axi_wlast) begin
                    write_active_q     <= 1'b0;
                    write_resp_valid_q <= 1'b1;
                    write_resp_q <= (write_request_error_q ||
                                     write_protocol_error_q ||
                                     write_last_mismatch)
                                    ? `AXI_RESP_SLVERR
                                    : `AXI_RESP_OKAY;
                    write_beat_q <= 9'b0;
                end
                else begin
                    if (write_beat_q < 9'd256) begin
                        write_beat_q <= write_beat_q + 1'b1;
                    end
                end
            end
        end
    end

    wire unused_inputs = ^{s_axi_awlock, s_axi_awcache, s_axi_awprot,
                           s_axi_awqos, s_axi_arlock, s_axi_arcache,
                           s_axi_arprot, s_axi_arqos};

`ifndef SYNTHESIS
    initial begin
        if (ADDR_WIDTH != 32) begin
            $error("axi_ram_slave: the simulation image tasks require ADDR_WIDTH=32");
        end
        if ((DATA_WIDTH % 8) != 0 || DATA_BYTES < 1 ||
            ((DATA_BYTES & (DATA_BYTES - 1)) != 0)) begin
            $error("axi_ram_slave: DATA_WIDTH must contain a power-of-two number of bytes");
        end
        if (MEM_BYTES < 1 ||
            (({32'b0, BASE_ADDR} + MEM_BYTES) > 64'h1_0000_0000)) begin
            $error("axi_ram_slave: BASE_ADDR plus MEM_BYTES exceeds the address space");
        end
    end

    always @(posedge clk) begin
        if (!reset && s_axi_wvalid && s_axi_wready && write_last_mismatch) begin
            $error("axi_ram_slave: WLAST does not match AWLEN");
        end
    end
`endif

endmodule
