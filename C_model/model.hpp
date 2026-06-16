#pragma once

#include "state.hpp"
#include <string>

struct mycore_retire_trace {
    bool retire = false;
    bool commit = false;
    uint32_t pc = 0;
    uint32_t instr = 0;
    uint32_t rd = 0;
    uint32_t rd_value = 0;

    bool dmem_valid = false;
    bool dmem_is_read = false;
    bool dmem_is_write = false;
    uint32_t dmem_addr = 0;
    uint32_t dmem_wstrb = 0;
    uint32_t dmem_wdata = 0;
    uint32_t dmem_rdata = 0;
};

class mycore {
    public:
        mycore() : state_({0, {0}}), mem_() {};
        void reset();
        void load_image();
        void load_image(const std::string& filename);
        void mem_write32(uint32_t addr, uint32_t data);
        void set_pc(uint32_t pc);
        void set_reg(uint32_t idx, uint32_t value);
        mycore_retire_trace step();
    private:
        mycore_state state_;
        memory mem_;
};
