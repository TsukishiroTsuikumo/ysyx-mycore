`timescale 1ns/1ps

module reg_R (
    input             clk,
    input             reset,
    input       [4:0] r1_addr,
    output     [31:0] r1_out,
    input       [4:0] r2_addr,
    output     [31:0] r2_out,
    input       [4:0] r3_addr,
    output     [31:0] r3_out,
    input       [4:0] r4_addr,
    output     [31:0] r4_out,
    input             w1_en,
    input       [4:0] w1_addr,
    input      [31:0] w1_in,
    input             w2_en,
    input       [4:0] w2_addr,
    input      [31:0] w2_in
);

    reg [31:0] reg_val [0:31];
    integer i;

    assign r1_out = (r1_addr == 5'd0) ? 32'b0 :
                    (w2_en && (w2_addr == r1_addr)) ? w2_in :
                    (w1_en && (w1_addr == r1_addr)) ? w1_in :
                    reg_val[r1_addr];
    assign r2_out = (r2_addr == 5'd0) ? 32'b0 :
                    (w2_en && (w2_addr == r2_addr)) ? w2_in :
                    (w1_en && (w1_addr == r2_addr)) ? w1_in :
                    reg_val[r2_addr];
    assign r3_out = (r3_addr == 5'd0) ? 32'b0 :
                    (w2_en && (w2_addr == r3_addr)) ? w2_in :
                    (w1_en && (w1_addr == r3_addr)) ? w1_in :
                    reg_val[r3_addr];
    assign r4_out = (r4_addr == 5'd0) ? 32'b0 :
                    (w2_en && (w2_addr == r4_addr)) ? w2_in :
                    (w1_en && (w1_addr == r4_addr)) ? w1_in :
                    reg_val[r4_addr];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                reg_val[i] <= 32'b0;
        end
        else begin
            reg_val[0] <= 32'b0;
            if (w1_en && (w1_addr != 5'd0))
                reg_val[w1_addr] <= w1_in;
            if (w2_en && (w2_addr != 5'd0))
                reg_val[w2_addr] <= w2_in;
        end
    end

endmodule
