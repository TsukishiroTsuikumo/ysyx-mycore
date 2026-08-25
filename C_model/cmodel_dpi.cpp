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

extern "C" void cmodel_imem_write32(uint32_t addr, uint32_t data) {
    g_core.imem_write32(addr, data);
}

extern "C" void cmodel_set_pc(uint32_t pc) {
    g_core.set_pc(pc);
}

extern "C" void cmodel_set_reg(uint32_t idx, uint32_t value) {
    g_core.set_reg(idx, value);
}

extern "C" uint32_t cmodel_get_reg(uint32_t idx) {
    return g_core.get_reg(idx);
}

extern "C" uint32_t cmodel_mem_peek8(uint32_t addr) {
    return g_core.mem_peek8(addr);
}

extern "C" uint32_t cmodel_mem_peek32(uint32_t addr) {
    return g_core.mem_peek32(addr);
}

extern "C" int cmodel_step(
    uint32_t* pc,
    uint32_t* instr,
    uint32_t* commit_valid,
    uint32_t* rd_addr,
    uint32_t* rd_data,
    uint32_t* addr,
    uint32_t* is_read,
    uint32_t* rdata,
    uint32_t* is_write,
    uint32_t* wstrb,
    uint32_t* wdata
) {
    try {
        const cmodel_retire_trace trace = g_core.step();

        *pc = trace.pc;
        *instr = trace.instr;
        *commit_valid = trace.commit_valid ? 1u : 0u;
        *rd_addr = trace.rd_addr;
        *rd_data = trace.rd_data;
        *addr = trace.addr;
        *is_read = trace.is_read ? 1u : 0u;
        *rdata = trace.rdata;
        *is_write = trace.is_write ? 1u : 0u;
        *wstrb = trace.wstrb;
        *wdata = trace.wdata;
        return 1;
    } catch (const std::exception& e) {
        report_error("cmodel_step", e);
        return 0;
    }
}
