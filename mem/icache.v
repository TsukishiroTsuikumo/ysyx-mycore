module icache 
(
    input           en_sig,
    input   [31:0]  addr,
    output  reg [31:0]  intruction
);
    
    localparam pm_size = 32000;
    
    reg [31:0] pm[0:pm_size-1];

    always @(*) begin
        intruction = 32'b0;
        if(en_sig) begin
            intruction = pm[addr];
        end
    end

endmodule
