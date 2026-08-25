`timescale 1ns/1ps

// Forty-eight-entry physical register file used by the bounded OoO backend.
// Architectural reset mappings p0..p31 start ready; rename-only registers
// p32..p47 start free and not ready.  Allocation has priority over a CDB
// write to the same tag so a newly renamed destination cannot inherit stale
// readiness when a physical tag is recycled.
module reg_R (
    input             clk,
    input             reset,

    input       [5:0] read0_tag_in,
    output     [31:0] read0_data_out,
    output            read0_ready_out,
    input       [5:0] read1_tag_in,
    output     [31:0] read1_data_out,
    output            read1_ready_out,
    input       [5:0] read2_tag_in,
    output     [31:0] read2_data_out,
    output            read2_ready_out,
    input       [5:0] read3_tag_in,
    output     [31:0] read3_data_out,
    output            read3_ready_out,

    input             allocate0_en_in,
    input       [5:0] allocate0_tag_in,
    input             allocate1_en_in,
    input       [5:0] allocate1_tag_in,

    input             cdb0_en_in,
    input       [5:0] cdb0_tag_in,
    input      [31:0] cdb0_data_in,
    input             cdb1_en_in,
    input       [5:0] cdb1_tag_in,
    input      [31:0] cdb1_data_in
);

    localparam [5:0] PHYS_REG_COUNT = 6'd48;

    reg [31:0] reg_value [0:47];
    reg        reg_ready [0:47];
    integer reset_index;

    wire read0_allocating;
    wire read1_allocating;
    wire read2_allocating;
    wire read3_allocating;
    wire read0_cdb0;
    wire read0_cdb1;
    wire read1_cdb0;
    wire read1_cdb1;
    wire read2_cdb0;
    wire read2_cdb1;
    wire read3_cdb0;
    wire read3_cdb1;

    assign read0_allocating =
        (allocate0_en_in && (allocate0_tag_in == read0_tag_in)) ||
        (allocate1_en_in && (allocate1_tag_in == read0_tag_in));
    assign read1_allocating =
        (allocate0_en_in && (allocate0_tag_in == read1_tag_in)) ||
        (allocate1_en_in && (allocate1_tag_in == read1_tag_in));
    assign read2_allocating =
        (allocate0_en_in && (allocate0_tag_in == read2_tag_in)) ||
        (allocate1_en_in && (allocate1_tag_in == read2_tag_in));
    assign read3_allocating =
        (allocate0_en_in && (allocate0_tag_in == read3_tag_in)) ||
        (allocate1_en_in && (allocate1_tag_in == read3_tag_in));

    assign read0_cdb0 = cdb0_en_in && (cdb0_tag_in == read0_tag_in);
    assign read0_cdb1 = cdb1_en_in && (cdb1_tag_in == read0_tag_in);
    assign read1_cdb0 = cdb0_en_in && (cdb0_tag_in == read1_tag_in);
    assign read1_cdb1 = cdb1_en_in && (cdb1_tag_in == read1_tag_in);
    assign read2_cdb0 = cdb0_en_in && (cdb0_tag_in == read2_tag_in);
    assign read2_cdb1 = cdb1_en_in && (cdb1_tag_in == read2_tag_in);
    assign read3_cdb0 = cdb0_en_in && (cdb0_tag_in == read3_tag_in);
    assign read3_cdb1 = cdb1_en_in && (cdb1_tag_in == read3_tag_in);

    // CDB1 wins the impossible same-tag dual-CDB collision, matching the
    // registered write ordering below.  Allocation suppresses both bypasses.
    assign read0_data_out = (read0_tag_in == 6'd0) ? 32'b0 :
        read0_allocating ? 32'b0 :
        read0_cdb1 ? cdb1_data_in :
        read0_cdb0 ? cdb0_data_in :
        (read0_tag_in < PHYS_REG_COUNT) ? reg_value[read0_tag_in] : 32'b0;
    assign read1_data_out = (read1_tag_in == 6'd0) ? 32'b0 :
        read1_allocating ? 32'b0 :
        read1_cdb1 ? cdb1_data_in :
        read1_cdb0 ? cdb0_data_in :
        (read1_tag_in < PHYS_REG_COUNT) ? reg_value[read1_tag_in] : 32'b0;
    assign read2_data_out = (read2_tag_in == 6'd0) ? 32'b0 :
        read2_allocating ? 32'b0 :
        read2_cdb1 ? cdb1_data_in :
        read2_cdb0 ? cdb0_data_in :
        (read2_tag_in < PHYS_REG_COUNT) ? reg_value[read2_tag_in] : 32'b0;
    assign read3_data_out = (read3_tag_in == 6'd0) ? 32'b0 :
        read3_allocating ? 32'b0 :
        read3_cdb1 ? cdb1_data_in :
        read3_cdb0 ? cdb0_data_in :
        (read3_tag_in < PHYS_REG_COUNT) ? reg_value[read3_tag_in] : 32'b0;

    assign read0_ready_out = (read0_tag_in == 6'd0) ? 1'b1 :
        (read0_tag_in >= PHYS_REG_COUNT) ? 1'b0 :
        read0_allocating ? 1'b0 :
        (read0_cdb1 || read0_cdb0) ? 1'b1 : reg_ready[read0_tag_in];
    assign read1_ready_out = (read1_tag_in == 6'd0) ? 1'b1 :
        (read1_tag_in >= PHYS_REG_COUNT) ? 1'b0 :
        read1_allocating ? 1'b0 :
        (read1_cdb1 || read1_cdb0) ? 1'b1 : reg_ready[read1_tag_in];
    assign read2_ready_out = (read2_tag_in == 6'd0) ? 1'b1 :
        (read2_tag_in >= PHYS_REG_COUNT) ? 1'b0 :
        read2_allocating ? 1'b0 :
        (read2_cdb1 || read2_cdb0) ? 1'b1 : reg_ready[read2_tag_in];
    assign read3_ready_out = (read3_tag_in == 6'd0) ? 1'b1 :
        (read3_tag_in >= PHYS_REG_COUNT) ? 1'b0 :
        read3_allocating ? 1'b0 :
        (read3_cdb1 || read3_cdb0) ? 1'b1 : reg_ready[read3_tag_in];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (reset_index = 0; reset_index < 48;
                 reset_index = reset_index + 1) begin
                reg_value[reset_index] <= 32'b0;
                if (reset_index < 32)
                    reg_ready[reset_index] <= 1'b1;
                else
                    reg_ready[reset_index] <= 1'b0;
            end
        end
        else begin
            if (cdb0_en_in && (cdb0_tag_in != 6'd0) &&
                (cdb0_tag_in < PHYS_REG_COUNT)) begin
                reg_value[cdb0_tag_in] <= cdb0_data_in;
                reg_ready[cdb0_tag_in] <= 1'b1;
            end
            if (cdb1_en_in && (cdb1_tag_in != 6'd0) &&
                (cdb1_tag_in < PHYS_REG_COUNT)) begin
                reg_value[cdb1_tag_in] <= cdb1_data_in;
                reg_ready[cdb1_tag_in] <= 1'b1;
            end

            if (allocate0_en_in && (allocate0_tag_in != 6'd0) &&
                (allocate0_tag_in < PHYS_REG_COUNT)) begin
                reg_ready[allocate0_tag_in] <= 1'b0;
            end
            if (allocate1_en_in && (allocate1_tag_in != 6'd0) &&
                (allocate1_tag_in < PHYS_REG_COUNT)) begin
                reg_ready[allocate1_tag_in] <= 1'b0;
            end

            reg_value[0] <= 32'b0;
            reg_ready[0] <= 1'b1;
        end
    end

`ifndef SYNTHESIS
    task write_phys_reg;
        input [5:0] address;
        input [31:0] data;
        begin
            if (address == 6'd0) begin
                reg_value[0] = 32'b0;
                reg_ready[0] = 1'b1;
            end
            else if (address < PHYS_REG_COUNT) begin
                reg_value[address] = data;
                reg_ready[address] = 1'b1;
            end
        end
    endtask

    task read_phys_reg;
        input [5:0] address;
        output [31:0] data;
        begin
            if (address == 6'd0)
                data = 32'b0;
            else if (address < PHYS_REG_COUNT)
                data = reg_value[address];
            else
                data = 32'b0;
        end
    endtask
`endif

endmodule
