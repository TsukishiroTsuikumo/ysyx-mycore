module controller(
    input       [31:0]  current_pc,
    output      [31:0]  next_pc,
    output  reg         ifetch,
    output  reg [31:0]  pm_addr,

    // Control Signal
    input           is_cd_jp,
    input   [31:0]  imm_cd_jp,
    input           is_jal,
    input   [31:0]  imm_jal,
    input           is_jalr,
    input   [31:0]  imm_jalr,
    input           is_jp,
    input   [31:0]  jp_inst_pc
);

    // whether fetch instruction
    always @(*) begin
        if(issue_sig) begin
            ifetch = 1;
            pm_addr = current_pc;
        end
    end
    
    assign wire btb_hit = 1'b0;
    assign wire [32:0] btb_target = 32'b0;
    reg [31:0]  npc;
    // next pc
    always @(*) begin
        if(is_cd_jp) begin
            npc = current_pc + imm_cd_jp;
        end
        else if(is_jalr) begin
            npc = current_pc + imm_jalr;
        end
        else if(is_jal) begin
            npc = current_pc + imm_jal;
        end
        else if(btb_hit) begin
            npc = btb_target;
        end
        else begin
            npc = current_pc + 4;
        end
    end

    assign next_pc = npc;

endmodule