module controller (
    input       [31:0]  current_pc,
    output      [31:0]  next_pc,
    output  reg         ifetch,
    output  reg [31:0]  pm_addr,
    input               is_cd_jp,
    input       [31:0]  imm_cd_jp,
    input               is_jal,
    input       [31:0]  imm_jal,
    input               is_jalr,
    input       [31:0]  imm_jalr,
    input               is_jp,
    input       [31:0]  jp_inst_pc
);

    reg [31:0] npc;

    always @(*) begin
        ifetch  = 1'b1;
        pm_addr = current_pc;
    end

    always @(*) begin
        if (is_cd_jp) begin
            npc = jp_inst_pc + imm_cd_jp;
        end else if (is_jalr) begin
            npc = imm_jalr;
        end else if (is_jal) begin
            npc = jp_inst_pc + imm_jal;
        end else begin
            npc = current_pc + 32'd4;
        end
    end

    assign next_pc = is_jp ? npc : (current_pc + 32'd4);

endmodule
