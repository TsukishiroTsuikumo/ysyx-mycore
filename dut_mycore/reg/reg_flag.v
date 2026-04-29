module reg_flag
( input			    clk,
  input			    reset,
  input             flag_en,
  input	   [3:0]    flagw,
  output   [3:0]    flagr
);

    reg ZF, SF, OF, CF;
    
    assign flagr = {CF, OF, SF, ZF};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ZF <= 1'b0;
            SF <= 1'b0;
            OF <= 1'b0;
            CF <= 1'b0;
        end
        else begin
            if (flag_en) begin
                ZF <= flagw[0];
                SF <= flagw[1];
                OF <= flagw[2];
                CF <= flagw[3];
            end
        end
    end

endmodule
