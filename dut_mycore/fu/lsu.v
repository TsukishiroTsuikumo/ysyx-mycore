module lsu (
    input               is_used,
    input        [2:0]  opcode,
    input       [31:0]  lsuA,
    input       [31:0]  lsuB,
    input       [31:0]  addr_imm,
    output      [31:0]  dm_addr,
    output  reg [31:0]  dm_out,

    output  reg  [3:0]  is_ld,
    output  reg  [3:0]  is_st
);

    localparam lb  = 3'b000;
    localparam lh  = 3'b001;
    localparam lw  = 3'b010;
    localparam lbu = 3'b100;
    localparam lhu = 3'b101;
    localparam sb  = 3'b110;
    localparam sh  = 3'b111;
    localparam sw  = 3'b110;

    always @(*) begin
        if(is_used) begin
            
            dm_out = lsuA;
            dm_addr = lsuB + addr_imm;
            ls_ld = 4'b0;
            ls_st = 4'b0;

            case(opcode)
                lb: begin
                    is_ld = 4'b1;
                end
                lh  : begin
                    is_ld = 4'b0011;
                end
                lw: begin
                    is_ld = 4'b1111;
                end
                lbu: begin
                    is_ld = 4'b0001;
                end
                lhu: begin
                    is_ld = 4'b0011;
                end
                sb: begin
                    is_st = 4'b0001;
                end
                sh: begin
                    is_st = 4'b0011;
                end
                sw: begin
                    is_st = 4'b1111;
                end
            endcase
        end 
        else begin
            dm_addr = 32'b0;
            dm_out = 32'b0;
            is_ld = 4'b0;
            is_st = 4'b0;
        end
    end

endmodule