module imu (
    input               is_used,
    input       [1:0]   opcode,
    input       [31:0]  current_pc,
    input       [31:0]  imm,
    output  reg [31:0]  out
);

    always @(*) begin
        if(is_used) begin
            case(opcode)
                2'b01: out = imm; // LUI
                2'b10: out = current_pc + imm; // AUIPC
                default: out = 32'b0;
            endcase
        end
        else out = 32'b0;
    end

endmodule
