#include "model.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {

uint32_t encode_i(uint32_t imm, uint32_t rs1, uint32_t funct3,
                  uint32_t rd, uint32_t opcode = 0x13) {
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) |
           (rd << 7) | opcode;
}

uint32_t encode_r(uint32_t funct7, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3, uint32_t rd) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (rd << 7) | 0x33;
}

uint32_t encode_s(uint32_t imm, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3) {
    return (((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | ((imm & 0x1f) << 7) | 0x23;
}

uint32_t encode_b(uint32_t imm, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3) {
    return (((imm >> 12) & 0x1) << 31) |
           (((imm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (((imm >> 1) & 0xf) << 8) |
           (((imm >> 11) & 0x1) << 7) | 0x63;
}

[[noreturn]] void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << std::endl;
    std::exit(1);
}

void expect(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

void test_integer_memory_and_branch() {
    mycore core;
    core.reset();
    core.mem_write32(0x00, encode_i(5, 0, 0, 1));               // addi x1,x0,5
    core.mem_write32(0x04, encode_i(3, 0, 0, 2));               // addi x2,x0,3
    core.mem_write32(0x08, encode_r(0, 2, 1, 0, 3));            // add x3,x1,x2
    core.mem_write32(0x0c, encode_s(0x100, 3, 0, 2));           // sw x3,0x100(x0)
    core.mem_write32(0x10, encode_i(0x100, 0, 2, 4, 0x03));     // lw x4,0x100(x0)
    core.mem_write32(0x14, encode_b(8, 4, 3, 0));               // beq x3,x4,+8
    core.mem_write32(0x18, encode_i(1, 0, 0, 5));               // skipped
    core.mem_write32(0x1c, encode_i(9, 0, 0, 6));               // addi x6,x0,9

    cmodel_retire_trace trace;
    trace = core.step();
    expect(trace.commit_valid && trace.rd_addr == 1 && trace.rd_data == 5,
           "ADDI trace mismatch");
    core.step();
    trace = core.step();
    expect(trace.rd_addr == 3 && trace.rd_data == 8, "ADD trace mismatch");
    trace = core.step();
    expect(trace.is_write && trace.addr == 0x100 && trace.wdata == 8,
           "store trace mismatch");
    trace = core.step();
    expect(trace.is_read && trace.rdata == 8 && trace.rd_data == 8,
           "load trace mismatch");
    trace = core.step();
    expect(!trace.commit_valid, "branch unexpectedly wrote a register");
    trace = core.step();
    expect(trace.pc == 0x1c && trace.rd_addr == 6 && trace.rd_data == 9,
           "taken branch target mismatch");
}

void test_m_extension_edges() {
    mycore core;
    core.reset();
    core.set_reg(1, 7);
    core.set_reg(2, 3);
    core.mem_write32(0x00, encode_r(1, 2, 1, 0, 3)); // mul
    core.mem_write32(0x04, encode_r(1, 2, 1, 4, 4)); // div
    core.mem_write32(0x08, encode_r(1, 0, 1, 5, 5)); // divu by zero
    core.mem_write32(0x0c, encode_r(1, 0, 1, 7, 6)); // remu by zero

    expect(core.step().rd_data == 21, "MUL mismatch");
    expect(core.step().rd_data == 2, "DIV mismatch");
    expect(core.step().rd_data == 0xffffffffu, "DIVU-by-zero mismatch");
    expect(core.step().rd_data == 7, "REMU-by-zero mismatch");
}

} // namespace

int main() {
    test_integer_memory_and_branch();
    test_m_extension_edges();
    std::cout << "PASS: C model RV32IM unit tests" << std::endl;
    return 0;
}
