`timescale 1ns/1ps

module reg_PC
( input			  clk,
  input			  reset,
  input			  pc_en,
  input	  [31:0]  pcw,
  output  [31:0]  pcr
);

  reg [31:0] pc_val;

  always @(posedge clk or posedge reset) begin
	if(reset) begin
	  pc_val <= 32'b0;
	end
	else begin
	  if(pc_en) begin
		pc_val <= pcw;
	  end
	end
  end

  assign pcr = pc_val;

endmodule
