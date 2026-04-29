module pipe_reg
( input				  clk,
  input	  [31:0]  pipe_in,
  output  [31:0]  pipe_out
);

  reg [31:0] pipe_val;
  assign pipe_out = pipe_val;

  always @(posedge clk) begin
	pipe_val <= pipe_in;
  end

endmodule
