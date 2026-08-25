`timescale 1ns/1ps

// Fixed two-lane common-data-bus arbitration.  Non-backpressurable memory
// completion and held mul/div completion have priority over combinational
// integer candidates.
module cdb_arbiter (
    input             load_valid,
    input       [2:0] load_rob,
    input             load_writes,
    input       [5:0] load_pdst,
    input      [31:0] load_value,
    input             load_control,
    input      [31:0] load_target,
    input             load_mispredict,

    input             muldiv_valid,
    input       [2:0] muldiv_rob,
    input             muldiv_writes,
    input       [5:0] muldiv_pdst,
    input      [31:0] muldiv_value,
    input             muldiv_control,
    input      [31:0] muldiv_target,
    input             muldiv_mispredict,

    input             int0_valid,
    input       [2:0] int0_rob,
    input             int0_writes,
    input       [5:0] int0_pdst,
    input      [31:0] int0_value,
    input             int0_control,
    input      [31:0] int0_target,
    input             int0_mispredict,

    input             int1_valid,
    input       [2:0] int1_rob,
    input             int1_writes,
    input       [5:0] int1_pdst,
    input      [31:0] int1_value,
    input             int1_control,
    input      [31:0] int1_target,
    input             int1_mispredict,

    output reg        cdb0_valid,
    output reg  [2:0] cdb0_rob,
    output reg        cdb0_writes,
    output reg  [5:0] cdb0_pdst,
    output reg [31:0] cdb0_value,
    output reg        cdb0_control,
    output reg [31:0] cdb0_target,
    output reg        cdb0_mispredict,

    output reg        cdb1_valid,
    output reg  [2:0] cdb1_rob,
    output reg        cdb1_writes,
    output reg  [5:0] cdb1_pdst,
    output reg [31:0] cdb1_value,
    output reg        cdb1_control,
    output reg [31:0] cdb1_target,
    output reg        cdb1_mispredict,

    output reg        load_grant,
    output reg        muldiv_grant,
    output reg        int0_grant,
    output reg        int1_grant
);

    always @(*) begin
        cdb0_valid = 1'b0;
        cdb0_rob = 3'b0;
        cdb0_writes = 1'b0;
        cdb0_pdst = 6'b0;
        cdb0_value = 32'b0;
        cdb0_control = 1'b0;
        cdb0_target = 32'b0;
        cdb0_mispredict = 1'b0;

        cdb1_valid = 1'b0;
        cdb1_rob = 3'b0;
        cdb1_writes = 1'b0;
        cdb1_pdst = 6'b0;
        cdb1_value = 32'b0;
        cdb1_control = 1'b0;
        cdb1_target = 32'b0;
        cdb1_mispredict = 1'b0;

        load_grant = 1'b0;
        muldiv_grant = 1'b0;
        int0_grant = 1'b0;
        int1_grant = 1'b0;

        if (load_valid) begin
            cdb0_valid = 1'b1;
            cdb0_rob = load_rob;
            cdb0_writes = load_writes;
            cdb0_pdst = load_pdst;
            cdb0_value = load_value;
            cdb0_control = load_control;
            cdb0_target = load_target;
            cdb0_mispredict = load_mispredict;
            load_grant = 1'b1;
        end
        else if (muldiv_valid) begin
            cdb0_valid = 1'b1;
            cdb0_rob = muldiv_rob;
            cdb0_writes = muldiv_writes;
            cdb0_pdst = muldiv_pdst;
            cdb0_value = muldiv_value;
            cdb0_control = muldiv_control;
            cdb0_target = muldiv_target;
            cdb0_mispredict = muldiv_mispredict;
            muldiv_grant = 1'b1;
        end
        else if (int0_valid) begin
            cdb0_valid = 1'b1;
            cdb0_rob = int0_rob;
            cdb0_writes = int0_writes;
            cdb0_pdst = int0_pdst;
            cdb0_value = int0_value;
            cdb0_control = int0_control;
            cdb0_target = int0_target;
            cdb0_mispredict = int0_mispredict;
            int0_grant = 1'b1;
        end
        else if (int1_valid) begin
            cdb0_valid = 1'b1;
            cdb0_rob = int1_rob;
            cdb0_writes = int1_writes;
            cdb0_pdst = int1_pdst;
            cdb0_value = int1_value;
            cdb0_control = int1_control;
            cdb0_target = int1_target;
            cdb0_mispredict = int1_mispredict;
            int1_grant = 1'b1;
        end

        if (load_valid) begin
            if (muldiv_valid) begin
                cdb1_valid = 1'b1;
                cdb1_rob = muldiv_rob;
                cdb1_writes = muldiv_writes;
                cdb1_pdst = muldiv_pdst;
                cdb1_value = muldiv_value;
                cdb1_control = muldiv_control;
                cdb1_target = muldiv_target;
                cdb1_mispredict = muldiv_mispredict;
                muldiv_grant = 1'b1;
            end
            else if (int0_valid) begin
                cdb1_valid = 1'b1;
                cdb1_rob = int0_rob;
                cdb1_writes = int0_writes;
                cdb1_pdst = int0_pdst;
                cdb1_value = int0_value;
                cdb1_control = int0_control;
                cdb1_target = int0_target;
                cdb1_mispredict = int0_mispredict;
                int0_grant = 1'b1;
            end
            else if (int1_valid) begin
                cdb1_valid = 1'b1;
                cdb1_rob = int1_rob;
                cdb1_writes = int1_writes;
                cdb1_pdst = int1_pdst;
                cdb1_value = int1_value;
                cdb1_control = int1_control;
                cdb1_target = int1_target;
                cdb1_mispredict = int1_mispredict;
                int1_grant = 1'b1;
            end
        end
        else if (muldiv_valid) begin
            if (int0_valid) begin
                cdb1_valid = 1'b1;
                cdb1_rob = int0_rob;
                cdb1_writes = int0_writes;
                cdb1_pdst = int0_pdst;
                cdb1_value = int0_value;
                cdb1_control = int0_control;
                cdb1_target = int0_target;
                cdb1_mispredict = int0_mispredict;
                int0_grant = 1'b1;
            end
            else if (int1_valid) begin
                cdb1_valid = 1'b1;
                cdb1_rob = int1_rob;
                cdb1_writes = int1_writes;
                cdb1_pdst = int1_pdst;
                cdb1_value = int1_value;
                cdb1_control = int1_control;
                cdb1_target = int1_target;
                cdb1_mispredict = int1_mispredict;
                int1_grant = 1'b1;
            end
        end
        else if (int0_valid && int1_valid) begin
            cdb1_valid = 1'b1;
            cdb1_rob = int1_rob;
            cdb1_writes = int1_writes;
            cdb1_pdst = int1_pdst;
            cdb1_value = int1_value;
            cdb1_control = int1_control;
            cdb1_target = int1_target;
            cdb1_mispredict = int1_mispredict;
            int1_grant = 1'b1;
        end
    end

endmodule
