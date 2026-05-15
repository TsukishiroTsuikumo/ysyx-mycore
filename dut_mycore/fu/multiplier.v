module multiplier(
    input           is_used,
    input   [3:0]   opcode,
    input   [31:0]  mpyA,
    input   [31:0]  mpyB,
    output  [31:0]  mpyC
);
    localparam mul = 4'b0001;   // low signed * signed
    localparam mulh = 4'b0010;  // high signed * signed
    localparam mulsu = 4'b0100; // high signed * unsigned
    localparam mulu = 4'b1000;  // high unsigned * unsigned

    wire [31:0] a_in;
    wire [31:0] b_in;
    assign a_in = is_used ? mpyA : 32'b0;
    assign b_in = is_used ? mpyB : 32'b0;

    reg [31:0] product;
    wire signed [32:0] a_signed_ext = {a_in[31], a_in};
    wire signed [32:0] b_signed_ext = {b_in[31], b_in};
    wire signed [32:0] b_unsigned_ext = {1'b0, b_in};

    wire signed [65:0] product_ss = a_signed_ext * b_signed_ext;
    wire signed [65:0] product_su = a_signed_ext * b_unsigned_ext;
    wire        [63:0] product_uu = a_in * b_in;

    always @(*) begin
        case (opcode)
            mul: product = product_ss[31:0];
            mulh: product = product_ss[63:32];
            mulsu: product = product_su[63:32];
            mulu: product = product_uu[63:32];
            default: product = 32'b0;
        endcase
    end

    assign mpyC = product;

endmodule
