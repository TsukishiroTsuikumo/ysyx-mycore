module mycore (
  input			      clk,
  input			      reset,
  input	  [31:0]  pm_rd_in,
  output  [31:0]  pm_addr_out,
  output		      ifetch, // fetach instruction enable signal
  input	  [31:0]  dm_rd_in,
  output  [31:0]  dm_wr_out,
  output  [31:0]  dm_addr_out,
  output	 [3:0]  dm_ld, // load enable signal
  output	 [3:0]  dm_st, // store enable signal
);

  // ------------------------------------------- //
  // -- Pipe IF1: Generate PC, Predict Branch -- //
  // ------------------------------------------- //

  wire [31:0] current_pc_if1;
  wire [31:0] next_pc;

  controller controller(
    .current_pc(current_pc_if1),
    .next_pc(next_pc),
    .ifetch(ifetch),
    .pm_addr(pm_addr_out),
    .is_cd_jp(is_cd_jp),
    .imm_cd_jp(imm),
    .is_jal(is_jal),
    .imm_jal(imm_id1_id2),
    .isjalr(is_jalr),
    .imm_jalr(imm_jalr),
    .is_jp(is_jp_id2),
    .jp_inst_pc(PC_id1_id2)
  );
  
  // ------------------------------------------- //
  // --------------- IF1 to IF2 ---------------- //
  // ------------------------------------------- //

  reg_PC PC(
    .clk(clk),
    .reset(reset),
    .pc_en(ifetch), // from controller
    .pcw(next_pc), // from controller
    .pcr(current_pc_if1) // to controller
  );

  reg [31:0] PC_if1_if2;

  always @(posedge clk) begin
    PC_if1_if2 <= current_pc;
  end

  // --------------------------------------------- //
  // ------- Pipe2 IF2: Fetch Instruction -------- //
  // --------------------------------------------- //

  wire [31:0] instr = pm_rd_in; // from pm
  

  // --------------------------------------------- //
  // ---------------- IF2 to ID1 ----------------- //
  // --------------------------------------------- //

  reg [31:0] instr_if2_id1;
  reg [31:0] PC_if2_id1;

  always @(posedge clk) begin
    instr_if2_id1 <= instr;
    PC_if2_id1 <= PC_if1_if2;
  end

  // --------------------------------------------- //
  // ------- Pipe3 ID1: Decode Instruction ------- //
  // --------------------------------------------- //

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

  decoder1 .decoder1 (
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

  // --------------------------------------------- //
  // --------------- ID1 to ID2 ------------------ //
  // --------------------------------------------- //

  reg   [4:0] rs1_addr_id1_id2;
  reg   [4:0] rs2_addr_id1_id2;
  reg   [4:0] rd_addr_id1_id2;
  reg  [31:0] imm_id1_id2;
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
  reg         is_jal_id1_id2;
  reg         is_jalr_id1_id2;
  reg         is_cd_jp_id1_id2;
  reg  [31:0] PC_id1_id2;

  always @(posedge clk) begin
    rs1_addr_id1_id2      <= rs1_addr_id1;
    rs2_addr_id1_id2      <= rs2_addr_id1;
    rd_addr_id1_id2       <= rd_addr_id1;
    imm_id1_id2           <= imm_id1;
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
    is_jal_id1_id2        <= is_jal_id1;
    is_jalr_id1_id2       <= is_jalr_id1;
    is_cd_jp_id1_id2      <= is_cd_jp_id1;
    PC_id1_id2            <= pc_id1;
  end

  // --------------------------------------------- //
  // ------- Pipe4 ID2: Register Renaming -------- //
  // --------------------------------------------- //

  assign wire is_jp_id2 = is_jal_id1_id2 | is_jalr_id1_id2 | is_cd_jp_id1_id2;

  wire   [4:0]  rs1_rename_addr;
  wire   [4:0]  rs2_rename_addr;
  wire   [4:0]  rd_rename_addr;
  wire  [31:0]  w1_in;
  wire          w1_en_wb;
  wire   [4:0]  w1_addr_wb;

  rename rename(
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

  // --------------------------------------------- //
  // ---------------- ID2 to ID3 ----------------- //
  // --------------------------------------------- //

  wire [32:0] r1_out;
  wire [32:0] r2_out;

  reg_R regfile(
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

  always @(posedge clk) begin
    imm_id2_ex1           <= imm_id1_id2;
    sel_rs1_id2_ex1       <= sel_rs1_id1_id2;
    sel_rs2_id2_ex1       <= sel_rs2_id1_id2;
    sel_rd_id2_ex1        <= sel_rd_id1_id2;
    sel_imm_id2_ex1       <= sel_imm_id1_id2;
    use_sig_id2_ex1       <= use_signal_id1_id2;
    adder_op_id2_ex1      <= adder_op_id1_id2;
    shifter_op_id2_ex1    <= shifter_op_id1_id2;
    alu_op_id2_ex1        <= alu_op_id1_id2;
    multiplier_op_id2_ex1 <= multiplier_op_id1_id2;
    divider_op_id2_ex1    <= divider_op_id1_id2;
    is_jal_id2_ex1        <= is_jal_id1_id2;
    is_jalr_id2_ex1       <= is_jalr_id1_id2;
    is_cd_jp_id2_ex1      <= is_cd_jp_id1_id2;
  end

  // --------------------------------------------- //
  // ------- Pipe5 ID3: Issue Instruction -------- //
  // --------------------------------------------- //


  // --------------------------------------------- //
  // ---------------- ID3 to EX ------------------ //
  // --------------------------------------------- //

  // --------------------------------------------- //
  // ------- Pipe6 EX: Execute Instruction ------- //
  // --------------------------------------------- //


  assign wire [31:0] rs1 = r1_out;
  assign wire [31:0] rs2 = sel_imm ? imm : r2_out;

  wire [31:0] aluC;
  wire [31:0] addC;
  wire [31:0] shfC;
  wire [31:0] lsuC;
  wire [31:0] out;

  alu alu_1(
    .is_used(use_alu),
    .opcode(alu_op),
    .aluA(rs1),
    .aluB(rs2),
    .aluC(aluC)
  );

  adder adder_1(
    .is_used(use_adder),
    .opcode(adder_op),
    .addA(rs1),
    .addB(rs2),
    .addC(addC),
    .branch_cd(is_cd_jp)
  );

  shifter shifter_1(
    .is_used(use_shifter),
    .opcode(shifter_op),
    .shfA(rs1),
    .shfB(rs2),
    .shfC(shfC)
  );

  wire [31:0] dm_out_ex;
  wire [31:0] dm_addr_ex;
  wire [3:0] dm_ld_ex;
  wire [3:0] dm_st_ex;
  lsu lsu_1(
    .is_used(use_lsu),
    .opcode(lsu_op),
    .lsuA(rs1),
    .lsuB(rs2),
    .addr_imm(imm),
    .dm_addr(dm_addr_ex),
    .dm_out(lsuC),
    .is_ld(dm_ld_ex),
    .is_st(dm_st_ex)
  );

  // ----------------------------------------------- //
  // ----------------- EX to MEM ------------------- //
  // ----------------------------------------------- //

  reg [31:0] pipe_ex_mem;
  reg [31:0] dm_addr_ex_mem;
  reg [3:0] dm_ld_ex_mem;
  reg [3:0] dm_st_ex_mem;

  always @(posedge clk) begin
    
    if(use_alu) begin
      pipe_ex_mem <= aluC;
    end
    else if(use_adder) begin
      pipe_ex_mem <= addC;
    end
    else if(use_shifter) begin
      pipe_ex_mem <= shfC;
    end
    else if(use_lsu) begin
      pipe_ex_mem <= lsuC;
    end
    else begin
      pipe_ex_mem <= 32'b0;
    end

    dm_addr_ex_mem <= dm_addr_ex;
    dm_ld_ex_mem <= dm_ld_ex;
    dm_st_ex_mem <= dm_st_ex;
  end

  // ----------------------------------------------- //
  // ------------- MEM: Memory Access -------------- //
  // ----------------------------------------------- //

  assign wire dm_ld = dm_ld_ex_mem;
  assign wire dm_st = dm_st_ex_mem;
  assign wire dm_addr_out = dm_addr_ex_mem;
  assign wire dm_wr_out = pipe_ex_mem;

  // ----------------------------------------------- //
  // ------------------ MEM to WB ------------------ //
  // ----------------------------------------------- //

  reg [31:0]  pipe_mem_wb;

  always @(posedge clk) begin
    pipe_mem_wb <= pipe_ex_mem;
    rd_addr_mem_wb <= rd_addr_ex_mem;
  end


  // ----------------------------------------------- //
  // ---- Pipe8 WB: Write back to register file ---- //
  // ----------------------------------------------- //

  wire [31:0] rd_in_wb = dm_ld_ex_mem ? dm_rd_in : pipe_mem_wb;
  wire  [4:0] rd_addr_wb = rd_addr_mem_wb;



endmodule