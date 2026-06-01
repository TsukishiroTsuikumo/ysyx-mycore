class dcache_test extends cache_base_test;
    `uvm_component_utils(dcache_test)

    function new(string name = "dcache_test", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
