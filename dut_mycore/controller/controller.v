module controller(
    input       [31:0]  current_pc,
    output      [31:0]  next_pc,

    input               valid,
    output  reg         pm_req_valid,
    output  reg [31:0]  pm_req_addr,
    input               pm_req_ready,
    input               pm_resp_valid,

    // Control Signal
    input               is_cd_jp,
    input       [31:0]  cd_jp_imm,
    input               is_jal,
    input       [31:0]  jal_pc,
    input       [31:0]  jal_imm,
    input               is_jalr,
    input       [31:0]  jalr_trgt,
    input       [31:0]  jp_inst_pc,
    output  reg  [4:0]  flush_sig
);

    always @(*) begin
        pm_req_valid = valid;
        pm_req_addr = current_pc;
    end
    
    wire btb_hit;
    wire [31:0] npc_cd;
    wire [31:0] btb_target;
    wire [31:0] npc_jal;
    wire [31:0] npc_4;
    assign npc_cd = jp_inst_pc + cd_jp_imm;
    assign npc_jal = jal_pc + jal_imm;
    assign npc_4 = current_pc + 4;
    assign btb_hit = 1'b0;
    assign btb_target = 32'b0;
    // next pc
    reg [31:0] npc;
    always @(*) begin
        flush_sig = 5'b00000;
        if(is_cd_jp) begin
            npc = npc_cd;
            flush_sig = 5'b00111;
        end
        else if(is_jalr) begin
            npc = jalr_trgt & ~1;
            flush_sig = 5'b00111;
        end
        else if(is_jal) begin
            npc = npc_jal;
            flush_sig = 5'b00011;
        end
        else if(btb_hit) begin
            npc = btb_target;
            flush_sig = 5'b00000;
        end
        else begin
            npc = npc_4;
            flush_sig = 5'b00000;
        end
    end

    assign next_pc = npc;

endmodule
