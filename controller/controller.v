module controller(
    input       [31:0]  new_pc,
    output  reg [31:0]  next_pc,
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
            pm_addr = new_pc;
        end
    end
    
    assign wire btb_hit = 1'b0;
    assign wire [32:0] btb_target = 32'b0;
    // next pc
    always @(*) begin
        if(is_cd_jp) begin
            next_pc = new_pc + imm_cd_jp;
        end
        else if(is_jalr) begin
            next_pc = new_pc + imm_jalr;
        end
        else if(is_jal) begin
            next_pc = new_pc + imm_jal;
        end
        else if(btb_hit) begin
            next_pc = btb_target;
        end
        else begin
            next_pc = new_pc + 4;
        end
    end

    assign next_pc = npc;

endmodule