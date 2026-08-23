`ifndef YSYX_MYCORE_AXI_DEFS_VH
`define YSYX_MYCORE_AXI_DEFS_VH

// AXI4 response encodings.
`define AXI_RESP_OKAY   2'b00
`define AXI_RESP_EXOKAY 2'b01
`define AXI_RESP_SLVERR 2'b10
`define AXI_RESP_DECERR 2'b11

// AXI4 burst encodings.
`define AXI_BURST_FIXED 2'b00
`define AXI_BURST_INCR  2'b01
`define AXI_BURST_WRAP  2'b10

`endif
