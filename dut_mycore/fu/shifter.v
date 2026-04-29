module shifter (
    input           is_used,
    input    [1:0]  opcode,
    input   [31:0]  shfA,
    input   [31:0]  shfB,
    output  [31:0]  shfC
);

    localparam sll = 2'b00;
    localparam srl = 2'b01;
    localparam sra = 2'b10;

    assign wire [31:0] a_in = is_used ? shfA : 32'b0;
    assign wire [31:0] b_in = is_used ? shfB : 32'b0;

    assign wire sel_bit = b_in[4:0]; // only consider the lower 5 bits of shfB for shift amount

    assign wire [31:0] sll4 = {a_in[15:0], 16'b0};
    assign wire [31:0] srl4 = {16'b0, a_in[31:16]};
    assign wire [31:0] sra4 = {16{a_in[31]}, a_in[31:16]};
    assign wire rst4 = sel_bit[4] ? (opcode == sll ? sll4 : (opcode == srl ? srl4 : sra4)) : shfA;

    assign wire [31:0] sll3 = {rst4[23:0], 8'b0};
    assign wire [31:0] srl3 = {8'b0, rst4[31:8]};
    assign wire [31:0] sra3 = {8{rst4[31]}, rst4[31:8]};
    assign wire rst3 = sel_bit[3] ? (opcode == sll ? sll3 : (opcode == srl ? srl3 : sra3)) : rst4;

    assign wire [31:0] sll2 = {rst3[27:0], 4'b0};
    assign wire [31:0] srl2 = {4'b0, rst3[31:4]};
    assign wire [31:0] sra2 = {4{rst3[31]}, rst3[31:4]};
    assign wire rst2 = sel_bit[2] ? (opcode == sll ? sll2 : (opcode == srl ? srl2 : sra2)) : rst3;

    assign wire [31:0] sll1 = {rst2[29:0], 2'b0};
    assign wire [31:0] srl1 = {2'b0, rst2[31:2]};
    assign wire [31:0] sra1 = {2{rst2[31]}, rst2[31:2]};
    assign wire rst1 = sel_bit[1] ? (opcode == sll ? sll1 : (opcode == srl ? srl1 : sra1)) : rst2;

    assign wire [31:0] sll0 = {rst1[30:0], 1'b0};
    assign wire [31:0] srl0 = {1'b0, rst1[31:1]};
    assign wire [31:0] sra0 = {rst1[31], rst1[31:1]};
    assign shfC = sel_bit[0] ? (opcode == sll ? sll0 : (opcode == srl ? srl0 : sra0)) : rst1;

endmodule