`timescale 1ns/1ps

module ooo_rat_tb;
    logic clk;
    logic reset;

    logic        recovery;
    logic [1:0]  dispatch_count;
    logic        src0_1_used;
    logic [4:0]  src0_1_addr;
    wire  [5:0]  src0_1_tag;
    logic        src0_2_used;
    logic [4:0]  src0_2_addr;
    wire  [5:0]  src0_2_tag;
    logic        src1_1_used;
    logic [4:0]  src1_1_addr;
    wire  [5:0]  src1_1_tag;
    logic        src1_2_used;
    logic [4:0]  src1_2_addr;
    wire  [5:0]  src1_2_tag;
    logic        dst0_writes;
    logic [4:0]  dst0_arch;
    wire  [5:0]  new_pdst0;
    wire  [5:0]  old_pdst0;
    logic        dst1_writes;
    logic [4:0]  dst1_arch;
    wire  [5:0]  new_pdst1;
    wire  [5:0]  old_pdst1;
    wire  [5:0]  free_count;
    logic        commit0_valid;
    logic        commit0_writes;
    logic [4:0]  commit0_arch;
    logic [5:0]  commit0_pdst;
    logic [5:0]  commit0_old_pdst;
    logic        commit1_valid;
    logic        commit1_writes;
    logic [4:0]  commit1_arch;
    logic [5:0]  commit1_pdst;
    logic [5:0]  commit1_old_pdst;

    logic [5:0]  prf_read0_tag;
    wire [31:0]  prf_read0_data;
    wire         prf_read0_ready;
    logic [5:0]  prf_read1_tag;
    wire [31:0]  prf_read1_data;
    wire         prf_read1_ready;
    logic [5:0]  prf_read2_tag;
    wire [31:0]  prf_read2_data;
    wire         prf_read2_ready;
    logic [5:0]  prf_read3_tag;
    wire [31:0]  prf_read3_data;
    wire         prf_read3_ready;
    logic        prf_allocate0_en;
    logic [5:0]  prf_allocate0_tag;
    logic        prf_allocate1_en;
    logic [5:0]  prf_allocate1_tag;
    logic        prf_cdb0_en;
    logic [5:0]  prf_cdb0_tag;
    logic [31:0] prf_cdb0_data;
    logic        prf_cdb1_en;
    logic [5:0]  prf_cdb1_tag;
    logic [31:0] prf_cdb1_data;

    reg [5:0] observed_amt_tag;

    rat rat_dut (
        .clk                 (clk),
        .reset               (reset),
        .recovery_in         (recovery),
        .dispatch_count_in   (dispatch_count),
        .src0_1_used_in      (src0_1_used),
        .src0_1_addr_in      (src0_1_addr),
        .src0_1_tag_out      (src0_1_tag),
        .src0_2_used_in      (src0_2_used),
        .src0_2_addr_in      (src0_2_addr),
        .src0_2_tag_out      (src0_2_tag),
        .src1_1_used_in      (src1_1_used),
        .src1_1_addr_in      (src1_1_addr),
        .src1_1_tag_out      (src1_1_tag),
        .src1_2_used_in      (src1_2_used),
        .src1_2_addr_in      (src1_2_addr),
        .src1_2_tag_out      (src1_2_tag),
        .dst0_writes_in      (dst0_writes),
        .dst0_arch_in        (dst0_arch),
        .new_pdst0_out       (new_pdst0),
        .old_pdst0_out       (old_pdst0),
        .dst1_writes_in      (dst1_writes),
        .dst1_arch_in        (dst1_arch),
        .new_pdst1_out       (new_pdst1),
        .old_pdst1_out       (old_pdst1),
        .free_count_out      (free_count),
        .commit0_valid_in    (commit0_valid),
        .commit0_writes_in   (commit0_writes),
        .commit0_arch_in     (commit0_arch),
        .commit0_pdst_in     (commit0_pdst),
        .commit0_old_pdst_in (commit0_old_pdst),
        .commit1_valid_in    (commit1_valid),
        .commit1_writes_in   (commit1_writes),
        .commit1_arch_in     (commit1_arch),
        .commit1_pdst_in     (commit1_pdst),
        .commit1_old_pdst_in (commit1_old_pdst)
    );

    reg_R prf_dut (
        .clk              (clk),
        .reset            (reset),
        .read0_tag_in     (prf_read0_tag),
        .read0_data_out   (prf_read0_data),
        .read0_ready_out  (prf_read0_ready),
        .read1_tag_in     (prf_read1_tag),
        .read1_data_out   (prf_read1_data),
        .read1_ready_out  (prf_read1_ready),
        .read2_tag_in     (prf_read2_tag),
        .read2_data_out   (prf_read2_data),
        .read2_ready_out  (prf_read2_ready),
        .read3_tag_in     (prf_read3_tag),
        .read3_data_out   (prf_read3_data),
        .read3_ready_out  (prf_read3_ready),
        .allocate0_en_in  (prf_allocate0_en),
        .allocate0_tag_in (prf_allocate0_tag),
        .allocate1_en_in  (prf_allocate1_en),
        .allocate1_tag_in (prf_allocate1_tag),
        .cdb0_en_in       (prf_cdb0_en),
        .cdb0_tag_in      (prf_cdb0_tag),
        .cdb0_data_in     (prf_cdb0_data),
        .cdb1_en_in       (prf_cdb1_en),
        .cdb1_tag_in      (prf_cdb1_tag),
        .cdb1_data_in     (prf_cdb1_data)
    );

    task automatic clear_rat_inputs;
        begin
            recovery = 1'b0;
            dispatch_count = 2'd0;
            src0_1_used = 1'b0;
            src0_1_addr = 5'd0;
            src0_2_used = 1'b0;
            src0_2_addr = 5'd0;
            src1_1_used = 1'b0;
            src1_1_addr = 5'd0;
            src1_2_used = 1'b0;
            src1_2_addr = 5'd0;
            dst0_writes = 1'b0;
            dst0_arch = 5'd0;
            dst1_writes = 1'b0;
            dst1_arch = 5'd0;
            commit0_valid = 1'b0;
            commit0_writes = 1'b0;
            commit0_arch = 5'd0;
            commit0_pdst = 6'd0;
            commit0_old_pdst = 6'd0;
            commit1_valid = 1'b0;
            commit1_writes = 1'b0;
            commit1_arch = 5'd0;
            commit1_pdst = 6'd0;
            commit1_old_pdst = 6'd0;
        end
    endtask

    task automatic clear_prf_inputs;
        begin
            prf_read0_tag = 6'd0;
            prf_read1_tag = 6'd0;
            prf_read2_tag = 6'd0;
            prf_read3_tag = 6'd0;
            prf_allocate0_en = 1'b0;
            prf_allocate0_tag = 6'd0;
            prf_allocate1_en = 1'b0;
            prf_allocate1_tag = 6'd0;
            prf_cdb0_en = 1'b0;
            prf_cdb0_tag = 6'd0;
            prf_cdb0_data = 32'd0;
            prf_cdb1_en = 1'b0;
            prf_cdb1_tag = 6'd0;
            prf_cdb1_data = 32'd0;
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        clear_rat_inputs();
        clear_prf_inputs();

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        #1;

        // Reset establishes the architectural identity map and sixteen free
        // rename-only registers.  PRF p0..p31 are ready; p32 is not.
        if (free_count !== 6'd16)
            $fatal(1, "reset RAT free count got=%0d expected=16", free_count);
        src0_1_used = 1'b1;
        src0_1_addr = 5'd0;
        src0_2_used = 1'b1;
        src0_2_addr = 5'd7;
        prf_read0_tag = 6'd0;
        prf_read1_tag = 6'd31;
        prf_read2_tag = 6'd32;
        prf_read3_tag = 6'd47;
        #1;
        if ((src0_1_tag !== 6'd0) || (src0_2_tag !== 6'd7))
            $fatal(1, "reset RAT identity/x0 mapping mismatch");
        if ((prf_read0_data !== 32'd0) || !prf_read0_ready ||
            (prf_read1_data !== 32'd0) || !prf_read1_ready ||
            (prf_read2_data !== 32'd0) || prf_read2_ready ||
            (prf_read3_data !== 32'd0) || prf_read3_ready)
            $fatal(1, "reset PRF ready/x0 state mismatch");

        // Two destinations allocate distinct lowest free physical registers.
        @(negedge clk);
        clear_rat_inputs();
        dispatch_count = 2'd2;
        dst0_writes = 1'b1;
        dst0_arch = 5'd5;
        dst1_writes = 1'b1;
        dst1_arch = 5'd6;
        #1;
        if ((new_pdst0 !== 6'd32) || (old_pdst0 !== 6'd5) ||
            (new_pdst1 !== 6'd33) || (old_pdst1 !== 6'd6))
            $fatal(1, "dual allocation tags mismatch new=%0d/%0d old=%0d/%0d",
                   new_pdst0, new_pdst1, old_pdst0, old_pdst1);
        @(posedge clk);
        #1;
        if (free_count !== 6'd14)
            $fatal(1, "dual allocation free count got=%0d expected=14",
                   free_count);

        // Lane 1 reads lane 0's new mapping, and a lane-1 WAW observes that
        // same new mapping as its old destination.
        @(negedge clk);
        clear_rat_inputs();
        dispatch_count = 2'd2;
        dst0_writes = 1'b1;
        dst0_arch = 5'd10;
        dst1_writes = 1'b1;
        dst1_arch = 5'd10;
        src1_1_used = 1'b1;
        src1_1_addr = 5'd10;
        #1;
        if ((new_pdst0 !== 6'd34) || (new_pdst1 !== 6'd35) ||
            (src1_1_tag !== 6'd34) || (old_pdst0 !== 6'd10) ||
            (old_pdst1 !== 6'd34))
            $fatal(1, "same-packet RAW/WAW forwarding mismatch");
        @(posedge clk);
        #1;
        src0_1_used = 1'b1;
        src0_1_addr = 5'd10;
        #1;
        if ((src0_1_tag !== 6'd35) || (free_count !== 6'd12))
            $fatal(1, "WAW final RAT mapping/free count mismatch");

        // Two independent commits update both AMT entries and release both
        // superseded architectural reset mappings in one cycle.
        @(negedge clk);
        clear_rat_inputs();
        commit0_valid = 1'b1;
        commit0_writes = 1'b1;
        commit0_arch = 5'd5;
        commit0_pdst = 6'd32;
        commit0_old_pdst = 6'd5;
        commit1_valid = 1'b1;
        commit1_writes = 1'b1;
        commit1_arch = 5'd6;
        commit1_pdst = 6'd33;
        commit1_old_pdst = 6'd6;
        @(posedge clk);
        #1;
        rat_dut.read_amt(5'd5, observed_amt_tag);
        if (observed_amt_tag !== 6'd32)
            $fatal(1, "dual commit AMT x5 mismatch got=%0d", observed_amt_tag);
        rat_dut.read_amt(5'd6, observed_amt_tag);
        if (observed_amt_tag !== 6'd33)
            $fatal(1, "dual commit AMT x6 mismatch got=%0d", observed_amt_tag);
        if (free_count !== 6'd14)
            $fatal(1, "dual commit free count got=%0d expected=14", free_count);

        // Commit the WAW pair in order: the younger lane must win AMT and the
        // intermediate physical destination must become free.
        @(negedge clk);
        clear_rat_inputs();
        commit0_valid = 1'b1;
        commit0_writes = 1'b1;
        commit0_arch = 5'd10;
        commit0_pdst = 6'd34;
        commit0_old_pdst = 6'd10;
        commit1_valid = 1'b1;
        commit1_writes = 1'b1;
        commit1_arch = 5'd10;
        commit1_pdst = 6'd35;
        commit1_old_pdst = 6'd34;
        @(posedge clk);
        #1;
        rat_dut.read_amt(5'd10, observed_amt_tag);
        if ((observed_amt_tag !== 6'd35) || (free_count !== 6'd16))
            $fatal(1, "ordered WAW commit mismatch amt=%0d free=%0d",
                   observed_amt_tag, free_count);

        // Allocate a recovering control destination followed by two younger
        // speculative destinations.  The current free-list order is known.
        @(negedge clk);
        clear_rat_inputs();
        dispatch_count = 2'd1;
        dst0_writes = 1'b1;
        dst0_arch = 5'd11;
        #1;
        if ((new_pdst0 !== 6'd5) || (old_pdst0 !== 6'd11))
            $fatal(1, "recovery control allocation mismatch");
        @(posedge clk);
        #1;

        @(negedge clk);
        clear_rat_inputs();
        dispatch_count = 2'd2;
        dst0_writes = 1'b1;
        dst0_arch = 5'd12;
        dst1_writes = 1'b1;
        dst1_arch = 5'd13;
        #1;
        if ((new_pdst0 !== 6'd6) || (new_pdst1 !== 6'd10))
            $fatal(1, "younger speculative allocation mismatch");
        @(posedge clk);
        #1;
        if (free_count !== 6'd13)
            $fatal(1, "pre-recovery free count got=%0d expected=13", free_count);

        // Recovery applies the retiring control's commit to AMT first, then
        // rebuilds RAT/free state and discards the younger speculative maps.
        @(negedge clk);
        clear_rat_inputs();
        recovery = 1'b1;
        commit0_valid = 1'b1;
        commit0_writes = 1'b1;
        commit0_arch = 5'd11;
        commit0_pdst = 6'd5;
        commit0_old_pdst = 6'd11;
        @(posedge clk);
        #1;
        recovery = 1'b0;
        src0_1_used = 1'b1;
        src0_1_addr = 5'd11;
        src0_2_used = 1'b1;
        src0_2_addr = 5'd12;
        src1_1_used = 1'b1;
        src1_1_addr = 5'd13;
        src1_2_used = 1'b1;
        src1_2_addr = 5'd10;
        #1;
        if ((src0_1_tag !== 6'd5) || (src0_2_tag !== 6'd12) ||
            (src1_1_tag !== 6'd13) || (src1_2_tag !== 6'd35) ||
            (free_count !== 6'd16))
            $fatal(1, "post-commit recovery RAT/free reconstruction mismatch");
        rat_dut.read_amt(5'd11, observed_amt_tag);
        if (observed_amt_tag !== 6'd5)
            $fatal(1, "recovery lost same-cycle commit got AMT x11=p%0d",
                   observed_amt_tag);
        rat_dut.read_amt(5'd12, observed_amt_tag);
        if (observed_amt_tag !== 6'd12)
            $fatal(1, "recovery retained younger x12 mapping");

        // A simultaneous allocate and CDB write stores the data but allocation
        // wins readiness, so the recycled tag cannot look completed.
        @(negedge clk);
        clear_rat_inputs();
        clear_prf_inputs();
        prf_read0_tag = 6'd40;
        prf_allocate0_en = 1'b1;
        prf_allocate0_tag = 6'd40;
        prf_cdb0_en = 1'b1;
        prf_cdb0_tag = 6'd40;
        prf_cdb0_data = 32'ha5a5_5a5a;
        #1;
        if (prf_read0_ready || (prf_read0_data !== 32'd0))
            $fatal(1, "PRF allocation did not suppress same-cycle CDB bypass");
        @(posedge clk);
        #1;
        @(negedge clk);
        prf_allocate0_en = 1'b0;
        prf_cdb0_en = 1'b0;
        #1;
        if (prf_read0_ready ||
            (prf_read0_data !== 32'ha5a5_5a5a))
            $fatal(1, "PRF allocation did not win registered ready priority");

        // CDB-only completion is visible combinationally and remains ready.
        prf_cdb1_en = 1'b1;
        prf_cdb1_tag = 6'd40;
        prf_cdb1_data = 32'h1122_3344;
        #1;
        if (!prf_read0_ready || (prf_read0_data !== 32'h1122_3344))
            $fatal(1, "PRF CDB bypass mismatch");
        @(posedge clk);
        #1;
        @(negedge clk);
        prf_cdb1_en = 1'b0;
        #1;
        if (!prf_read0_ready || (prf_read0_data !== 32'h1122_3344))
            $fatal(1, "PRF CDB registered write mismatch");

        // No allocation, CDB, or debug write may change physical zero.
        prf_read0_tag = 6'd0;
        prf_allocate0_en = 1'b1;
        prf_allocate0_tag = 6'd0;
        prf_allocate1_en = 1'b1;
        prf_allocate1_tag = 6'd0;
        prf_cdb0_en = 1'b1;
        prf_cdb0_tag = 6'd0;
        prf_cdb0_data = 32'hdead_beef;
        prf_cdb1_en = 1'b1;
        prf_cdb1_tag = 6'd0;
        prf_cdb1_data = 32'hffff_ffff;
        #1;
        if (!prf_read0_ready || (prf_read0_data !== 32'd0))
            $fatal(1, "PRF x0 changed during allocate/CDB collision");
        @(posedge clk);
        #1;
        @(negedge clk);
        clear_prf_inputs();
        prf_read0_tag = 6'd0;
        #1;
        if (!prf_read0_ready || (prf_read0_data !== 32'd0))
            $fatal(1, "PRF x0 was not immutable");

        $display("OOO_RAT_TEST PASS");
        $finish;
    end
endmodule
