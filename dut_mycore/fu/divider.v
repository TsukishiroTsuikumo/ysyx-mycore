module devider (
    input is_used,
    input [1:0] opcode,
    input [31:0] divA,
    input [31:0] divB,
    output reg [31:0] divC
);

    localparam div = 2'b00;
    localparam rem = 2'b01;
    localparam divu = 2'b10;
    localparam remu = 2'b11;

    always @(*) begin
        if(is_used) begin
            case(opcode)
                div: begin
                    divC = $signed(divA) / $signed(divB);
                end
                rem: begin
                    divC = $signed(divA) % $signed(divB);
                end
                divu: begin
                    divC = divA / divB;
                end
                remu: begin
                    divC = divA % divB;
                end
            endcase
        end 
        else begin
            divC = 32'b0;
        end
    end
    
endmodule