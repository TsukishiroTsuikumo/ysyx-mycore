module mycore (
  input         clk,
  input         reset,
  input  [31:0] pm_rd_in,
  output [31:0] pm_addr_out,
  output        ifetch,
  input  [31:0] dm_rd_in,
  output [31:0] dm_wr_out,
  output [31:0] dm_addr_out,
  output [3:0]  dm_ld,
  output [3:0]  dm_st
);

  wire [31:0] current_pc_if1;
  wire [31:0] next_pc;

  wire [31:0] imm_id1_id2;
  wire        is_jal_id1_id2;
  wire        is_jalr_id1_id2;
  wire        is_cd_jp_id1_id2;
  wire        is_jp_id2;
  wire [31:0] PC_id1_id2;

  controller u_controller (
    .current_pc(current_pc_if1),
    .next_pc(next_pc),
    .ifetch(ifetch),
    .pm_addr(pm_addr_out),
    .is_cd_jp(is_cd_jp_id1_id2),
    .imm_cd_jp(imm_id1_id2),
    .is_jal(is_jal_id1_id2),
    .imm_jal(imm_id1_id2),
    .is_jalr(is_jalr_id1_id2),
    .imm_jalr(32'b0),
    .is_jp(is_jp_id2),
    .jp_inst_pc(PC_id1_id2)
  );

  reg_PC u_pc (
    .clk(clk),
    .reset(reset),
    .pc_en(ifetch),
    .pcw(next_pc),
    .pcr(current_pc_if1)
  );

  reg [31:0] PC_if1_if2;
  always @(posedge clk) begin
    PC_if1_if2 <= current_pc_if1;
  end

  wire [31:0] instr = pm_rd_in;

  reg [31:0] instr_if2_id1;
  reg [31:0] PC_if2_id1;
  always @(posedge clk) begin
    instr_if2_id1 <= instr;
    PC_if2_id1    <= PC_if1_if2;
  end

  wire         sel_rs1_id1;
  wire  [4:0]  rs1_addr_id1;
  wire         sel_rs2_id1;
  wire  [4:0]  rs2_addr_id1;
  wire         sel_imm_id1;
  wire [31:0]  imm_id1;
  wire         sel_rd_id1;
  wire  [4:0]  rd_addr_id1;
  wire  [2:0]  adder_op_id1;
  wire  [1:0]  shifter_op_id1;
  wire  [1:0]  multiplier_op_id1;
  wire  [1:0]  divider_op_id1;
  wire  [1:0]  alu_op_id1;
  wire  [4:0]  use_signal_id1;
  wire         is_jal_id1;
  wire         is_jalr_id1;
  wire         is_cd_jp_id1;

  decoder1 u_decoder1 (
    .instr(instr_if2_id1),
    .sel_rs1(sel_rs1_id1),
    .rs1_addr(rs1_addr_id1),
    .sel_rs2(sel_rs2_id1),
    .rs2_addr(rs2_addr_id1),
    .sel_imm(sel_imm_id1),
    .imm(imm_id1),
    .rd_addr(rd_addr_id1),
    .sel_rd(sel_rd_id1),
    .adder_op(adder_op_id1),
    .shifter_op(shifter_op_id1),
    .alu_op(alu_op_id1),
    .multiplier_op(multiplier_op_id1),
    .divider_op(divider_op_id1),
    .use_signal(use_signal_id1),
    .is_jal(is_jal_id1),
    .is_jalr(is_jalr_id1),
    .is_cd_jp(is_cd_jp_id1)
  );

  reg   [4:0] rs1_addr_id1_id2;
  reg   [4:0] rs2_addr_id1_id2;
  reg   [4:0] rd_addr_id1_id2;
  reg  [31:0] imm_id1_id2_r;
  reg         sel_rs1_id1_id2;
  reg         sel_rs2_id1_id2;
  reg         sel_rd_id1_id2;
  reg         sel_imm_id1_id2;
  reg   [4:0] use_sig_id1_id2;
  reg   [2:0] adder_op_id1_id2;
  reg   [1:0] shifter_op_id1_id2;
  reg   [1:0] multiplier_op_id1_id2;
  reg   [1:0] divider_op_id1_id2;
  reg   [1:0] alu_op_id1_id2;
  reg         is_jal_id1_id2_r;
  reg         is_jalr_id1_id2_r;
  reg         is_cd_jp_id1_id2_r;
  reg  [31:0] PC_id1_id2_r;

  assign imm_id1_id2    = imm_id1_id2_r;
  assign is_jal_id1_id2 = is_jal_id1_id2_r;
  assign is_jalr_id1_id2= is_jalr_id1_id2_r;
  assign is_cd_jp_id1_id2 = is_cd_jp_id1_id2_r;
  assign PC_id1_id2     = PC_id1_id2_r;

  always @(posedge clk) begin
    rs1_addr_id1_id2      <= rs1_addr_id1;
    rs2_addr_id1_id2      <= rs2_addr_id1;
    rd_addr_id1_id2       <= rd_addr_id1;
    imm_id1_id2_r         <= imm_id1;
    sel_rs1_id1_id2       <= sel_rs1_id1;
    sel_rs2_id1_id2       <= sel_rs2_id1;
    sel_rd_id1_id2        <= sel_rd_id1;
    sel_imm_id1_id2       <= sel_imm_id1;
    use_sig_id1_id2       <= use_signal_id1;
    adder_op_id1_id2      <= adder_op_id1;
    shifter_op_id1_id2    <= shifter_op_id1;
    alu_op_id1_id2        <= alu_op_id1;
    multiplier_op_id1_id2 <= multiplier_op_id1;
    divider_op_id1_id2    <= divider_op_id1;
    is_jal_id1_id2_r      <= is_jal_id1;
    is_jalr_id1_id2_r     <= is_jalr_id1;
    is_cd_jp_id1_id2_r    <= is_cd_jp_id1;
    PC_id1_id2_r          <= PC_if2_id1;
  end

  assign is_jp_id2 = is_jal_id1_id2_r | is_jalr_id1_id2_r | is_cd_jp_id1_id2_r;

  wire   [4:0]  rs1_rename_addr;
  wire   [4:0]  rs2_rename_addr;
  wire   [4:0]  rd_rename_addr;
  wire  [31:0]  w1_in;
  wire          w1_en_wb;
  wire   [4:0]  w1_addr_wb;
  wire  [31:0]  rd_in_wb;
  wire   [4:0]  rd_addr_wb;

  rename u_rename (
    .rs1_addr(rs1_addr_id1_id2),
    .rs2_addr(rs2_addr_id1_id2),
    .rd_addr(rd_addr_id1_id2),
    .rs1_rename_addr(rs1_rename_addr),
    .rs2_rename_addr(rs2_rename_addr),
    .rd_rename_addr(rd_rename_addr),
    .rd_value_wb(rd_in_wb),
    .rd_addr_in_wb(rd_addr_wb),
    .w1_value(w1_in),
    .w1_en(w1_en_wb),
    .w1_addr(w1_addr_wb)
  );

  wire [31:0] r1_out;
  wire [31:0] r2_out;
  reg_R u_regfile (
    .clk(clk),
    .reset(reset),
    .r1_addr(rs1_rename_addr),
    .r1_out(r1_out),
    .r2_addr(rs2_rename_addr),
    .r2_out(r2_out),
    .w1_en(w1_en_wb),
    .w1_addr(w1_addr_wb),
    .w1_in(w1_in)
  );

  reg  [31:0] imm_id2_ex1;
  reg         sel_rs1_id2_ex1;
  reg         sel_rs2_id2_ex1;
  reg         sel_rd_id2_ex1;
  reg         sel_imm_id2_ex1;
  reg   [4:0] use_sig_id2_ex1;
  reg   [2:0] adder_op_id2_ex1;
  reg   [1:0] shifter_op_id2_ex1;
  reg   [1:0] multiplier_op_id2_ex1;
  reg   [1:0] divider_op_id2_ex1;
  reg   [1:0] alu_op_id2_ex1;
  reg         is_jal_id2_ex1;
  reg         is_jalr_id2_ex1;
  reg         is_cd_jp_id2_ex1;
  reg   [4:0] rd_addr_id2_ex1;

  always @(posedge clk) begin
    imm_id2_ex1           <= imm_id1_id2_r;
    sel_rs1_id2_ex1       <= sel_rs1_id1_id2;
    sel_rs2_id2_ex1       <= sel_rs2_id1_id2;
    sel_rd_id2_ex1        <= sel_rd_id1_id2;
    sel_imm_id2_ex1       <= sel_imm_id1_id2;
    use_sig_id2_ex1       <= use_sig_id1_id2;
    adder_op_id2_ex1      <= adder_op_id1_id2;
    shifter_op_id2_ex1    <= shifter_op_id1_id2;
    alu_op_id2_ex1        <= alu_op_id1_id2;
    multiplier_op_id2_ex1 <= multiplier_op_id1_id2;
    divider_op_id2_ex1    <= divider_op_id1_id2;
    is_jal_id2_ex1        <= is_jal_id1_id2_r;
    is_jalr_id2_ex1       <= is_jalr_id1_id2_r;
    is_cd_jp_id2_ex1      <= is_cd_jp_id1_id2_r;
    rd_addr_id2_ex1       <= rd_rename_addr;
  end

  wire [31:0] rs1 = r1_out;
  wire [31:0] rs2 = sel_imm_id2_ex1 ? imm_id2_ex1 : r2_out;

  wire use_divider = use_sig_id2_ex1[4];
  wire use_multiplier = use_sig_id2_ex1[3];
  wire use_shifter = use_sig_id2_ex1[2];
  wire use_alu = use_sig_id2_ex1[1];
  wire use_adder = use_sig_id2_ex1[0];
  wire use_lsu = 1'b0;
  wire [2:0] lsu_op = 3'b000;

  wire [31:0] aluC;
  wire [31:0] addC;
  wire [31:0] shfC;
  wire [31:0] lsuC;

  alu u_alu (
    .is_used(use_alu),
    .opcode(alu_op_id2_ex1),
    .aluA(rs1),
    .aluB(rs2),
    .aluC(aluC)
  );

  wire branch_cd_unused;
  adder u_adder (
    .is_used(use_adder),
    .opcode(adder_op_id2_ex1),
    .addA(rs1),
    .addB(rs2),
    .addC(addC),
    .branch_cd(branch_cd_unused)
  );

  shifter u_shifter (
    .is_used(use_shifter),
    .opcode(shifter_op_id2_ex1),
    .shfA(rs1),
    .shfB(rs2),
    .shfC(shfC)
  );

  wire [31:0] dm_addr_ex;
  wire [3:0]  dm_ld_ex;
  wire [3:0]  dm_st_ex;
  lsu u_lsu (
    .is_used(use_lsu),
    .opcode(lsu_op),
    .lsuA(rs1),
    .lsuB(rs2),
    .addr_imm(imm_id2_ex1),
    .dm_addr(dm_addr_ex),
    .dm_out(lsuC),
    .is_ld(dm_ld_ex),
    .is_st(dm_st_ex)
  );

  reg [31:0] pipe_ex_mem;
  reg [31:0] dm_addr_ex_mem;
  reg [3:0]  dm_ld_ex_mem;
  reg [3:0]  dm_st_ex_mem;
  reg [4:0]  rd_addr_ex_mem;

  always @(posedge clk) begin
    if (use_alu) begin
      pipe_ex_mem <= aluC;
    end else if (use_adder) begin
      pipe_ex_mem <= addC;
    end else if (use_shifter) begin
      pipe_ex_mem <= shfC;
    end else if (use_lsu) begin
      pipe_ex_mem <= lsuC;
    end else begin
      pipe_ex_mem <= 32'b0;
    end
    dm_addr_ex_mem <= dm_addr_ex;
    dm_ld_ex_mem   <= dm_ld_ex;
    dm_st_ex_mem   <= dm_st_ex;
    rd_addr_ex_mem <= rd_addr_id2_ex1;
  end

  assign dm_ld       = dm_ld_ex_mem;
  assign dm_st       = dm_st_ex_mem;
  assign dm_addr_out = dm_addr_ex_mem;
  assign dm_wr_out   = pipe_ex_mem;

  reg [31:0] pipe_mem_wb;
  reg [4:0]  rd_addr_mem_wb;

  always @(posedge clk) begin
    pipe_mem_wb   <= pipe_ex_mem;
    rd_addr_mem_wb <= rd_addr_ex_mem;
  end

  assign rd_in_wb  = (dm_ld_ex_mem != 4'b0) ? dm_rd_in : pipe_mem_wb;
  assign rd_addr_wb = rd_addr_mem_wb;

endmodule
