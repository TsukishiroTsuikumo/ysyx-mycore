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
        bit         pending_valid;
        bit [127:0] pending_data;
        bit         ready_now;
        bit [127:0] line_data;
        bit [127:0] line_by_address [bit [27:0]];
        bit [27:0]  line_key;
        int unsigned word_index;

        vif.req_ready  <= 1'b0;
        vif.resp_valid <= 1'b0;
        vif.resp_data  <= {4{32'h0000_0013}};

        pending_valid = 1'b0;
        pending_data  = {4{32'h0000_0013}};
        ready_now     = 1'b0;

        fork
            begin
                forever begin
                    @(negedge vif.clk);
                    if (vif.reset) begin
                        vif.req_ready  <= 1'b0;
                        vif.resp_valid <= 1'b0;
                        vif.resp_data  <= {4{32'h0000_0013}};
                        pending_valid  = 1'b0;
                        pending_data   = {4{32'h0000_0013}};
                        ready_now      = 1'b0;
                        line_by_address.delete();
                    end
                    else begin
                        ready_now = 1'b1;

                        vif.req_ready  <= ready_now;
                        vif.resp_valid <= pending_valid;
                        vif.resp_data  <= pending_data;

                        pending_valid = 1'b0;
                        pending_data  = {4{32'h0000_0013}};
                    end
                end
            end

            begin
                forever begin
                    @(posedge vif.clk);

                    if (vif.reset) begin
                        pending_valid = 1'b0;
                        pending_data  = {4{32'h0000_0013}};
                        line_by_address.delete();
                    end
                    else if (vif.req_valid && vif.req_ready) begin
                        line_key = vif.req_addr[31:4];
                        if (line_by_address.exists(line_key)) begin
                            line_data = line_by_address[line_key];
                        end
                        else begin
                            line_data = {4{32'h0000_0013}};
                            for (word_index = 0; word_index < 4;
                                 word_index = word_index + 1) begin
                                seq_item_port.get_next_item(item);
                                line_data[word_index*32 +: 32] = item.instr;
                                seq_item_port.item_done();
                            end
                            line_by_address[line_key] = line_data;
                        end
                        pending_data  = line_data;
                        pending_valid = 1'b1;
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
        vif.resp_data  <= {4{32'h0000_0013}};

    endtask

endclass
