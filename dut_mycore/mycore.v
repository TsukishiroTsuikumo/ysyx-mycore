`timescale 1ns/1ps

module mycore (
  input			      clk,
  input			      reset,

  output		      pm_req_valid_out,
  output  [31:0]  pm_req_addr_out,
  input           pm_req_ready_in,
  input           pm_resp_valid_in,
  input   [31:0]  pm_resp_data_in,

  output  [31:0]  dm_req_addr_out,

  output          dm_req_rvalid_out,
  input           dm_req_rready_in,
  input           dm_resp_rvalid_in,
  input   [31:0]  dm_resp_rdata_in,

  output          dm_req_wvalid_out,
  input           dm_req_wready_in,
  output   [3:0]  dm_req_wstrb_out,
  output  [31:0]  dm_req_wdata_out,
  input           dm_resp_wvalid_in
);

  // ------------------------------------------- //
  // -- Pipe1 IF: Generate PC, Predict Branch -- //
  // ------------------------------------------- //

  wire        if_stall;
  wire [31:0] current_pc_if;
  wire [31:0] next_pc;
  wire  [4:0] flush_sig;

  controller controller_inst(
    .current_pc(current_pc_if),
    .next_pc(next_pc),

    .pm_req_addr(pm_req_addr_out),

    .is_cd_jp(is_cd_jp_ex && valid_id_ex),
    .cd_jp_imm(imm_id_ex),
    .is_jal(is_jal_id && valid[0]),
    .jal_pc(PC_id),
    .jal_imm(imm_id),
    .is_jalr(is_jalr_id_ex && valid_id_ex),
    .jalr_trgt(addC),
    .jp_inst_pc(PC_id_ex),
    .flush_sig(flush_sig)
  );
  
  // --------------------------------------------- //
  // ----------------- IF to ID ------------------ //
  // --------------------------------------------- //

  wire pc_en = ~(if_stall && !flush_sig[0]);

  reg_PC PC(
    .clk(clk),
    .reset(reset),
    .pc_en(pc_en),
    .pcw(next_pc),
    .pcr(current_pc_if)
  );

  instr_queue #(8) instr_queue_inst(
    .clk(clk),
    .reset(reset),
    .pm_req_valid(pm_req_valid_out),
    .pm_req_addr(pm_req_addr_out),
    .pm_req_ready(pm_req_ready_in),
    .pm_resp_valid(pm_resp_valid_in),
    .pm_resp_data(pm_resp_data_in),
    .if_stall(if_stall),
    .stall(hzd_stall[0]),
    .flush(flush_sig[0]),
    .instr_out(instr_id),
    .pc_out(PC_id),
    .instr_valid(instr_valid)
  );

  // --------------------------------------------- //
  // -------- Pipe2 ID: Decode Instruction ------- //
  // --------------------------------------------- //
  
  wire         instr_valid;
  wire [31:0]  PC_id;
  wire [31:0]  instr_id;
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
  wire  [1:0]  imu_op_id;

  wire  [6:0]  use_signal_id;
  wire         is_jal_id;
  wire         is_jalr_id;

  decoder decoder_inst(
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
    .imu_op(imu_op_id),

    .use_signal(use_signal_id),
    .is_jal(is_jal_id),
    .is_jalr(is_jalr_id)
  );

  wire  [3:0] hzd_stall;
  wire  [3:0] valid;

  hazard hazard_inst(
    .dm_req_rvalid(dm_req_rvalid_out),
    .dm_req_rready(dm_req_rready_in),
    .dm_req_rready_DLY1(dm_req_rready_mem_wb),
    .dm_resp_rvalid(dm_resp_rvalid_in),

    .dm_req_wvalid(dm_req_wvalid_out),
    .dm_req_wready(dm_req_wready_in),
    .dm_req_wready_DLY1(dm_req_wready_mem_wb),
    .dm_resp_wvalid(dm_resp_wvalid_in),
    
    .rs1_addr_id(rs1_addr_id),
    .rs2_addr_id(rs2_addr_id),
    .rd_addr_id_ex(rd_addr_id_ex),
    .rd_addr_ex_mem(rd_addr_ex_mem),
    .rd_addr_mem_wb(rd_addr_mem_wb),
    .w1_en_id_ex(sel_rd_id_ex),
    .w1_en_ex_mem(sel_rd_ex_mem),
    .w1_en_mem_wb(sel_rd_mem_wb),
    .valid_id_ex(valid_id_ex),
    .valid_ex_mem(valid_ex_mem),
    .valid_mem_wb(valid_mem_wb),

    .hzd_stall_out(hzd_stall),
    .valid_out(valid)
  );

  wire [31:0] r1_out_id;
  wire [31:0] r2_out_id;

  reg_R regfile(
    .clk(clk),
    .reset(reset),
    .r1_addr(rs1_addr_id),
    .r1_out(r1_out_id), 
    .r2_addr(rs2_addr_id),
    .r2_out(r2_out_id),
    .w1_en(commit_valid),
    .w1_addr(rd_addr_wb),
    .w1_in(w1_in_wb)
  );

  // --------------------------------------------- //
  // ---------------- ID to EX ------------------- //
  // --------------------------------------------- //

  reg   [4:0] rd_addr_id_ex;
  reg  [31:0] imm_id_ex;
  reg         sel_rd_id_ex;
  reg         sel_imm_id_ex;
  reg   [6:0] use_signal_id_ex;
  reg  [31:0] r1_out_id_ex;
  reg  [31:0] r2_out_id_ex;

  reg   [2:0] adder_op_id_ex;
  reg   [1:0] shifter_op_id_ex;
  reg   [3:0] multiplier_op_id_ex;
  reg   [3:0] divider_op_id_ex;
  reg   [1:0] alu_op_id_ex;
  reg   [2:0] lsu_op_id_ex;
  reg   [1:0] imu_op_id_ex;

  reg         is_jal_id_ex;
  reg         is_jalr_id_ex;
  reg  [31:0] PC_id_ex;
  reg  [31:0] instr_id_ex;
  reg         valid_id_ex;

  always @(posedge clk or posedge reset) begin
    if(reset | flush_sig[2]) begin
      rd_addr_id_ex <= 5'b0;
      imm_id_ex <= 32'b0;
      sel_rd_id_ex <= 1'b0;
      sel_imm_id_ex <= 1'b0;
      use_signal_id_ex <= 7'b0;
      r1_out_id_ex <= 32'b0;
      r2_out_id_ex <= 32'b0;
      adder_op_id_ex <= 3'b000;
      shifter_op_id_ex <= 2'b00;
      alu_op_id_ex <= 2'b00;
      multiplier_op_id_ex <= 4'b0000;
      divider_op_id_ex <= 4'b0000;
      lsu_op_id_ex <= 3'b000;
      imu_op_id_ex <= 2'b00;
      is_jal_id_ex <= 1'b0;
      is_jalr_id_ex <= 1'b0;
      PC_id_ex <= 32'b0;
      instr_id_ex <= 32'b0;
      valid_id_ex <= 1'b0;
    end
    else if(hzd_stall[1]) begin
      rd_addr_id_ex <= rd_addr_id_ex;
      imm_id_ex <= imm_id_ex;
      sel_rd_id_ex <= sel_rd_id_ex;
      sel_imm_id_ex <= sel_imm_id_ex;
      use_signal_id_ex <= use_signal_id_ex;
      r1_out_id_ex <= r1_out_id_ex;
      r2_out_id_ex <= r2_out_id_ex;
      adder_op_id_ex <= adder_op_id_ex;
      shifter_op_id_ex <= shifter_op_id_ex;
      alu_op_id_ex <= alu_op_id_ex;
      multiplier_op_id_ex <= multiplier_op_id_ex;
      divider_op_id_ex <= divider_op_id_ex;
      lsu_op_id_ex <= lsu_op_id_ex;
      imu_op_id_ex <= imu_op_id_ex;
      is_jal_id_ex <= is_jal_id_ex;
      is_jalr_id_ex <= is_jalr_id_ex;
      PC_id_ex <= PC_id_ex;
      instr_id_ex <= instr_id_ex;
      valid_id_ex <= valid_id_ex;
    end
    else begin
      rd_addr_id_ex       <= rd_addr_id;
      imm_id_ex           <= imm_id;
      sel_rd_id_ex        <= sel_rd_id;
      sel_imm_id_ex       <= sel_imm_id;
      use_signal_id_ex    <= use_signal_id;
      r1_out_id_ex        <= r1_out_id;
      r2_out_id_ex        <= r2_out_id;
      adder_op_id_ex      <= adder_op_id;
      shifter_op_id_ex    <= shifter_op_id;
      alu_op_id_ex        <= alu_op_id;
      multiplier_op_id_ex <= multiplier_op_id;
      divider_op_id_ex    <= divider_op_id;
      lsu_op_id_ex        <= lsu_op_id;
      imu_op_id_ex        <= imu_op_id;
      is_jal_id_ex        <= is_jal_id;
      is_jalr_id_ex       <= is_jalr_id;
      PC_id_ex            <= PC_id;
      instr_id_ex         <= instr_id;
      valid_id_ex         <= instr_valid && valid[0];
    end
  end

  // --------------------------------------------- //
  // ------- Pipe4 EX: Execute Instruction ------- //
  // --------------------------------------------- //

  wire [31:0] rs1, rs2;
  assign rs1 = r1_out_id_ex;
  assign rs2 = sel_imm_id_ex ? imm_id_ex : r2_out_id_ex;

  wire [31:0] aluC;
  wire [31:0] addC;
  wire [31:0] shfC;
  wire [31:0] lsuC;
  wire [31:0] mpyC;
  wire [31:0] divC;
  wire [31:0] imuC;

  alu alu_inst(
    .is_used(use_signal_id_ex[1]),
    .opcode(alu_op_id_ex),
    .aluA(rs1),
    .aluB(rs2),
    .aluC(aluC)
  );

  wire is_cd_jp_ex;
  adder adder_inst(
    .is_used(use_signal_id_ex[0]),
    .opcode(adder_op_id_ex),
    .sel_rd(sel_rd_id_ex),
    .addA(rs1),
    .addB(rs2),
    .addC(addC),
    .branch_cd(is_cd_jp_ex)
  );

  shifter shifter_inst(
    .is_used(use_signal_id_ex[2]),
    .opcode(shifter_op_id_ex),
    .shfA(rs1),
    .shfB(rs2),
    .shfC(shfC)
  );

  multiplier multiplier_inst(
    .is_used(use_signal_id_ex[3]),
    .opcode(multiplier_op_id_ex),
    .mpyA(rs1),
    .mpyB(rs2),
    .mpyC(mpyC)
  );

  wire [31:0] dm_addr_ex;
  wire [3:0] dm_ld_ex;
  wire [3:0] dm_st_ex;
  lsu lsu_inst(
    .is_used(use_signal_id_ex[5]),
    .opcode(lsu_op_id_ex),
    .lsuA(rs1),
    .lsuB(rs2),
    .st_value(r2_out_id_ex),
    .dm_addr(dm_addr_ex),
    .dm_out(lsuC),
    .is_ld(dm_ld_ex),
    .is_st(dm_st_ex)
  );

  divider divider_inst(
    .is_used(use_signal_id_ex[4]),
    .opcode(divider_op_id_ex),
    .divA(rs1),
    .divB(rs2),
    .divC(divC)
  );

  imu imu_inst(
    .is_used(use_signal_id_ex[6]),
    .opcode(imu_op_id_ex),
    .current_pc(PC_id_ex),
    .imm(imm_id_ex),
    .out(imuC)
  );

  wire [31:0] ret_addr = PC_id_ex + 4;
  wire jal_sig = (is_jal_id_ex | is_jalr_id_ex) & valid_id_ex;

  // ----------------------------------------------- //
  // ----------------- EX to MEM ------------------- //
  // ----------------------------------------------- //

  reg  [4:0] rd_addr_ex_mem;
  reg        sel_rd_ex_mem;
  reg [31:0] pipe_ex_mem;
  reg [31:0] dm_addr_ex_mem;
  reg  [3:0] dm_ld_ex_mem;
  reg  [3:0] dm_st_ex_mem;
  reg  [2:0] lsu_op_ex_mem;
  reg        valid_ex_mem;
  reg [31:0] PC_ex_mem;
  reg [31:0] instr_ex_mem;

  always @(posedge clk or posedge reset) begin
    if(reset) begin
      rd_addr_ex_mem <= 5'b0;
      sel_rd_ex_mem <= 1'b0;
      pipe_ex_mem <= 32'b0;
      dm_addr_ex_mem <= 32'b0;
      dm_ld_ex_mem <= 4'b0;
      dm_st_ex_mem <= 4'b0;
      lsu_op_ex_mem <= 3'b0;
      valid_ex_mem <= 1'b0;
      instr_ex_mem <= 32'b0;
      PC_ex_mem <= 32'b0;
    end
    else if(flush_sig[3]) begin // flush
      rd_addr_ex_mem <= 5'b0;
      sel_rd_ex_mem <= 1'b0;
      pipe_ex_mem <= 32'b0;
      dm_addr_ex_mem <= 32'b0;
      dm_ld_ex_mem <= 4'b0;
      dm_st_ex_mem <= 4'b0;
      lsu_op_ex_mem <= 3'b0;
      valid_ex_mem <= 1'b0;
      PC_ex_mem <= 32'b0;
      instr_ex_mem <= 32'b0;
    end
    else if(hzd_stall[2]) begin
      rd_addr_ex_mem <= rd_addr_ex_mem;
      sel_rd_ex_mem <= sel_rd_ex_mem;
      pipe_ex_mem <= pipe_ex_mem;
      dm_addr_ex_mem <= dm_addr_ex_mem;
      dm_ld_ex_mem <= dm_ld_ex_mem;
      dm_st_ex_mem <= dm_st_ex_mem;
      lsu_op_ex_mem <= lsu_op_ex_mem;
      valid_ex_mem <= valid_ex_mem;
      PC_ex_mem <= PC_ex_mem;
      instr_ex_mem <= instr_ex_mem;
    end
    else begin
      case (jal_sig)
        1'b1: pipe_ex_mem <= ret_addr;
        default: begin
          case (use_signal_id_ex)
            7'b0000001: pipe_ex_mem <= addC;
            7'b0000010: pipe_ex_mem <= aluC;
            7'b0000100: pipe_ex_mem <= shfC;
            7'b0001000: pipe_ex_mem <= mpyC;
            7'b0010000: pipe_ex_mem <= divC;
            7'b0100000: pipe_ex_mem <= lsuC;
            7'b1000000: pipe_ex_mem <= imuC;
            default:   pipe_ex_mem <= 32'b0;
          endcase
        end
      endcase
      sel_rd_ex_mem   <= sel_rd_id_ex;
      rd_addr_ex_mem <= rd_addr_id_ex;
      dm_addr_ex_mem <= dm_addr_ex;
      dm_ld_ex_mem   <= dm_ld_ex;
      dm_st_ex_mem   <= dm_st_ex;
      lsu_op_ex_mem  <= lsu_op_id_ex;
      valid_ex_mem   <= valid_id_ex & valid[1];
      instr_ex_mem   <= instr_id_ex;
      PC_ex_mem      <= PC_id_ex;
    end
  end

  // ----------------------------------------------- //
  // ----------Pipe5 MEM: Memory Access ------------ //
  // ----------------------------------------------- //
  
  assign dm_req_addr_out = dm_addr_ex_mem;
  assign dm_req_rvalid_out = valid_ex_mem & (|dm_ld_ex_mem);
  assign dm_req_wstrb_out = valid_ex_mem ? dm_st_ex_mem : 4'b0;
  assign dm_req_wvalid_out = valid_ex_mem & (|dm_st_ex_mem);
  assign dm_req_wdata_out = pipe_ex_mem;

  // ----------------------------------------------- //
  // ------------------ MEM to WB ------------------ //
  // ----------------------------------------------- //

  reg [31:0]  pipe_mem_wb;
  reg  [4:0]  rd_addr_mem_wb;
  reg         sel_rd_mem_wb;
  reg  [3:0]  dm_ld_mem_wb;
  reg  [2:0]  lsu_op_mem_wb;
  reg         dm_req_rready_mem_wb;
  reg         dm_req_wready_mem_wb;
  reg         valid_mem_wb;
  reg [31:0] instr_mem_wb;
  reg [31:0] PC_mem_wb;

  always @(posedge clk or posedge reset) begin
    if(reset | flush_sig[4]) begin
      pipe_mem_wb <= 32'b0;
      rd_addr_mem_wb <= 5'b0;
      sel_rd_mem_wb <= 1'b0;
      dm_ld_mem_wb <= 4'b0;
      lsu_op_mem_wb <= 3'b0;
      valid_mem_wb <= 1'b0;
      dm_req_rready_mem_wb <= 1'b0;
      dm_req_wready_mem_wb <= 1'b0;
      instr_mem_wb <= 32'b0;
      PC_mem_wb <= 32'b0;
    end
    else if(hzd_stall[3]) begin
      pipe_mem_wb <= pipe_mem_wb;
      rd_addr_mem_wb <= rd_addr_mem_wb;
      sel_rd_mem_wb <= sel_rd_mem_wb;
      dm_ld_mem_wb <= dm_ld_mem_wb;
      lsu_op_mem_wb <= lsu_op_mem_wb;
      dm_req_rready_mem_wb <= dm_req_rready_mem_wb;
      dm_req_wready_mem_wb <= dm_req_wready_mem_wb;
      valid_mem_wb <= valid_mem_wb;
      instr_mem_wb <= instr_mem_wb;
      PC_mem_wb <= PC_mem_wb;
    end
    else begin
      pipe_mem_wb <= pipe_ex_mem;
      rd_addr_mem_wb <= rd_addr_ex_mem;
      sel_rd_mem_wb <= sel_rd_ex_mem;
      dm_ld_mem_wb <= dm_ld_ex_mem;
      lsu_op_mem_wb <= lsu_op_ex_mem;
      dm_req_rready_mem_wb <= dm_req_rready_in && dm_req_rvalid_out;
      dm_req_wready_mem_wb <= dm_req_wready_in && dm_req_wvalid_out;
      valid_mem_wb <= valid_ex_mem & valid[2];
      instr_mem_wb <= instr_ex_mem;
      PC_mem_wb <= PC_ex_mem;
    end
  end

  // ----------------------------------------------- //
  // ------- Pipe6 WB: Write back and commit ------- //
  // ----------------------------------------------- //

  wire        is_ld_wb = (dm_ld_mem_wb != 4'b0);
  reg  [31:0] dm_rd_wb;
  always @(*) begin
    case(lsu_op_mem_wb)
      3'b000: dm_rd_wb = {{24{dm_resp_rdata_in[7]}},  dm_resp_rdata_in[7:0]};   // lb
      3'b001: dm_rd_wb = {{16{dm_resp_rdata_in[15]}}, dm_resp_rdata_in[15:0]};  // lh
      3'b010: dm_rd_wb = dm_resp_rdata_in;                              // lw
      3'b011: dm_rd_wb = {24'b0, dm_resp_rdata_in[7:0]};                // lbu
      3'b100: dm_rd_wb = {16'b0, dm_resp_rdata_in[15:0]};               // lhu
      default: dm_rd_wb = 32'b0;
    endcase
  end
  wire  [4:0] rd_addr_wb = rd_addr_mem_wb;
  wire [31:0] w1_in_wb = is_ld_wb ? dm_rd_wb : pipe_mem_wb;
  wire        commit_valid = sel_rd_mem_wb && (!is_ld_wb || dm_resp_rvalid_in) && valid_mem_wb && valid[3];
  wire        retire_valid = valid_mem_wb && valid[3];

endmodule
