class fetch_instr_driver extends uvm_driver #(instr_item);
    `uvm_component_utils(fetch_instr_driver)

    virtual icache_if vif;
    instr_item item;
    uvm_event#(uvm_object) test_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual icache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("FETCH_INSTR_DRIVER", "Virtual interface not found")
        end
        test_done = uvm_event_pool::get_global("test_done");
    endfunction

    virtual task run_phase(uvm_phase phase);

        instr_item item;
        bit        resp_v_next;
        bit [31:0] resp_data_next;

        vif.req_ready  <= 1'b0;
        vif.resp_valid <= 1'b0;
        vif.resp_data  <= 32'h0000_0013;

        resp_v_next    = 1'b0;
        resp_data_next = 32'h0000_0013;

        fork
            begin
                forever begin
                    @(posedge vif.clk);

                    if (vif.rst) begin
                        vif.req_ready  <= 1'b0;
                        vif.resp_valid <= 1'b0;
                        vif.resp_data  <= 32'h0000_0013;
                        resp_v_next      = 1'b0;
                        resp_data_next   = 32'h0000_0013;
                    end
                    else begin
                        vif.resp_valid <= resp_v_next;
                        vif.resp_data  <= resp_data_next;

                        vif.req_ready <= 1'b1;
                        resp_v_next = 1'b0;

                        if (vif.req_valid) begin
                            seq_item_port.get_next_item(item);
                            resp_data_next = item.instr;
                            resp_v_next    = 1'b1;
                            seq_item_port.item_done();
                        end
                    end
                end
            end

            begin
                test_done.wait_ptrigger();
                `uvm_info("FETCH_INSTR_DRIVER", "Test done event received, ending driver run phase", UVM_LOW)
            end
        join_any
        disable fork;

        vif.req_ready  <= 1'b0;
        vif.resp_valid <= 1'b0;
        vif.resp_data  <= 32'h0000_0013;

    endtask

endclass
