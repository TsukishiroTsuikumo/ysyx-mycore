module hazard(
    input               dm_req_rvalid,
    input               dm_req_rready,
    input               dm_req_rready_DLY1,
    input               dm_resp_rvalid,

    input               dm_req_wvalid,
    input               dm_req_wready,
    input               dm_req_wready_DLY1,
    input               dm_resp_wvalid,

    input       [4:0]   rs1_addr_id,
    input       [4:0]   rs2_addr_id,
    input       [4:0]   rd_addr_id_ex,
    input       [4:0]   rd_addr_ex_mem,
    input       [4:0]   rd_addr_mem_wb,
    input               w1_en_id_ex,
    input               w1_en_ex_mem,
    input               w1_en_mem_wb,
    input               valid_id_ex,
    input               valid_ex_mem,
    input               valid_mem_wb,
    output  reg [3:0]   hzd_stall_out,
    output  reg [3:0]   valid_out
);

    always @(*) begin
        hzd_stall_out = 4'b0000;
        valid_out = 4'b1111;

        if( (valid_id_ex  && w1_en_id_ex  && rd_addr_id_ex  != 5'b0 && (rs1_addr_id == rd_addr_id_ex  || rs2_addr_id == rd_addr_id_ex ))
        ||  (valid_ex_mem && w1_en_ex_mem && rd_addr_ex_mem != 5'b0 && (rs1_addr_id == rd_addr_ex_mem || rs2_addr_id == rd_addr_ex_mem))
        ) begin
           hzd_stall_out[0] = 1'b1;
           valid_out[0] = 1'b0; //id
        end
        
        if( (dm_req_rvalid && !dm_req_rready) || (dm_req_wvalid && !dm_req_wready)) begin
            hzd_stall_out[0] = 1'b1; //if to id
            hzd_stall_out[1] = 1'b1; //id to ex
            hzd_stall_out[2] = 1'b1; //ex to mem
            valid_out[2] = 1'b0; //mem
        end
        if( (dm_req_rready_DLY1 && !dm_resp_rvalid) || (dm_req_wready_DLY1 && !dm_resp_wvalid) ) begin
            hzd_stall_out[0] = 1'b1;
            hzd_stall_out[1] = 1'b1;
            hzd_stall_out[2] = 1'b1;
            hzd_stall_out[3] = 1'b1; //mem to wb
            valid_out[3] = 1'b0; //wb
        end
    end

endmodule
