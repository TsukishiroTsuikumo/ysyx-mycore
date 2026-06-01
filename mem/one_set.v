module one_set #(
    parameter TAG_WIDTH     = 1,
    parameter OFFSET_WIDTH  = 4,
    parameter WAY_WIDTH     = 2,
    parameter WAY_NUM       = 1 << WAY_WIDTH,
    parameter LINE_BYTES    = 1 << OFFSET_WIDTH,
    parameter LINE_WIDTH    = LINE_BYTES * 8
)(
    input                           clk,
    input                           reset,

    input          [TAG_WIDTH-1:0]  set_tag,

    input                           rd_req_in,
    output  reg                     rd_hit_out,
    input         [LINE_BYTES-1:0]  rdata_strb_in,
    output  reg   [LINE_WIDTH-1:0]  rdata_out,
    output  reg                     rd_fire_out,

    input                           wr_req_in,
    input                           wr_refill_in,
    output  reg                     wr_hit_out,
    input         [LINE_BYTES-1:0]  wdata_strb_in,
    input         [LINE_WIDTH-1:0]  wdata_in,
    output  reg                     wr_fire_out,

    output  reg                     miss_out,
    output  reg                     miss_need_wb_out,
    output  reg     [TAG_WIDTH-1:0] wb_tag_out,
    output  reg    [LINE_WIDTH-1:0] wb_data_out
);

    reg    [LINE_WIDTH-1:0] cache_line [0:WAY_NUM-1];
    reg     [TAG_WIDTH-1:0] line_tag   [0:WAY_NUM-1];
    reg               [1:0] line_state [0:WAY_NUM-1]; // bit0 valid, bit1 dirty
    reg     [WAY_WIDTH-1:0] line_time  [0:WAY_NUM-1];

    reg                     hit;
    reg     [WAY_WIDTH-1:0] hit_way;
    reg     [WAY_WIDTH-1:0] victim_way;
    reg                     found_invalid;

    // Hit logic and victim selection logic
    always @(*) begin
        integer i;

        hit = 1'b0;
        hit_way = {WAY_WIDTH{1'b0}};
        victim_way = {WAY_WIDTH{1'b0}};
        found_invalid = 1'b0;

        for (i = 0; i < WAY_NUM; i = i + 1) begin
            if ( !hit &&line_state[i][0] && line_tag[i] == set_tag ) begin
                hit = 1'b1;
                hit_way = i[WAY_WIDTH-1:0];
            end
            if ( !line_state[i][0] ) begin
                found_invalid = 1'b1;
                victim_way = i[WAY_WIDTH-1:0];
            end
            else if ( !found_invalid && (line_time[i] == {WAY_WIDTH{1'b0}}) ) begin
                victim_way = i[WAY_WIDTH-1:0];
            end
        end
    end

    // Miss logic
    always @(*) begin
        wr_hit_out = hit && wr_req_in;
        rd_hit_out = hit && rd_req_in;
        miss_out = !hit && (rd_req_in || wr_req_in);
        miss_need_wb_out = miss_out && line_state[victim_way][0] && line_state[victim_way][1];
        wb_tag_out = line_tag[victim_way];
        wb_data_out = cache_line[victim_way];
    end

    // Line Read, with one cycle delay for combinational read
    reg [LINE_BYTES-1:0] rdata_strb_DLY1;
    reg                  rd_hit_DLY1;
    reg  [WAY_WIDTH-1:0] hit_way_DLY1;
    always @(posedge clk) begin
        rd_hit_DLY1 <= rd_hit_out;
        rdata_strb_DLY1 <= rdata_strb_in;
        hit_way_DLY1 <= hit_way;
    end
    always @(*) begin
        integer i;
        rdata_out = {LINE_WIDTH{1'b0}};
        rd_fire_out = 1'b0;
        if (rd_hit_DLY1) begin
            for (i = 0; i < LINE_BYTES; i = i + 1) begin
                if (rdata_strb_DLY1[i]) begin
                    rdata_out[i*8+7 -: 8] = cache_line[hit_way_DLY1][i*8+7 -: 8];
                end
            end
            rd_fire_out = 1'b1;
        end
    end

    // Line Write, with sequential logic to update the cache line and metadata
    always @(posedge clk or posedge reset) begin
        integer i;
        if(reset) begin
            for(i=0; i<WAY_NUM; i=i+1) begin
                line_state[i] <= 2'b00; // Invalidate all lines on reset
            end
            wr_fire_out <= 1'b0;
        end
        else begin
            if(wr_hit_out) begin
                for(i=0; i<LINE_BYTES; i=i+1) begin
                    if (wdata_strb_in[i]) begin
                        cache_line[hit_way][i*8+7 -: 8] <= wdata_in[i*8+7 -: 8];
                    end
                end
                line_state[hit_way][1] <= 1'b1;
                wr_fire_out <= 1'b1;
            end
            else if (wr_refill_in) begin
                cache_line[victim_way] <= wdata_in;
                line_tag[victim_way]   <= set_tag;
                line_state[victim_way] <= 2'b01;
                for(i=0; i<WAY_NUM; i=i+1) begin
                    if (line_time[i] != {WAY_WIDTH{1'b0}}) begin
                        line_time[i] <= line_time[i] - 1'b1;
                    end
                end
                line_time[victim_way] <= {WAY_WIDTH{1'b1}};
                wr_fire_out <= 1'b1;
            end
            else begin
                wr_fire_out <= 1'b0;
            end
        end
    end

endmodule
