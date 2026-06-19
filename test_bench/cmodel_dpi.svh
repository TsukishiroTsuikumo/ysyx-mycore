import "DPI-C" function int cmodel_init_empty();
import "DPI-C" function int cmodel_init_from_file(input string filename);
import "DPI-C" function void cmodel_mem_write32(input int unsigned addr, input int unsigned data);
import "DPI-C" function void cmodel_set_pc(input int unsigned pc);
import "DPI-C" function void cmodel_set_reg(input int unsigned idx, input int unsigned value);
import "DPI-C" function int cmodel_step(
    output int unsigned pc,
    output int unsigned instr,
    output int unsigned commit_valid,
    output int unsigned rd_addr,
    output int unsigned rd_data,
    output int unsigned addr,
    output int unsigned is_read,
    output int unsigned rdata,
    output int unsigned is_write,
    output int unsigned wstrb,
    output int unsigned wdata
);
