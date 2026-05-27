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
    input               raw_stall,
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

    localparam PTR_WIDTH = clog2(QUEUE_DEPTH);
    reg [PTR_WIDTH:0] read_ptr;
    reg [PTR_WIDTH:0] pc_tail;
    reg [PTR_WIDTH:0] instr_tail;
    reg [PTR_WIDTH:0] old_resp_drop_count;

    wire pc_empty = (pc_tail == read_ptr);
    wire pc_full = (pc_tail[PTR_WIDTH-1:0] == read_ptr[PTR_WIDTH-1:0]) && (pc_tail[PTR_WIDTH] != read_ptr[PTR_WIDTH]);
    wire instr_empty = (instr_tail == read_ptr);
    wire instr_full = (instr_tail[PTR_WIDTH-1:0] == read_ptr[PTR_WIDTH-1:0]) && (instr_tail[PTR_WIDTH] != read_ptr[PTR_WIDTH]);

    assign pm_req_valid = !pc_full && !instr_full;
    wire wr_pc_en = pm_req_valid && pm_req_ready;
    assign if_stall = !wr_pc_en;

    wire [PTR_WIDTH:0] outstanding_resp_count = pc_tail - instr_tail;
    wire [PTR_WIDTH:0] flush_req_count = wr_pc_en ? {{PTR_WIDTH{1'b0}}, 1'b1} : {PTR_WIDTH+1{1'b0}};
    wire [PTR_WIDTH:0] flush_resp_count = (pm_resp_valid && ((outstanding_resp_count != {PTR_WIDTH+1{1'b0}}) || wr_pc_en)) ?
                                            {{PTR_WIDTH{1'b0}}, 1'b1} : {PTR_WIDTH+1{1'b0}};
    wire [PTR_WIDTH:0] flush_drop_count = outstanding_resp_count + flush_req_count - flush_resp_count;

    wire drop_old_resp_en = pm_resp_valid && (old_resp_drop_count != {PTR_WIDTH+1{1'b0}});
    wire wr_instr_en = pm_resp_valid && !drop_old_resp_en && !instr_full;

    wire rd_en = !pc_empty && !instr_empty;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_ptr <= 0;
            pc_tail <= 0;
            instr_tail <= 0;
            old_resp_drop_count <= 0;
            instr_out <= 32'h00000013;
            pc_out <= 32'h00000000;
            instr_valid <= 1'b0;
        end
        else if (flush) begin
            read_ptr <= 0;
            pc_tail <= 0;
            instr_tail <= 0;
            old_resp_drop_count <= flush_drop_count;
            instr_out <= 32'h00000013;
            pc_out <= 32'h00000000;
            instr_valid <= 1'b0;
        end
        else begin

            if (wr_pc_en) begin
                pc_fifo[pc_tail[PTR_WIDTH-1:0]] <= pm_req_addr;
                pc_tail <= pc_tail + 1'b1;
            end

            if (wr_instr_en) begin
                instr_fifo[instr_tail[PTR_WIDTH-1:0]] <= pm_resp_data;
                instr_tail <= instr_tail + 1'b1;
            end

            if (drop_old_resp_en) begin
                old_resp_drop_count <= old_resp_drop_count - 1'b1;
            end

            if (raw_stall) begin
                instr_out <= instr_out;
                pc_out <= pc_out;
                read_ptr <= read_ptr;
                instr_valid <= instr_valid;
            end
            else if(rd_en) begin
                instr_out <= instr_fifo[read_ptr[PTR_WIDTH-1:0]];
                pc_out <= pc_fifo[read_ptr[PTR_WIDTH-1:0]];
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
