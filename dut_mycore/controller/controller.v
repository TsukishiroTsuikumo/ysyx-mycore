module controller(
    input       [31:0]  current_pc,
    output      [31:0]  next_pc,
    output  reg         ifetch,
    output  reg [31:0]  pm_addr,

    // Control Signal
    input           is_cd_jp,
    input   [31:0]  cd_jp_imm,
    input           is_jal,
    input   [31:0]  jal_imm,
    input           is_jalr,
    input   [31:0]  jalr_trgt,
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
    
    wire btb_hit;
    wire [31:0] btb_target;
    wire [31:0] npc_jal;
    wire [31:0] npc_4;
    assign npc1 = current_pc + cd_jp_imm;
    assign npc_jal = current_pc + jal_imm;
    assign npc_4 = current_pc + 4;
    assign btb_hit = 1'b0;
    assign btb_target = 32'b0;
    // next pc
    reg [31:0] npc;
    always @(*) begin
        if(is_cd_jp) begin
            npc = npc1;
        end
        else if(is_jalr) begin
            npc = jalr_trgt;
        end
        else if(is_jal) begin
            npc = npc_jal;
        end
        else if(btb_hit) begin
            npc = btb_target;
        end
        else begin
            npc = npc_4;
        end
    end

    assign next_pc = npc;

endmodule
