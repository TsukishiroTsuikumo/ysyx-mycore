class program_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(program_scoreboard)

    localparam bit [31:0] EBREAK_INSTR = 32'h0010_0073;

    bit done_seen;
    bit done_by_store;
    bit done_by_ebreak;
    bit [31:0] done_addr;
    bit [31:0] expected_exit;
    bit [31:0] actual_exit;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        done_seen     = 1'b0;
        done_by_store = 1'b0;
        done_by_ebreak = 1'b0;
        done_addr      = 32'h0000_1000;
        expected_exit  = 32'h0;
        actual_exit    = 32'h0;
    endfunction

    local function bit [31:0] strobe_mask(input bit [3:0] strobe);
        bit [31:0] mask;
        begin
            mask = 32'h0;
            for (int i = 0; i < 4; i++) begin
                if (strobe[i]) begin
                    mask[i*8 +: 8] = 8'hff;
                end
            end
            return mask;
        end
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("PROGRAM_DONE_ADDR=%h", done_addr));
        void'($value$plusargs("PROGRAM_EXPECTED_EXIT=%h", expected_exit));
    endfunction

    virtual function void write(mycore_item item);
        program_item pitem;

        super.write(item);

        if (!$cast(pitem, item)) begin
            `uvm_warning("PROGRAM_SCORE", "received non-program item; cannot check program result")
            return;
        end

        if (!done_seen && (pitem.dm_st != 4'b0) && (pitem.dm_addr == done_addr)) begin
            bit [31:0] mask;
            done_seen     = 1'b1;
            done_by_store = 1'b1;
            actual_exit   = pitem.dm_wr;
            mask          = strobe_mask(pitem.dm_st);

            if ((actual_exit & mask) !== (expected_exit & mask)) begin
                `uvm_error("PROGRAM_SCORE",
                           $sformatf("program exit mismatch: actual=0x%08h expected=0x%08h strobe=0x%0h mask=0x%08h",
                                     actual_exit, expected_exit, pitem.dm_st, mask))
            end
            else begin
                `uvm_info("PROGRAM_SCORE",
                          $sformatf("program exit matched: actual=0x%08h expected=0x%08h strobe=0x%0h",
                                    actual_exit, expected_exit, pitem.dm_st),
                          UVM_LOW)
            end
        end
        else if (!done_seen && pitem.ifetch && pitem.ins_valid && (pitem.pm_rd == EBREAK_INSTR)) begin
            done_seen      = 1'b1;
            done_by_ebreak = 1'b1;
            actual_exit    = 32'h0;

            if (expected_exit != 32'h0) begin
                `uvm_error("PROGRAM_SCORE",
                           $sformatf("ebreak finished program, but expected exit is 0x%08h",
                                     expected_exit))
            end
            else begin
                `uvm_info("PROGRAM_SCORE", "program finished by ebreak", UVM_LOW)
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (!done_seen) begin
            `uvm_error("PROGRAM_SCORE", "program did not reach a recognized done condition")
        end
        else if (done_by_store) begin
            `uvm_info("PROGRAM_SCORE",
                      $sformatf("done by store: addr=0x%08h exit=0x%08h expected=0x%08h",
                                done_addr, actual_exit, expected_exit),
                      UVM_LOW)
        end
        else if (done_by_ebreak) begin
            `uvm_info("PROGRAM_SCORE", "done by ebreak", UVM_LOW)
        end
    endfunction

endclass
