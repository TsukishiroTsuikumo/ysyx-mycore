module ROB #(
    parameter DEPTH = 8
)
(
    input               clk,
    input               reset,
    input               flush,

    // from decoder
    input               instr_valid,
    input       [31:0]  instr_pc,
    input               sel_rd,
    input        [4:0]  rd_addr,
    input       [31:0]  rd_data,

    output              instr_stall,

    // to commit
    output              commit_valid,
    output       [4:0]  commit_rd_addr,
    output      [31:0]  commit_rd_data
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

    reg [31:0]  rob_id_fifo     [0:DEPTH-1];
    reg [31:0]  entry_valid_fifo[0:DEPTH-1];
    reg [31:0]  pc_fifo         [0:DEPTH-1];
    //reg [31:0]  instr_fifo      [0:DEPTH-1];
    reg         sel_rd_fifo     [0:DEPTH-1];
    reg  [4:0]  rd_addr_fifo    [0:DEPTH-1];
    reg [31:0]  rd_data_fifo    [0:DEPTH-1];
    reg         is_jp_fifo      [0:DEPTH-1];
    reg         valid_fifo      [0:DEPTH-1];
    reg         finish_fifo     [0:DEPTH-1];

    localparam PTR_WIDTH = clog2(DEPTH);
    reg [PTR_WIDTH:0] head;
    reg [PTR_WIDTH:0] tail;

    wire full = (head[PTR_WIDTH-1:0] == tail[PTR_WIDTH-1:0]) && (head[PTR_WIDTH] != tail[PTR_WIDTH]);
    wire empty = (head == tail);

    assign instr_stall = full;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 0;
            tail <= 0;
            instr_stall <= 1'b0;
            for (int i = 0; i < DEPTH; i = i + 1) begin
                entry_valid_fifo[i] = 1'b0;
            end
        end 
        else begin
            if (instr_valid) begin
                entry_valid_fifo[head[PTR_WIDTH-1:0]] = 1'b1;
                pc_fifo[head[PTR_WIDTH-1:0]]          = instr_pc;
                //instr_fifo[head[PTR_WIDTH-1:0]]     = instr;
                sel_rd_fifo[head[PTR_WIDTH-1:0]]      = sel_rd;
                rd_addr_fifo[head[PTR_WIDTH-1:0]]     = rd_addr;
                head = head + 1'b1;
            end
        end
    end

    always @(*) begin
        
        commit_valid = 1'b0;
        commit_rd_addr = 5'h0;
        commit_rd_data = 32'h0;
        
        if(finish_fifo[head[PTR_WIDTH-1:0]] && entry_valid_fifo[head[PTR_WIDTH-1:0]]) begin
            if (sel_rd_fifo[head[PTR_WIDTH-1:0]]) begin
                commit_valid   = 1'b1;
                commit_rd_addr = rd_addr_fifo[head[PTR_WIDTH-1:0]];
                commit_rd_data = rd_data_fifo[head[PTR_WIDTH-1:0]];
                if (is_jp_fifo[head[PTR_WIDTH-1:0]]) begin
                    head = tail;
                    tail = tail + 1'b1;
                end
            end
            entry_valid_fifo[head[PTR_WIDTH-1:0]] = 1'b0;
            head = head + 1'b1;
        end
    
    end

endmodule
