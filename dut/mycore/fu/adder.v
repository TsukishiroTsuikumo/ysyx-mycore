module adder (
    input                is_used,
    input         [2:0]  opcode,
    input                sel_rd,
    input        [31:0]  addA,
    input        [31:0]  addB,
    output  reg  [31:0]  addC,
    output  reg          branch_cd // branch condition signal, if = 1, branch is taken
);
    localparam add = 3'b000;
    localparam sub = 3'b111;
    localparam eq  = 3'b011;
    localparam ne  = 3'b100;
    localparam lt  = 3'b001;
    localparam ge  = 3'b010;
    localparam ltu = 3'b101;
    localparam geu = 3'b110;

    wire [31:0] a_in;
    wire [31:0] b_in;
    wire sel_sub;
    wire [31:0] b_in_mux;
    
    assign a_in = is_used ? addA : 32'b0;
    assign b_in = is_used ? addB : 32'b0;
    assign sel_sub = (opcode != add);
    assign b_in_mux = sel_sub ? ~b_in : b_in;
    wire [33:0] sum;

    assign sum = {1'b0, a_in} + {1'b0, b_in_mux} + sel_sub;

    wire ZF, SF, OF, CF;
    assign ZF = (sum[31:0] == 32'b0);
    assign SF = sum[31];
    assign OF = (a_in[31] != b_in[31]) && (sum[31] != a_in[31]);
    assign CF = sum[32];

    always @(*) begin
        branch_cd = 1'b0;
        addC = 32'b0;
        if (sel_rd) begin
            case (opcode)
                add: addC = sum[31:0];
                sub: addC = sum[31:0];
                lt:  addC = (SF ^ OF) ? 32'b1 : 32'b0;
                ltu: addC = ~CF ? 32'b1 : 32'b0;
            endcase
        end
        else begin
            case (opcode)
                eq:  branch_cd = ZF;
                ne:  branch_cd = ~ZF;
                lt:  branch_cd = SF ^ OF;
                ge:  branch_cd = ~(SF ^ OF);
                ltu: branch_cd = ~CF;
                geu: branch_cd = CF;
            endcase
        end
    end

endmodule
