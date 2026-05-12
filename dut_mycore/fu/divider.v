module divider (
    input is_used,
    input [3:0] opcode,
    input [31:0] divA,
    input [31:0] divB,
    output reg [31:0] divC
);

    localparam div = 4'b0001;
    localparam divu = 4'b0010;
    localparam rem = 4'b0100;
    localparam remu = 4'b1000;

    wire [31:0] a_in = is_used ? divA : 32'b0;
    wire [31:0] b_in = is_used ? divB : 32'b0;

    always @(*) begin
        case(opcode)
            div: begin
                if (b_in == 32'b0) begin
                    divC = 32'hffff_ffff;
                end
                else if ((a_in == 32'h8000_0000) && (b_in == 32'hffff_ffff)) begin
                    divC = 32'h8000_0000;
                end
                else begin
                    divC = $signed(a_in) / $signed(b_in);
                end
            end
            rem: begin
                if (b_in == 32'b0) begin
                    divC = a_in;
                end
                else if ((a_in == 32'h8000_0000) && (b_in == 32'hffff_ffff)) begin
                    divC = 32'b0;
                end
                else begin
                    divC = $signed(a_in) % $signed(b_in);
                end
            end
            divu: begin
                divC = (b_in == 32'b0) ? 32'hffff_ffff : (a_in / b_in);
            end
            remu: begin
                divC = (b_in == 32'b0) ? a_in : (a_in % b_in);
            end
            default: divC = 32'b0;
        endcase
    end
    
endmodule
