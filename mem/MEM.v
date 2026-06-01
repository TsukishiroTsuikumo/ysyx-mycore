module MEM #(
    parameter MEM_WIDTH = 20, // 1MB memory (2^20 bytes)
    parameter MEM_BYTES = (1 << MEM_WIDTH),
    parameter LINE_WIDTH = 4, // 2 ^4 = 16 bytes per line
    parameter LINE_BYTES = (1 << LINE_WIDTH),
    parameter LINE_DATA_WIDTH = LINE_BYTES * 8
)(
    input               clk,
    input               reset,

    // ICache read channel
    input                               ic_req_rvalid,
    output reg                          ic_req_rready,
    input                      [31:0]   ic_req_raddr,

    output reg                          ic_resp_rvalid,
    output reg  [LINE_DATA_WIDTH-1:0]   ic_resp_rdata,

    // DCache read channel
    input               dc_req_rvalid,
    output reg                          dc_req_rready,
    input                      [31:0]   dc_req_raddr,

    output reg                          dc_resp_rvalid,
    output reg  [LINE_DATA_WIDTH-1:0]   dc_resp_rdata,

    // DCache write channel
    input                               dc_req_wvalid,
    output reg                          dc_req_wready,
    input                      [31:0]   dc_req_waddr,
    input       [LINE_DATA_WIDTH-1:0]   dc_req_wdata,

    output reg                          dc_resp_wvalid
);

    localparam [31:0] LINE_MASK = LINE_BYTES - 1;

    reg [7:0] mem [0:MEM_BYTES-1];

    task write_byte;
        input [31:0] addr;
        input [7:0] data;
        begin
            if (addr >= MEM_BYTES) begin
                $display("Error: write_byte address out of bounds: %h", addr);
            end
            else begin
                mem[addr] = data;
            end
        end
    endtask

    task write_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            write_byte(addr + 0, data[7:0]);
            write_byte(addr + 1, data[15:8]);
            write_byte(addr + 2, data[23:16]);
            write_byte(addr + 3, data[31:24]);
        end
    endtask

    task load_word_image;
        input [255*8:1] file_name;
        integer fd;
        integer code;
        integer word_addr;
        reg [31:0] instr;
        reg [1023:0] line;
        begin
            fd = $fopen(file_name, "r");
            if (fd == 0) begin
                $display("Error: Failed to open memory image: %0s", file_name);
            end
            else begin
                word_addr = 0;
                while (!$feof(fd)) begin
                    code = $fscanf(fd, "%h", instr);
                    if (code == 1) begin
                        write_word(word_addr << 2, instr);
                        word_addr = word_addr + 1;
                    end
                    else begin
                        code = $fgets(line, fd);
                    end
                end
                $fclose(fd);
                $display("MEM: loaded %0d 32-bit words from %0s", word_addr, file_name);
            end
        end
    endtask

    // Initial memory
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

        if($value$plusargs("MEM=%s",tmp_memfile)) begin
            memfile = {tmp_memfile, ".mem"};
            load_word_image(memfile);
        end
        else if($value$plusargs("MEM_FILE=%s",exact_memfile)) begin
            load_word_image(exact_memfile);
        end
    end

    function [31:0] aligned_addr(input [31:0] addr);
        reg [31:0] line_addr;
        begin
            line_addr = addr & ~LINE_MASK;
            if(line_addr > MEM_BYTES - LINE_BYTES) begin
                $display("Error: Address out of bounds: %h", addr);
                aligned_addr = 0;
            end
            else begin
                aligned_addr = line_addr;
            end
        end
    endfunction

    // Write mem
    integer i_wr;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            dc_resp_wvalid <= 1'b0;
        end
        else if (dc_req_wfire) begin
            for (i_wr = 0; i_wr < LINE_BYTES; i_wr = i_wr + 1) begin
                mem[aligned_addr(dc_req_waddr) + i_wr] <= dc_req_wdata[i_wr*8 +: 8];
            end
            dc_resp_wvalid <= 1'b1;
        end
        else begin
            dc_resp_wvalid <= 1'b0;
        end
    end

    // Read mem
    integer i_dc_rd;
    integer i_ic_rd;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            dc_resp_rvalid <= 1'b0;
            dc_resp_rdata  <= {LINE_DATA_WIDTH{1'b0}};
            ic_resp_rvalid <= 1'b0;
            ic_resp_rdata  <= {LINE_DATA_WIDTH{1'b0}};
        end
        else if(dc_req_rfire) begin
            for (i_dc_rd = 0; i_dc_rd < LINE_BYTES; i_dc_rd = i_dc_rd + 1) begin
                dc_resp_rdata[i_dc_rd*8 +: 8] <= mem[aligned_addr(dc_req_raddr) + i_dc_rd];
            end
            dc_resp_rvalid <= 1'b1;
            ic_resp_rvalid <= 1'b0;
        end 
        else if (ic_req_rfire) begin
            for (i_ic_rd = 0; i_ic_rd < LINE_BYTES; i_ic_rd = i_ic_rd + 1) begin
                ic_resp_rdata[i_ic_rd*8 +: 8] <= mem[aligned_addr(ic_req_raddr) + i_ic_rd];
            end
            dc_resp_rvalid <= 1'b0;
            ic_resp_rvalid <= 1'b1;
        end
        else begin
            dc_resp_rvalid <= 1'b0;
            ic_resp_rvalid <= 1'b0;
        end
    end

    // State machine states
    reg [1:0] current_state;
    reg [1:0] next_state;

    localparam IDLE  = 2'd0;
    localparam DC_WR = 2'd1;
    localparam DC_RD = 2'd2;
    localparam IC_RD = 2'd3;

    wire ic_req_rfire = ic_req_rvalid && ic_req_rready;
    wire dc_req_rfire = dc_req_rvalid && dc_req_rready;
    wire dc_req_wfire = dc_req_wvalid && dc_req_wready;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @(*) begin
        case (current_state)
            IDLE: begin
                if (dc_req_wvalid) begin
                    next_state = DC_WR;
                end
                else if (dc_req_rvalid) begin
                    next_state = DC_RD;
                end
                else if (ic_req_rvalid) begin
                    next_state = IC_RD;
                end
                else begin
                    next_state = IDLE;
                end
            end

            DC_WR: begin
                if(dc_resp_wvalid) begin
                    if(dc_req_wfire) begin
                        next_state = DC_WR;
                    end
                    else if(dc_req_rfire) begin
                        next_state = DC_RD;
                    end
                    else if(ic_req_rfire) begin
                        next_state = IC_RD;
                    end
                    else begin
                        next_state = IDLE;
                    end
                end
                else begin
                    next_state = DC_WR;
                end
            end

            DC_RD: begin
                if (dc_resp_rvalid) begin
                    if(dc_req_wfire) begin
                        next_state = DC_WR;
                    end
                    else if(dc_req_rfire) begin
                        next_state = DC_RD;
                    end
                    else if(ic_req_rfire) begin
                        next_state = IC_RD;
                    end
                    else begin
                        next_state = IDLE;
                    end
                end
                else begin
                    next_state = DC_RD;
                end
            end

            IC_RD: begin
                if (ic_resp_rvalid) begin
                    if(dc_req_wfire) begin
                        next_state = DC_WR;
                    end
                    else if(dc_req_rfire) begin
                        next_state = DC_RD;
                    end
                    else if(ic_req_rfire) begin
                        next_state = IC_RD;
                    end
                    else begin
                        next_state = IDLE;
                    end
                end
                else begin
                    next_state = IC_RD;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always @(*) begin

        ic_req_rready = 1'b0;
        dc_req_rready = 1'b0;
        dc_req_wready = 1'b0;

        case (current_state)
            IDLE: begin
                if(dc_req_wvalid) begin
                    dc_req_wready = 1'b1;
                end
                else if (dc_req_rvalid) begin
                    dc_req_rready = 1'b1;
                end
                else if (ic_req_rvalid) begin
                    ic_req_rready = 1'b1;
                end
            end

            DC_WR: begin
                if (dc_resp_wvalid) begin
                    if(dc_req_wvalid) begin
                        dc_req_wready = 1'b1;
                    end
                    else if (dc_req_rvalid) begin
                        dc_req_rready = 1'b1;
                    end
                    else if (ic_req_rvalid) begin
                        ic_req_rready = 1'b1;
                    end
                end
            end

            DC_RD: begin
                if (dc_resp_rvalid) begin
                    if(dc_req_wvalid) begin
                        dc_req_wready = 1'b1;
                    end
                    else if (dc_req_rvalid) begin
                        dc_req_rready = 1'b1;
                    end
                    else if (ic_req_rvalid) begin
                        ic_req_rready = 1'b1;
                    end
                end
            end

            IC_RD: begin
                if (ic_resp_rvalid) begin
                    if(dc_req_wvalid) begin
                        dc_req_wready = 1'b1;
                    end
                    else if (dc_req_rvalid) begin
                        dc_req_rready = 1'b1;
                    end
                    else if (ic_req_rvalid) begin
                        ic_req_rready = 1'b1;
                    end
                end
            end

        endcase

    end

endmodule
