module hazard(
    input               pm_req_ready,
    input               pm_req_valid,
    input               pm_resp_valid,

    input               dm_ld,
    input               dm_rd_valid,

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
    output  reg [4:0]   hzd_stall_out,
    output  reg [5:0]   valid_out
);

    always @(*) begin
        hzd_stall_out = 5'b00000;
        valid_out = 6'b111111;
        if( !(pm_req_ready && pm_resp_valid) ) begin
            hzd_stall_out[0] = 1'b1;
        end
        else if(valid_id_ex && w1_en_id_ex && rd_addr_id_ex != 5'b0 &&
           (rs1_addr_id == rd_addr_id_ex || rs2_addr_id == rd_addr_id_ex)) begin
            hzd_stall_out = 5'b00011;
            valid_out = 6'b111011;
        end
        else if(valid_ex_mem && w1_en_ex_mem && rd_addr_ex_mem != 5'b0 &&
                (rs1_addr_id == rd_addr_ex_mem || rs2_addr_id == rd_addr_ex_mem)) begin
            hzd_stall_out = 5'b00011;
            valid_out = 6'b111011;
        end
        else if(valid_mem_wb && w1_en_mem_wb && rd_addr_mem_wb != 5'b0 &&
                (rs1_addr_id == rd_addr_mem_wb || rs2_addr_id == rd_addr_mem_wb)) begin
            hzd_stall_out = 5'b00011;
            valid_out = 6'b111011;
        end
        else if( (|dm_ld) && (!dm_rd_valid) ) begin
            hzd_stall_out = 5'b01111;
            valid_out = 6'b011111;
        end
        else begin
            hzd_stall_out = 5'b00000;
            valid_out = 6'b111111;
        end
    end

endmodule
