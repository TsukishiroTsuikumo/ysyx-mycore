class program_responder extends fetch_instr_driver;
    `uvm_component_utils(program_responder)

    program_image image;
    uvm_analysis_port#(instr_item) analysis_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(program_image)::get(this, "", "image", image)) begin
            `uvm_fatal("PROGRAM_RESPONDER", "Failed to get program image from config DB");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        instr_item item;
        bit        resp_valid_next;
        bit [31:0] resp_data_next;
        bit        req_fire_sample;
        bit [31:0] req_addr_sample;

        vif.req_ready  <= 1'b0;
        vif.resp_valid <= 1'b0;
        vif.resp_data  <= 32'h0000_0013;

        resp_valid_next = 1'b0;
        resp_data_next  = 32'h0000_0013;
        req_fire_sample = 1'b0;
        req_addr_sample = 32'h0000_0000;

        fork
            begin
                forever begin
                    @(negedge vif.clk);
                    vif.req_ready <= !vif.rst;
                    req_fire_sample = !vif.rst && vif.req_valid;
                    req_addr_sample = vif.req_addr;
                end
            end

            begin
                forever begin
                    @(posedge vif.clk);

                    if (vif.rst) begin
                        vif.req_ready  <= 1'b0;
                        vif.resp_valid <= 1'b0;
                        vif.resp_data  <= 32'h0000_0013;
                        resp_valid_next = 1'b0;
                        resp_data_next  = 32'h0000_0013;
                        req_fire_sample = 1'b0;
                        req_addr_sample = 32'h0000_0000;
                    end
                    else begin
                        vif.resp_valid <= resp_valid_next;
                        vif.resp_data  <= resp_data_next;

                        if (resp_valid_next) begin
                            item = instr_item::type_id::create("item");
                            item.instr = resp_data_next;
                            analysis_port.write(item);
                        end

                        resp_valid_next = 1'b0;

                        if (req_fire_sample) begin
                            resp_data_next  = image.read_instr(req_addr_sample);
                            resp_valid_next = 1'b1;
                        end
                    end
                end
            end

            begin
                test_done.wait_ptrigger();
            end
        join_any
        disable fork;

        vif.req_ready  <= 1'b0;
        vif.resp_valid <= 1'b0;
        vif.resp_data  <= 32'h0000_0013;
    endtask

endclass
