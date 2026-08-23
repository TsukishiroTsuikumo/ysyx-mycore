`timescale 1ns/1ps

// Event counters for single/dual-issue A/B verification.
//
// Stall inputs are independent event pulses and may overlap.  IPC is derived
// by the verification environment from retired_instr_count / cycle_count;
// keeping division out of RTL makes the counters synthesis-friendly.
module perf_counters #(
    parameter integer COUNTER_WIDTH = 64,
    parameter integer ISSUE_WIDTH   = 2
)(
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         clear,

    input  wire [1:0]                   issue_valid,
    input  wire [1:0]                   retire_valid,

    input  wire                         frontend_empty,
    input  wire                         data_hazard_stall,
    input  wire                         memory_stall,
    input  wire                         pair_serialize,

    output reg  [COUNTER_WIDTH-1:0]     cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     issued_instr_count,
    output reg  [COUNTER_WIDTH-1:0]     retired_instr_count,
    output reg  [COUNTER_WIDTH-1:0]     dual_issue_cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     dual_retire_cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     frontend_empty_cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     data_hazard_stall_cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     memory_stall_cycle_count,
    output reg  [COUNTER_WIDTH-1:0]     pair_serialize_cycle_count
);

    wire [1:0] issue_increment = {1'b0, issue_valid[0]} +
                                 {1'b0, issue_valid[1]};
    wire [1:0] retire_increment = {1'b0, retire_valid[0]} +
                                  {1'b0, retire_valid[1]};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_count <= {COUNTER_WIDTH{1'b0}};
            issued_instr_count <= {COUNTER_WIDTH{1'b0}};
            retired_instr_count <= {COUNTER_WIDTH{1'b0}};
            dual_issue_cycle_count <= {COUNTER_WIDTH{1'b0}};
            dual_retire_cycle_count <= {COUNTER_WIDTH{1'b0}};
            frontend_empty_cycle_count <= {COUNTER_WIDTH{1'b0}};
            data_hazard_stall_cycle_count <= {COUNTER_WIDTH{1'b0}};
            memory_stall_cycle_count <= {COUNTER_WIDTH{1'b0}};
            pair_serialize_cycle_count <= {COUNTER_WIDTH{1'b0}};
        end
        else if (clear) begin
            cycle_count <= {COUNTER_WIDTH{1'b0}};
            issued_instr_count <= {COUNTER_WIDTH{1'b0}};
            retired_instr_count <= {COUNTER_WIDTH{1'b0}};
            dual_issue_cycle_count <= {COUNTER_WIDTH{1'b0}};
            dual_retire_cycle_count <= {COUNTER_WIDTH{1'b0}};
            frontend_empty_cycle_count <= {COUNTER_WIDTH{1'b0}};
            data_hazard_stall_cycle_count <= {COUNTER_WIDTH{1'b0}};
            memory_stall_cycle_count <= {COUNTER_WIDTH{1'b0}};
            pair_serialize_cycle_count <= {COUNTER_WIDTH{1'b0}};
        end
        else begin
            cycle_count <= cycle_count + 1'b1;
            issued_instr_count <= issued_instr_count + issue_increment;
            retired_instr_count <= retired_instr_count + retire_increment;

            if (&issue_valid)
                dual_issue_cycle_count <= dual_issue_cycle_count + 1'b1;
            if (&retire_valid)
                dual_retire_cycle_count <= dual_retire_cycle_count + 1'b1;
            if (frontend_empty)
                frontend_empty_cycle_count <= frontend_empty_cycle_count + 1'b1;
            if (data_hazard_stall)
                data_hazard_stall_cycle_count <=
                    data_hazard_stall_cycle_count + 1'b1;
            if (memory_stall)
                memory_stall_cycle_count <= memory_stall_cycle_count + 1'b1;
            if (pair_serialize)
                pair_serialize_cycle_count <= pair_serialize_cycle_count + 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (COUNTER_WIDTH < 32)
            $fatal(1, "perf_counters COUNTER_WIDTH must be at least 32");
        if ((ISSUE_WIDTH != 1) && (ISSUE_WIDTH != 2))
            $fatal(1, "perf_counters ISSUE_WIDTH must be 1 or 2");
    end

    always @(posedge clk) begin
        if (!reset && !clear) begin
            if (issue_valid[1] && !issue_valid[0])
                $error("perf_counters observed lane1 issue without lane0");
            if (retire_valid[1] && !retire_valid[0])
                $error("perf_counters observed lane1 retire without lane0");
            if ((ISSUE_WIDTH == 1) && issue_valid[1])
                $error("perf_counters observed dual issue in ISSUE_WIDTH=1 mode");
            if ((ISSUE_WIDTH == 1) && retire_valid[1])
                $error("perf_counters observed dual retire in ISSUE_WIDTH=1 mode");
        end
    end
    // synthesis translate_on

endmodule
