module rename (
    input   [4:0]   rs1_addr,
    input   [4:0]   rs2_addr,
    input   [4:0]   rd_addr,
    output  [4:0]   rs1_rename_addr,
    output  [4:0]   rs2_rename_addr,
    output  [4:0]   rd_rename_addr,

    input  [31:0]  rd_value_wb,
    input  [4:0]   rd_addr_in_wb,
    output [31:0]  w1_value,
    output         w1_en,
    output  [4:0]  w1_addr
);

    assign rs1_rename_addr = rs1_addr;
    assign rs2_rename_addr = rs2_addr;
    assign rd_rename_addr  = rd_addr;

    assign w1_value = rd_value_wb;
    assign w1_en = 1'b1;
    assign w1_addr = rd_addr_in_wb;

endmodule