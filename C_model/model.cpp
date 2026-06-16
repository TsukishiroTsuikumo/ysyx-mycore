#include "model.hpp"
#include <cstdint>
#include <iostream>

namespace {

inline uint32_t sign_extend(uint32_t value, unsigned width) {
    const uint32_t sign = 1u << (width - 1);
    return (value ^ sign) - sign;
}

inline uint32_t div_signed(uint32_t lhs, uint32_t rhs) {
    if (rhs == 0) return 0xffffffffu;
    if (lhs == 0x80000000u && rhs == 0xffffffffu) return 0x80000000u;
    return static_cast<uint32_t>(static_cast<int32_t>(lhs) / static_cast<int32_t>(rhs));
}

inline uint32_t rem_signed(uint32_t lhs, uint32_t rhs) {
    if (rhs == 0) return lhs;
    if (lhs == 0x80000000u && rhs == 0xffffffffu) return 0;
    return static_cast<uint32_t>(static_cast<int32_t>(lhs) % static_cast<int32_t>(rhs));
}

} // namespace

void mycore::reset() {
    state_ = mycore_state{};
    mem_.clear();
}

void mycore::load_image() {
    mem_.load_image();
}

void mycore::load_image(const std::string& filename) {
    mem_.load_image(filename);
}

void mycore::mem_write32(uint32_t addr, uint32_t data) {
    mem_.write32(addr, data);
}

void mycore::set_pc(uint32_t pc) {
    state_.pc = pc;
}

void mycore::set_reg(uint32_t idx, uint32_t value) {
    if (idx < state_.regs.size()) {
        state_.regs[idx] = (idx == 0) ? 0 : value;
    }
}

