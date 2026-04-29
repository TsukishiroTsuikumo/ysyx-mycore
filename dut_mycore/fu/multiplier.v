module multiplier(
    input           is_used,
    input   [3:0]   opcode,
    input   [31:0]  mpyA,
    input   [31:0]  mpyB,
    output  [31:0]  mpyC
);
    localparam mul = 4'b0001; // signed * signed
    localparam mulh = 4'b0010; // signed * signed
    localparam mulsu = 4'b0100; // signed * unsigned
    localparam mulu = 4'b1000;  // unsigned * unsigned

    wire [31:0] a_in;
    wire [31:0] b_in;
    assign a_in = is_used ? mpyA : 32'b0;
    assign b_in = is_used ? mpyB : 32'b0;

    reg [31:0] product;
    always @(*) begin
        case (opcode)
            mul: product = $signed(a_in) * $signed(b_in);
            mulh: product = ($signed(a_in) * $signed(b_in)) >> 32;
            mulsu: product = ($signed(a_in) * b_in) >> 32;
            mulu: product = a_in * b_in;
            default: product = 32'b0;
        endcase
    end

    assign mpyC = product;

endmodule
