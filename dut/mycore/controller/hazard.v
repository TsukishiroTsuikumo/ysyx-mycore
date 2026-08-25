`timescale 1ns/1ps

module hazard (
    input             backend_ready,
    input             kill_issue,
    input             slot0_valid,
    input             slot1_valid,
    input       [2:0] slot0_class,
    input       [2:0] slot1_class,
    input             slot0_rs1_used,
    input             slot0_rs2_used,
    input             slot1_rs1_used,
    input             slot1_rs2_used,
    input       [4:0] slot0_rs1_addr,
    input       [4:0] slot0_rs2_addr,
    input       [4:0] slot1_rs1_addr,
    input       [4:0] slot1_rs2_addr,
    input             slot0_writes_rd,
    input             slot1_writes_rd,
    input       [4:0] slot0_rd_addr,
    input       [4:0] slot1_rd_addr,
    input             id_ex_valid0,
    input             id_ex_valid1,
    input             id_ex_writes_rd0,
    input             id_ex_writes_rd1,
    input       [4:0] id_ex_rd_addr0,
    input       [4:0] id_ex_rd_addr1,
    input             ex_mem_valid0,
    input             ex_mem_valid1,
    input             ex_mem_writes_rd0,
    input             ex_mem_writes_rd1,
    input       [4:0] ex_mem_rd_addr0,
    input       [4:0] ex_mem_rd_addr1,
    output reg  [1:0] issue_valid,
    output reg  [1:0] consume_count,
    output            slot0_old_raw,
    output            slot1_old_raw,
    output            intra_pair_raw,
    output            structural_pair_block,
    output            data_hazard_stall,
    output            pair_serialize
);

    localparam [2:0] CLASS_SIMPLE_INT = 3'd0;

    wire pending0;
    wire pending1;
    wire pending2;
    wire pending3;
    wire slot0_rs1_raw;
    wire slot0_rs2_raw;
    wire slot1_rs1_raw;
    wire slot1_rs2_raw;
    wire both_simple;

    assign pending0 = id_ex_valid0 && id_ex_writes_rd0 &&
                      (id_ex_rd_addr0 != 5'd0);
    assign pending1 = id_ex_valid1 && id_ex_writes_rd1 &&
                      (id_ex_rd_addr1 != 5'd0);
    assign pending2 = ex_mem_valid0 && ex_mem_writes_rd0 &&
                      (ex_mem_rd_addr0 != 5'd0);
    assign pending3 = ex_mem_valid1 && ex_mem_writes_rd1 &&
                      (ex_mem_rd_addr1 != 5'd0);

    assign slot0_rs1_raw = slot0_rs1_used && (slot0_rs1_addr != 5'd0) &&
        ((pending0 && (slot0_rs1_addr == id_ex_rd_addr0)) ||
         (pending1 && (slot0_rs1_addr == id_ex_rd_addr1)) ||
         (pending2 && (slot0_rs1_addr == ex_mem_rd_addr0)) ||
         (pending3 && (slot0_rs1_addr == ex_mem_rd_addr1)));
    assign slot0_rs2_raw = slot0_rs2_used && (slot0_rs2_addr != 5'd0) &&
        ((pending0 && (slot0_rs2_addr == id_ex_rd_addr0)) ||
         (pending1 && (slot0_rs2_addr == id_ex_rd_addr1)) ||
         (pending2 && (slot0_rs2_addr == ex_mem_rd_addr0)) ||
         (pending3 && (slot0_rs2_addr == ex_mem_rd_addr1)));
    assign slot1_rs1_raw = slot1_rs1_used && (slot1_rs1_addr != 5'd0) &&
        ((pending0 && (slot1_rs1_addr == id_ex_rd_addr0)) ||
         (pending1 && (slot1_rs1_addr == id_ex_rd_addr1)) ||
         (pending2 && (slot1_rs1_addr == ex_mem_rd_addr0)) ||
         (pending3 && (slot1_rs1_addr == ex_mem_rd_addr1)));
    assign slot1_rs2_raw = slot1_rs2_used && (slot1_rs2_addr != 5'd0) &&
        ((pending0 && (slot1_rs2_addr == id_ex_rd_addr0)) ||
         (pending1 && (slot1_rs2_addr == id_ex_rd_addr1)) ||
         (pending2 && (slot1_rs2_addr == ex_mem_rd_addr0)) ||
         (pending3 && (slot1_rs2_addr == ex_mem_rd_addr1)));

    assign slot0_old_raw = slot0_valid && (slot0_rs1_raw || slot0_rs2_raw);
    assign slot1_old_raw = slot1_valid && (slot1_rs1_raw || slot1_rs2_raw);
    assign intra_pair_raw = slot0_valid && slot1_valid &&
                            slot0_writes_rd && (slot0_rd_addr != 5'd0) &&
        ((slot1_rs1_used && (slot1_rs1_addr == slot0_rd_addr)) ||
         (slot1_rs2_used && (slot1_rs2_addr == slot0_rd_addr)));
    assign both_simple = (slot0_class == CLASS_SIMPLE_INT) &&
                         (slot1_class == CLASS_SIMPLE_INT);
    assign structural_pair_block = slot0_valid && slot1_valid && !both_simple;
    assign data_hazard_stall = slot0_valid && slot0_old_raw;

    always @(*) begin
        issue_valid = 2'b00;
        consume_count = 2'd0;
        if (backend_ready && !kill_issue && slot0_valid &&
            !slot0_old_raw) begin
            issue_valid[0] = 1'b1;
            consume_count = 2'd1;
            if (slot1_valid && both_simple && !slot1_old_raw &&
                !intra_pair_raw) begin
                issue_valid[1] = 1'b1;
                consume_count = 2'd2;
            end
        end
    end

    assign pair_serialize = issue_valid[0] && slot1_valid &&
                            !issue_valid[1];

endmodule
