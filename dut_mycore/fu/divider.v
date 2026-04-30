module divider (
    input is_used,
    input [3:0] opcode,
    input [31:0] divA,
    input [31:0] divB,
    output reg [31:0] divC
);

    localparam div = 4'b0001;
    localparam rem = 4'b0010;
    localparam divu = 4'b0100;
    localparam remu = 4'b1000;

    wire [31:0] a_in = is_used ? divA : 32'b0;
    wire [31:0] b_in = is_used ? divB : 32'b0;

    always @(*) begin
        case(opcode)
            div: begin
                divC = $signed(a_in) / $signed(b_in);
            end
            rem: begin
                divC = $signed(a_in) % $signed(b_in);
            end
            divu: begin
                divC = a_in / b_in;
            end
            remu: begin
                divC = a_in % b_in;
            end
            default: divC = 32'b0;
        endcase
    end
    
endmodule
