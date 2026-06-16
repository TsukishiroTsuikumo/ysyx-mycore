import "DPI-C" function int cmodel_init_empty();
import "DPI-C" function int cmodel_init_from_file(input string filename);
import "DPI-C" function void cmodel_mem_write32(input int unsigned addr, input int unsigned data);
import "DPI-C" function void cmodel_set_pc(input int unsigned pc);
import "DPI-C" function void cmodel_set_reg(input int unsigned idx, input int unsigned value);
import "DPI-C" function int cmodel_step(
    output int unsigned retire,
    output int unsigned commit,
    output int unsigned pc,
    output int unsigned instr,
    output int unsigned rd,
    output int unsigned rd_value,
    output int unsigned dmem_valid,
    output int unsigned dmem_is_read,
    output int unsigned dmem_is_write,
    output int unsigned dmem_addr,
    output int unsigned dmem_wstrb,
    output int unsigned dmem_wdata,
    output int unsigned dmem_rdata
);
