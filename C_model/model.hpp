#pragma once

#include "state.hpp"
#include <string>

struct cmodel_retire_trace {
    uint32_t pc = 0;
    uint32_t instr = 0;
    bool     commit_valid = false;
    uint32_t rd_addr = 0;
    uint32_t rd_data = 0;
    uint32_t addr = 0;
    bool     is_read = false;
    uint32_t rdata = 0;
    bool     is_write = false;
    uint32_t wstrb = 0;
    uint32_t wdata = 0;
};

class mycore {
    public:
        mycore() : state_({0, {0}}), mem_(), imem_(), use_separate_imem_(false) {};
        void reset();
        void load_image();
        void load_image(const std::string& filename);
        void mem_write32(uint32_t addr, uint32_t data);
        void imem_write32(uint32_t addr, uint32_t data);
        void set_pc(uint32_t pc);
        void set_reg(uint32_t idx, uint32_t value);
        uint32_t get_reg(uint32_t idx) const;
        uint8_t mem_peek8(uint32_t addr) const;
        uint32_t mem_peek32(uint32_t addr) const;
        cmodel_retire_trace step();
    private:
        mycore_state state_;
        memory mem_;
        memory imem_;
        bool use_separate_imem_;
};
