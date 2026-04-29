module icache 
(
    input           en_sig,
    input   [31:0]  addr,
    output  [31:0]  intruction
);
    
    localparam pm_size = 32000;
    
    reg [31:0] pm[pm_size:0];

    always @(*) begin
         if(en_sig) begin
            intruction = pm[addr];
        end
    end

endmodule