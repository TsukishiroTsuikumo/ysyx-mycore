`ifndef YSYX_CACHE_MONITOR_SVH
`define YSYX_CACHE_MONITOR_SVH

class cache_monitor extends uvm_monitor;
    `uvm_component_utils(cache_monitor)

    virtual cache_uvm_if vif;
    uvm_analysis_port #(cache_transaction) analysis_port;
    cache_transaction ic_pending;
    cache_transaction dc_pending;
    bit left_initial_reset;
    bit reset_reported;
    bit flush_reported;

    function new(string name = "cache_monitor", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_uvm_if)::get(this, "", "vif", vif))
            `uvm_fatal("CACHE_MONITOR", "cache_uvm_if was not configured")
    endfunction

    virtual task run_phase(uvm_phase phase);
        cache_transaction item;
        forever begin
            @(posedge vif.clk);
            if (vif.reset) begin
                ic_pending = null;
                dc_pending = null;
                if (left_initial_reset && !reset_reported) begin
                    item = cache_transaction::type_id::create("reset_item");
                    item.op = cache_transaction::CACHE_RESET;
                    analysis_port.write(item);
                    reset_reported = 1'b1;
                end
                continue;
            end
            left_initial_reset = 1'b1;
            reset_reported = 1'b0;

            if (vif.flush_request && !flush_reported) begin
                item = cache_transaction::type_id::create("flush_item");
                item.op = cache_transaction::IC_FLUSH;
                if (ic_pending != null) begin
                    item.addr = ic_pending.addr;
                    item.mem_read_count = ic_pending.mem_read_count;
                end
                analysis_port.write(item);
                flush_reported = 1'b1;
                ic_pending = null;
            end
            else if (!vif.flush_request) begin
                flush_reported = 1'b0;
            end

            if (vif.ic_cpu_req_valid && vif.ic_cpu_req_ready) begin
                if (ic_pending != null)
                    `uvm_error("CACHE_MONITOR", "overlapping ICache CPU requests")
                ic_pending = cache_transaction::type_id::create("ic_pending");
                ic_pending.op = cache_transaction::IC_READ;
                ic_pending.addr = vif.ic_cpu_req_addr;
            end
            if (vif.dc_cpu_read_valid && vif.dc_cpu_read_ready) begin
                if (dc_pending != null)
                    `uvm_error("CACHE_MONITOR", "overlapping DCache CPU requests")
                dc_pending = cache_transaction::type_id::create("dc_read_pending");
                dc_pending.op = cache_transaction::DC_READ;
                dc_pending.addr = vif.dc_cpu_req_addr;
            end
            if (vif.dc_cpu_write_valid && vif.dc_cpu_write_ready) begin
                if (dc_pending != null)
                    `uvm_error("CACHE_MONITOR", "overlapping DCache CPU requests")
                dc_pending = cache_transaction::type_id::create("dc_write_pending");
                dc_pending.op = cache_transaction::DC_WRITE;
                dc_pending.addr = vif.dc_cpu_req_addr;
                dc_pending.wstrb = vif.dc_cpu_write_strb;
                dc_pending.wdata = vif.dc_cpu_write_data;
            end

            if (ic_pending != null) begin
                ic_pending.latency++;
                if (vif.ic_mem_req_valid && vif.ic_mem_req_ready)
                    ic_pending.mem_read_count++;
                if (vif.ic_mem_resp_valid &&
                    vif.ic_mem_resp_code != 2'b00) begin
                    ic_pending.fault = 1'b1;
                    ic_pending.response_code = vif.ic_mem_resp_code;
                end
                if (vif.ic_cpu_resp_valid) begin
                    ic_pending.rdata = vif.ic_cpu_resp_data;
                    analysis_port.write(ic_pending);
                    ic_pending = null;
                end
            end

            if (dc_pending != null) begin
                dc_pending.latency++;
                if (vif.dc_mem_read_valid && vif.dc_mem_read_ready)
                    dc_pending.mem_read_count++;
                if (vif.dc_mem_write_valid && vif.dc_mem_write_ready)
                    dc_pending.mem_write_count++;
                if (vif.dc_mem_read_resp_valid &&
                    vif.dc_mem_read_resp_code != 2'b00) begin
                    dc_pending.fault = 1'b1;
                    dc_pending.fault_is_writeback = 1'b0;
                    dc_pending.response_code = vif.dc_mem_read_resp_code;
                end
                if (vif.dc_mem_write_resp_valid &&
                    vif.dc_mem_write_resp_code != 2'b00) begin
                    dc_pending.fault = 1'b1;
                    dc_pending.fault_is_writeback = 1'b1;
                    dc_pending.response_code = vif.dc_mem_write_resp_code;
                end
                if (vif.dc_cpu_read_resp_valid &&
                    dc_pending.op == cache_transaction::DC_READ) begin
                    dc_pending.rdata = vif.dc_cpu_read_data;
                    analysis_port.write(dc_pending);
                    dc_pending = null;
                end
                else if (vif.dc_cpu_write_resp_valid &&
                         dc_pending.op == cache_transaction::DC_WRITE) begin
                    analysis_port.write(dc_pending);
                    dc_pending = null;
                end
            end
        end
    endtask
endclass

`endif
