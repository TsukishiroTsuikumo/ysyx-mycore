module alu (
    input               is_used,
    input        [1:0]  opcode,
    input       [31:0]  aluA,
    input       [31:0]  aluB,
    output  reg [31:0]  aluC
);

    localparam op_or = 2'b01;
    localparam op_and = 2'b10;
    localparam op_xor = 2'b11;

    assign wire [31:0] a_in = is_used ? aluA : 32'b0;
    assign wire [31:0] b_in = is_used ? aluB : 32'b0;

    always @(*) begin
        case(opcode)
            op_or: aluC = a_in | b_in;
            op_and: aluC = a_in & b_in;
            op_xor: aluC = a_in ^ b_in;
            default: aluC = 32'b0;
        endcase
    end

endmodule
    