interface mycore_if(
    input bit clk,
    input bit reset
);
    logic   [31:0]  pm_rd;
    logic   [31:0]  pm_addr;
    logic           ifetch;
    logic   [31:0]  dm_rd;
    logic   [31:0]  dm_wr;
    logic   [31:0]  dm_addr;
    logic    [3:0]  dm_st;
    logic    [3:0]  dm_ld;
    logic           ld_valid;

    modport driver_port (
        output pm_rd,
        output pm_addr,
        output ifetch,
        output dm_rd,
        output dm_wr,
        output dm_addr,
        output dm_st,
        output dm_ld,
        output ld_valid
    );

    modport dut_port (
        input   pm_rd,
        output  pm_addr,
        output  ifetch,
        input   dm_rd,
        output  dm_wr,
        output  dm_addr,
        output  dm_st,
        output  dm_ld,
        input   ld_valid
    );

    modport PM_port (
        output pm_rd,
        input  pm_addr,
        input  ifetch
    );

    modport DM_port (
        output  dm_rd,
        input   dm_wr,
        input   dm_addr,
        input   dm_st,
        input   dm_ld,
        output  ld_valid
    );
    
endinterface
