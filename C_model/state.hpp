#pragma once

#include <cstdint>
#include <array>
#include <map>
#include <string>

struct mycore_state {
    uint32_t pc = 0;
    std::array<uint32_t, 32> regs = {0}; 
};

class memory {
    
    public:

        memory() = default;

        void load_image();
        void load_image(const std::string& filename);
        void clear();

        void write8(uint32_t addr, uint32_t data);
        void write16(uint32_t addr, uint32_t data);
        void write32(uint32_t addr, uint32_t data);
        
        uint8_t read8(uint32_t addr) const;
        uint16_t read16(uint32_t addr) const;
        uint32_t read32(uint32_t addr) const;
        bool has_word(uint32_t addr) const;

    private:
        std::map<uint32_t, uint8_t> mem;
};
