module mem_DM #(
    parameter DM_addr_width = 14 // 16KB memory (2^14 bytes)
)(
    input              clk_dm,
    input              reset_dm,

    input       [31:0] dm_addr_in,
    input       [31:0] dm_wr_in,
    input        [3:0] dm_ld_in,
    input        [3:0] dm_st_in,
    output reg  [31:0] dm_rd_out,
    output reg         ld_valid_out
);

    localparam integer DM_size = (1 << DM_addr_width);
    reg [7:0] DM[0:DM_size-1];

    // Load DM content from file at initialization
    reg [255*8:1] dmfile = "data.DM";
    reg [255*8:1] tmp_dmfile;
    initial begin
        if($value$plusargs("DM=%s",tmp_dmfile)) begin
            dmfile = {tmp_dmfile, ".DM"};
        end
        $readmemh(dmfile, DM);
    end

    function [31:0] addr_DM (input [31:0] address);
        begin
            addr_DM = address;
            if(address+3 >= DM_size) begin
                $display("Error: Address out of bounds: %h", address);
                addr_DM = 0;
            end
        end
    endfunction

    reg [31:0] dm_addr_DLY1;
    reg  [3:0] dm_ld_DLY1;
    always @(posedge clk_dm) begin
        dm_addr_DLY1    <= dm_addr_in;
        dm_ld_DLY1      <= dm_ld_in;
    end

    event value_changed;
    // Combinational logic to read data from DM based on delayed address and load signals
    always @( value_changed or dm_ld_DLY1 or dm_addr_DLY1) begin
        integer i;
        dm_rd_out = 0;
        ld_valid_out = 0;
        for (i = 0; i < 4; i = i + 1) begin
            if(dm_ld_DLY1[i]) dm_rd_out[i*8+7 -: 8] = DM[addr_DM(dm_addr_DLY1)+i];
        end
        ld_valid_out = (dm_ld_DLY1 != 0);
    end

    // Sequential logic to write data to DM on store signals
    always @(posedge clk_dm or posedge reset_dm) begin  
        integer i;
        if(reset_dm) begin
            for(i=0;i<DM_size;i++)
                DM[i] = 0;
            $readmemh(dmfile, DM);
            -> value_changed;
        end
        else begin
            for(i=0;i<4;i+=1) begin
                if(dm_st_in[i]) begin
                    DM[addr_DM(dm_addr_in)+i] = dm_wr_in[i*8+7-:8];
                    -> value_changed;
                end
            end
        end
    end

endmodule
