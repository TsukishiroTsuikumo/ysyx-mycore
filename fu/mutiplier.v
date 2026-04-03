module multiplier(
    input           is_used,
    input   [1:0]   opcode,
    input   [31:0]  mpyA,
    input   [31:0]  mpyB,
    output [31:0]   mpyC
);
    localparam mul = 2'b00;
    localparam mulh = 2'b01;
    localparam mulsu = 2'b10;
    localparam mulu = 2'b11;

    wire [31:0] a_in = is_used ? mpyA : 32'b0;
    wire [31:0] b_in = is_used ? mpyB : 32'b0;
    wire [63:0] prod_u = a_in * b_in;
    wire signed [31:0] a_s = a_in;
    wire signed [31:0] b_s = b_in;
    wire signed [63:0] prod_s = a_s * b_s;

    assign mpyC = (opcode == mulh) ? prod_s[63:32] : prod_u[31:0];

endmodule
