module decoder1 (
    input       [31:0]  instr,
    output  reg         sel_rs1,
    output  reg [4:0]   rs1_addr,
    output  reg         sel_rs2,
    output  reg [4:0]   rs2_addr,
    output  reg         sel_imm,
    output  reg [31:0]  imm,
    output  reg         sel_rd,
    output  reg [4:0]   rd_addr,
    output  reg [2:0]   adder_op,
    output  reg [1:0]   shifter_op,
    output  reg [1:0]   multiplier_op,
    output  reg [1:0]   divider_op,
    output  reg [1:0]   alu_op,
    output      [4:0]   use_signal,
    output  reg         is_jal,
    output  reg         is_jalr,
    output  reg         is_cd_jp
);

    wire [6:0] func7  = instr[31:25];
    wire [2:0] func3  = instr[14:12];
    wire [6:0] opcode = instr[6:0];

    reg use_divider;
    reg use_multiplier;
    reg use_shifter;
    reg use_alu;
    reg use_adder;

    always @(*) begin
        sel_rs1       = 1'b0;
        rs1_addr      = instr[19:15];
        sel_rs2       = 1'b0;
        rs2_addr      = instr[24:20];
        sel_imm       = 1'b0;
        imm           = 32'b0;
        sel_rd        = 1'b0;
        rd_addr       = instr[11:7];
        adder_op      = 3'b000;
        shifter_op    = 2'b00;
        multiplier_op = 2'b00;
        divider_op    = 2'b00;
        alu_op        = 2'b00;
        use_divider   = 1'b0;
        use_multiplier= 1'b0;
        use_shifter   = 1'b0;
        use_alu       = 1'b0;
        use_adder     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        is_cd_jp      = 1'b0;

        case (opcode)
            7'b0110011: begin
                sel_rs1 = 1'b1;
                sel_rs2 = 1'b1;
                sel_rd  = 1'b1;
                if (func7 == 7'b0000001) begin
                    use_multiplier = 1'b1;
                    multiplier_op  = func3[1:0];
                end else begin
                    case (func3)
                        3'b000: begin
                            use_adder = 1'b1;
                            adder_op  = (func7 == 7'b0100000) ? 3'b111 : 3'b000;
                        end
                        3'b111: begin use_alu = 1'b1; alu_op = 2'b01; end
                        3'b110: begin use_alu = 1'b1; alu_op = 2'b10; end
                        3'b100: begin use_alu = 1'b1; alu_op = 2'b11; end
                        3'b001: begin use_shifter = 1'b1; shifter_op = 2'b00; end
                        3'b101: begin
                            use_shifter = 1'b1;
                            shifter_op  = (func7 == 7'b0100000) ? 2'b10 : 2'b01;
                        end
                        default: begin end
                    endcase
                end
            end
            7'b0010011: begin
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                imm     = {{20{instr[31]}}, instr[31:20]};
                case (func3)
                    3'b000: begin use_adder = 1'b1; adder_op = 3'b000; end
                    3'b111: begin use_alu = 1'b1; alu_op = 2'b01; end
                    3'b110: begin use_alu = 1'b1; alu_op = 2'b10; end
                    3'b100: begin use_alu = 1'b1; alu_op = 2'b11; end
                    3'b001: begin use_shifter = 1'b1; shifter_op = 2'b00; end
                    3'b101: begin
                        use_shifter = 1'b1;
                        shifter_op  = (func7 == 7'b0100000) ? 2'b10 : 2'b01;
                    end
                    default: begin end
                endcase
            end
            7'b0000011: begin
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                imm     = {{20{instr[31]}}, instr[31:20]};
            end
            7'b0100011: begin
                sel_rs1 = 1'b1;
                sel_rs2 = 1'b1;
                sel_imm = 1'b1;
                imm     = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            7'b1100011: begin
                sel_rs1  = 1'b1;
                sel_rs2  = 1'b1;
                is_cd_jp = 1'b1;
                use_adder= 1'b1;
                imm      = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
                case (func3)
                    3'b000: adder_op = 3'b011;
                    3'b001: adder_op = 3'b100;
                    3'b100: adder_op = 3'b001;
                    3'b101: adder_op = 3'b010;
                    3'b110: adder_op = 3'b101;
                    3'b111: adder_op = 3'b110;
                    default: adder_op = 3'b000;
                endcase
            end
            7'b1101111: begin
                sel_rd = 1'b1;
                is_jal = 1'b1;
                imm    = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            7'b1100111: begin
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                is_jalr = 1'b1;
                imm     = {{20{instr[31]}}, instr[31:20]};
            end
            7'b0110111, 7'b0010111: begin
                sel_rd = 1'b1;
                sel_imm= 1'b1;
                use_adder = 1'b1;
                imm = {instr[31:12], 12'b0};
            end
            default: begin end
        endcase
    end

    assign use_signal = {use_divider, use_multiplier, use_shifter, use_alu, use_adder};

endmodule
