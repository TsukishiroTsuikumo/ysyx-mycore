module Dcache #(
    parameter DM_LINE_BYTES = 16,
    parameter DM_WAY_NUM    = 4,
    parameter DM_SET_NUM    = 16,
    parameter DM_LINE_WIDTH = DM_LINE_BYTES * 8
)(
    input                           clk,
    input                           reset,

    // CPU data memory interface
    input                    [31:0] dm_req_addr_in,

    input                           dm_req_rvalid_in,
    output                          dm_req_rready_in,
    output  reg                     dm_resp_rvalid_out,
    output  reg              [31:0] dm_resp_rdata_out,

    input                           dm_req_wvalid_in,
    output                          dm_req_wready_out,
    input                     [3:0] dm_req_wstrb_in,
    input                    [31:0] dm_req_wdata_in,
    output  reg                     dm_resp_wready_out,

    // MEM line read interface
    output  reg                     dc_req_rvalid,
    input                           dc_req_rready,
    output  reg              [31:0] dc_req_raddr,

    input                           dc_resp_rvalid,
    input       [DM_LINE_WIDTH-1:0] dc_resp_rdata,

    // MEM line writeback interface
    output  reg                     dc_req_wvalid,
    input                           dc_req_wready,
    output  reg              [31:0] dc_req_waddr,
    output  reg [DM_LINE_WIDTH-1:0] dc_req_wdata,

    input                           dc_resp_wvalid
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

    localparam integer OFFSET_WIDTH = clog2(DM_LINE_BYTES);
    localparam integer INDEX_WIDTH  = clog2(DM_SET_NUM);
    localparam integer WAY_WIDTH    = (DM_WAY_NUM <= 1) ? 1 : clog2(DM_WAY_NUM);
    localparam integer TAG_WIDTH    = 32 - OFFSET_WIDTH - INDEX_WIDTH;
    localparam [31:0]  LINE_MASK    = DM_LINE_BYTES - 1;

    localparam IDLE  = 2'd0;
    localparam BUSY  = 2'd1;
    localparam WRMEM = 2'd2;
    localparam RDMEM = 2'd3;

    reg [1:0] current_state;
    reg [1:0] next_state;

    wire cpu_read_fire;
    wire cpu_write_fire;
    wire cpu_req_fire;
    wire cpu_req_is_write_now;

    wire [OFFSET_WIDTH-1:0] req_offset_now;
    wire [INDEX_WIDTH-1:0] req_index_now;
    wire [TAG_WIDTH-1:0] req_tag_now;
    wire [31:0] req_line_addr_now;
    wire [31:0] req_offset_q_ext;

    reg [31:0] req_addr_q;
    reg [TAG_WIDTH-1:0] req_tag_q;
    reg [OFFSET_WIDTH-1:0] req_offset_q;
    reg [INDEX_WIDTH-1:0] req_index_q;
    reg req_is_write_q;
    reg [3:0] req_wstrb_q;
    reg [31:0] req_wdata_q;

    reg mem_req_sent;
    reg refill_done_q;
    reg [31:0] wb_addr_q;
    reg [DM_LINE_WIDTH-1:0] wb_data_q;

    wire [TAG_WIDTH-1:0] active_tag;
    wire [INDEX_WIDTH-1:0] active_index;

    wire [DM_SET_NUM-1:0] set_rd_req;
    wire [DM_SET_NUM-1:0] set_wr_req;
    wire [DM_SET_NUM-1:0] set_wr_refill;
    wire [DM_SET_NUM-1:0] set_rd_hit;
    wire [DM_SET_NUM-1:0] set_wr_hit;
    wire [DM_SET_NUM-1:0] set_rd_fire;
    wire [DM_SET_NUM-1:0] set_wr_fire;
    wire [DM_SET_NUM-1:0] set_miss;
    wire [DM_SET_NUM-1:0] set_miss_need_wb;
    wire [TAG_WIDTH-1:0] set_wb_tag [0:DM_SET_NUM-1];
    wire [DM_LINE_WIDTH-1:0] set_wb_data [0:DM_SET_NUM-1];
    wire [DM_LINE_WIDTH-1:0] set_rdata [0:DM_SET_NUM-1];

    wire selected_rd_hit;
    wire selected_wr_hit;
    wire selected_rd_fire;
    wire selected_wr_fire;
    wire selected_miss;
    wire selected_miss_need_wb;

    reg [DM_LINE_BYTES-1:0] cpu_wstrb_line;
    reg [DM_LINE_WIDTH-1:0] cpu_wdata_line;
    reg [31:0] selected_read_word;

    integer byte_idx;
    integer line_byte_idx;

    assign dm_req_wready_out = (current_state == IDLE);
    assign dm_req_rready_in = (current_state == IDLE) && !dm_req_wvalid_in;

    assign cpu_write_fire = dm_req_wvalid_in && dm_req_wready_out;
    assign cpu_read_fire = dm_req_rvalid_in && dm_req_rready_in;
    assign cpu_req_fire = cpu_write_fire || cpu_read_fire;
    assign cpu_req_is_write_now = cpu_write_fire;

    assign req_offset_now = dm_req_addr_in[OFFSET_WIDTH-1:0];
    assign req_index_now = dm_req_addr_in[OFFSET_WIDTH +: INDEX_WIDTH];
    assign req_tag_now = dm_req_addr_in[31:OFFSET_WIDTH+INDEX_WIDTH];
    assign req_line_addr_now = dm_req_addr_in & ~LINE_MASK;
    assign req_offset_q_ext = {{(32-OFFSET_WIDTH){1'b0}}, req_offset_q};

    assign active_tag = (current_state == IDLE) ? req_tag_now : req_tag_q;
    assign active_index = (current_state == IDLE) ? req_index_now : req_index_q;

    assign selected_rd_hit = set_rd_hit[active_index];
    assign selected_wr_hit = set_wr_hit[active_index];
    assign selected_rd_fire = set_rd_fire[req_index_q];
    assign selected_wr_fire = set_wr_fire[req_index_q];
    assign selected_miss = set_miss[active_index];
    assign selected_miss_need_wb = set_miss_need_wb[active_index];

    always @(*) begin
        cpu_wstrb_line = {DM_LINE_BYTES{1'b0}};
        cpu_wdata_line = {DM_LINE_WIDTH{1'b0}};

        if (current_state == IDLE && (dm_req_wvalid_in || dm_req_rvalid_in)) begin
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
                line_byte_idx = dm_req_addr_in[OFFSET_WIDTH-1:0];
                line_byte_idx = line_byte_idx + byte_idx;
                if (dm_req_wstrb_in[byte_idx] && line_byte_idx < DM_LINE_BYTES) begin
                    cpu_wstrb_line[line_byte_idx] = 1'b1;
                    cpu_wdata_line[line_byte_idx*8 +: 8] = dm_req_wdata_in[byte_idx*8 +: 8];
                end
            end
        end
        else begin
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
                line_byte_idx = req_offset_q_ext;
                line_byte_idx = line_byte_idx + byte_idx;
                if (req_wstrb_q[byte_idx] && line_byte_idx < DM_LINE_BYTES) begin
                    cpu_wstrb_line[line_byte_idx] = 1'b1;
                    cpu_wdata_line[line_byte_idx*8 +: 8] = req_wdata_q[byte_idx*8 +: 8];
                end
            end
        end
    end

    always @(*) begin
        selected_read_word = 32'b0;

        for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            line_byte_idx = req_offset_q_ext;
            line_byte_idx = line_byte_idx + byte_idx;
            if (line_byte_idx < DM_LINE_BYTES) begin
                selected_read_word[byte_idx*8 +: 8] = set_rdata[req_index_q][line_byte_idx*8 +: 8];
            end
        end
    end

    genvar set_idx;
    generate
        for (set_idx = 0; set_idx < DM_SET_NUM; set_idx = set_idx + 1) begin: gen_dcache_set
            localparam [INDEX_WIDTH-1:0] SET_INDEX = set_idx;

            assign set_rd_req[set_idx] =
                (current_state == IDLE && cpu_read_fire && req_index_now == SET_INDEX) ||
                (current_state == BUSY && refill_done_q && !req_is_write_q && req_index_q == SET_INDEX);

            assign set_wr_req[set_idx] =
                (current_state == IDLE && cpu_write_fire && req_index_now == SET_INDEX) ||
                (current_state == BUSY && refill_done_q && req_is_write_q && req_index_q == SET_INDEX) ||
                (current_state == RDMEM && dc_resp_rvalid && req_index_q == SET_INDEX);

            assign set_wr_refill[set_idx] =
                (current_state == RDMEM && dc_resp_rvalid && req_index_q == SET_INDEX);

            one_set #(
                .TAG_WIDTH(TAG_WIDTH),
                .OFFSET_WIDTH(OFFSET_WIDTH),
                .WAY_WIDTH(WAY_WIDTH),
                .WAY_NUM(DM_WAY_NUM),
                .LINE_BYTES(DM_LINE_BYTES),
                .LINE_WIDTH(DM_LINE_WIDTH)
            ) set_inst (
                .clk( clk ),
                .reset( reset ),
                .set_tag( active_tag ),

                .rd_req_in( set_rd_req[set_idx] ),
                .rd_hit_out( set_rd_hit[set_idx] ),
                .rdata_strb_in( {DM_LINE_BYTES{1'b1}} ),
                .rdata_out( set_rdata[set_idx] ),
                .rd_fire_out( set_rd_fire[set_idx] ),

                .wr_req_in( set_wr_req[set_idx] ),
                .wr_refill_in( set_wr_refill[set_idx] ),
                .wr_hit_out( set_wr_hit[set_idx] ),
                .wdata_strb_in( set_wr_refill[set_idx] ? {DM_LINE_BYTES{1'b1}} : cpu_wstrb_line ),
                .wdata_in( set_wr_refill[set_idx] ? dc_resp_rdata : cpu_wdata_line ),
                .wr_fire_out( set_wr_fire[set_idx] ),

                .miss_out( set_miss[set_idx] ),
                .miss_need_wb_out( set_miss_need_wb[set_idx] ),
                .wb_tag_out( set_wb_tag[set_idx] ),
                .wb_data_out( set_wb_data[set_idx] )
            );
        end
    endgenerate

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
                if (cpu_req_fire && ((cpu_req_is_write_now && selected_wr_hit) ||
                                     (!cpu_req_is_write_now && selected_rd_hit))) begin
                    next_state = BUSY;
                end
                else if (cpu_req_fire && selected_miss && selected_miss_need_wb) begin
                    next_state = WRMEM;
                end
                else if (cpu_req_fire && selected_miss) begin
                    next_state = RDMEM;
                end
                else begin
                    next_state = IDLE;
                end
            end

            BUSY: begin
                if ((req_is_write_q && selected_wr_fire) || (!req_is_write_q && selected_rd_fire)) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = BUSY;
                end
            end

            WRMEM: begin
                if (dc_resp_wvalid) begin
                    next_state = RDMEM;
                end
                else begin
                    next_state = WRMEM;
                end
            end

            RDMEM: begin
                if (dc_resp_rvalid) begin
                    next_state = BUSY;
                end
                else begin
                    next_state = RDMEM;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(*) begin
        dm_resp_rvalid_out = 1'b0;
        dm_resp_rdata_out = 32'b0;
        dm_resp_wready_out = 1'b0;

        dc_req_rvalid = 1'b0;
        dc_req_raddr = req_addr_q & ~LINE_MASK;

        dc_req_wvalid = 1'b0;
        dc_req_waddr = wb_addr_q;
        dc_req_wdata = wb_data_q;

        case (current_state)
            BUSY: begin
                if (req_is_write_q && selected_wr_fire) begin
                    dm_resp_wready_out = 1'b1;
                end
                else if (!req_is_write_q && selected_rd_fire) begin
                    dm_resp_rvalid_out = 1'b1;
                    dm_resp_rdata_out = selected_read_word;
                end
            end

            WRMEM: begin
                if (!mem_req_sent) begin
                    dc_req_wvalid = 1'b1;
                end
                dc_req_waddr = wb_addr_q;
                dc_req_wdata = wb_data_q;
            end

            RDMEM: begin
                if (!mem_req_sent) begin
                    dc_req_rvalid = 1'b1;
                end
                dc_req_raddr = req_addr_q & ~LINE_MASK;
            end

            default: begin
                dc_req_raddr = req_line_addr_now;
                dc_req_waddr = wb_addr_q;
                dc_req_wdata = wb_data_q;
            end
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            req_addr_q <= 32'b0;
            req_tag_q <= {TAG_WIDTH{1'b0}};
            req_offset_q <= {OFFSET_WIDTH{1'b0}};
            req_index_q <= {INDEX_WIDTH{1'b0}};
            req_is_write_q <= 1'b0;
            req_wstrb_q <= 4'b0;
            req_wdata_q <= 32'b0;
            mem_req_sent <= 1'b0;
            refill_done_q <= 1'b0;
            wb_addr_q <= 32'b0;
            wb_data_q <= {DM_LINE_WIDTH{1'b0}};
        end
        else begin
            if (cpu_req_fire) begin
                req_addr_q <= dm_req_addr_in;
                req_tag_q <= req_tag_now;
                req_offset_q <= req_offset_now;
                req_index_q <= req_index_now;
                req_is_write_q <= cpu_req_is_write_now;
                req_wstrb_q <= cpu_req_is_write_now ? dm_req_wstrb_in : 4'b0;
                req_wdata_q <= cpu_req_is_write_now ? dm_req_wdata_in : 32'b0;
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b0;

                if (selected_miss_need_wb) begin
                    wb_addr_q <= {set_wb_tag[req_index_now], req_index_now, {OFFSET_WIDTH{1'b0}}};
                    wb_data_q <= set_wb_data[req_index_now];
                end
            end
            else if (current_state == WRMEM && dc_req_wvalid && dc_req_wready) begin
                mem_req_sent <= 1'b1;
            end
            else if (current_state == WRMEM && dc_resp_wvalid) begin
                mem_req_sent <= 1'b0;
            end
            else if (current_state == RDMEM && dc_req_rvalid && dc_req_rready) begin
                mem_req_sent <= 1'b1;
            end
            else if (current_state == RDMEM && dc_resp_rvalid) begin
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b1;
            end
            else if (current_state == BUSY &&
                     ((req_is_write_q && selected_wr_fire) || (!req_is_write_q && selected_rd_fire))) begin
                refill_done_q <= 1'b0;
            end
            else if (current_state == IDLE) begin
                mem_req_sent <= 1'b0;
                refill_done_q <= 1'b0;
            end
        end
    end

endmodule
