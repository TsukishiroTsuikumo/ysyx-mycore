// Processor-side instruction monitor shared by direct-memory and integrated
// Cache/AXI modes. Cache-line traffic is checked independently by axi_observer.
class cache_system_monitor extends uvm_monitor;
    `uvm_component_utils(cache_system_monitor)

    uvm_analysis_port #(instr_item) instr_port;

    int unsigned core_ifetch_req_count;
    int unsigned core_ifetch_resp_count;
    bit          hold_core_ifetch_req;
    bit [31:0]   hold_core_ifetch_addr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        instr_port = new("instr_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge $root.test_bench.clk);
            uvm_wait_for_nba_region();

            if ($root.test_bench.dut.reset) begin
                hold_core_ifetch_req = 1'b0;
                continue;
            end

            if (hold_core_ifetch_req &&
                $root.test_bench.dut.core_pm_req_valid &&
                !$root.test_bench.dut.core_pm_req_ready &&
                ($root.test_bench.dut.core_pm_req_addr !== hold_core_ifetch_addr)) begin
                `uvm_error("ICACHE_HS", $sformatf(
                    "core fetch address changed while stalled old=0x%08x new=0x%08x",
                    hold_core_ifetch_addr,
                    $root.test_bench.dut.core_pm_req_addr))
            end

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
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("ICACHE_HS", $sformatf(
            "core_ifetch req=%0d resp=%0d",
            core_ifetch_req_count, core_ifetch_resp_count), UVM_LOW)
    endfunction

endclass
