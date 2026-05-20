module Icache #(
    parameter PM_LINE_BYTES = 16, // 16 bytes per line
    parameter PM_WAY_NUM    = 4,  // 4-way set associative
    parameter PM_SET_NUM    = 16, // 16 sets
    parameter PM_LINE_WIDTH = PM_LINE_BYTES * 8
)(
    input                           clk,
    input                           reset,

    // CPU Read Interface
    input                           pm_req_valid_in,
    input                    [31:0] pm_req_addr_in,
    output                          pm_req_ready_out,

    output  reg                     pm_resp_valid_out,
    output  reg              [31:0] pm_resp_data_out,

    // MEM Read Interface
    output  reg                     ic_req_rvalid,
    input                           ic_req_rready,
    output  reg              [31:0] ic_req_raddr,

    input                           ic_resp_rvalid,
    input       [PM_LINE_WIDTH-1:0] ic_resp_rdata
);

    function integer clog2(input integer value);
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1) begin
                clog2 = clog2 + 1;
            end
        end
    endfunction

    localparam integer OFFSET_WIDTH = clog2(PM_LINE_BYTES);
    localparam integer INDEX_WIDTH  = clog2(PM_SET_NUM);
    localparam integer WAY_WIDTH    = (PM_WAY_NUM <= 1) ? 1 : clog2(PM_WAY_NUM);
    localparam integer TAG_WIDTH    = 32 - OFFSET_WIDTH - INDEX_WIDTH;
    localparam [31:0]  LINE_MASK    = PM_LINE_BYTES - 1;

    localparam IDLE  = 2'd0;
    localparam BUSY  = 2'd1;
    localparam WRMEM = 2'd2;
    localparam RDMEM = 2'd3;

    reg [1:0] current_state;
    reg [1:0] next_state;

    wire cpu_req_fire;
    wire [OFFSET_WIDTH-1:0] req_offset_now;
    wire [INDEX_WIDTH-1:0] req_index_now;
    wire [TAG_WIDTH-1:0] req_tag_now;
    wire [31:0] req_line_addr_now;

    reg [31:0] req_addr_q;
    reg [TAG_WIDTH-1:0] req_tag_q;
    reg [OFFSET_WIDTH-1:0] req_offset_q;
    reg [INDEX_WIDTH-1:0] req_index_q;
    reg mem_req_sent;
    reg refill_done_q;

    wire [TAG_WIDTH-1:0] active_tag;
    wire [INDEX_WIDTH-1:0] active_index;

    wire [PM_SET_NUM-1:0] set_rd_req;
    wire [PM_SET_NUM-1:0] set_wr_req;
    wire [PM_SET_NUM-1:0] set_rd_hit;
    wire [PM_SET_NUM-1:0] set_wr_hit;
    wire [PM_SET_NUM-1:0] set_rd_fire;
    wire [PM_SET_NUM-1:0] set_wr_fire;
    wire [PM_SET_NUM-1:0] set_miss;
    wire [PM_SET_NUM-1:0] set_miss_need_wb;
    wire [TAG_WIDTH-1:0] set_wb_tag [0:PM_SET_NUM-1];
    wire [PM_LINE_WIDTH-1:0] set_wb_data [0:PM_SET_NUM-1];
    wire [PM_LINE_WIDTH-1:0] set_rdata [0:PM_SET_NUM-1];
    wire [PM_SET_NUM-1:0] set_wb_tag_used;
    wire [PM_SET_NUM-1:0] set_wb_data_used;

    wire [PM_LINE_BYTES-1:0] read_all_bytes;
    wire [PM_LINE_BYTES-1:0] write_all_bytes;
    wire selected_rd_hit;
    wire selected_rd_fire;
    wire selected_miss;
    wire selected_miss_need_wb;
    wire unused_set_sideband;

    reg [31:0] selected_read_word;

    assign pm_req_ready_out = (current_state == IDLE);
    assign cpu_req_fire = pm_req_valid_in && pm_req_ready_out;
    assign req_offset_now = pm_req_addr_in[OFFSET_WIDTH-1:0];
    assign req_index_now = pm_req_addr_in[OFFSET_WIDTH +: INDEX_WIDTH];
    assign req_tag_now = pm_req_addr_in[31:OFFSET_WIDTH+INDEX_WIDTH];
    assign req_line_addr_now = pm_req_addr_in & ~LINE_MASK;

    assign active_tag = (current_state == IDLE) ? req_tag_now : req_tag_q;
    assign active_index = (current_state == IDLE) ? req_index_now : req_index_q;

    assign read_all_bytes = {PM_LINE_BYTES{1'b1}};
    assign write_all_bytes = {PM_LINE_BYTES{1'b1}};

    assign selected_rd_hit = set_rd_hit[active_index];
    assign selected_rd_fire = set_rd_fire[req_index_q];
    assign selected_miss = set_miss[active_index];
    assign selected_miss_need_wb = set_miss_need_wb[active_index];
    assign unused_set_sideband = (|set_wr_hit) | (|set_wr_fire) | (|set_wb_tag_used) |
                                 (|set_wb_data_used) | selected_miss_need_wb;

    always @(*) begin
        selected_read_word = {
            set_rdata[req_index_q][(req_offset_q + 3)*8 +: 8],
            set_rdata[req_index_q][(req_offset_q + 2)*8 +: 8],
            set_rdata[req_index_q][(req_offset_q + 1)*8 +: 8],
            set_rdata[req_index_q][req_offset_q*8 +: 8]
        };
    end

    genvar set_idx;
    generate
        for (set_idx = 0; set_idx < PM_SET_NUM; set_idx = set_idx + 1) begin: gen_icache_set
            localparam [INDEX_WIDTH-1:0] SET_INDEX = set_idx;

            assign set_rd_req[set_idx] =
                (current_state == IDLE && cpu_req_fire && req_index_now == SET_INDEX) ||
                (current_state == BUSY && refill_done_q && req_index_q == SET_INDEX);

            assign set_wr_req[set_idx] =
                (current_state == RDMEM && ic_resp_rvalid && req_index_q == SET_INDEX);
            assign set_wb_tag_used[set_idx] = |set_wb_tag[set_idx];
            assign set_wb_data_used[set_idx] = |set_wb_data[set_idx];

            one_set #(
                .TAG_WIDTH(TAG_WIDTH),
                .OFFSET_WIDTH(OFFSET_WIDTH),
                .WAY_WIDTH(WAY_WIDTH),
                .WAY_NUM(PM_WAY_NUM),
                .LINE_BYTES(PM_LINE_BYTES),
                .LINE_WIDTH(PM_LINE_WIDTH)
            ) set_inst (
                .clk( clk ),
                .reset( reset ),
                .set_tag( active_tag ),

                .rd_req_in( set_rd_req[set_idx] ),
                .rd_hit_out( set_rd_hit[set_idx] ),
                .rdata_strb_in( read_all_bytes ),
                .rdata_out( set_rdata[set_idx] ),
                .rd_fire_out( set_rd_fire[set_idx] ),

                .wr_req_in( set_wr_req[set_idx] ),
                .wr_refill_in( set_wr_req[set_idx] ),
                .wr_hit_out( set_wr_hit[set_idx] ),
                .wdata_strb_in( write_all_bytes ),
                .wdata_in( ic_resp_rdata ),
                .wr_fire_out( set_wr_fire[set_idx] ),

                .miss_out( set_miss[set_idx] ),
                .miss_need_wb_out( set_miss_need_wb[set_idx] ),
                .wb_tag_out( set_wb_tag[set_idx] ),
                .wb_data_out( set_wb_data[set_idx] )
            );
        end
    endgenerate

    // FSM state
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @(*) begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (cpu_req_fire && selected_rd_hit) begin
                    next_state = BUSY;
                end
                else if (cpu_req_fire && selected_miss && !selected_miss_need_wb) begin
                    next_state = RDMEM;
                end
                else if (cpu_req_fire && selected_miss && selected_miss_need_wb) begin
                    next_state = WRMEM;
                end
                else begin
                    next_state = IDLE;
                end
            end

            BUSY: begin
                if (selected_rd_fire) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = BUSY;
                end
            end

            RDMEM: begin
                if (ic_resp_rvalid) begin
                    next_state = BUSY;
                end
                else begin
                    next_state = RDMEM;
                end
            end

            WRMEM: begin
                next_state = RDMEM;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(*) begin
        pm_resp_valid_out = 1'b0;
        pm_resp_data_out = 32'h00000013;
        ic_req_rvalid = 1'b0;
        ic_req_raddr = req_addr_q & ~LINE_MASK;

        case (current_state)
            BUSY: begin
                if (selected_rd_fire) begin
                    pm_resp_valid_out = 1'b1;
                    pm_resp_data_out = selected_read_word;
                end
            end

            RDMEM: begin
                if (!mem_req_sent) begin
                    ic_req_rvalid = 1'b1;
                end
                ic_req_raddr = req_addr_q & ~LINE_MASK;
            end

            WRMEM: begin
                ic_req_rvalid = 1'b0;
                ic_req_raddr = req_addr_q & ~LINE_MASK;
            end

            default: begin
                ic_req_rvalid = 1'b0;
                ic_req_raddr = req_line_addr_now;
            end
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            req_addr_q <= 32'b0;
            req_tag_q <= {TAG_WIDTH{1'b0}};
            req_offset_q <= {OFFSET_WIDTH{1'b0}};
            req_index_q <= {INDEX_WIDTH{1'b0}};
            mem_req_sent <= 1'b0;
            refill_done_q <= 1'b0;
        end
        else begin
            if (cpu_req_fire) begin
                req_addr_q <= pm_req_addr_in;
                req_tag_q <= req_tag_now;
                req_offset_q <= req_offset_now;
                req_index_q <= req_index_now;
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b0;
            end
            else if (current_state == RDMEM && ic_req_rvalid && ic_req_rready) begin
                mem_req_sent <= 1'b1;
            end
            else if (current_state == RDMEM && ic_resp_rvalid) begin
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b1;
            end
            else if (current_state == BUSY && selected_rd_fire) begin
                refill_done_q <= 1'b0;
            end
            else if (current_state == IDLE) begin
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b0;
            end
        end
    end

endmodule
