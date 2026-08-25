module instr_queue #(
    parameter QUEUE_DEPTH = 4
)(
    input               clk,
    input               reset,

    output              pm_req_valid,
    input       [31:0]  pm_req_addr,
    input               pm_req_ready,

    input               pm_resp_valid,
    input       [31:0]  pm_resp_data,

    output              if_stall,
    input               stall,
    input               flush,

    output  reg [31:0]  instr_out,
    output  reg [31:0]  pc_out,
    output  reg         instr_valid
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

    reg [31:0] instr_fifo [0:QUEUE_DEPTH-1];
    reg [31:0] pc_fifo    [0:QUEUE_DEPTH-1];
    reg        req_fifo   [0:QUEUE_DEPTH-1];
    reg        rsp_fifo   [0:QUEUE_DEPTH-1];

    localparam PTR_WIDTH = clog2(QUEUE_DEPTH);
    reg [PTR_WIDTH:0] read_ptr;
    reg [PTR_WIDTH:0] malloc_ptr;
    reg [PTR_WIDTH:0] instr_tail;
    reg [PTR_WIDTH:0] old_resp_drop_count;

    wire queue_empty = (malloc_ptr == read_ptr);
    wire queue_full = (malloc_ptr[PTR_WIDTH-1:0] == read_ptr[PTR_WIDTH-1:0]) && (malloc_ptr[PTR_WIDTH] != read_ptr[PTR_WIDTH]);

    assign pm_req_valid = !queue_full;
    wire wr_pc_en = pm_req_valid && pm_req_ready;
    assign if_stall = !wr_pc_en;
    wire [PTR_WIDTH:0] outstanding_resp_count = malloc_ptr - instr_tail;
    wire [PTR_WIDTH:0] flush_req_count = wr_pc_en ? {{PTR_WIDTH{1'b0}}, 1'b1} : {PTR_WIDTH+1{1'b0}};
    wire [PTR_WIDTH:0] flush_pending_resp_count = old_resp_drop_count + outstanding_resp_count;
    wire [PTR_WIDTH:0] flush_resp_count = (pm_resp_valid && (flush_pending_resp_count != {PTR_WIDTH+1{1'b0}})) ?
                                            {{PTR_WIDTH{1'b0}}, 1'b1} : {PTR_WIDTH+1{1'b0}};
    wire [PTR_WIDTH:0] flush_drop_count = old_resp_drop_count + outstanding_resp_count + flush_req_count - flush_resp_count;
    wire drop_old_resp_en = pm_resp_valid && (old_resp_drop_count != {PTR_WIDTH+1{1'b0}});
    wire resp_alloc_same_cycle = wr_pc_en && (malloc_ptr == instr_tail);
    wire wr_instr_en = (req_fifo[instr_tail[PTR_WIDTH-1:0]] == 1'b1)
                    || resp_alloc_same_cycle;
    wire wr_instr_fire = wr_instr_en
                    && (rsp_fifo[instr_tail[PTR_WIDTH-1:0]] == 1'b0)
                    && !drop_old_resp_en
                    && pm_resp_valid;

    wire rd_en = !queue_empty 
              && req_fifo[read_ptr[PTR_WIDTH-1:0]]
              && rsp_fifo[read_ptr[PTR_WIDTH-1:0]];


    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_ptr <= 0;
            malloc_ptr <= 0;
            instr_tail <= 0;
            old_resp_drop_count <= 0;
            instr_out <= 32'h00000013;
            pc_out <= 32'h00000000;
            instr_valid <= 1'b0;
            for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
                req_fifo[i] <= 1'b0;
                rsp_fifo[i] <= 1'b0;
                pc_fifo[i]    <= 32'h0;
                instr_fifo[i] <= 32'h00000013;
            end
        end
        else if (flush) begin
            read_ptr <= 0;
            malloc_ptr <= 0;
            instr_tail <= 0;
            old_resp_drop_count <= flush_drop_count;
            instr_out <= 32'h00000013;
            pc_out <= 32'h00000000;
            instr_valid <= 1'b0;
            for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
                req_fifo[i] <= 1'b0;
                rsp_fifo[i] <= 1'b0;
                pc_fifo[i]    <= 32'h0;
                instr_fifo[i] <= 32'h00000013;
            end
        end
        else begin
            if (wr_pc_en) begin
                pc_fifo[malloc_ptr[PTR_WIDTH-1:0]] <= pm_req_addr;
                req_fifo[malloc_ptr[PTR_WIDTH-1:0]] <= 1'b1;
                malloc_ptr <= malloc_ptr + 1'b1;
            end

            if (wr_instr_fire) begin
                instr_fifo[instr_tail[PTR_WIDTH-1:0]] <= pm_resp_data;
                rsp_fifo[instr_tail[PTR_WIDTH-1:0]] <= 1'b1;
                instr_tail <= instr_tail + 1'b1;
            end

            if (drop_old_resp_en) begin
                old_resp_drop_count <= old_resp_drop_count - 1'b1;
            end

            if (stall) begin
                instr_out <= instr_out;
                pc_out <= pc_out;
                read_ptr <= read_ptr;
                instr_valid <= instr_valid;
            end
            else if(rd_en) begin
                instr_out <= instr_fifo[read_ptr[PTR_WIDTH-1:0]];
                pc_out <= pc_fifo[read_ptr[PTR_WIDTH-1:0]];
                req_fifo[read_ptr[PTR_WIDTH-1:0]] <= 1'b0;
                rsp_fifo[read_ptr[PTR_WIDTH-1:0]] <= 1'b0;
                read_ptr <= read_ptr + 1'b1;
                instr_valid <= 1'b1;
            end
            else begin
                instr_out <= 32'h00000013;
                pc_out <= 32'h00000000;
                read_ptr <= read_ptr;
                instr_valid <= 1'b0;
            end
        end
    end

endmodule
