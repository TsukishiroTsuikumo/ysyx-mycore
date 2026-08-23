`ifndef YSYX_CACHE_MEMORY_MODEL_SVH
`define YSYX_CACHE_MEMORY_MODEL_SVH

class cache_memory_model extends uvm_component;
    `uvm_component_utils(cache_memory_model)

    localparam int unsigned MEM_BYTES = 4096;
    virtual cache_uvm_if vif;
    bit [7:0] mem [0:MEM_BYTES-1];
    bit [31:0] lfsr_q = 32'hc001_cafe;

    int unsigned accepted_reads;
    int unsigned accepted_writes;
    int unsigned response_delay_hits[3];
    int unsigned ready_backpressure_cycles;
    int unsigned successful_writebacks;
    int unsigned failed_writebacks;
    int unsigned concurrent_pending_cycles;

    bit reset_active = 1'b1;
    bit ic_pending, dr_pending, dw_pending;
    bit [31:0] ic_addr_q, dr_addr_q, dw_addr_q;
    bit [127:0] dw_data_q;
    bit [1:0] ic_resp_q, dr_resp_q, dw_resp_q;
    int unsigned ic_delay_q, dr_delay_q, dw_delay_q;
    int unsigned ic_request_count, dr_request_count, dw_request_count;
    int unsigned ic_stall_q, dr_stall_q, dw_stall_q;
    bit ic_ready_q, dr_ready_q, dw_ready_q;

    function new(string name = "cache_memory_model", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic bit [7:0] initial_byte(bit [31:0] address);
        bit [31:0] mixed;
        mixed = (address * 32'd29) ^ (address >> 3) ^ 32'h0000_005a;
        return mixed[7:0];
    endfunction

    function automatic bit [31:0] next_lfsr(bit [31:0] value);
        return {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    function automatic int unsigned scheduled_delay(
        int unsigned request_index,
        bit [31:0] random_bits
    );
        case (request_index)
            0: return 0;
            1: return 2;
            2: return 4;
            default: return random_bits[2:0] % 6;
        endcase
    endfunction

    function automatic int unsigned delay_bucket(int unsigned delay);
        if (delay == 0) return 0;
        if (delay <= 2) return 1;
        return 2;
    endfunction

    function automatic bit [1:0] ic_response(bit [31:0] address);
        // Dedicated stale-fault probe for the in-flight flush test.  A correct
        // controller drains this response without a refill, CPU completion, or
        // fault pulse.
        if ((address & 32'hffff_fff0) == 32'h0000_0750) return 2'b10;
        if ((address & 32'hffff_fff0) == 32'h0000_0800) return 2'b10;
        if ((address & 32'hffff_fff0) == 32'h0000_0900) return 2'b11;
        return 2'b00;
    endfunction

    function automatic bit [1:0] dc_read_response(bit [31:0] address);
        if ((address & 32'hffff_fff0) == 32'h0000_0a00) return 2'b10;
        return 2'b00;
    endfunction

    function automatic bit [1:0] dc_write_response(bit [31:0] address);
        if ((address & 32'hffff_fff0) == 32'h0000_0b00) return 2'b10;
        return 2'b00;
    endfunction

    function automatic bit [127:0] read_line(bit [31:0] address);
        bit [127:0] line;
        int unsigned base;
        base = address & 32'hffff_fff0;
        if (base + 15 >= MEM_BYTES)
            `uvm_fatal("CACHE_MEMORY", $sformatf("read outside memory: 0x%08x", address))
        for (int unsigned i = 0; i < 16; i++)
            line[i*8 +: 8] = mem[base+i];
        return line;
    endfunction

    function void write_line(bit [31:0] address, bit [127:0] data);
        int unsigned base;
        base = address & 32'hffff_fff0;
        if (base + 15 >= MEM_BYTES)
            `uvm_fatal("CACHE_MEMORY", $sformatf("write outside memory: 0x%08x", address))
        for (int unsigned i = 0; i < 16; i++)
            mem[base+i] = data[i*8 +: 8];
    endfunction

    function void arm_ic_ready();
        int unsigned stall;
        stall = scheduled_delay(ic_request_count, lfsr_q);
        ic_stall_q = stall;
        ic_ready_q = (stall == 0);
        vif.ic_mem_req_ready <= ic_ready_q;
    endfunction

    function void arm_dr_ready();
        int unsigned stall;
        stall = scheduled_delay(dr_request_count, lfsr_q >> 3);
        dr_stall_q = stall;
        dr_ready_q = (stall == 0);
        vif.dc_mem_read_ready <= dr_ready_q;
    endfunction

    function void arm_dw_ready();
        int unsigned stall;
        stall = scheduled_delay(dw_request_count, lfsr_q >> 6);
        dw_stall_q = stall;
        dw_ready_q = (stall == 0);
        vif.dc_mem_write_ready <= dw_ready_q;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_uvm_if)::get(this, "", "vif", vif))
            `uvm_fatal("CACHE_MEMORY", "cache_uvm_if was not configured")
        for (int unsigned i = 0; i < MEM_BYTES; i++)
            mem[i] = initial_byte(i);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit accepted;
        int unsigned delay;

        vif.ic_mem_req_ready       <= 1'b0;
        vif.ic_mem_resp_valid      <= 1'b0;
        vif.ic_mem_resp_data       <= '0;
        vif.ic_mem_resp_code       <= 2'b00;
        vif.dc_mem_read_ready      <= 1'b0;
        vif.dc_mem_read_resp_valid <= 1'b0;
        vif.dc_mem_read_resp_data  <= '0;
        vif.dc_mem_read_resp_code  <= 2'b00;
        vif.dc_mem_write_ready     <= 1'b0;
        vif.dc_mem_write_resp_valid <= 1'b0;
        vif.dc_mem_write_resp_code <= 2'b00;

        forever begin
            @(posedge vif.clk);
            if (vif.reset) begin
                reset_active = 1'b1;
                ic_pending = 1'b0;
                dr_pending = 1'b0;
                dw_pending = 1'b0;
                ic_ready_q = 1'b0;
                dr_ready_q = 1'b0;
                dw_ready_q = 1'b0;
                vif.ic_mem_req_ready <= 1'b0;
                vif.dc_mem_read_ready <= 1'b0;
                vif.dc_mem_write_ready <= 1'b0;
                vif.ic_mem_resp_valid <= 1'b0;
                vif.dc_mem_read_resp_valid <= 1'b0;
                vif.dc_mem_write_resp_valid <= 1'b0;
                continue;
            end

            vif.ic_mem_resp_valid <= 1'b0;
            vif.dc_mem_read_resp_valid <= 1'b0;
            vif.dc_mem_write_resp_valid <= 1'b0;
            lfsr_q = next_lfsr(lfsr_q);

            if (reset_active) begin
                reset_active = 1'b0;
                arm_ic_ready();
                arm_dr_ready();
                arm_dw_ready();
                continue;
            end

            accepted = 1'b0;
            if (ic_pending) begin
                if (ic_delay_q == 0) begin
                    vif.ic_mem_resp_valid <= 1'b1;
                    vif.ic_mem_resp_data <= read_line(ic_addr_q);
                    vif.ic_mem_resp_code <= ic_resp_q;
                    ic_pending = 1'b0;
                    arm_ic_ready();
                end
                else ic_delay_q--;
            end
            else if (vif.ic_mem_req_valid && ic_ready_q) begin
                ic_addr_q = vif.ic_mem_req_addr;
                ic_resp_q = ic_response(ic_addr_q);
                // Keep the dedicated I/D-concurrency probes outstanding long
                // enough to overlap even when the independently pipelined
                // cache controllers reach memory one cycle apart.
                if ((ic_addr_q & 32'hffff_fff0) == 32'h0000_0750)
                    delay = 8;
                else if ((ic_addr_q & 32'hffff_fff0) == 32'h0000_0550)
                    delay = 6;
                else
                    delay = scheduled_delay(ic_request_count, lfsr_q);
                ic_delay_q = delay;
                response_delay_hits[delay_bucket(delay)]++;
                accepted_reads++;
                ic_request_count++;
                ic_pending = 1'b1;
                ic_ready_q = 1'b0;
                vif.ic_mem_req_ready <= 1'b0;
                accepted = 1'b1;
            end
            else if (!ic_ready_q && vif.ic_mem_req_valid) begin
                ready_backpressure_cycles++;
                if (ic_stall_q != 0) ic_stall_q--;
                if (ic_stall_q == 0) begin
                    ic_ready_q = 1'b1;
                    vif.ic_mem_req_ready <= 1'b1;
                end
            end

            if (dr_pending) begin
                if (dr_delay_q == 0) begin
                    vif.dc_mem_read_resp_valid <= 1'b1;
                    vif.dc_mem_read_resp_data <= read_line(dr_addr_q);
                    vif.dc_mem_read_resp_code <= dr_resp_q;
                    dr_pending = 1'b0;
                    arm_dr_ready();
                end
                else dr_delay_q--;
            end
            else if (vif.dc_mem_read_valid && dr_ready_q) begin
                dr_addr_q = vif.dc_mem_read_addr;
                dr_resp_q = dc_read_response(dr_addr_q);
                if ((dr_addr_q & 32'hffff_fff0) == 32'h0000_0650)
                    delay = 6;
                else
                    delay = scheduled_delay(dr_request_count, lfsr_q >> 3);
                dr_delay_q = delay;
                response_delay_hits[delay_bucket(delay)]++;
                accepted_reads++;
                dr_request_count++;
                dr_pending = 1'b1;
                dr_ready_q = 1'b0;
                vif.dc_mem_read_ready <= 1'b0;
            end
            else if (!dr_ready_q && vif.dc_mem_read_valid) begin
                ready_backpressure_cycles++;
                if (dr_stall_q != 0) dr_stall_q--;
                if (dr_stall_q == 0) begin
                    dr_ready_q = 1'b1;
                    vif.dc_mem_read_ready <= 1'b1;
                end
            end

            if (dw_pending) begin
                if (dw_delay_q == 0) begin
                    vif.dc_mem_write_resp_valid <= 1'b1;
                    vif.dc_mem_write_resp_code <= dw_resp_q;
                    if (dw_resp_q == 2'b00) begin
                        write_line(dw_addr_q, dw_data_q);
                        successful_writebacks++;
                    end
                    else failed_writebacks++;
                    dw_pending = 1'b0;
                    arm_dw_ready();
                end
                else dw_delay_q--;
            end
            else if (vif.dc_mem_write_valid && dw_ready_q) begin
                dw_addr_q = vif.dc_mem_write_addr;
                dw_data_q = vif.dc_mem_write_data;
                dw_resp_q = dc_write_response(dw_addr_q);
                delay = scheduled_delay(dw_request_count, lfsr_q >> 6);
                dw_delay_q = delay;
                response_delay_hits[delay_bucket(delay)]++;
                accepted_writes++;
                dw_request_count++;
                dw_pending = 1'b1;
                dw_ready_q = 1'b0;
                vif.dc_mem_write_ready <= 1'b0;
            end
            else if (!dw_ready_q && vif.dc_mem_write_valid) begin
                ready_backpressure_cycles++;
                if (dw_stall_q != 0) dw_stall_q--;
                if (dw_stall_q == 0) begin
                    dw_ready_q = 1'b1;
                    vif.dc_mem_write_ready <= 1'b1;
                end
            end

            if (ic_pending && dr_pending)
                concurrent_pending_cycles++;
        end
    endtask
endclass

`endif
