`timescale 1ns/1ps

// Two-wide, oldest-first issue selector for the in-order intermediate core.
//
// Class encoding is shared with execute_lane and documented in
// docs/dual-issue-inorder.md.  Only two SIMPLE_INT instructions may issue as a
// pair.  Memory, control-flow and M-extension instructions are serialized in
// lane 0.  There is deliberately no same-cycle lane0-to-lane1 forwarding.
module issue_control #(
    parameter integer ISSUE_WIDTH = 2
)(
    input  wire                         backend_ready,
    input  wire                         kill_issue,

    input  wire [1:0]                   slot_valid,
    input  wire [1:0][2:0]              slot_class,
    input  wire [1:0]                   slot_rs1_used,
    input  wire [1:0]                   slot_rs2_used,
    input  wire [1:0][4:0]              slot_rs1_addr,
    input  wire [1:0][4:0]              slot_rs2_addr,
    input  wire [1:0]                   slot_writes_rd,
    input  wire [1:0][4:0]              slot_rd_addr,

    // Older destination registers that have not reached the bypassable WB
    // stage.  MEM/WB is intentionally absent: the 4R2W register file supplies
    // same-cycle WB-to-ID bypasses for both write ports.
    input  wire [1:0]                   id_ex_valid,
    input  wire [1:0]                   id_ex_writes_rd,
    input  wire [1:0][4:0]              id_ex_rd_addr,
    input  wire [1:0]                   ex_mem_valid,
    input  wire [1:0]                   ex_mem_writes_rd,
    input  wire [1:0][4:0]              ex_mem_rd_addr,

    output reg  [1:0]                   issue_valid,
    output reg  [1:0]                   consume_count,

    output wire                         slot0_old_raw,
    output wire                         slot1_old_raw,
    output wire                         intra_pair_raw,
    output wire                         structural_pair_block,
    output wire                         data_hazard_stall,
    output wire                         pair_serialize
);

    localparam [2:0] CLASS_SIMPLE_INT = 3'd0;
    localparam [2:0] CLASS_MULDIV     = 3'd1;
    localparam [2:0] CLASS_LSU        = 3'd2;
    localparam [2:0] CLASS_CONTROL    = 3'd3;
    localparam [2:0] CLASS_INVALID    = 3'd4;

    wire [3:0] pending_valid;
    wire [3:0][4:0] pending_rd;

    assign pending_valid[0] = id_ex_valid[0] && id_ex_writes_rd[0] &&
                              (id_ex_rd_addr[0] != 5'd0);
    assign pending_valid[1] = id_ex_valid[1] && id_ex_writes_rd[1] &&
                              (id_ex_rd_addr[1] != 5'd0);
    assign pending_valid[2] = ex_mem_valid[0] && ex_mem_writes_rd[0] &&
                              (ex_mem_rd_addr[0] != 5'd0);
    assign pending_valid[3] = ex_mem_valid[1] && ex_mem_writes_rd[1] &&
                              (ex_mem_rd_addr[1] != 5'd0);

    assign pending_rd[0] = id_ex_rd_addr[0];
    assign pending_rd[1] = id_ex_rd_addr[1];
    assign pending_rd[2] = ex_mem_rd_addr[0];
    assign pending_rd[3] = ex_mem_rd_addr[1];

    wire slot0_rs1_raw = slot_rs1_used[0] && (slot_rs1_addr[0] != 5'd0) &&
        ((pending_valid[0] && (slot_rs1_addr[0] == pending_rd[0])) ||
         (pending_valid[1] && (slot_rs1_addr[0] == pending_rd[1])) ||
         (pending_valid[2] && (slot_rs1_addr[0] == pending_rd[2])) ||
         (pending_valid[3] && (slot_rs1_addr[0] == pending_rd[3])));

    wire slot0_rs2_raw = slot_rs2_used[0] && (slot_rs2_addr[0] != 5'd0) &&
        ((pending_valid[0] && (slot_rs2_addr[0] == pending_rd[0])) ||
         (pending_valid[1] && (slot_rs2_addr[0] == pending_rd[1])) ||
         (pending_valid[2] && (slot_rs2_addr[0] == pending_rd[2])) ||
         (pending_valid[3] && (slot_rs2_addr[0] == pending_rd[3])));

    wire slot1_rs1_raw = slot_rs1_used[1] && (slot_rs1_addr[1] != 5'd0) &&
        ((pending_valid[0] && (slot_rs1_addr[1] == pending_rd[0])) ||
         (pending_valid[1] && (slot_rs1_addr[1] == pending_rd[1])) ||
         (pending_valid[2] && (slot_rs1_addr[1] == pending_rd[2])) ||
         (pending_valid[3] && (slot_rs1_addr[1] == pending_rd[3])));

    wire slot1_rs2_raw = slot_rs2_used[1] && (slot_rs2_addr[1] != 5'd0) &&
        ((pending_valid[0] && (slot_rs2_addr[1] == pending_rd[0])) ||
         (pending_valid[1] && (slot_rs2_addr[1] == pending_rd[1])) ||
         (pending_valid[2] && (slot_rs2_addr[1] == pending_rd[2])) ||
         (pending_valid[3] && (slot_rs2_addr[1] == pending_rd[3])));

    assign slot0_old_raw = slot_valid[0] && (slot0_rs1_raw || slot0_rs2_raw);
    assign slot1_old_raw = slot_valid[1] && (slot1_rs1_raw || slot1_rs2_raw);

    // Only a younger read of the older instruction's destination is an
    // intra-pair dependency.  WAW and WAR pairs remain legal and ordered.
    assign intra_pair_raw = slot_valid[0] && slot_valid[1] &&
                            slot_writes_rd[0] &&
                            (slot_rd_addr[0] != 5'd0) &&
        ((slot_rs1_used[1] && (slot_rs1_addr[1] == slot_rd_addr[0])) ||
         (slot_rs2_used[1] && (slot_rs2_addr[1] == slot_rd_addr[0])));

    wire both_simple = (slot_class[0] == CLASS_SIMPLE_INT) &&
                       (slot_class[1] == CLASS_SIMPLE_INT);

    assign structural_pair_block = slot_valid[0] && slot_valid[1] &&
                                   !both_simple;
    assign data_hazard_stall = slot_valid[0] && slot0_old_raw;

    always @(*) begin
        issue_valid = 2'b00;
        consume_count = 2'd0;

        if (backend_ready && !kill_issue && slot_valid[0] &&
            !slot0_old_raw) begin
            issue_valid[0] = 1'b1;
            consume_count = 2'd1;

            if ((ISSUE_WIDTH == 2) && slot_valid[1] && both_simple &&
                !slot1_old_raw && !intra_pair_raw) begin
                issue_valid[1] = 1'b1;
                consume_count = 2'd2;
            end
        end

        // synthesis translate_off
        if (slot_valid[1] && !slot_valid[0])
            $error("issue_control received lane1 without the older lane0");
        if (issue_valid[1] && !issue_valid[0])
            $error("issue_control issued lane1 without lane0");
        if ((consume_count != {1'b0, issue_valid[0]} +
                              {1'b0, issue_valid[1]}))
            $error("issue_control consume_count does not match issue_valid");
        if (issue_valid[1] && (!both_simple || slot1_old_raw ||
                              intra_pair_raw || (ISSUE_WIDTH != 2)))
            $error("issue_control emitted an illegal dual-issue pair");
        if ((|issue_valid) && (!backend_ready || kill_issue))
            $error("issue_control issued while backend was blocked or killed");
        if ((ISSUE_WIDTH == 1) && issue_valid[1])
            $error("issue_control lane1 active in single-issue mode");
        // synthesis translate_on
    end

    assign pair_serialize = issue_valid[0] && slot_valid[1] &&
                            !issue_valid[1];

    // synthesis translate_off
    initial begin
        if ((ISSUE_WIDTH != 1) && (ISSUE_WIDTH != 2))
            $fatal(1, "issue_control ISSUE_WIDTH must be 1 or 2");
        if ((CLASS_MULDIV == CLASS_SIMPLE_INT) ||
            (CLASS_LSU == CLASS_SIMPLE_INT) ||
            (CLASS_CONTROL == CLASS_SIMPLE_INT) ||
            (CLASS_INVALID == CLASS_SIMPLE_INT))
            $fatal(1, "issue_control instruction class encoding collision");
    end
    // synthesis translate_on

endmodule
