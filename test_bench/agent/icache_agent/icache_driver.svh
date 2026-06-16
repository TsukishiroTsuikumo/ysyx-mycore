class icache_driver extends uvm_driver #(icache_item);
    `uvm_component_utils(icache_driver)

    virtual icache_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual icache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ICACHE_DRIVER", "Virtual interface not found")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        icache_item item;

        vif.req_valid <= 1'b0;
        vif.req_addr  <= 32'b0;

        forever begin
            seq_item_port.get_next_item(item);

            @(posedge vif.clk);
            while (vif.reset) begin
                @(posedge vif.clk);
            end

            vif.req_valid <= 1'b1;
            vif.req_addr  <= item.address;

            do begin
                @(posedge vif.clk);
            end while (!vif.req_ready);

            vif.req_valid <= 1'b0;
            seq_item_port.item_done();
        end
    endtask

endclass
