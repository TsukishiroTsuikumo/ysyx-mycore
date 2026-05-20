`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */
module cache_test_bench;
/* verilator lint_on DECLFILENAME */

    localparam DONE_ADDR  = 32'h0000_0104;
    localparam DONE_VALUE = 32'h0000_0034;

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
                         cycle, u_core.w1_addr_wb, u_core.w1_in_wb, u_core.PC_ir_id);
            end

            if (dm_req_wvalid && dm_req_wready &&
                dm_req_addr == DONE_ADDR && dm_req_wstrb == 4'hf) begin
                done_seen <= 1'b1;
                if (dm_req_wdata == DONE_VALUE) begin
                    $display("CACHE_TEST_PASS: done store data=0x%08h cycle=%0d", dm_req_wdata, cycle);
                    #2 $finish;
                end
                else begin
                    $display("CACHE_TEST_FAIL: done store data=0x%08h expected=0x%08h cycle=%0d",
                             dm_req_wdata, DONE_VALUE, cycle);
                    #2 $fatal;
                end
            end

            if (cycle > 2000) begin
                if (!done_seen) begin
                    $display("CACHE_TEST_TIMEOUT: done store was not observed");
                end
                #2 $fatal;
            end
        end
    end

endmodule
