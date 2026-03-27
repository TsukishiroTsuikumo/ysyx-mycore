module reg_R
#(parameter reg_log = 1'b0,
  parameter reg_log_name = "X"
)

( input			      clk,
  input			      reset,
  // Read Port 1
  input	   [4:0]  r1_addr,
  output  [31:0]  r1_out,
  // Read Port 2
  input	   [4:0]  r2_addr,
  output  [31:0]  r2_out,
  // Write Port 1
  input			      w1_en,
  input	   [4:0]  w1_addr,
  input	  [31:0]  w1_in
);

  reg [31:0] reg_val[0:31];

  assign r1_out = r1_addr ? reg_val[r1_addr] : 32'b0;
  assign r2_out = r2_addr ? reg_val[r2_addr] : 32'b0;

  always @( posedge clk or posedge reset) begin // Write
    if (reset) begin
      integer i;
      for(i=1;i<32;i++) begin
      reg_val[i] <= 32'b0;
      end
    end
    else if(w1_en) begin
      if (!w1_addr) begin
      reg_val[w1_addr] <= w1_in;
      end
    end
  end

endmodule


  
