`timescale 1ns/1ps

// Structural dispatch and global issue interlock for the bounded OoO core.
// Data dependencies are represented by RAT tags and are woken in the RS;
// this block therefore replaces the old pipeline-register RAW comparison
// with prefix admission against the current ROB/PRF/RS/LSQ capacities.
module hazard (
    input      [1:0] fetch_valid_in,
    input            recovery_in,

    input      [3:0] rob_free_count_in,
    input      [5:0] prf_free_count_in,
    input      [3:0] rs_free_count_in,
    input      [3:0] lsq_free_count_in,

    input      [1:0] phys_need_in,
    input      [1:0] rs_need_in,
    input      [1:0] lsq_need_in,
    input      [1:0] is_control_in,
    input      [1:0] is_fence_in,
    input            any_control_inflight_in,
    input            any_fence_inflight_in,

    input            rob_head_is_fence_in,
    input            memory_idle_in,

    output reg [1:0] dispatch_count_out,
    output     [1:0] dispatch_valid_out,
    output           issue_enable_out,
    output           fence_complete_out
);

    wire [1:0] total_phys_need;
    wire [1:0] total_rs_need;
    wire [1:0] total_lsq_need;
    wire       slot0_can_dispatch;
    wire       slot1_can_dispatch;

    assign total_phys_need = {1'b0, phys_need_in[0]} +
                             {1'b0, phys_need_in[1]};
    assign total_rs_need = {1'b0, rs_need_in[0]} +
                           {1'b0, rs_need_in[1]};
    assign total_lsq_need = {1'b0, lsq_need_in[0]} +
                            {1'b0, lsq_need_in[1]};

    assign slot0_can_dispatch = fetch_valid_in[0] && !recovery_in &&
        (rob_free_count_in >= 4'd1) &&
        (prf_free_count_in >= {5'b0, phys_need_in[0]}) &&
        (rs_free_count_in >= {3'b0, rs_need_in[0]}) &&
        (lsq_free_count_in >= {3'b0, lsq_need_in[0]}) &&
        !(is_control_in[0] && any_control_inflight_in) &&
        !(is_fence_in[0] && any_fence_inflight_in);

    // Lane 1 is strictly a younger prefix member.  Controls and fences are
    // always re-presented later in lane 0 and dispatch alone there.
    assign slot1_can_dispatch = slot0_can_dispatch &&
        fetch_valid_in[1] && (rob_free_count_in >= 4'd2) &&
        (prf_free_count_in >= {4'b0, total_phys_need}) &&
        (rs_free_count_in >= {2'b0, total_rs_need}) &&
        (lsq_free_count_in >= {2'b0, total_lsq_need}) &&
        !is_control_in[0] && !is_control_in[1] &&
        !is_fence_in[0] && !is_fence_in[1];

    always @(*) begin
        dispatch_count_out = 2'd0;
        if (slot0_can_dispatch) begin
            if (slot1_can_dispatch)
                dispatch_count_out = 2'd2;
            else
                dispatch_count_out = 2'd1;
        end
    end

    assign dispatch_valid_out[0] = (dispatch_count_out != 2'd0);
    assign dispatch_valid_out[1] = (dispatch_count_out == 2'd2);
    assign issue_enable_out = !recovery_in;
    // A recovering head is necessarily a control rather than a FENCE, so
    // recovery need not feed this head-ready path (and keeping it out avoids
    // a combinational ROB -> hazard -> ROB loop).
    assign fence_complete_out = rob_head_is_fence_in && memory_idle_in;

endmodule
