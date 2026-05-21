`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */
module cache_test_bench;
/* verilator lint_on DECLFILENAME */

    localparam PASS_REG   = 5'd20;
    localparam PASS_VALUE = 32'h0000_0001;
    localparam FAIL_VALUE = 32'hffff_ffff;

    reg clk;
    reg reset;

    wire        pm_req_valid;
    wire [31:0] pm_req_addr;
    wire        pm_req_ready;
    wire        pm_resp_valid;
    wire [31:0] pm_resp_data;

    wire [31:0] dm_req_addr;
    wire        dm_req_rvalid;
    wire        dm_req_rready;
    wire        dm_resp_rvalid;
    wire [31:0] dm_resp_rdata;
    wire        dm_req_wvalid;
    wire        dm_req_wready;
    wire  [3:0] dm_req_wstrb;
    wire [31:0] dm_req_wdata;
    wire        dm_resp_wvalid;

    wire        ic_req_rvalid;
    wire        ic_req_rready;
    wire [31:0] ic_req_raddr;
    wire        ic_resp_rvalid;
    wire [127:0] ic_resp_rdata;

    wire        dc_req_rvalid;
    wire        dc_req_rready;
    wire [31:0] dc_req_raddr;
    wire        dc_resp_rvalid;
    wire [127:0] dc_resp_rdata;
    wire        dc_req_wvalid;
    wire        dc_req_wready;
    wire [31:0] dc_req_waddr;
    wire [127:0] dc_req_wdata;
    wire        dc_resp_wvalid;

    integer cycle;
    reg done_seen;

    task check_reg;
        input [4:0] reg_id;
        input [31:0] expected;
        reg [31:0] actual;
        begin
            actual = (reg_id == 5'd0) ? 32'h0000_0000 : u_core.regfile.reg_val[reg_id];
            if (actual !== expected) begin
                $display("CACHE_TEST_FAIL: x%0d=0x%08h expected=0x%08h cycle=%0d",
                         reg_id, actual, expected, cycle);
                #2 $fatal;
            end
        end
    endtask

    task check_expected_regs;
        begin
            check_reg(5'd2,  32'h0000_0003);
            check_reg(5'd3,  32'h0000_0006);
            check_reg(5'd4,  32'h0000_000b);
            check_reg(5'd5,  32'h0000_000b);
            check_reg(5'd7,  32'h0000_0007);
            check_reg(5'd8,  32'h0000_0012);
            check_reg(5'd11, 32'h0000_0019);
            check_reg(5'd12, 32'h0000_0019);
            check_reg(5'd14, 32'h0000_001f);
            check_reg(5'd16, 32'h0000_000b);
            check_reg(5'd17, 32'h0000_002a);
            check_reg(5'd18, 32'h0000_002a);
            check_reg(5'd31, 32'h0000_0000);
        end
    endtask

    mycore u_core (
        .clk( clk ),
        .reset( reset ),

        .pm_req_valid_out( pm_req_valid ),
        .pm_req_addr_out( pm_req_addr ),
        .pm_req_ready_in( pm_req_ready ),
        .pm_resp_valid_in( pm_resp_valid ),
        .pm_resp_data_in( pm_resp_data ),

        .dm_req_addr_out( dm_req_addr ),

        .dm_req_rvalid_out( dm_req_rvalid ),
        .dm_req_rready_in ( dm_req_rready ),
        .dm_resp_rvalid_in( dm_resp_rvalid ),
        .dm_resp_rdata_in( dm_resp_rdata ),

        .dm_req_wvalid_out( dm_req_wvalid ),
        .dm_req_wready_in( dm_req_wready ),
        .dm_req_wstrb_out( dm_req_wstrb ),
        .dm_req_wdata_out( dm_req_wdata ),
        .dm_resp_wvalid_in( dm_resp_wvalid )
    );

    Icache #(
        .PM_LINE_BYTES(16),
        .PM_WAY_NUM(4),
        .PM_SET_NUM(16)
    ) u_icache (
        .clk( clk ),
        .reset( reset ),

        .pm_req_valid_in( pm_req_valid ),
        .pm_req_addr_in( pm_req_addr ),
        .pm_req_ready_out( pm_req_ready ),

        .pm_resp_valid_out( pm_resp_valid ),
        .pm_resp_data_out( pm_resp_data ),

        .ic_req_rvalid( ic_req_rvalid ),
        .ic_req_rready( ic_req_rready ),
        .ic_req_raddr( ic_req_raddr ),

        .ic_resp_rvalid( ic_resp_rvalid ),
        .ic_resp_rdata( ic_resp_rdata )
    );

    Dcache #(
        .DM_LINE_BYTES(16),
        .DM_WAY_NUM(4),
        .DM_SET_NUM(16)
    ) u_dcache (
        .clk( clk ),
        .rst( reset ),

        .dm_req_addr_in( dm_req_addr ),

        .dm_req_rvalid_in( dm_req_rvalid ),
        .dm_req_rready_in( dm_req_rready ),
        .dm_resp_rvalid_out( dm_resp_rvalid ),
        .dm_resp_rdata_out( dm_resp_rdata ),

        .dm_req_wvalid_in( dm_req_wvalid ),
        .dm_req_wready_out( dm_req_wready ),
        .dm_req_wstrb_in( dm_req_wstrb ),
        .dm_req_wdata_in( dm_req_wdata ),
        .dm_resp_wready_out( dm_resp_wvalid ),

        .dc_req_rvalid( dc_req_rvalid ),
        .dc_req_rready( dc_req_rready ),
        .dc_req_raddr( dc_req_raddr ),

        .dc_resp_rvalid( dc_resp_rvalid ),
        .dc_resp_rdata( dc_resp_rdata ),

        .dc_req_wvalid( dc_req_wvalid ),
        .dc_req_wready( dc_req_wready ),
        .dc_req_waddr( dc_req_waddr ),
        .dc_req_wdata( dc_req_wdata ),

        .dc_resp_wvalid( dc_resp_wvalid )
    );

    MEM #(
        .MEM_WIDTH(12),
        .LINE_WIDTH(4)
    ) u_mem (
        .clk( clk ),
        .reset( reset ),

        .ic_req_rvalid( ic_req_rvalid ),
        .ic_req_rready( ic_req_rready ),
        .ic_req_raddr( ic_req_raddr ),
        .ic_resp_rvalid( ic_resp_rvalid ),
        .ic_resp_rdata( ic_resp_rdata ),

        .dc_req_rvalid( dc_req_rvalid ),
        .dc_req_rready( dc_req_rready ),
        .dc_req_raddr( dc_req_raddr ),
        .dc_resp_rvalid( dc_resp_rvalid ),
        .dc_resp_rdata( dc_resp_rdata ),

        .dc_req_wvalid( dc_req_wvalid ),
        .dc_req_wready( dc_req_wready ),
        .dc_req_waddr( dc_req_waddr ),
        .dc_req_wdata( dc_req_wdata ),
        .dc_resp_wvalid( dc_resp_wvalid )
    );

    // Program and initial data are loaded by MEM.v from cache_test/program.mem.

    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end

    initial begin
        $dumpfile("cache_test.vcd");
        $dumpvars(0, cache_test_bench);

        reset = 1'b1;
        done_seen = 1'b0;
        cycle = 0;

        repeat (8) @(posedge clk);
        reset = 1'b0;
    end

    always @(posedge clk) begin
        if (reset) begin
            cycle <= 0;
        end
        else begin
            cycle <= cycle + 1;

            if (u_core.commit_valid) begin
                $display("[cycle %0d] commit rd=x%0d data=0x%08h pc=0x%08h",
                         cycle, u_core.w1_addr_wb, u_core.w1_in_wb, u_core.PC_id);

                if (u_core.w1_addr_wb == PASS_REG) begin
                    done_seen <= 1'b1;
                    if (u_core.w1_in_wb == PASS_VALUE) begin
                        check_expected_regs();
                        $display("CACHE_TEST_PASS: x%0d=0x%08h cycle=%0d",
                                 PASS_REG, u_core.w1_in_wb, cycle);
                        #2 $finish;
                    end
                    else if (u_core.w1_in_wb == FAIL_VALUE) begin
                        $display("CACHE_TEST_FAIL: x%0d=0x%08h cycle=%0d",
                                 PASS_REG, u_core.w1_in_wb, cycle);
                        #2 $fatal;
                    end
                end
            end

            if ($test$plusargs("DEBUG_FRONTEND") && cycle < 140) begin
                $display("[cycle %0d] fe pc_if=0x%08h req=%0b ready=%0b resp=%0b raw=%0b hzd=%06b valid=%06b q_r=%0d q_pc_t=%0d q_i_t=%0d q_pc=0x%08h q_instr=0x%08h",
                         cycle,
                         u_core.current_pc_if,
                         pm_req_valid,
                         pm_req_ready,
                         pm_resp_valid,
                         u_core.raw_stall,
                         u_core.hzd_stall,
                         u_core.valid,
                         u_core.instr_queue_inst.read_ptr,
                         u_core.instr_queue_inst.pc_tail,
                         u_core.instr_queue_inst.instr_tail,
                         u_core.PC_id,
                         u_core.instr_id);
            end

            if ($test$plusargs("DEBUG_MEM") && cycle < 220) begin
                if (dm_req_rvalid || dm_resp_rvalid || dm_req_wvalid || dm_resp_wvalid) begin
                    $display("[cycle %0d] dm rv=%0b rr=%0b rresp=%0b wv=%0b wr=%0b wresp=%0b addr=0x%08h wstrb=%h wdata=0x%08h rdata=0x%08h",
                             cycle,
                             dm_req_rvalid,
                             dm_req_rready,
                             dm_resp_rvalid,
                             dm_req_wvalid,
                             dm_req_wready,
                             dm_resp_wvalid,
                             dm_req_addr,
                             dm_req_wstrb,
                             dm_req_wdata,
                             dm_resp_rdata);
                end
            end

            if ($test$plusargs("DEBUG_PIPE") && cycle >= 66 && cycle < 84) begin
                $display("[cycle %0d] pipe id_pc=0x%08h id_instr=0x%08h raw=%0b v=%06b | idex_pc=0x%08h idex_v=%0b idex_rd=x%0d use=%07b rs1=0x%08h rs2=0x%08h lsu=%03b | exmem_v=%0b st=%h ld=%h addr=0x%08h data=0x%08h",
                         cycle,
                         u_core.PC_id,
                         u_core.instr_id,
                         u_core.raw_stall,
                         u_core.valid,
                         u_core.PC_id_ex,
                         u_core.valid_id_ex,
                         u_core.w1_addr_id_ex,
                         u_core.use_signal_id_ex,
                         u_core.r1_out_id_ex,
                         u_core.r2_out_id_ex,
                         u_core.lsu_op_id_ex,
                         u_core.valid_ex_mem,
                         u_core.dm_st_ex_mem,
                         u_core.dm_ld_ex_mem,
                         u_core.dm_addr_ex_mem,
                         u_core.pipe_ex_mem);
            end

            if (cycle > 2000) begin
                if (!done_seen) begin
                    $display("CACHE_TEST_TIMEOUT: pass register write was not observed");
                end
                #2 $fatal;
            end
        end
    end

endmodule
