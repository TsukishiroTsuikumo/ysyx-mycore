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
    output          probe_commit,
    output  [4:0]   probe_rd_addr,
    output  [31:0]  probe_rd_data
);

    mycore u_core (
        .clk                (clk),
        .reset              (reset),

        .pm_req_valid_out   (pm_req_valid),
        .pm_req_addr_out    (pm_req_addr),
        .pm_req_ready_in    (pm_req_ready),
        .pm_resp_valid_in   (pm_resp_valid),
        .pm_resp_data_in    (pm_resp_data),

        .dm_req_addr_out    (dm_req_addr),

        .dm_req_rvalid_out  (dm_req_rvalid),
        .dm_req_rready_in   (dm_req_rready),
        .dm_resp_rvalid_in  (dm_resp_rvalid),
        .dm_resp_rdata_in   (dm_resp_rdata),

        .dm_req_wvalid_out  (dm_req_wvalid),
        .dm_req_wready_in   (dm_req_wready),
        .dm_req_wstrb_out   (dm_req_wstrb),
        .dm_req_wdata_out   (dm_req_wdata),
        .dm_resp_wvalid_in  (dm_resp_wvalid)
    );

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_probe_reg
            assign probe_regfile[i] = u_core.regfile.reg_val[i];
        end
    endgenerate

    assign probe_pc = u_core.PC_id;

    reg        probe_commit_r;
    reg [4:0]  probe_rd_addr_r;
    reg [31:0] probe_rd_data_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            probe_commit_r  <= 1'b0;
            probe_rd_addr_r <= 5'b0;
            probe_rd_data_r <= 32'b0;
        end
        else begin
            probe_commit_r  <= u_core.commit_valid;
            probe_rd_addr_r <= u_core.w1_addr_wb;
            probe_rd_data_r <= u_core.w1_in_wb;
        end
    end

    assign probe_commit = probe_commit_r;
    assign probe_rd_addr = probe_rd_addr_r;
    assign probe_rd_data = probe_rd_data_r;

endmodule
