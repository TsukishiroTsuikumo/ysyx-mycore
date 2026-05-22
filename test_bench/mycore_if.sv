interface mycore_if(
    input bit clk
);
    logic           reset;

    logic           pm_req_valid;
    logic   [31:0]  pm_req_addr;
    logic           pm_req_ready;
    logic           pm_resp_valid;
    logic   [31:0]  pm_resp_data;

    logic   [31:0]  dm_req_addr;

    logic           dm_req_rvalid;
    logic           dm_req_rready;
    logic           dm_resp_rvalid;
    logic   [31:0]  dm_resp_rdata;

    logic           dm_req_wvalid;
    logic           dm_req_wready;
    logic    [3:0]  dm_req_wstrb;
    logic   [31:0]  dm_req_wdata;
    logic           dm_resp_wvalid;

    modport driver_port (
        input   reset,
        output  pm_req_valid,
        output  pm_req_addr,
        input   pm_req_ready,
        input   pm_resp_valid,
        input   pm_resp_data,

        output  dm_req_addr,

        output  dm_req_rvalid,
        input   dm_req_rready,
        input   dm_resp_rvalid,
        input   dm_resp_rdata,

        output  dm_req_wvalid,
        input   dm_req_wready,
        output  dm_req_wstrb,
        output  dm_req_wdata,
        input   dm_resp_wvalid
    );

    modport dut_port (
        input   reset,
        output  pm_req_valid,
        output  pm_req_addr,
        input   pm_req_ready,
        input   pm_resp_valid,
        input   pm_resp_data,

        output  dm_req_addr,

        output  dm_req_rvalid,
        input   dm_req_rready,
        input   dm_resp_rvalid,
        input   dm_resp_rdata,

        output  dm_req_wvalid,
        input   dm_req_wready,
        output  dm_req_wstrb,
        output  dm_req_wdata,
        input   dm_resp_wvalid
    );

    modport PM_port (
        input   pm_req_valid,
        input   pm_req_addr,
        output  pm_req_ready,
        output  pm_resp_valid,
        output  pm_resp_data
    );

    modport DM_port (
        input   dm_req_addr,

        input   dm_req_rvalid,
        output  dm_req_rready,
        output  dm_resp_rvalid,
        output  dm_resp_rdata,

        input   dm_req_wvalid,
        output  dm_req_wready,
        input   dm_req_wstrb,
        input   dm_req_wdata,
        output  dm_resp_wvalid
    );
    
endinterface
