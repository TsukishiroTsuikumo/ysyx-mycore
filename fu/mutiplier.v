module multiplier(
    input           is_used,
    input   [1:0]   opcode,
    input           mpyA,
    input           mpyB,
    output [31:0]   mpyC
);
    localparam mul = 2'b00;
    localparam mulh = 2'b01;
    localparam mulsu = 2'b10;
    localparam mulu = 2'b11;

    assign wire [31:0] a_in = is_used ? mpyA : 32'b0;
    assign wire [31:0] b_in = is_used ? mpyB : 32'b0;


endmodule