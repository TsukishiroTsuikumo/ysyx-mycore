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
  input           ld_valid
);

  // ------------------------------------------- //
  // -- Pipe1 IF: Generate PC, Predict Branch -- //
  // ------------------------------------------- //

  wire [31:0] current_pc_if;
  wire [31:0] next_pc;

  controller controller(
    .current_pc(current_pc_if),
    .next_pc(next_pc),
    .ifetch(ifetch),
    .pm_addr(pm_addr_out),
    .is_cd_jp(is_cd_jp_ex),
    .cd_jp_imm(imm_is_ex),
    .is_jal(is_jal_id),
    .jal_imm(imm_id),
    .is_jalr(is_jalr_ex),
    .jalr_trgt(addC),
    .is_jp(is_jp_id_rn),
    .jp_inst_pc(PC_id_rn)
  );
  
  // ------------------------------------------- //
  // ---------------- IF to ID ----------------- //
  // ------------------------------------------- //

  reg_PC PC(
    .clk(clk),
    .reset(reset),
    .pc_en(ifetch), // from controller
    .pcw(next_pc), // from controller
    .pcr(current_pc_if) // to controller
  );

  reg [31:0] PC_if_id;

  always @(posedge clk) begin
    PC_if_id <= current_pc_if;
  end

  // --------------------------------------------- //
  // -------- Pipe2 ID: Decode Instruction ------- //
  // --------------------------------------------- //

  wire [31:0] instr;
  assign instr_id = pm_rd_in; // from pm

  wire         sel_rs1_id;
  wire  [4:0]  rs1_addr_id;
  wire         sel_rs2_id;
  wire  [4:0]  rs2_addr_id;
  wire         sel_imm_id;
  wire [31:0]  imm_id;
  wire         sel_rd_id;
  wire  [4:0]  rd_addr_id;
  wire  [2:0]  adder_op_id;
  wire  [1:0]  shifter_op_id;
  wire  [1:0]  multiplier_op_id;
  wire  [1:0]  divider_op_id;
  wire  [1:0]  alu_op_id;
  wire  [4:0]  use_signal_id;
  wire         is_jal_id;
  wire         is_jalr_id;
  wire         is_cd_jp_id;

  decoder1 .decoder1 (
    .instr(instr_id),

    .sel_rs1(sel_rs1_id),
    .rs1_addr(rs1_addr_id),
    .sel_rs2(sel_rs2_id),
    .rs2_addr(rs2_addr_id),
    .sel_imm(sel_imm_id),
    .imm(imm_id),
    .rd_addr(rd_addr_id),
    .sel_rd(sel_rd_id),

    .adder_op(adder_op_id),
    .shifter_op(shifter_op_id),
    .alu_op(alu_op_id),
    .multiplier_op(multiplier_op_id),
    .divider_op(divider_op_id),

    .use_signal(use_signal_id),
    .is_jal(is_jal_id),
    .is_jalr(is_jalr_id),
    .is_cd_jp(is_cd_jp_id)
    
  );

  // --------------------------------------------- //
  // ---------------- ID to RN ------------------- //
  // --------------------------------------------- //

  reg   [4:0] rs1_addr_id_rn;
  reg   [4:0] rs2_addr_id_rn;
  reg   [4:0] rd_addr_id_rn;
  reg  [31:0] imm_id_rn;
  reg         sel_rs1_id_rn;
  reg         sel_rs2_id_rn;
  reg         sel_rd_id_rn;
  reg         sel_imm_id_rn;
  reg   [4:0] use_sig_id_rn;
  reg   [2:0] adder_op_id_rn;
  reg   [1:0] shifter_op_id_rn;
  reg   [1:0] multiplier_op_id_rn;
  reg   [1:0] divider_op_id_rn;
  reg   [1:0] alu_op_id_rn;
  reg         is_jal_id_rn;
  reg         is_jalr_id_rn;
  reg         is_cd_jp_id_rn;
  reg  [31:0] PC_id_rn;

  always @(posedge clk) begin
    rs1_addr_id_rn      <= rs1_addr_id;
    rs2_addr_id_rn      <= rs2_addr_id;
    rd_addr_id_rn       <= rd_addr_id;
    imm_id_rn           <= imm_id;
    sel_rs1_id_rn       <= sel_rs1_id;
    sel_rs2_id_rn       <= sel_rs2_id;
    sel_rd_id_rn        <= sel_rd_id;
    sel_imm_id_rn       <= sel_imm_id;
    use_sig_id_rn       <= use_signal_id;
    adder_op_id_rn      <= adder_op_id;
    shifter_op_id_rn    <= shifter_op_id;
    alu_op_id_rn        <= alu_op_id;
    multiplier_op_id_rn <= multiplier_op_id;
    divider_op_id_rn    <= divider_op_id;
    is_jal_id_rn        <= is_jal_id;
    is_jalr_id_rn       <= is_jalr_id;
    is_cd_jp_id_rn      <= is_cd_jp_id;
    PC_id_rn            <= PC_if_id;
  end

  // --------------------------------------------- //
  // -------- Pipe3 RN: Register Renaming -------- //
  // --------------------------------------------- //

  assign wire is_jp_rn = is_jal_id_rn | is_jalr_id_rn | is_cd_jp_id_rn;

  wire   [4:0]  rs1_rename_addr;
  wire   [4:0]  rs2_rename_addr;
  wire   [4:0]  rd_rename_addr;
  wire  [31:0]  w1_in;
  wire          w1_en_wb;
  wire   [4:0]  w1_addr_wb;

  rename rename(
    .rs1_addr(rs1_addr_id_rn),
    .rs2_addr(rs2_addr_id_rn),
    .rd_addr(rd_addr_id_rn),
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
  // ----------------- RN to DP ------------------ //
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

  reg  [31:0] imm_rn_dp;
  reg         sel_rs1_rn_dp;
  reg         sel_rs2_rn_dp;
  reg         sel_rd_rn_dp;
  reg         sel_imm_rn_dp;
  reg   [4:0] use_sig_rn_dp;
  reg   [2:0] adder_op_rn_dp;
  reg   [1:0] shifter_op_rn_dp;
  reg   [1:0] multiplier_op_rn_dp;
  reg   [1:0] divider_op_rn_dp;
  reg   [1:0] alu_op_rn_dp;
  reg         is_jal_rn_dp;
  reg         is_jalr_rn_dp;
  reg         is_cd_jp_rn_dp;
  reg  [31:0] PC_rn_dp;
  reg [4:0] rd_addr_rn_dp;
  reg [31:0] 

  always @(posedge clk) begin
    imm_rn_dp           <= imm_id_rn;
    sel_rs1_rn_dp       <= sel_rs1_id_rn;
    sel_rs2_rn_dp       <= sel_rs2_id_rn;
    sel_rd_rn_dp        <= sel_rd_id_rn;
    sel_imm_rn_dp       <= sel_imm_id_rn;
    use_sig_rn_dp       <= use_signal_id_rn;
    adder_op_rn_dp      <= adder_op_id_rn;
    shifter_op_rn_dp    <= shifter_op_id_rn;
    alu_op_rn_dp        <= alu_op_id_rn;
    multiplier_op_rn_dp <= multiplier_op_id_rn;
    divider_op_rn_dp    <= divider_op_id_rn;
    is_jal_rn_dp        <= is_jal_id_rn;
    is_jalr_rn_dp       <= is_jalr_id_rn;
    is_cd_jp_rn_dp      <= is_cd_jp_id_rn;
    PC_rn_dp            <= PC_if_id;
  end

  // --------------------------------------------- //
  // ------ Pipe4 DP: Dispatch Instruction ------- //
  // --------------------------------------------- //


  // --------------------------------------------- //
  // ----------------- DP to IS ------------------ //
  // --------------------------------------------- //

  // --------------------------------------------- //
  // -------- Pipe5 IS: Issue Instruction -------- //
  // --------------------------------------------- //

  // --------------------------------------------- //
  // ----------------- IS to EX ------------------ //
  // --------------------------------------------- //

  // --------------------------------------------- //
  // ------- Pipe6 EX: Execute Instruction ------- //
  // --------------------------------------------- //

  wire [31:0] rs1, rs2;
  assign rs1 = is_jalr_rn_dp ? PC_rn_dp : r1_out;
  assign rs2 = sel_imm ? imm_is_ex : r2_out;

  wire [31:0] aluC;
  wire [31:0] addC;
  wire [31:0] shfC;
  wire [31:0] lsuC;
  wire [31:0] mpyC;
  wire [31:0] divC;
  wire [31:0] out;

  alu alu_1(
    .is_used(use_alu),
    .opcode(alu_op),
    .aluA(rs1),
    .aluB(rs2),
    .aluC(aluC)
  );

  wire is_cd_jp_ex;
  adder adder_1(
    .is_used(use_adder),
    .opcode(adder_op),
    .addA(rs1),
    .addB(rs2),
    .addC(addC),
    .branch_cd(is_cd_jp_ex)
  );

  shifter shifter_1(
    .is_used(use_shifter),
    .opcode(shifter_op),
    .shfA(rs1),
    .shfB(rs2),
    .shfC(shfC)
  );

  multiplier multiplier_1(
    .is_used(use_multiplier),
    .opcode(multiplier_op),
    .mpyA(rs1),
    .mpyB(rs2),
    .mpyC(mpyC)
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

  divider divider_1(
    .is_used(use_divider),
    .opcode(divider_op),
    .divA(rs1),
    .divB(rs2),
    .divC(divC)
  );

  // ----------------------------------------------- //
  // ----------------- EX to MEM ------------------- //
  // ----------------------------------------------- //

  reg [31:0] pipe_ex_mem;
  reg [31:0] dm_addr_ex_mem;
  reg  [3:0] dm_ld_ex_mem;
  reg  [3:0] dm_st_ex_mem;

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
    else if(use_divider) begin
      pipe_ex_mem <= divC;
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
  // ------- Pipe8 WB: Write back and commit ------- //
  // ----------------------------------------------- //

  assign w1_addr_wb = rd_addr_mem_wb;
  assign w1_value = ld_valid ? dm_rd_in : pipe_mem_wb;
  assign w1_en_wb = 



endmodule