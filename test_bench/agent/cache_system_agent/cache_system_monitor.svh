class cache_system_monitor extends uvm_monitor;
    `uvm_component_utils(cache_system_monitor)

    uvm_analysis_port #(instr_item) instr_port;
    uvm_analysis_port #(fetch_data_item) dmem_port;

    int unsigned core_ifetch_req_count;
    int unsigned core_ifetch_resp_count;
    int unsigned ic_mem_req_count;
    int unsigned ic_mem_resp_count;
    int unsigned core_dread_req_count;
    int unsigned core_dread_resp_count;
    int unsigned core_dwrite_req_count;
    int unsigned core_dwrite_resp_count;
    int unsigned dc_mem_read_req_count;
    int unsigned dc_mem_read_resp_count;
    int unsigned dc_mem_write_req_count;
    int unsigned dc_mem_write_resp_count;

    bit        hold_core_ifetch_req;
    bit [31:0] hold_core_ifetch_addr;
    bit        hold_ic_mem_req;
    bit [31:0] hold_ic_mem_addr;
    bit        hold_core_dread_req;
    bit [31:0] hold_core_dread_addr;
    bit        hold_core_dwrite_req;
    bit [31:0] hold_core_dwrite_addr;
    bit [3:0]  hold_core_dwrite_strb;
    bit [31:0] hold_core_dwrite_data;
    bit        hold_dc_mem_read_req;
    bit [31:0] hold_dc_mem_read_addr;
    bit        hold_dc_mem_write_req;
    bit [31:0] hold_dc_mem_write_addr;
    bit [127:0] hold_dc_mem_write_data;
    bit [31:0] core_dread_addr_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        instr_port = new("instr_port", this);
        dmem_port = new("dmem_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge $root.test_bench.clk);
            uvm_wait_for_nba_region();

            if ($root.test_bench.dut.reset) begin
                hold_core_ifetch_req = 1'b0;
                hold_ic_mem_req = 1'b0;
                hold_core_dread_req = 1'b0;
                hold_core_dwrite_req = 1'b0;
                hold_dc_mem_read_req = 1'b0;
                hold_dc_mem_write_req = 1'b0;
                continue;
            end

            check_core_ifetch();
            check_ic_mem_read();
        end
    endtask

    function void check_core_ifetch();
        if ($root.test_bench.dut.core_pm_req_valid &&
            $root.test_bench.dut.core_pm_req_ready) begin
            core_ifetch_req_count++;
        end
        if ($root.test_bench.dut.core_pm_resp_valid) begin
            instr_item item;
            core_ifetch_resp_count++;
            item = instr_item::type_id::create("item");
            item.instr = $root.test_bench.dut.core_pm_resp_data;
            instr_port.write(item);
        end

        hold_core_ifetch_req = $root.test_bench.dut.core_pm_req_valid &&
                               !$root.test_bench.dut.core_pm_req_ready;
        hold_core_ifetch_addr = $root.test_bench.dut.core_pm_req_addr;
    endfunction

    function void check_ic_mem_read();
        if (hold_ic_mem_req &&
            $root.test_bench.dut.ic_req_rvalid &&
            !$root.test_bench.dut.ic_req_rready &&
            ($root.test_bench.dut.ic_req_raddr !== hold_ic_mem_addr)) begin
            `uvm_error("CACHE_HS", $sformatf(
                "icache-mem read addr changed while stalled old=0x%08x new=0x%08x",
                hold_ic_mem_addr, $root.test_bench.dut.ic_req_raddr))
        end

        if ($root.test_bench.dut.ic_req_rvalid &&
            $root.test_bench.dut.ic_req_rready) begin
            ic_mem_req_count++;
        end
        if ($root.test_bench.dut.ic_resp_rvalid) begin
            ic_mem_resp_count++;
        end

        hold_ic_mem_req = $root.test_bench.dut.ic_req_rvalid &&
                          !$root.test_bench.dut.ic_req_rready;
        hold_ic_mem_addr = $root.test_bench.dut.ic_req_raddr;
    endfunction

    function void check_core_dread();
        if (hold_core_dread_req &&
            $root.test_bench.dut.core_dm_req_rvalid &&
            !$root.test_bench.dut.core_dm_req_rready &&
            ($root.test_bench.dut.core_dm_req_addr !== hold_core_dread_addr)) begin
            `uvm_error("CACHE_HS", $sformatf(
                "core-dcache read addr changed while stalled old=0x%08x new=0x%08x",
                hold_core_dread_addr, $root.test_bench.dut.core_dm_req_addr))
        end

        if ($root.test_bench.dut.core_dm_req_rvalid &&
            $root.test_bench.dut.core_dm_req_rready) begin
            core_dread_req_count++;
            core_dread_addr_q.push_back($root.test_bench.dut.core_dm_req_addr);
        end
        if ($root.test_bench.dut.core_dm_resp_rvalid) begin
            fetch_data_item item;
            core_dread_resp_count++;
            item = fetch_data_item::type_id::create("item");
            item.is_read = 1'b1;
            item.is_write = 1'b0;
            if (core_dread_addr_q.size() != 0) begin
                item.addr = core_dread_addr_q.pop_front();
            end
            else begin
                item.addr = 32'b0;
                `uvm_error("CACHE_HS", "core-dcache read response without pending request")
            end
            item.data = $root.test_bench.dut.core_dm_resp_rdata;
            dmem_port.write(item);
        end

        hold_core_dread_req = $root.test_bench.dut.core_dm_req_rvalid &&
                              !$root.test_bench.dut.core_dm_req_rready;
        hold_core_dread_addr = $root.test_bench.dut.core_dm_req_addr;
    endfunction

    function void check_core_dwrite();
        if (hold_core_dwrite_req &&
            $root.test_bench.dut.core_dm_req_wvalid &&
            !$root.test_bench.dut.core_dm_req_wready &&
            (($root.test_bench.dut.core_dm_req_addr !== hold_core_dwrite_addr) ||
             ($root.test_bench.dut.core_dm_req_wstrb !== hold_core_dwrite_strb) ||
             ($root.test_bench.dut.core_dm_req_wdata !== hold_core_dwrite_data))) begin
            `uvm_error("CACHE_HS", "core-dcache write request changed while stalled")
        end

        if ($root.test_bench.dut.core_dm_req_wvalid &&
            $root.test_bench.dut.core_dm_req_wready) begin
            fetch_data_item item;
            core_dwrite_req_count++;
            item = fetch_data_item::type_id::create("item");
            item.is_read = 1'b0;
            item.is_write = 1'b1;
            item.addr = $root.test_bench.dut.core_dm_req_addr;
            item.wstrb = $root.test_bench.dut.core_dm_req_wstrb;
            item.wdata = $root.test_bench.dut.core_dm_req_wdata;
            dmem_port.write(item);
        end
        if ($root.test_bench.dut.core_dm_resp_wvalid) begin
            core_dwrite_resp_count++;
        end

        hold_core_dwrite_req = $root.test_bench.dut.core_dm_req_wvalid &&
                               !$root.test_bench.dut.core_dm_req_wready;
        hold_core_dwrite_addr = $root.test_bench.dut.core_dm_req_addr;
        hold_core_dwrite_strb = $root.test_bench.dut.core_dm_req_wstrb;
        hold_core_dwrite_data = $root.test_bench.dut.core_dm_req_wdata;
    endfunction

    function void check_dc_mem_read();
        if (hold_dc_mem_read_req &&
            $root.test_bench.dut.dc_req_rvalid &&
            !$root.test_bench.dut.dc_req_rready &&
            ($root.test_bench.dut.dc_req_raddr !== hold_dc_mem_read_addr)) begin
            `uvm_error("CACHE_HS", $sformatf(
                "dcache-mem read addr changed while stalled old=0x%08x new=0x%08x",
                hold_dc_mem_read_addr, $root.test_bench.dut.dc_req_raddr))
        end

        if ($root.test_bench.dut.dc_req_rvalid &&
            $root.test_bench.dut.dc_req_rready) begin
            dc_mem_read_req_count++;
        end
        if ($root.test_bench.dut.dc_resp_rvalid) begin
            dc_mem_read_resp_count++;
        end

        hold_dc_mem_read_req = $root.test_bench.dut.dc_req_rvalid &&
                               !$root.test_bench.dut.dc_req_rready;
        hold_dc_mem_read_addr = $root.test_bench.dut.dc_req_raddr;
    endfunction

    function void check_dc_mem_write();
        if (hold_dc_mem_write_req &&
            $root.test_bench.dut.dc_req_wvalid &&
            !$root.test_bench.dut.dc_req_wready &&
            (($root.test_bench.dut.dc_req_waddr !== hold_dc_mem_write_addr) ||
             ($root.test_bench.dut.dc_req_wdata !== hold_dc_mem_write_data))) begin
            `uvm_error("CACHE_HS", "dcache-mem write request changed while stalled")
        end

        if ($root.test_bench.dut.dc_req_wvalid &&
            $root.test_bench.dut.dc_req_wready) begin
            dc_mem_write_req_count++;
        end
        if ($root.test_bench.dut.dc_resp_wvalid) begin
            dc_mem_write_resp_count++;
        end

        hold_dc_mem_write_req = $root.test_bench.dut.dc_req_wvalid &&
                                !$root.test_bench.dut.dc_req_wready;
        hold_dc_mem_write_addr = $root.test_bench.dut.dc_req_waddr;
        hold_dc_mem_write_data = $root.test_bench.dut.dc_req_wdata;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("CACHE_HS", $sformatf(
            "core_ifetch req=%0d resp=%0d ic_mem req=%0d resp=%0d",
            core_ifetch_req_count, core_ifetch_resp_count,
            ic_mem_req_count, ic_mem_resp_count), UVM_LOW)
    endfunction

endclass
