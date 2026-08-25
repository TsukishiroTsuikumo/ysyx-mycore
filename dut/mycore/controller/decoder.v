`timescale 1ns/1ps

module decoder (
    input      [31:0] instr,
    output      [4:0] rs1_addr,
    output      [4:0] rs2_addr,
    output reg        rs1_used,
    output reg        rs2_used,
    output reg        sel_imm,
    output reg [31:0] imm,
    output reg        sel_rd,
    output      [4:0] rd_addr,
    output reg  [2:0] adder_op,
    output reg  [1:0] shifter_op,
    output reg  [3:0] multiplier_op,
    output reg  [3:0] divider_op,
    output reg  [1:0] alu_op,
    output reg  [2:0] lsu_op,
    output reg  [1:0] imu_op,
    output      [6:0] use_signal,
    output reg  [2:0] instr_class,
    output reg        supported,
    output reg        is_branch,
    output reg        is_jal,
    output reg        is_jalr
);

    localparam [2:0] CLASS_SIMPLE_INT = 3'd0;
    localparam [2:0] CLASS_MULDIV     = 3'd1;
    localparam [2:0] CLASS_LSU        = 3'd2;
    localparam [2:0] CLASS_CONTROL    = 3'd3;
    localparam [2:0] CLASS_INVALID    = 3'd4;

    wire [6:0] funct7;
    wire [2:0] funct3;
    wire [6:0] opcode;
    reg use_adder;
    reg use_shifter;
    reg use_multiplier;
    reg use_divider;
    reg use_alu;
    reg use_lsu;
    reg use_imu;

    assign funct7 = instr[31:25];
    assign funct3 = instr[14:12];
    assign opcode = instr[6:0];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd_addr = instr[11:7];
    assign use_signal = {use_imu, use_lsu, use_divider,
                         use_multiplier, use_shifter, use_alu, use_adder};

    always @(*) begin
        rs1_used = 1'b0;
        rs2_used = 1'b0;
        sel_imm = 1'b0;
        imm = 32'b0;
        sel_rd = 1'b0;
        adder_op = 3'b000;
        shifter_op = 2'b00;
        multiplier_op = 4'b0000;
        divider_op = 4'b0000;
        alu_op = 2'b00;
        lsu_op = 3'b000;
        imu_op = 2'b00;
        use_adder = 1'b0;
        use_shifter = 1'b0;
        use_multiplier = 1'b0;
        use_divider = 1'b0;
        use_alu = 1'b0;
        use_lsu = 1'b0;
        use_imu = 1'b0;
        instr_class = CLASS_INVALID;
        supported = 1'b0;
        is_branch = 1'b0;
        is_jal = 1'b0;
        is_jalr = 1'b0;

        case (opcode)
            7'b0110011: begin
                rs1_used = 1'b1;
                rs2_used = 1'b1;
                if (funct7 == 7'b0000001) begin
                    instr_class = CLASS_MULDIV;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    case (funct3)
                        3'b000: begin use_multiplier = 1'b1; multiplier_op = 4'b0001; end
                        3'b001: begin use_multiplier = 1'b1; multiplier_op = 4'b0010; end
                        3'b010: begin use_multiplier = 1'b1; multiplier_op = 4'b0100; end
                        3'b011: begin use_multiplier = 1'b1; multiplier_op = 4'b1000; end
                        3'b100: begin use_divider = 1'b1; divider_op = 4'b0001; end
                        3'b101: begin use_divider = 1'b1; divider_op = 4'b0010; end
                        3'b110: begin use_divider = 1'b1; divider_op = 4'b0100; end
                        3'b111: begin use_divider = 1'b1; divider_op = 4'b1000; end
                    endcase
                end
                else if (funct7 == 7'b0000000) begin
                    instr_class = CLASS_SIMPLE_INT;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    case (funct3)
                        3'b000: begin use_adder = 1'b1; adder_op = 3'b000; end
                        3'b001: begin use_shifter = 1'b1; shifter_op = 2'b01; end
                        3'b010: begin use_adder = 1'b1; adder_op = 3'b001; end
                        3'b011: begin use_adder = 1'b1; adder_op = 3'b101; end
                        3'b100: begin use_alu = 1'b1; alu_op = 2'b11; end
                        3'b101: begin use_shifter = 1'b1; shifter_op = 2'b10; end
                        3'b110: begin use_alu = 1'b1; alu_op = 2'b01; end
                        3'b111: begin use_alu = 1'b1; alu_op = 2'b10; end
                    endcase
                end
                else if ((funct7 == 7'b0100000) &&
                         ((funct3 == 3'b000) || (funct3 == 3'b101))) begin
                    instr_class = CLASS_SIMPLE_INT;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    if (funct3 == 3'b000) begin
                        use_adder = 1'b1;
                        adder_op = 3'b111;
                    end
                    else begin
                        use_shifter = 1'b1;
                        shifter_op = 2'b11;
                    end
                end
            end

            7'b0010011: begin
                rs1_used = 1'b1;
                sel_imm = 1'b1;
                imm = {{20{instr[31]}}, instr[31:20]};
                if ((funct3 != 3'b001) && (funct3 != 3'b101)) begin
                    instr_class = CLASS_SIMPLE_INT;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    case (funct3)
                        3'b000: begin use_adder = 1'b1; adder_op = 3'b000; end
                        3'b010: begin use_adder = 1'b1; adder_op = 3'b001; end
                        3'b011: begin use_adder = 1'b1; adder_op = 3'b101; end
                        3'b100: begin use_alu = 1'b1; alu_op = 2'b11; end
                        3'b110: begin use_alu = 1'b1; alu_op = 2'b01; end
                        3'b111: begin use_alu = 1'b1; alu_op = 2'b10; end
                    endcase
                end
                else if ((funct3 == 3'b001) && (funct7 == 7'b0000000)) begin
                    instr_class = CLASS_SIMPLE_INT;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    use_shifter = 1'b1;
                    shifter_op = 2'b01;
                end
                else if ((funct3 == 3'b101) &&
                         ((funct7 == 7'b0000000) ||
                          (funct7 == 7'b0100000))) begin
                    instr_class = CLASS_SIMPLE_INT;
                    supported = 1'b1;
                    sel_rd = 1'b1;
                    use_shifter = 1'b1;
                    if (funct7 == 7'b0000000)
                        shifter_op = 2'b10;
                    else
                        shifter_op = 2'b11;
                end
            end

            7'b0000011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b010, 3'b100, 3'b101: begin
                        instr_class = CLASS_LSU;
                        supported = 1'b1;
                        rs1_used = 1'b1;
                        sel_imm = 1'b1;
                        sel_rd = 1'b1;
                        imm = {{20{instr[31]}}, instr[31:20]};
                        use_lsu = 1'b1;
                        case (funct3)
                            3'b000: lsu_op = 3'b000;
                            3'b001: lsu_op = 3'b001;
                            3'b010: lsu_op = 3'b010;
                            3'b100: lsu_op = 3'b011;
                            3'b101: lsu_op = 3'b100;
                            default: lsu_op = 3'b000;
                        endcase
                    end
                    default: begin end
                endcase
            end

            7'b0100011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b010: begin
                        instr_class = CLASS_LSU;
                        supported = 1'b1;
                        rs1_used = 1'b1;
                        rs2_used = 1'b1;
                        sel_imm = 1'b1;
                        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                        use_lsu = 1'b1;
                        case (funct3)
                            3'b000: lsu_op = 3'b101;
                            3'b001: lsu_op = 3'b110;
                            3'b010: lsu_op = 3'b111;
                            default: lsu_op = 3'b101;
                        endcase
                    end
                    default: begin end
                endcase
            end

            7'b1100011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111: begin
                        instr_class = CLASS_CONTROL;
                        supported = 1'b1;
                        rs1_used = 1'b1;
                        rs2_used = 1'b1;
                        imm = {{20{instr[31]}}, instr[7], instr[30:25],
                               instr[11:8], 1'b0};
                        use_adder = 1'b1;
                        is_branch = 1'b1;
                        case (funct3)
                            3'b000: adder_op = 3'b011;
                            3'b001: adder_op = 3'b100;
                            3'b100: adder_op = 3'b001;
                            3'b101: adder_op = 3'b010;
                            3'b110: adder_op = 3'b101;
                            3'b111: adder_op = 3'b110;
                            default: adder_op = 3'b011;
                        endcase
                    end
                    default: begin end
                endcase
            end

            7'b1101111: begin
                instr_class = CLASS_CONTROL;
                supported = 1'b1;
                sel_rd = 1'b1;
                imm = {{12{instr[31]}}, instr[19:12], instr[20],
                       instr[30:21], 1'b0};
                is_jal = 1'b1;
            end

            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    instr_class = CLASS_CONTROL;
                    supported = 1'b1;
                    rs1_used = 1'b1;
                    sel_imm = 1'b1;
                    sel_rd = 1'b1;
                    imm = {{20{instr[31]}}, instr[31:20]};
                    use_adder = 1'b1;
                    adder_op = 3'b000;
                    is_jalr = 1'b1;
                end
            end

            7'b0110111: begin
                instr_class = CLASS_SIMPLE_INT;
                supported = 1'b1;
                sel_rd = 1'b1;
                imm = {instr[31:12], 12'b0};
                use_imu = 1'b1;
                imu_op = 2'b01;
            end

            7'b0010111: begin
                instr_class = CLASS_SIMPLE_INT;
                supported = 1'b1;
                sel_rd = 1'b1;
                imm = {instr[31:12], 12'b0};
                use_imu = 1'b1;
                imu_op = 2'b10;
            end

            7'b0001111: begin
                if (funct3 == 3'b000) begin
                    instr_class = CLASS_CONTROL;
                    supported = 1'b1;
                end
            end

            default: begin end
        endcase
    end

endmodule
