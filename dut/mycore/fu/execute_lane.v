`timescale 1ns/1ps

// Combinational RV32I integer execution lane.
//
// OP, OP-IMM, LUI and AUIPC are marked pairable_simple and may execute in
// either lane.  RV32I control-flow instructions are also evaluated here so a
// full lane can reuse the branch/redirect helpers, but issue_control always
// serializes them in lane 0.  LOAD/STORE and RV32M are classified and expose
// operand metadata, while supported remains low because their execution is
// owned by the shared LSU and lane-0 M-extension units.
module execute_lane #(
    parameter integer XLEN = 32
)(
    input  wire                     valid,
    input  wire [31:0]              instr,
    input  wire [31:0]              pc,
    input  wire [31:0]              rs1_value,
    input  wire [31:0]              rs2_value,

    output reg  [2:0]               instr_class,
    output reg                      supported,
    output reg                      pairable_simple,
    output reg                      rs1_used,
    output reg                      rs2_used,
    output reg                      writes_rd,
    output reg  [4:0]               rd_addr,

    output reg                      result_valid,
    output reg  [31:0]              result,

    output reg                      control_valid,
    output reg                      branch_valid,
    output reg                      branch_taken,
    output reg                      redirect_valid,
    output reg  [31:0]              redirect_target
);

    localparam [2:0] CLASS_SIMPLE_INT = 3'd0;
    localparam [2:0] CLASS_MULDIV     = 3'd1;
    localparam [2:0] CLASS_LSU        = 3'd2;
    localparam [2:0] CLASS_CONTROL    = 3'd3;
    localparam [2:0] CLASS_INVALID    = 3'd4;

    localparam [6:0] OPCODE_OP       = 7'b0110011;
    localparam [6:0] OPCODE_OP_IMM   = 7'b0010011;
    localparam [6:0] OPCODE_LOAD     = 7'b0000011;
    localparam [6:0] OPCODE_STORE    = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH   = 7'b1100011;
    localparam [6:0] OPCODE_JALR     = 7'b1100111;
    localparam [6:0] OPCODE_JAL      = 7'b1101111;
    localparam [6:0] OPCODE_LUI      = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC    = 7'b0010111;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] shamt  = instr[24:20];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_b = {{20{instr[31]}}, instr[7], instr[30:25],
                         instr[11:8], 1'b0};
    wire [31:0] imm_j = {{12{instr[31]}}, instr[19:12], instr[20],
                         instr[30:21], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};

    task automatic accept_simple_result(input [31:0] value);
        begin
            instr_class = CLASS_SIMPLE_INT;
            supported = 1'b1;
            pairable_simple = 1'b1;
            writes_rd = 1'b1;
            result_valid = 1'b1;
            result = value;
        end
    endtask

    always @(*) begin
        instr_class = CLASS_INVALID;
        supported = 1'b0;
        pairable_simple = 1'b0;
        rs1_used = 1'b0;
        rs2_used = 1'b0;
        writes_rd = 1'b0;
        rd_addr = instr[11:7];

        result_valid = 1'b0;
        result = 32'b0;

        control_valid = 1'b0;
        branch_valid = 1'b0;
        branch_taken = 1'b0;
        redirect_valid = 1'b0;
        redirect_target = 32'b0;

        if (valid) begin
            case (opcode)
                OPCODE_OP: begin
                    rs1_used = 1'b1;
                    rs2_used = 1'b1;

                    if (funct7 == 7'b0000001) begin
                        // RV32M is recognized for issue classification but is
                        // executed only by the full lane's existing M units.
                        instr_class = CLASS_MULDIV;
                        writes_rd = 1'b1;
                    end
                    else if (funct7 == 7'b0000000) begin
                        case (funct3)
                            3'b000: accept_simple_result(rs1_value + rs2_value); // ADD
                            3'b001: accept_simple_result(rs1_value << rs2_value[4:0]); // SLL
                            3'b010: accept_simple_result(
                                ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0); // SLT
                            3'b011: accept_simple_result(
                                (rs1_value < rs2_value) ? 32'd1 : 32'd0); // SLTU
                            3'b100: accept_simple_result(rs1_value ^ rs2_value); // XOR
                            3'b101: accept_simple_result(rs1_value >> rs2_value[4:0]); // SRL
                            3'b110: accept_simple_result(rs1_value | rs2_value); // OR
                            3'b111: accept_simple_result(rs1_value & rs2_value); // AND
                            default: begin end
                        endcase
                    end
                    else if (funct7 == 7'b0100000) begin
                        case (funct3)
                            3'b000: accept_simple_result(rs1_value - rs2_value); // SUB
                            3'b101: accept_simple_result(
                                $signed(rs1_value) >>> rs2_value[4:0]); // SRA
                            default: begin end
                        endcase
                    end
                end

                OPCODE_OP_IMM: begin
                    rs1_used = 1'b1;
                    case (funct3)
                        3'b000: accept_simple_result(rs1_value + imm_i); // ADDI
                        3'b010: accept_simple_result(
                            ($signed(rs1_value) < $signed(imm_i)) ? 32'd1 : 32'd0); // SLTI
                        3'b011: accept_simple_result(
                            (rs1_value < imm_i) ? 32'd1 : 32'd0); // SLTIU
                        3'b100: accept_simple_result(rs1_value ^ imm_i); // XORI
                        3'b110: accept_simple_result(rs1_value | imm_i); // ORI
                        3'b111: accept_simple_result(rs1_value & imm_i); // ANDI
                        3'b001: begin
                            if (funct7 == 7'b0000000)
                                accept_simple_result(rs1_value << shamt); // SLLI
                        end
                        3'b101: begin
                            if (funct7 == 7'b0000000)
                                accept_simple_result(rs1_value >> shamt); // SRLI
                            else if (funct7 == 7'b0100000)
                                accept_simple_result($signed(rs1_value) >>> shamt); // SRAI
                        end
                        default: begin end
                    endcase
                end

                OPCODE_LUI: begin
                    accept_simple_result(imm_u);
                end

                OPCODE_AUIPC: begin
                    accept_simple_result(pc + imm_u);
                end

                OPCODE_LOAD: begin
                    // RV32I defines LB/LH/LW/LBU/LHU only.  Keep illegal
                    // funct3 encodings out of the LSU so the integrated core
                    // cannot accidentally retire a fabricated zero load.
                    case (funct3)
                        3'b000, 3'b001, 3'b010,
                        3'b100, 3'b101: begin
                            instr_class = CLASS_LSU;
                            rs1_used = 1'b1;
                            writes_rd = 1'b1;
                        end
                        default: begin end
                    endcase
                end

                OPCODE_STORE: begin
                    // RV32I defines SB/SH/SW only.  In particular, never
                    // emit a zero-strobe request for an illegal store.
                    case (funct3)
                        3'b000, 3'b001, 3'b010: begin
                            instr_class = CLASS_LSU;
                            rs1_used = 1'b1;
                            rs2_used = 1'b1;
                        end
                        default: begin end
                    endcase
                end

                OPCODE_BRANCH: begin
                    instr_class = CLASS_CONTROL;
                    rs1_used = 1'b1;
                    rs2_used = 1'b1;
                    branch_valid = 1'b1;

                    case (funct3)
                        3'b000: begin supported = 1'b1; branch_taken = (rs1_value == rs2_value); end // BEQ
                        3'b001: begin supported = 1'b1; branch_taken = (rs1_value != rs2_value); end // BNE
                        3'b100: begin supported = 1'b1; branch_taken = ($signed(rs1_value) < $signed(rs2_value)); end // BLT
                        3'b101: begin supported = 1'b1; branch_taken = ($signed(rs1_value) >= $signed(rs2_value)); end // BGE
                        3'b110: begin supported = 1'b1; branch_taken = (rs1_value < rs2_value); end // BLTU
                        3'b111: begin supported = 1'b1; branch_taken = (rs1_value >= rs2_value); end // BGEU
                        default: begin supported = 1'b0; branch_taken = 1'b0; end
                    endcase

                    control_valid = supported;
                    redirect_valid = supported && branch_taken;
                    redirect_target = pc + imm_b;
                end

                OPCODE_JAL: begin
                    instr_class = CLASS_CONTROL;
                    supported = 1'b1;
                    writes_rd = 1'b1;
                    result_valid = 1'b1;
                    result = pc + 4;
                    control_valid = 1'b1;
                    redirect_valid = 1'b1;
                    redirect_target = pc + imm_j;
                end

                OPCODE_JALR: begin
                    instr_class = CLASS_CONTROL;
                    rs1_used = 1'b1;
                    if (funct3 == 3'b000) begin
                        supported = 1'b1;
                        writes_rd = 1'b1;
                        result_valid = 1'b1;
                        result = pc + 4;
                        control_valid = 1'b1;
                        redirect_valid = 1'b1;
                        redirect_target = (rs1_value + imm_i) & 32'hffff_fffe;
                    end
                end

                default: begin
                    instr_class = CLASS_INVALID;
                end
            endcase
        end

        // Assertions live in the producing combinational process so they see
        // a settled, internally consistent output set rather than a transient
        // delta-cycle ordering between two always blocks.
        // synthesis translate_off
        if (pairable_simple &&
            (!supported || (instr_class != CLASS_SIMPLE_INT) || control_valid))
            $error("execute_lane marked a non-simple instruction pairable");
        if (redirect_valid && !control_valid)
            $error("execute_lane redirect without a valid control instruction");
        if (branch_taken && !branch_valid)
            $error("execute_lane branch_taken without branch_valid");
        if (result_valid && !writes_rd)
            $error("execute_lane result_valid without an architectural rd write");
        if ((instr_class == CLASS_MULDIV || instr_class == CLASS_LSU) &&
            pairable_simple)
            $error("execute_lane marked a serialized instruction pairable");
        // synthesis translate_on
    end

    // synthesis translate_off
    initial begin
        if (XLEN != 32)
            $fatal(1, "execute_lane currently supports XLEN=32 only");
    end
    // synthesis translate_on

endmodule
