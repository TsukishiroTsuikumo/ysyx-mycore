`timescale 1ns/1ps

// Decode metadata shared by the rename and execution stages of ooo_core.
// Unsupported encodings are deliberately classified as invalid; the
// experimental core retires them as inert instructions because it has no
// architectural exception/CSR subsystem.
module ooo_decode (
    input  logic [31:0] instr,

    output logic        supported,
    output logic [2:0]  op_class,
    output logic        rs1_used,
    output logic        rs2_used,
    output logic        writes_rd,
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic [4:0]  rd_addr
);

    localparam logic [2:0] CLASS_ALU     = 3'd0;
    localparam logic [2:0] CLASS_MULDIV  = 3'd1;
    localparam logic [2:0] CLASS_LOAD    = 3'd2;
    localparam logic [2:0] CLASS_STORE   = 3'd3;
    localparam logic [2:0] CLASS_CONTROL = 3'd4;
    localparam logic [2:0] CLASS_INVALID = 3'd5;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    always_comb begin
        opcode = instr[6:0];
        funct3 = instr[14:12];
        funct7 = instr[31:25];

        supported = 1'b0;
        op_class = CLASS_INVALID;
        rs1_used = 1'b0;
        rs2_used = 1'b0;
        writes_rd = 1'b0;
        rs1_addr = instr[19:15];
        rs2_addr = instr[24:20];
        rd_addr = instr[11:7];

        unique case (opcode)
            7'b0110011: begin // OP and RV32M
                rs1_used = 1'b1;
                rs2_used = 1'b1;
                writes_rd = 1'b1;
                if (funct7 == 7'b0000001) begin
                    supported = 1'b1;
                    op_class = CLASS_MULDIV;
                end
                else if (funct7 == 7'b0000000) begin
                    supported = 1'b1;
                    op_class = CLASS_ALU;
                end
                else if ((funct7 == 7'b0100000) &&
                         ((funct3 == 3'b000) || (funct3 == 3'b101))) begin
                    supported = 1'b1;
                    op_class = CLASS_ALU;
                end
            end

            7'b0010011: begin // OP-IMM
                rs1_used = 1'b1;
                writes_rd = 1'b1;
                op_class = CLASS_ALU;
                unique case (funct3)
                    3'b001: supported = (funct7 == 7'b0000000);
                    3'b101: supported = (funct7 == 7'b0000000) ||
                                            (funct7 == 7'b0100000);
                    default: supported = 1'b1;
                endcase
            end

            7'b0110111,       // LUI
            7'b0010111: begin // AUIPC
                supported = 1'b1;
                op_class = CLASS_ALU;
                writes_rd = 1'b1;
            end

            7'b0000011: begin // LOAD
                rs1_used = 1'b1;
                writes_rd = 1'b1;
                op_class = CLASS_LOAD;
                unique case (funct3)
                    3'b000, 3'b001, 3'b010,
                    3'b100, 3'b101: supported = 1'b1;
                    default: supported = 1'b0;
                endcase
            end

            7'b0100011: begin // STORE
                rs1_used = 1'b1;
                rs2_used = 1'b1;
                op_class = CLASS_STORE;
                unique case (funct3)
                    3'b000, 3'b001, 3'b010: supported = 1'b1;
                    default: supported = 1'b0;
                endcase
            end

            7'b1100011: begin // conditional branch
                rs1_used = 1'b1;
                rs2_used = 1'b1;
                op_class = CLASS_CONTROL;
                unique case (funct3)
                    3'b000, 3'b001, 3'b100, 3'b101,
                    3'b110, 3'b111: supported = 1'b1;
                    default: supported = 1'b0;
                endcase
            end

            7'b1100111: begin // JALR
                rs1_used = 1'b1;
                writes_rd = 1'b1;
                op_class = CLASS_CONTROL;
                supported = (funct3 == 3'b000);
            end

            7'b1101111: begin // JAL
                writes_rd = 1'b1;
                op_class = CLASS_CONTROL;
                supported = 1'b1;
            end

            default: begin end
        endcase

        // Invalid instructions and x0 never allocate a physical destination.
        if (!supported || (rd_addr == 5'd0))
            writes_rd = 1'b0;
    end

endmodule
