module rename (
    input   [4:0]   rs1_addr,
    input   [4:0]   rs2_addr,
    input   [4:0]   rd_addr,
    output  [4:0]   rs1_rename_addr,
    output  [4:0]   rs2_rename_addr,
    output  [4:0]   rd_rename_addr
);

    assign rs1_rename_addr = rs1_addr;
    assign rs2_rename_addr = rs2_addr;
    assign rd_rename_addr  = rd_addr;

endmodule