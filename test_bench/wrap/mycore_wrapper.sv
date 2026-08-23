module mycore_wrapper (
    input           clk,
    input           reset,

    input           pm_req_ready,
    input           pm_resp_valid,
    input   [31:0]  pm_resp_data,
    output          pm_req_valid,
    output  [31:0]  pm_req_addr,

    output  [31:0]  dm_req_addr,
    output          dm_req_rvalid,
    input           dm_req_rready,
    input           dm_resp_rvalid,
    input   [31:0]  dm_resp_rdata,
    output          dm_req_wvalid,
    input           dm_req_wready,
    output  [3:0]   dm_req_wstrb,
    output  [31:0]  dm_req_wdata,
    input           dm_resp_wvalid,

    output  [31:0]  probe_pc,
    output  [31:0]  probe_regfile [0:31],
    output          probe_retire,
    output          probe_commit,
    output  [4:0]   probe_rd_addr,
    output  [31:0]  probe_rd_data,
    output  [31:0]  probe_instr,
    output          probe_bus_fault_valid,
    output          probe_bus_fault_is_write,
    output  [31:0]  probe_bus_fault_addr,
    output   [1:0]  probe_bus_fault_resp
);

    reg use_cache;

    wire          core_pm_req_valid;
    wire [31:0]   core_pm_req_addr;
    wire          core_pm_req_ready;
    wire          core_pm_resp_valid;
    wire [31:0]   core_pm_resp_data;

    wire [31:0]   core_dm_req_addr;
    wire          core_dm_req_rvalid;
    wire          core_dm_req_rready;
    wire          core_dm_resp_rvalid;
    wire [31:0]   core_dm_resp_rdata;
    wire          core_dm_req_wvalid;
    wire          core_dm_req_wready;
    wire [3:0]    core_dm_req_wstrb;
    wire [31:0]   core_dm_req_wdata;
    wire          core_dm_resp_wvalid;

    mycore u_core (
        .clk                (clk),
        .reset              (reset),

        .pm_req_valid_out   (core_pm_req_valid),
        .pm_req_addr_out    (core_pm_req_addr),
        .pm_req_ready_in    (core_pm_req_ready),
        .pm_resp_valid_in   (core_pm_resp_valid),
        .pm_resp_data_in    (core_pm_resp_data),

        .dm_req_addr_out    (core_dm_req_addr),

        .dm_req_rvalid_out  (core_dm_req_rvalid),
        .dm_req_rready_in   (core_dm_req_rready),
        .dm_resp_rvalid_in  (core_dm_resp_rvalid),
        .dm_resp_rdata_in   (core_dm_resp_rdata),

        .dm_req_wvalid_out  (core_dm_req_wvalid),
        .dm_req_wready_in   (core_dm_req_wready),
        .dm_req_wstrb_out   (core_dm_req_wstrb),
        .dm_req_wdata_out   (core_dm_req_wdata),
        .dm_resp_wvalid_in  (core_dm_resp_wvalid)
    );

    string uvm_testname;
    initial begin
        if (!$value$plusargs("UVM_TESTNAME=%s", uvm_testname)) begin
            uvm_testname = "";
        end
        use_cache = (uvm_testname == "program_test") ||
                    (uvm_testname == "mem_image_test");
    end

    wire          ic_req_rvalid;
    wire          ic_req_rready;
    wire [31:0]   ic_req_raddr;
    wire          ic_resp_rvalid;
    wire [127:0]  ic_resp_rdata;
    wire [1:0]    ic_resp_rresp;
    wire          ic_fault_valid;
    wire [31:0]   ic_fault_addr;
    wire [1:0]    ic_fault_resp;

    wire          dc_req_rvalid;
    wire          dc_req_rready;
    wire [31:0]   dc_req_raddr;
    wire          dc_resp_rvalid;
    wire [127:0]  dc_resp_rdata;
    wire [1:0]    dc_resp_rresp;
    wire          dc_req_wvalid;
    wire          dc_req_wready;
    wire [31:0]   dc_req_waddr;
    wire [127:0]  dc_req_wdata;
    wire          dc_resp_wvalid;
    wire [1:0]    dc_resp_wresp;
    wire          dc_fault_valid;
    wire          dc_fault_is_write;
    wire [31:0]   dc_fault_addr;
    wire [1:0]    dc_fault_resp;

    assign pm_req_valid = core_pm_req_valid;
    assign pm_req_addr  = core_pm_req_addr;

    assign dm_req_addr   = core_dm_req_addr;
    assign dm_req_rvalid = core_dm_req_rvalid;
    assign dm_req_wvalid = core_dm_req_wvalid;
    assign dm_req_wstrb  = core_dm_req_wstrb;
    assign dm_req_wdata  = core_dm_req_wdata;

    assign core_pm_req_ready   = use_cache ? cache_pm_req_ready   : pm_req_ready;
    assign core_pm_resp_valid  = use_cache ? cache_pm_resp_valid  : pm_resp_valid;
    assign core_pm_resp_data   = use_cache ? cache_pm_resp_data   : pm_resp_data;

    assign core_dm_req_rready  = use_cache ? cache_dm_req_rready  : dm_req_rready;
    assign core_dm_resp_rvalid = use_cache ? cache_dm_resp_rvalid : dm_resp_rvalid;
    assign core_dm_resp_rdata  = use_cache ? cache_dm_resp_rdata  : dm_resp_rdata;
    assign core_dm_req_wready  = use_cache ? cache_dm_req_wready  : dm_req_wready;
    assign core_dm_resp_wvalid = use_cache ? cache_dm_resp_wvalid : dm_resp_wvalid;

    wire          cache_pm_req_ready;
    wire          cache_pm_resp_valid;
    wire [31:0]   cache_pm_resp_data;
    wire          cache_dm_req_rready;
    wire          cache_dm_resp_rvalid;
    wire [31:0]   cache_dm_resp_rdata;
    wire          cache_dm_req_wready;
    wire          cache_dm_resp_wvalid;

    Icache u_icache (
        .clk                (clk),
        .reset              (reset),
        .flush              (1'b0),

        .pm_req_valid_in    (core_pm_req_valid),
        .pm_req_addr_in     (core_pm_req_addr),
        .pm_req_ready_out   (cache_pm_req_ready),
        .pm_resp_valid_out  (cache_pm_resp_valid),
        .pm_resp_data_out   (cache_pm_resp_data),

        .ic_req_rvalid      (ic_req_rvalid),
        .ic_req_rready      (ic_req_rready),
        .ic_req_raddr       (ic_req_raddr),
        .ic_resp_rvalid     (ic_resp_rvalid),
        .ic_resp_rdata      (ic_resp_rdata),
        .ic_resp_rresp      (ic_resp_rresp),
        .ic_fault_valid     (ic_fault_valid),
        .ic_fault_addr      (ic_fault_addr),
        .ic_fault_resp      (ic_fault_resp)
    );

    Dcache u_dcache (
        .clk                (clk),
        .reset                (reset),

        .dm_req_addr_in     (core_dm_req_addr),
        .dm_req_rvalid_in   (core_dm_req_rvalid),
        .dm_req_rready_in   (cache_dm_req_rready),
        .dm_resp_rvalid_out (cache_dm_resp_rvalid),
        .dm_resp_rdata_out  (cache_dm_resp_rdata),
        .dm_req_wvalid_in   (core_dm_req_wvalid),
        .dm_req_wready_out  (cache_dm_req_wready),
        .dm_req_wstrb_in    (core_dm_req_wstrb),
        .dm_req_wdata_in    (core_dm_req_wdata),
        .dm_resp_wready_out (cache_dm_resp_wvalid),

        .dc_req_rvalid      (dc_req_rvalid),
        .dc_req_rready      (dc_req_rready),
        .dc_req_raddr       (dc_req_raddr),
        .dc_resp_rvalid     (dc_resp_rvalid),
        .dc_resp_rdata      (dc_resp_rdata),
        .dc_resp_rresp      (dc_resp_rresp),
        .dc_req_wvalid      (dc_req_wvalid),
        .dc_req_wready      (dc_req_wready),
        .dc_req_waddr       (dc_req_waddr),
        .dc_req_wdata       (dc_req_wdata),
        .dc_resp_wvalid     (dc_resp_wvalid),
        .dc_resp_wresp      (dc_resp_wresp),
        .dc_fault_valid     (dc_fault_valid),
        .dc_fault_is_write  (dc_fault_is_write),
        .dc_fault_addr      (dc_fault_addr),
        .dc_fault_resp      (dc_fault_resp)
    );

    cache_axi_memory_system u_mem (
        .clk                (clk),
        .reset              (reset),

        .ic_req_rvalid      (ic_req_rvalid),
        .ic_req_rready      (ic_req_rready),
        .ic_req_raddr       (ic_req_raddr),
        .ic_resp_rvalid     (ic_resp_rvalid),
        .ic_resp_rdata      (ic_resp_rdata),
        .ic_resp_rresp      (ic_resp_rresp),

        .dc_req_rvalid      (dc_req_rvalid),
        .dc_req_rready      (dc_req_rready),
        .dc_req_raddr       (dc_req_raddr),
        .dc_resp_rvalid     (dc_resp_rvalid),
        .dc_resp_rdata      (dc_resp_rdata),
        .dc_resp_rresp      (dc_resp_rresp),

        .dc_req_wvalid      (dc_req_wvalid),
        .dc_req_wready      (dc_req_wready),
        .dc_req_waddr       (dc_req_waddr),
        .dc_req_wdata       (dc_req_wdata),
        .dc_resp_wvalid     (dc_resp_wvalid),
        .dc_resp_wresp      (dc_resp_wresp)
    );

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_probe_reg
            assign probe_regfile[i] = u_core.regfile.reg_val[i];
        end
    endgenerate

    reg        probe_commit_r;
    reg [4:0]  probe_rd_addr_r;
    reg [31:0] probe_rd_data_r;
    reg        probe_retire_r;
    reg [31:0] probe_pc_r;
    reg [31:0] probe_instr_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            probe_commit_r  <= 1'b0;
            probe_rd_addr_r <= 5'b0;
            probe_rd_data_r <= 32'b0;
            probe_retire_r <= 1'b0;
            probe_pc_r <= 32'b0;
            probe_instr_r <= 32'b0;
        end
        else begin
            probe_commit_r  <= u_core.commit_valid;
            probe_rd_addr_r <= u_core.rd_addr_wb;
            probe_rd_data_r <= u_core.w1_in_wb;
            probe_retire_r  <= u_core.retire_valid;
            probe_pc_r      <= u_core.PC_mem_wb;
            probe_instr_r   <= u_core.instr_mem_wb;
        end
    end

    assign probe_commit = probe_commit_r;
    assign probe_rd_addr = probe_rd_addr_r;
    assign probe_rd_data = probe_rd_data_r;
    assign probe_retire = probe_retire_r;
    assign probe_pc = probe_pc_r;
    assign probe_instr = probe_instr_r;

    reg        probe_bus_fault_valid_r;
    reg        probe_bus_fault_is_write_r;
    reg [31:0] probe_bus_fault_addr_r;
    reg  [1:0] probe_bus_fault_resp_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            probe_bus_fault_valid_r <= 1'b0;
            probe_bus_fault_is_write_r <= 1'b0;
            probe_bus_fault_addr_r <= 32'b0;
            probe_bus_fault_resp_r <= 2'b00;
        end
        else if (!probe_bus_fault_valid_r &&
                 (dc_fault_valid || ic_fault_valid)) begin
            probe_bus_fault_valid_r <= 1'b1;
            probe_bus_fault_is_write_r <= dc_fault_valid
                                          ? dc_fault_is_write : 1'b0;
            probe_bus_fault_addr_r <= dc_fault_valid
                                      ? dc_fault_addr : ic_fault_addr;
            probe_bus_fault_resp_r <= dc_fault_valid
                                      ? dc_fault_resp : ic_fault_resp;
        end
    end

    assign probe_bus_fault_valid = probe_bus_fault_valid_r;
    assign probe_bus_fault_is_write = probe_bus_fault_is_write_r;
    assign probe_bus_fault_addr = probe_bus_fault_addr_r;
    assign probe_bus_fault_resp = probe_bus_fault_resp_r;

endmodule
