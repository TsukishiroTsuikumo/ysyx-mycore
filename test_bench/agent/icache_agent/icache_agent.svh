class icache_agent extends uvm_agent;

    `uvm_component_utils(icache_agent)

    fetch_instr_seqencer seq;
    icache_driver driver;
    icache_monitor monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    driver = icache_driver::type_id::create("driver", this);
    monitor = icache_monitor::type_id::create("monitor", this);
  endfunction

endclass
