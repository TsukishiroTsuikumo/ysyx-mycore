`timescale 1ns/1ps

// Format a DCache word using the private lsu_op encoding from decoder.v.
module load_extender (
    input      [2:0]  lsu_op_in,
    input      [31:0] raw_data_in,
    output reg [31:0] value_out
);

    always @(*) begin
        case (lsu_op_in)
            3'b000: value_out = {{24{raw_data_in[7]}}, raw_data_in[7:0]};
            3'b001: value_out = {{16{raw_data_in[15]}}, raw_data_in[15:0]};
            3'b010: value_out = raw_data_in;
            3'b011: value_out = {24'b0, raw_data_in[7:0]};
            3'b100: value_out = {16'b0, raw_data_in[15:0]};
            default: value_out = 32'b0;
        endcase
    end

endmodule
