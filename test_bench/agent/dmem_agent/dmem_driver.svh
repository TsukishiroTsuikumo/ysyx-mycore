class dmem_driver extends uvm_driver #(dmem_item);

    `uvm_component_utils(dmem_driver)

    virtual dcache_if vif;
    uvm_event #(uvm_object) test_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMEM_DRIVER", "Failed to get dcache interface");
        end
        test_done = uvm_event_pool::get_global("test_done");
    endfunction

    virtual task run_phase(uvm_phase phase);
        dmem_item item;

        bit        resp_rvalid_next;
        bit [31:0] resp_rdata_next;
        bit        resp_wvalid_next;

        vif.req_rready <= 1'b0;
        vif.req_wready <= 1'b0;
        vif.resp_rvalid <= 1'b0;
        vif.resp_wvalid <= 1'b0;
        vif.resp_rdata  <= 32'h0000_0000;
        resp_rvalid_next = 1'b0;
        resp_rdata_next  = 32'h0000_0000;
        resp_wvalid_next = 1'b0;

        fork
            begin
                forever begin
                    @(posedge vif.clk);
                    if(vif.rst) begin
                        vif.req_rready <= 1'b0;
                        vif.req_wready <= 1'b0;
                        vif.resp_rvalid <= 1'b0;
                        vif.resp_wvalid <= 1'b0;
                        vif.resp_rdata  <= 32'h0000_0000;
                        resp_rvalid_next = 1'b0;
                        resp_rdata_next  = 32'h0000_0000;
                        resp_wvalid_next = 1'b0;
                    end
                    else begin
                        vif.req_rready  <= 1'b1;
                        vif.req_wready  <= 1'b1;
                        vif.resp_rvalid <= resp_rvalid_next;
                        vif.resp_rdata  <= resp_rdata_next;
                        vif.resp_wvalid <= resp_wvalid_next;

                        resp_rvalid_next = 1'b0;
                        resp_wvalid_next = 1'b0;

                        if(vif.req_rvalid) begin
                            seq_item_port.get_next_item(item);
                            resp_rdata_next  = item.data;
                            resp_rvalid_next = 1'b1;
                            seq_item_port.item_done();
                        end

                        if(vif.req_wvalid) begin
                            resp_wvalid_next = 1'b1;
                        end
                    end
                end
            end

            begin
                test_done.wait_ptrigger();
            end
        join_any
        disable fork;

        vif.req_rready <= 1'b0;
        vif.req_wready <= 1'b0;
        vif.resp_rvalid <= 1'b0;
        vif.resp_wvalid <= 1'b0;
            
    endtask

endclass
