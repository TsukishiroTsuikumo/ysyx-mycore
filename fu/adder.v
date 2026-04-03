module adder (
    input                is_used,     
    input         [2:0]  opcode,
    input        [31:0]  addA,
    input        [31:0]  addB,
    output       [31:0]  addC,
    output  reg          branch_cd // branch condition signal, if = 1, branch is taken
);
    localparam eq = 3'b011;
    localparam ne = 3'b100;
    localparam lt = 3'b001;
    localparam ge = 3'b010;
    localparam ltu = 3'b101;
    localparam geu = 3'b110;

    wire do_sub = (opcode == 3'b111) || (opcode == eq) || (opcode == ne) ||
                  (opcode == lt) || (opcode == ge) || (opcode == ltu) || (opcode == geu);

    wire [32:0] a_ext = is_used ? {1'b0, addA} : 33'b0;
    wire [32:0] b_ext = is_used ? {1'b0, addB} : 33'b0;
    wire [33:0] sum_ext = do_sub ? ({1'b0, a_ext} + {1'b0, ~b_ext} + 34'd1)
                                 : ({1'b0, a_ext} + {1'b0, b_ext});
    wire [31:0] sum = sum_ext[31:0];
    wire ZF = (sum == 32'b0);
    wire SF = sum[31];
    wire OF = do_sub ? ((addA[31] != addB[31]) && (sum[31] != addA[31]))
                     : ((addA[31] == addB[31]) && (sum[31] != addA[31]));
    wire CF = sum_ext[32];

    always @(*) begin
        case (opcode)
            eq: branch_cd = ZF;
            ne: branch_cd = ~ZF;
            lt: branch_cd = SF ^ OF;
            ge: branch_cd = ~ZF & ~(SF ^ OF);
            ltu: branch_cd = CF;
            geu: branch_cd = ~CF;
            default: branch_cd = 1'b0;
        endcase
    end

    assign addC = sum;

endmodule
