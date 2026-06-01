class fetch_data_driver extends uvm_driver #(fetch_data_item);

    `uvm_component_utils(fetch_data_driver)

    virtual dcache_if vif;
    uvm_event #(uvm_object) test_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("FETCH_DATA_DRIVER", "Failed to get dcache interface");
        end
        test_done = uvm_event_pool::get_global("test_done");
    endfunction

    virtual task run_phase(uvm_phase phase);
        fetch_data_item item;

        bit        resp_rvalid_next;
        bit [31:0] resp_rdata_next;
        bit        resp_wvalid_next;
        bit        read_busy;
        bit        write_busy;

        vif.req_rready <= 1'b0;
        vif.req_wready <= 1'b0;
        vif.resp_rvalid <= 1'b0;
        vif.resp_wvalid <= 1'b0;
        vif.resp_rdata  <= 32'h0000_0000;
        resp_rvalid_next = 1'b0;
        resp_rdata_next  = 32'h0000_0000;
        resp_wvalid_next = 1'b0;
        read_busy = 1'b0;
        write_busy = 1'b0;

        fork
            begin
                forever begin
                    @(negedge vif.clk);
                    vif.req_rready <= !vif.rst && !read_busy && !write_busy;
                    vif.req_wready <= !vif.rst && !read_busy && !write_busy;
                end
            end

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
                        read_busy = 1'b0;
                        write_busy = 1'b0;
                    end
                    else begin
                        vif.resp_rvalid <= resp_rvalid_next;
                        vif.resp_rdata  <= resp_rdata_next;
                        vif.resp_wvalid <= resp_wvalid_next;

                        if (resp_rvalid_next) begin
                            read_busy = 1'b0;
                        end
                        if (resp_wvalid_next) begin
                            write_busy = 1'b0;
                        end

                        resp_rvalid_next = 1'b0;
                        resp_wvalid_next = 1'b0;

                        if(vif.req_rvalid && vif.req_rready) begin
                            seq_item_port.get_next_item(item);
                            resp_rdata_next  = item.data;
                            resp_rvalid_next = 1'b1;
                            read_busy = 1'b1;
                            seq_item_port.item_done();
                        end

                        if(vif.req_wvalid && vif.req_wready) begin
                            resp_wvalid_next = 1'b1;
                            write_busy = 1'b1;
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
