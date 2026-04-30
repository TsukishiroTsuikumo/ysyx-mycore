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
  wire  [3:0] flush_sig;

  controller controller(
    .current_pc(current_pc_if),
    .next_pc(next_pc),
    .ifetch(ifetch),
    .pm_addr(pm_addr_out),
    .is_cd_jp(is_cd_jp_ex),
    .cd_jp_imm(imm_id_ex),
    .is_jal(is_jal_id),
    .jal_imm(imm_id),
    .is_jalr(is_jalr_id_ex),
    .jalr_trgt(addC),
    .jp_inst_pc(PC_id_ex),
    .flush_sig(flush_sig)
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
    if(flush_sig[0]) PC_if_id <= 32'b0; // flush
    else PC_if_id <= current_pc_if;
  end

  // --------------------------------------------- //
  // -------- Pipe2 ID: Decode Instruction ------- //
  // --------------------------------------------- //

  wire [31:0] instr_id;
  assign instr_id = pm_rd_in; // from pm

  wire  [4:0]  rs1_addr_id;
  wire  [4:0]  rs2_addr_id;
  wire         sel_imm_id;
  wire [31:0]  imm_id;
  wire         sel_rd_id;
  wire  [4:0]  rd_addr_id;

  wire  [2:0]  adder_op_id;
  wire  [1:0]  shifter_op_id;
  wire  [3:0]  multiplier_op_id;
  wire  [3:0]  divider_op_id;
  wire  [1:0]  alu_op_id;
  wire  [2:0]  lsu_op_id;

  wire  [5:0]  use_signal_id;
  wire         is_jal_id;
  wire         is_jalr_id;

  decoder decoder(
    .instr(instr_id),

    .rs1_addr(rs1_addr_id),
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
    .lsu_op(lsu_op_id),

    .use_signal(use_signal_id),
    .is_jal(is_jal_id),
    .is_jalr(is_jalr_id)
    
  );

  // --------------------------------------------- //
  // ---------------- ID to EX ------------------- //
  // --------------------------------------------- //

  reg   [4:0] w1_addr_id_ex;
  reg  [31:0] imm_id_ex;
  reg         w1_en_id_ex;
  reg         sel_imm_id_ex;
  reg   [5:0] use_signal_id_ex;

  reg   [2:0] adder_op_id_ex;
  reg   [1:0] shifter_op_id_ex;
  reg   [3:0] multiplier_op_id_ex;
  reg   [3:0] divider_op_id_ex;
  reg   [1:0] alu_op_id_ex;
  reg   [2:0] lsu_op_id_ex;

  reg         is_jal_id_ex;
  reg         is_jalr_id_ex;
  reg  [31:0] PC_id_ex;

  always @(posedge clk) begin
    if(flush_sig[1]) begin // flush
      w1_addr_id_ex <= 5'b0;
      imm_id_ex <= 32'b0;
      w1_en_id_ex <= 1'b0;
      sel_imm_id_ex <= 1'b0;
      use_signal_id_ex <= 6'b0;
      adder_op_id_ex <= 3'b000;
      shifter_op_id_ex <= 2'b00;
      alu_op_id_ex <= 2'b00;
      multiplier_op_id_ex <= 4'b0000;
      divider_op_id_ex <= 4'b0000;
      lsu_op_id_ex <= 3'b000;
      is_jal_id_ex <= 1'b0;
      is_jalr_id_ex <= 1'b0;
    end
    else begin
      w1_addr_id_ex       <= rd_addr_id;
      imm_id_ex           <= imm_id;
      w1_en_id_ex         <= sel_rd_id;
      sel_imm_id_ex       <= sel_imm_id;
      use_signal_id_ex    <= use_signal_id;
      adder_op_id_ex      <= adder_op_id;
      shifter_op_id_ex    <= shifter_op_id;
      alu_op_id_ex        <= alu_op_id;
      multiplier_op_id_ex <= multiplier_op_id;
      divider_op_id_ex    <= divider_op_id;
      lsu_op_id_ex        <= lsu_op_id;
      is_jal_id_ex        <= is_jal_id;
      is_jalr_id_ex       <= is_jalr_id;
      PC_id_ex            <= PC_if_id;
    end
  end

  wire [31:0] r1_out;
  wire [31:0] r2_out;

  reg_R regfile(
    .clk(clk),
    .reset(reset),
    .r1_addr(rs1_addr_id),
    .r1_out(r1_out), 
    .r2_addr(rs2_addr_id),
    .r2_out(r2_out),
    .w1_en(w1_en_wb),
    .w1_addr(w1_addr_wb),
    .w1_in(w1_in_wb)
  );

  // --------------------------------------------- //
  // ------- Pipe3 EX: Execute Instruction ------- //
  // --------------------------------------------- //

  wire [31:0] rs1, rs2;
  assign rs1 = r1_out;
  assign rs2 = sel_imm_id_ex ? imm_id_ex : r2_out;

  wire [31:0] aluC;
  wire [31:0] addC;
  wire [31:0] shfC;
  wire [31:0] lsuC;
  wire [31:0] mpyC;
  wire [31:0] divC;

  alu alu_1(
    .is_used(use_signal_id_ex[1]),
    .opcode(alu_op_id_ex),
    .aluA(rs1),
    .aluB(rs2),
    .aluC(aluC)
  );

  wire is_cd_jp_ex;
  adder adder_1(
    .is_used(use_signal_id_ex[0]),
    .opcode(adder_op_id_ex),
    .addA(rs1),
    .addB(rs2),
    .addC(addC),
    .branch_cd(is_cd_jp_ex)
  );

  shifter shifter_1(
    .is_used(use_signal_id_ex[2]),
    .opcode(shifter_op_id_ex),
    .shfA(rs1),
    .shfB(rs2),
    .shfC(shfC)
  );

  multiplier multiplier_1(
    .is_used(use_signal_id_ex[3]),
    .opcode(multiplier_op_id_ex),
    .mpyA(rs1),
    .mpyB(rs2),
    .mpyC(mpyC)
  );

  wire [31:0] dm_addr_ex;
  wire [3:0] dm_ld_ex;
  wire [3:0] dm_st_ex;
  lsu lsu_1(
    .is_used(use_signal_id_ex[5]),
    .opcode(lsu_op_id_ex),
    .lsuA(rs1),
    .lsuB(rs2),
    .st_value(r1_out),
    .dm_addr(dm_addr_ex),
    .dm_out(lsuC),
    .is_ld(dm_ld_ex),
    .is_st(dm_st_ex)
  );

  divider divider_1(
    .is_used(use_signal_id_ex[4]),
    .opcode(divider_op_id_ex),
    .divA(rs1),
    .divB(rs2),
    .divC(divC)
  );

  wire [31:0] ret_addr = PC_id_ex + 4;
  wire jal_sig = is_jal_id_ex | is_jalr_id_ex;

  // ----------------------------------------------- //
  // ----------------- EX to MEM ------------------- //
  // ----------------------------------------------- //

  reg  [4:0] w1_addr_ex_mem;
  reg        w1_en_ex_mem;
  reg [31:0] pipe_ex_mem;
  reg [31:0] dm_addr_ex_mem;
  reg  [3:0] dm_ld_ex_mem;
  reg  [3:0] dm_st_ex_mem;

  always @(posedge clk) begin
    if(flush_sig[2]) begin // flush
      w1_addr_ex_mem <= 5'b0;
      w1_en_ex_mem <= 1'b0;
      pipe_ex_mem <= 32'b0;
      dm_addr_ex_mem <= 32'b0;
      dm_ld_ex_mem <= 4'b0;
      dm_st_ex_mem <= 4'b0;
    end
    else begin
      case (jal_sig)
        1'b1: pipe_ex_mem <= ret_addr;
        default: begin
          case (use_signal_id_ex)
            6'b000001: pipe_ex_mem <= addC;
            6'b000010: pipe_ex_mem <= aluC;
            6'b000100: pipe_ex_mem <= shfC;
            6'b001000: pipe_ex_mem <= mpyC;
            6'b010000: pipe_ex_mem <= divC;
            6'b100000: pipe_ex_mem <= lsuC;
            default:   pipe_ex_mem <= 32'b0;
          endcase
        end
      endcase
      w1_en_ex_mem   <= w1_en_id_ex;
      w1_addr_ex_mem <= w1_addr_id_ex;
      dm_addr_ex_mem <= dm_addr_ex;
      dm_ld_ex_mem   <= dm_ld_ex;
      dm_st_ex_mem   <= dm_st_ex;
    end
  end

  // ----------------------------------------------- //
  // ----------Pipe4 MEM: Memory Access ------------ //
  // ----------------------------------------------- //

  assign dm_ld = dm_ld_ex_mem;
  assign dm_st = dm_st_ex_mem;
  assign dm_addr_out = dm_addr_ex_mem;
  assign dm_wr_out = pipe_ex_mem;

  // ----------------------------------------------- //
  // ------------------ MEM to WB ------------------ //
  // ----------------------------------------------- //

  reg [31:0]  pipe_mem_wb;
  reg  [4:0]  w1_addr_mem_wb;
  reg         w1_en_mem_wb;

  always @(posedge clk) begin
    if(flush_sig[3]) begin // flush
      pipe_mem_wb <= 32'b0;
      w1_addr_mem_wb <= 5'b0;
      w1_en_mem_wb <= 1'b0;
    end
    else begin
      pipe_mem_wb <= pipe_ex_mem;
      w1_addr_mem_wb <= w1_addr_ex_mem;
      w1_en_mem_wb <= w1_en_ex_mem;
    end
  end

  // ----------------------------------------------- //
  // ------- Pipe5 WB: Write back and commit ------- //
  // ----------------------------------------------- //

  
  wire  [4:0] w1_addr_wb = w1_addr_mem_wb;
  wire [31:0] w1_in_wb = ld_valid ? dm_rd_in : pipe_mem_wb;
  wire        w1_en_wb = w1_en_mem_wb;


endmodule
