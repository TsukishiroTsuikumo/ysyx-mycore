module controller(
    input       [31:0]  current_pc,
    output      [31:0]  next_pc,
    output  reg         ifetch,
    output  reg [31:0]  pm_addr,

    // Control Signal
    input               is_cd_jp,
    input       [31:0]  cd_jp_imm,
    input               is_jal,
    input       [31:0]  jal_imm,
    input               is_jalr,
    input       [31:0]  jalr_trgt,
    input       [31:0]  jp_inst_pc,
    output  reg  [3:0]  flush_sig
);

    // whether fetch instruction
    wire issue_sig = 1'b1;
    always @(*) begin
        if(issue_sig) begin
            ifetch = 1;
            pm_addr = current_pc;
        end
    end
    
    wire btb_hit;
    wire [31:0] npc_cd;
    wire [31:0] btb_target;
    wire [31:0] npc_jal;
    wire [31:0] npc_4;
    assign npc_cd = jp_inst_pc + cd_jp_imm;
    assign npc_jal = current_pc + jal_imm - 4;
    assign npc_4 = current_pc + 4;
    assign btb_hit = 1'b0;
    assign btb_target = 32'b0;
    // next pc
    reg [31:0] npc;
    assign flush_sig = 4'b0000;
    always @(*) begin
        if(is_cd_jp) begin
            npc = npc_cd;
            flush_sig = 4'b0011;
        end
        else if(is_jalr) begin
            npc = jalr_trgt;
            flush_sig = 4'b0011;
        end
        else if(is_jal) begin
            npc = npc_jal;
            flush_sig = 4'b0001;
        end
        else if(btb_hit) begin
            npc = btb_target;
            flush_sig = 4'b0000;
        end
        else begin
            npc = npc_4;
            flush_sig = 4'b0000;
        end
    end

    assign next_pc = npc;

endmodule
