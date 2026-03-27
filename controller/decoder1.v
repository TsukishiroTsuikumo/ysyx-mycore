module decoder1
(   input [31:0] instr,

    // Oprand
    output              sel_rs1
    output       [4:0]  rs1_addr,
    output  reg         sel_rs2,
    output       [4:0]  rs2_addr,
    output  reg         sel_imm,
    output  reg [31:0]  imm,
    output  reg         sel_rd,
    output       [4:0]  rd_addr,

    // Opcode Signal
    output  reg  [2:0]  adder_op,
    output  reg  [1:0]  shifter_op,
    output  reg  [1:0]  multiplier_op,
    output  reg  [1:0]  divider_op,
    output  reg  [1:0]  alu_op,

    // Control Signal
    output       [4:0]  use_signal,
    output  reg         is_jal,
    output  reg         is_jalr,
    output  reg         is_cd_jp
);

    assign wire func7 = instr[31:25];
    assign wire func3 = instr[14:12];
    assign wire opcode = instr[6:0];
    
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd_addr  = instr[11:7];

    always @(*) begin

        sel_rs1 = 1'b0;
        sel_rs2 = 1'b0;
        sel_rd  = 1'b0;
        sel_imm = 1'b0;
        imm     = 32'b0;
        addrer_op = 3'b000;
        shifter_op = 1'b0;
        multiplier_op = 1'b0;
        divider_op = 1'b0;
        use_adder = 1'b0;
        use_shifter = 1'b0;
        use_multiplier = 1'b0;
        use_divider = 1'b0;
        is_jal = 1'b0;
        is_jalr = 1'b0;
        is_cd_jp = 1'b0;

        case(opcode)

        // ----- R-Type ----- //
            7'b0110011: begin
                sel_rs1 = 1'b1;
                sel_rs2 = 1'b1;
                sel_rd  = 1'b1;
                if(func7 == 7'b0000001) begin
                    case(func3)
                        3'b000: begin
                            multiplier_op = 1; // mul
                            use_multiplier = 1'b1;
                        end
                        3'b001: begin
                            multiplier_op = 2; // mulh
                            use_multiplier = 1'b1;
                        end
                        3'b010: begin
                            multiplier_op = 3; // mulhu
                            use_multiplier = 1'b1;
                        end
                        3'b011: begin
                            multiplier_op = 4; // mulhsu
                            use_multiplier = 1'b1;
                        end
                        3'b100: begin
                            divider_op = 1; // div
                            use_divider = 1'b1;
                        end
                        3'b101: begin
                            divider_op = 2; // divu
                            use_divider = 1'b1;
                        end
                        3'b110: begin
                            divider_op = 3; // rem
                            use_divider = 1'b1;
                        end
                        3'b111: begin
                            divider_op = 4; // remu
                            use_divider = 1'b1;
                        end
                    endcase
                end
                else begin
                    case(func3)
                        3'b000: begin
                            use_addr = 1b'1;
                            if(func7 == 7'b0000000) begin
                                adder_op = 3'b000; // add
                            end
                            else if(func7 == 7'b0100000) begin
                                adder_op = 3'b111; // sub
                            end
                        end
                        3'b111: begin
                            alu_op = 1; // and
                            use_alu = 1'b1;
                        end
                        3'b110: begin
                            alu_op = 2; // or
                            use_alu = 1'b1;
                        end
                        3'b100: begin
                            alu_op = 3; // xor
                            use_alu = 1'b1;
                        end
                        3'b001: begin
                            shifter_op = 1; // sll
                            use_shifter = 1'b1;
                        end
                        3'b101: begin
                            use_shifter = 1'b1;
                            if(func7 == 7'b0000000) begin
                                shifter_op = 2; // srl
                            end
                            else if(func7 == 7'b0100000) begin
                                shifter_op = 3; // sra
                            end
                        end
                    endcase
                end
            end

        // ----- I-Type ----- //
            7'b0010011: begin
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                imm = {{20{instr[31]}}, instr[31:20]};
                case(func3)
                    3'b000: begin
                        adder_op = 3'b000; // addi
                        use_addr = 1'b1;
                    end
                    3'b111: begin
                        alu_op = 1; // andi
                        use_alu = 1'b1;
                    end
                    3'b110: begin
                        alu_op = 2; // ori
                        use_alu = 1'b1;
                    end
                    3'b100: begin
                        alu_op = 3; // xori
                        use_alu = 1'b1;
                    end
                    3'b001: begin
                        shifter_op = 1; // slli
                        use_shifter = 1'b1;
                    end
                    3'b101: begin
                        if(func7 == 7'b0000000) begin
                            shifter_op = 2; // srli
                            use_shifter = 1'b1;
                        end
                        else if(func7 == 7'b0100000) begin
                            shifter_op = 3; // srai
                            use_shifter = 1'b1;
                        end
                    end
                endcase
            end
            7'b0000011: begin
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                imm = {{20{instr[31]}}, instr[31:20]};
                case (func3)
                    3'b000: lb;
                    3'b001: lh;
                    3'b010: lw;
                    3'b100: lbu;
                    3'b101: lhu;
                endcase
            end
            7'b1100111: begin // jalr
                sel_rs1 = 1'b1;
                sel_imm = 1'b1;
                sel_rd  = 1'b1;
                is_jalr = 1'b1;
                imm = {{20{instr[31]}}, instr[31:20]};
            end

        // ----- S-Type ----- //
            7'b0100011: begin
                sel_rs1 = 1'b1;
                sel_rs2 = 1'b1;
                sel_imm = 1'b1;
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                case(func3)
                    3'b000: sel_mem = 2'b00; // sb
                    3'b001: sel_mem = 2'b01; // sh
                    3'b010: sel_mem = 2'b10; // sw
                endcase
            end

        // ----- B-Type ----- //
            7'b1100011: begin
                sel_rs1 = 1'b1;
                sel_rs2 = 1'b1;
                is_cd_jp = 1'b1;
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
                use_addr = 1'b1;
                case(func3)
                    3'b000: adder_op = 3'b011; // beq
                    3'b001: adder_op = 3'b100; // bne
                    3'b100: adder_op = 3'b001; // blt
                    3'b101: adder_op = 3'b010; // bge
                    3'b110: adder_op = 3'b101; // bltu
                    3'b111: adder_op = 3'b110; // bgeu
                endcase
            end

        // ----- J-Type ----- //
            7'b1101111: begin //jal
                sel_rd = 1'b1;
                is_jal = 1'b1;
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end

        // ----- U-type ----- //
            7'b0110111: begin  // lui
                sel_rd = 1'b1;
                imm = {instr[31:12], 12'b0};
            end

            7'b0010111: begin  // auipc
                sel_rd = 1'b1;
                imm = {instr[31:12], 12'b0};
            end

        endcase
    end

    assign use_signal = {use_divider, use_multiplier, use_shifter, use_alu, use_adder};

endmodule
