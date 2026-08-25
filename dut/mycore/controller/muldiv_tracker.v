`timescale 1ns/1ps

// Metadata and fixed-latency tracker for the directly instantiated RV32M
// function units.  This module intentionally contains no decoder or FU.
module muldiv_tracker (
    input             clk,
    input             reset,
    input             flush_in,

    input             start_valid_in,
    input       [6:0] start_use_signal_in,
    input      [31:0] mul_result_in,
    input      [31:0] div_result_in,
    input       [2:0] start_rob_in,
    input       [5:0] start_pdst_in,
    input             start_writes_in,
    output            start_ready_out,
    output            start_fire_out,
    output            busy_out,

    output            result_valid_out,
    input             result_grant_in,
    output     [31:0] result_value_out,
    output      [2:0] result_rob_out,
    output      [5:0] result_pdst_out,
    output            result_writes_out
);

    localparam [3:0] FIXED_LATENCY = 4'd12;

    reg        computing_q;
    reg  [3:0] count_q;
    reg        result_valid_q;
    reg [31:0] result_value_q;
    reg  [2:0] result_rob_q;
    reg  [5:0] result_pdst_q;
    reg        result_writes_q;

    wire operation_valid;
    assign operation_valid = start_use_signal_in[3] ||
                             start_use_signal_in[4];
    assign start_ready_out = !flush_in && !computing_q &&
                             !result_valid_q;
    assign start_fire_out = start_valid_in && start_ready_out &&
                            operation_valid;
    assign busy_out = computing_q || result_valid_q;
    assign result_valid_out = result_valid_q;
    assign result_value_out = result_value_q;
    assign result_rob_out = result_rob_q;
    assign result_pdst_out = result_pdst_q;
    assign result_writes_out = result_writes_q;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            computing_q <= 1'b0;
            count_q <= 4'b0;
            result_valid_q <= 1'b0;
            result_value_q <= 32'b0;
            result_rob_q <= 3'b0;
            result_pdst_q <= 6'b0;
            result_writes_q <= 1'b0;
        end
        else if (flush_in) begin
            computing_q <= 1'b0;
            count_q <= 4'b0;
            result_valid_q <= 1'b0;
            result_value_q <= 32'b0;
            result_rob_q <= 3'b0;
            result_pdst_q <= 6'b0;
            result_writes_q <= 1'b0;
        end
        else begin
            if (result_valid_q && result_grant_in)
                result_valid_q <= 1'b0;

            if (start_fire_out) begin
                computing_q <= 1'b1;
                count_q <= FIXED_LATENCY;
                if (start_use_signal_in[3])
                    result_value_q <= mul_result_in;
                else
                    result_value_q <= div_result_in;
                result_rob_q <= start_rob_in;
                result_pdst_q <= start_pdst_in;
                result_writes_q <= start_writes_in;
            end
            else if (computing_q) begin
                if (count_q > 4'd1) begin
                    count_q <= count_q - 4'd1;
                end
                else begin
                    computing_q <= 1'b0;
                    count_q <= 4'b0;
                    result_valid_q <= 1'b1;
                end
            end
        end
    end

endmodule
