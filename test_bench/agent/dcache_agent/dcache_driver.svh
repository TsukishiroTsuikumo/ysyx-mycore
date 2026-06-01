class dcache_driver extends uvm_driver #(dcache_item);

    `uvm_component_utils(dcache_driver)

    virtual dcache_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DCACHE_DRIVER", "Failed to get dcache interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        dcache_item item;

        vif.req_addr   <= 32'b0;
        vif.req_rvalid <= 1'b0;
        vif.req_wvalid <= 1'b0;
        vif.req_wstrb  <= 4'b0;
        vif.req_wdata  <= 32'b0;

        forever begin
            seq_item_port.get_next_item(item);

            @(posedge vif.clk);
            while (vif.rst) begin
                @(posedge vif.clk);
            end

            vif.req_addr <= item.addr;
            if (item.is_read) begin
                vif.req_rvalid <= 1'b1;
                do begin
                    @(posedge vif.clk);
                end while (!vif.req_rready);
                vif.req_rvalid <= 1'b0;
                do begin
                    @(posedge vif.clk);
                end while (!vif.resp_rvalid);
                item.rdata = vif.resp_rdata;
            end
            else begin
                vif.req_wvalid <= 1'b1;
                vif.req_wstrb  <= item.wstrb;
                vif.req_wdata  <= item.wdata;
                do begin
                    @(posedge vif.clk);
                end while (!vif.req_wready);
                vif.req_wvalid <= 1'b0;
                do begin
                    @(posedge vif.clk);
                end while (!vif.resp_wvalid);
            end

            seq_item_port.item_done();
        end
    endtask

endclass