mycore_retire_trace mycore::step() {
    static int step_count = 0;
    const bool has = mem_.has_word(state_.pc);
    const uint32_t instr = has ? mem_.read32(state_.pc) : 0x00000013u;
    const uint32_t pc = state_.pc;

    if (step_count < 5 || (pc >= 0x130 && pc <= 0x140))
        std::cout << "CMODEL step[" << step_count << "]: pc=0x" << std::hex << pc
                  << " has=" << has << " instr=0x" << instr << std::dec << std::endl;
    step_count++;
    const uint32_t opcode = instr & 0x7f;
    const uint32_t rd = (instr >> 7) & 0x1f;
    const uint32_t funct3 = (instr >> 12) & 0x7;
    const uint32_t rs1 = (instr >> 15) & 0x1f;
    const uint32_t rs2 = (instr >> 20) & 0x1f;
    const uint32_t funct7 = instr >> 25;
    const uint32_t v1 = state_.regs[rs1];
    const uint32_t v2 = state_.regs[rs2];

    uint32_t next_pc = pc + 4;
    uint32_t result = 0;
    bool write_rd = false;
    mycore_retire_trace trace;

    trace.retire = true;
    trace.pc = pc;
    trace.instr = instr;

    switch (opcode) {
    case 0x33: {
        const uint32_t shamt = v2 & 0x1f;
        write_rd = true;
        if (funct7 == 0x01) {
            switch (funct3) {
            case 0x0:
                result = static_cast<uint32_t>(static_cast<uint64_t>(v1) * v2);
                break;
            case 0x1:
                result = static_cast<uint32_t>((static_cast<int64_t>(static_cast<int32_t>(v1)) *
                                                static_cast<int64_t>(static_cast<int32_t>(v2))) >> 32);
                break;
            case 0x2:
                result = static_cast<uint32_t>((static_cast<int64_t>(static_cast<int32_t>(v1)) *
                                                static_cast<uint64_t>(v2)) >> 32);
                break;
            case 0x3:
                result = static_cast<uint32_t>((static_cast<uint64_t>(v1) * v2) >> 32);
                break;
            case 0x4:
                result = div_signed(v1, v2);
                break;
            case 0x5:
                result = (v2 == 0) ? 0xffffffffu : (v1 / v2);
                break;
            case 0x6:
                result = rem_signed(v1, v2);
                break;
            case 0x7:
                result = (v2 == 0) ? v1 : (v1 % v2);
                break;
            }
        } else if (funct7 == 0x20) {
            switch (funct3) {
            case 0x0:
                result = v1 - v2;
                break;
            case 0x5:
                result = static_cast<uint32_t>(static_cast<int32_t>(v1) >> shamt);
                break;
            default:
                write_rd = false;
                break;
            }
        } else {
            switch (funct3) {
            case 0x0:
                result = v1 + v2;
                break;
            case 0x1:
                result = v1 << shamt;
                break;
            case 0x2:
                result = (static_cast<int32_t>(v1) < static_cast<int32_t>(v2)) ? 1u : 0u;
                break;
            case 0x3:
                result = (v1 < v2) ? 1u : 0u;
                break;
            case 0x4:
                result = v1 ^ v2;
                break;
            case 0x5:
                result = v1 >> shamt;
                break;
            case 0x6:
                result = v1 | v2;
                break;
            case 0x7:
                result = v1 & v2;
                break;
            }
        }
        break;
    }
    case 0x13: {
        const uint32_t imm = sign_extend(instr >> 20, 12);
        const uint32_t shamt = (instr >> 20) & 0x1f;
        write_rd = true;
        switch (funct3) {
        case 0x0:
            result = v1 + imm;
            break;
        case 0x1:
            result = v1 << shamt;
            break;
        case 0x2:
            result = (static_cast<int32_t>(v1) < static_cast<int32_t>(imm)) ? 1u : 0u;
            break;
        case 0x3:
            result = (v1 < imm) ? 1u : 0u;
            break;
        case 0x4:
            result = v1 ^ imm;
            break;
        case 0x5:
            result = (funct7 == 0x20) ? static_cast<uint32_t>(static_cast<int32_t>(v1) >> shamt) : (v1 >> shamt);
            break;
        case 0x6:
            result = v1 | imm;
            break;
        case 0x7:
            result = v1 & imm;
            break;
        }
        break;
    }
    case 0x03: {
        const uint32_t addr = v1 + sign_extend(instr >> 20, 12);
        const uint32_t raw_data = mem_.read32(addr);
        write_rd = true;
        trace.dmem_valid = true;
        trace.dmem_is_read = true;
        trace.dmem_addr = addr;
        trace.dmem_rdata = raw_data;
        switch (funct3) {
        case 0x0:
            result = sign_extend(raw_data & 0xffu, 8);
            break;
        case 0x1:
            result = sign_extend(raw_data & 0xffffu, 16);
            break;
        case 0x2:
            result = raw_data;
            break;
        case 0x4:
            result = raw_data & 0xffu;
            break;
        case 0x5:
            result = raw_data & 0xffffu;
            break;
        default:
            write_rd = false;
            trace.dmem_valid = false;
            break;
        }
        break;
    }
    case 0x23: {
        const uint32_t imm = sign_extend(((instr >> 25) << 5) | rd, 12);
        const uint32_t addr = v1 + imm;
        trace.dmem_valid = true;
        trace.dmem_is_write = true;
        trace.dmem_addr = addr;
        trace.dmem_wdata = v2;
        switch (funct3) {
        case 0x0:
            trace.dmem_wstrb = 0x1;
            mem_.write8(addr, v2);
            break;
        case 0x1:
            trace.dmem_wstrb = 0x3;
            mem_.write16(addr, v2);
            break;
        case 0x2:
            trace.dmem_wstrb = 0xf;
            mem_.write32(addr, v2);
            break;
        default:
            trace.dmem_valid = false;
            break;
        }
        break;
    }
    case 0x63: {
        const uint32_t imm = sign_extend(((instr >> 31) << 12) |
                                         (((instr >> 7) & 0x1) << 11) |
                                         (((instr >> 25) & 0x3f) << 5) |
                                         (((instr >> 8) & 0xf) << 1),
                                         13);
        bool taken = false;
        switch (funct3) {
        case 0x0:
            taken = (v1 == v2);
            break;
        case 0x1:
            taken = (v1 != v2);
            break;
        case 0x4:
            taken = static_cast<int32_t>(v1) < static_cast<int32_t>(v2);
            break;
        case 0x5:
            taken = static_cast<int32_t>(v1) >= static_cast<int32_t>(v2);
            break;
        case 0x6:
            taken = v1 < v2;
            break;
        case 0x7:
            taken = v1 >= v2;
            break;
        }
        if (taken) next_pc = pc + imm;
        break;
    }
    case 0x6f: {
        const uint32_t imm = sign_extend(((instr >> 31) << 20) |
                                         (((instr >> 12) & 0xff) << 12) |
                                         (((instr >> 20) & 0x1) << 11) |
                                         (((instr >> 21) & 0x3ff) << 1),
                                         21);
        result = pc + 4;
        write_rd = true;
        next_pc = pc + imm;
        break;
    }
    case 0x67:
        result = pc + 4;
        write_rd = true;
        next_pc = (v1 + sign_extend(instr >> 20, 12)) & ~1u;
        break;
    case 0x37:
        result = instr & 0xfffff000u;
        write_rd = true;
        break;
    case 0x17:
        result = pc + (instr & 0xfffff000u);
        write_rd = true;
        break;
    }

    trace.commit = write_rd;
    trace.rd = rd;
    trace.rd_value = (rd == 0) ? 0 : result;

    if (write_rd && rd != 0) state_.regs[rd] = result;
    state_.regs[0] = 0;
    state_.pc = next_pc;
    return trace;
}
