`timescale 1ns/1ps

module axi_master_uvm_tb;
    import uvm_pkg::*;
    import axi_verif_pkg::*;

    localparam int unsigned ADDR_WIDTH  = 32;
    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned ID_WIDTH    = 2;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned OWNER_WIDTH = 1;

    typedef virtual axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_vif_t;

    logic clk;
    logic reset;
    string testname;

    initial clk = 1'b0;
    always #1 clk = ~clk;

    initial begin
        reset = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
    end

    initial begin : watchdog
        repeat (100000) @(posedge clk);
        $fatal(1, "Active AXI UVM test timed out");
    end

    axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_bus (
        .aclk    (clk),
        .aresetn (~reset)
    );

    axi_random_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .MEM_WORDS  (1024),
        .DATA_TAG   (32'h6000_0000),
        .SEED       (32'h1ace_b00c)
    ) slave (
        .clk           (clk),
        .reset         (reset),
        .s_axi_awid    (axi_bus.awid),
        .s_axi_awaddr  (axi_bus.awaddr),
        .s_axi_awlen   (axi_bus.awlen),
        .s_axi_awsize  (axi_bus.awsize),
        .s_axi_awburst (axi_bus.awburst),
        .s_axi_awlock  (axi_bus.awlock),
        .s_axi_awcache (axi_bus.awcache),
        .s_axi_awprot  (axi_bus.awprot),
        .s_axi_awqos   (axi_bus.awqos),
        .s_axi_awvalid (axi_bus.awvalid),
        .s_axi_awready (axi_bus.awready),
        .s_axi_wdata   (axi_bus.wdata),
        .s_axi_wstrb   (axi_bus.wstrb),
        .s_axi_wlast   (axi_bus.wlast),
        .s_axi_wvalid  (axi_bus.wvalid),
        .s_axi_wready  (axi_bus.wready),
        .s_axi_bid     (axi_bus.bid),
        .s_axi_bresp   (axi_bus.bresp),
        .s_axi_bvalid  (axi_bus.bvalid),
        .s_axi_bready  (axi_bus.bready),
        .s_axi_arid    (axi_bus.arid),
        .s_axi_araddr  (axi_bus.araddr),
        .s_axi_arlen   (axi_bus.arlen),
        .s_axi_arsize  (axi_bus.arsize),
        .s_axi_arburst (axi_bus.arburst),
        .s_axi_arlock  (axi_bus.arlock),
        .s_axi_arcache (axi_bus.arcache),
        .s_axi_arprot  (axi_bus.arprot),
        .s_axi_arqos   (axi_bus.arqos),
        .s_axi_arvalid (axi_bus.arvalid),
        .s_axi_arready (axi_bus.arready),
        .s_axi_rid     (axi_bus.rid),
        .s_axi_rdata   (axi_bus.rdata),
        .s_axi_rresp   (axi_bus.rresp),
        .s_axi_rlast   (axi_bus.rlast),
        .s_axi_rvalid  (axi_bus.rvalid),
        .s_axi_rready  (axi_bus.rready)
    );

    // The reusable random slave has no USER response ports.
    assign axi_bus.buser = '0;
    assign axi_bus.ruser = '0;

    axi_protocol_checker #(
        .CHECK_FINAL_QUIESCENCE (1'b1)
    ) protocol_checker (
        .axi (axi_bus)
    );

    initial begin
        uvm_config_db#(axi_vif_t)::set(null, "*", "vif", axi_bus);
        if (!$value$plusargs("UVM_TESTNAME=%s", testname)) begin
            testname = "axi_master_test";
        end
        run_test(testname);
    end

endmodule
