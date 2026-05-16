module Icache(
    input               clk,
    input               rst,

    input               pm_req_valid_in,
    input       [31:0]  pm_req_addr_in,
    output  reg         pm_req_ready_out,

    output  reg         pm_resp_valid_out,
    output  reg [31:0]  pm_resp_data_out
);

    localparam integer PM_size = (1 << PM_addr_width);
    reg [7:0] PM [0:PM_size-1];

    // Load PM content from file at initialization
    reg [255*8:1] pmfile= "data.PM";
    reg [255*8:1] tmp_pmfile;
    initial begin
        pm_resp_valid_out = 1'b0;
        pm_resp_data_out = 32'h00000013;
        if ($value$plusargs("PM=%s", tmp_pmfile)) begin
            pmfile = {tmp_pmfile, ".PM"};
        end
        $readmemh(pmfile, PM);
    end

    function [31:0] addr_PM (input [31:0] address);
        begin
            addr_PM = address;
            if(address+3 >= PM_size) begin
                $display("Error: Address out of bounds: %h", address);
                addr_PM = 0;
            end
        end
    endfunction

    
    always @(posedge rst_pm) begin
        integer i;
        if(rst_pm) begin
            for (i = 0; i < PM_size; i = i + 1) begin
                PM[i] = 0;
            end
            $readmemh(pmfile, PM);
        end
    end

    assign pm_req_ready_out = pm_req_valid_in;

    always @(posedge clk_pm) begin
        if (pm_req_valid_in) begin
            pm_resp_valid_out <= 1'b1;
            pm_resp_data_out <= {PM[addr_PM(pm_req_addr_in)+3], PM[addr_PM(pm_req_addr_in)+2], PM[addr_PM(pm_req_addr_in)+1], PM[addr_PM(pm_req_addr_in)]};
        end
        else begin
            pm_resp_valid_out <= 1'b0;
        end
    end

endmodule
