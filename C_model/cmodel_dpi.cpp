#include "model.hpp"

#include <cstdint>
#include <exception>
#include <iostream>

namespace {

mycore g_core;

void report_error(const char* func, const std::exception& e) {
    std::cerr << "CMODEL_ERROR " << func << ": " << e.what() << std::endl;
}

} // namespace

extern "C" int cmodel_init_empty() {
    try {
        g_core.reset();
        return 1;
    } catch (const std::exception& e) {
        report_error("cmodel_init_empty", e);
        return 0;
    }
}

extern "C" int cmodel_init_from_file(const char* filename) {
    try {
        g_core.reset();
        g_core.load_image(filename);
        return 1;
    } catch (const std::exception& e) {
        report_error("cmodel_init_from_file", e);
        return 0;
    }
}

extern "C" void cmodel_mem_write32(uint32_t addr, uint32_t data) {
    g_core.mem_write32(addr, data);
}

extern "C" void cmodel_set_pc(uint32_t pc) {
    g_core.set_pc(pc);
}

extern "C" void cmodel_set_reg(uint32_t idx, uint32_t value) {
    g_core.set_reg(idx, value);
}

extern "C" int cmodel_step(
    uint32_t* retire,
    uint32_t* commit,
    uint32_t* pc,
    uint32_t* instr,
    uint32_t* rd,
    uint32_t* rd_value,
    uint32_t* dmem_valid,
    uint32_t* dmem_is_read,
    uint32_t* dmem_is_write,
    uint32_t* dmem_addr,
    uint32_t* dmem_wstrb,
    uint32_t* dmem_wdata,
    uint32_t* dmem_rdata
) {
    try {
        const mycore_retire_trace trace = g_core.step();

        *retire = trace.retire ? 1u : 0u;
        *commit = trace.commit ? 1u : 0u;
        *pc = trace.pc;
        *instr = trace.instr;
        *rd = trace.rd;
        *rd_value = trace.rd_value;
        *dmem_valid = trace.dmem_valid ? 1u : 0u;
        *dmem_is_read = trace.dmem_is_read ? 1u : 0u;
        *dmem_is_write = trace.dmem_is_write ? 1u : 0u;
        *dmem_addr = trace.dmem_addr;
        *dmem_wstrb = trace.dmem_wstrb;
        *dmem_wdata = trace.dmem_wdata;
        *dmem_rdata = trace.dmem_rdata;
        return 1;
    } catch (const std::exception& e) {
        report_error("cmodel_step", e);
        return 0;
    }
}
