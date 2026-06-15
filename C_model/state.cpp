#include "state.hpp"
#include <fstream>
#include <stdexcept>
#include <vector>

using namespace std;

bool get_plusarg(const string& key, string& value) {
    ifstream cmdline("/proc/self/cmdline", ios::binary);
    if (!cmdline) {
        throw runtime_error("Failed to read /proc/self/cmdline");
    }

    const string prefix = "+" + key + "=";

    string arg;
    char ch;
    while (cmdline.get(ch)) {
        if (ch == '\0') {
            if (arg.rfind(prefix, 0) == 0) {
                value = arg.substr(prefix.size());
                return true;
            }
            arg.clear();
        } else {
            arg.push_back(ch);
        }
    }

    if (!arg.empty() && arg.rfind(prefix, 0) == 0) {
        value = arg.substr(prefix.size());
        return true;
    }

    return false;
}

void memory::load_image() {
    string filename;

    if (!get_plusarg("IMAGE_FILE", filename)) {
        throw runtime_error("Missing plusarg: use +IMAGE_FILE=<path>");
    }

    load_image(filename);
}

void memory::load_image(const string& filename) {
    ifstream infile(filename);
    if (!infile) {
        throw runtime_error("Failed to open memory image file: " + filename);
    }

    mem.clear();

    uint32_t word;
    uint32_t addr = 0;

    while (infile >> hex >> word) {
        write32(addr, word);
        addr += 4;
    }
}

void memory::write8(uint32_t addr, uint32_t data) {
    uint8_t byte = data & 0xFF;
    mem[addr] = byte;
}

void memory::write16(uint32_t addr, uint32_t data) {
    uint16_t word = data & 0xFFFF;
    mem[addr] = word & 0xFF;
    mem[addr + 1] = (word >> 8) & 0xFF;
}

void memory::write32(uint32_t addr, uint32_t data) {
    mem[addr] = data & 0xFF;
    mem[addr + 1] = (data >> 8) & 0xFF;
    mem[addr + 2] = (data >> 16) & 0xFF;
    mem[addr + 3] = (data >> 24) & 0xFF;
}

uint8_t memory::read8(uint32_t addr) const {
    return mem.at(addr);
}

uint16_t memory::read16(uint32_t addr) const {
    return (mem.at(addr + 1) << 8) | mem.at(addr);
}

uint32_t memory::read32(uint32_t addr) const {
    return (mem.at(addr + 3) << 24) | (mem.at(addr + 2) << 16) | (mem.at(addr + 1) << 8) | mem.at(addr);
}
