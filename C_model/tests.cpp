#include "model.hpp"

#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>

namespace {

uint32_t encode_i(int32_t imm, uint32_t rs1, uint32_t funct3,
                  uint32_t rd, uint32_t opcode = 0x13) {
    const uint32_t bits = static_cast<uint32_t>(imm);
    return ((bits & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) |
           (rd << 7) | opcode;
}

uint32_t encode_r(uint32_t funct7, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3, uint32_t rd) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (rd << 7) | 0x33;
}

uint32_t encode_s(int32_t imm, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3) {
    const uint32_t bits = static_cast<uint32_t>(imm);
    return (((bits >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | ((bits & 0x1f) << 7) | 0x23;
}

uint32_t encode_b(int32_t imm, uint32_t rs2, uint32_t rs1,
                  uint32_t funct3) {
    const uint32_t bits = static_cast<uint32_t>(imm);
    return (((bits >> 12) & 0x1) << 31) |
           (((bits >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (((bits >> 1) & 0xf) << 8) |
           (((bits >> 11) & 0x1) << 7) | 0x63;
}

uint32_t encode_u(uint32_t imm, uint32_t rd, uint32_t opcode) {
    return (imm & 0xfffff000u) | (rd << 7) | opcode;
}

uint32_t encode_j(int32_t imm, uint32_t rd) {
    const uint32_t bits = static_cast<uint32_t>(imm);
    return (((bits >> 20) & 0x1) << 31) |
           (((bits >> 1) & 0x3ff) << 21) |
           (((bits >> 11) & 0x1) << 20) |
           (((bits >> 12) & 0xff) << 12) | (rd << 7) | 0x6f;
}

[[noreturn]] void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << std::endl;
    std::exit(1);
}

void expect(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

std::string hex32(uint32_t value) {
    std::ostringstream out;
    out << "0x" << std::hex << std::setfill('0') << std::setw(8) << value;
    return out.str();
}

void expect_equal(uint32_t actual, uint32_t expected,
                  const std::string& message) {
    if (actual != expected) {
        fail(message + ": expected " + hex32(expected) + ", got " +
             hex32(actual));
    }
}

cmodel_retire_trace expect_rd(mycore& core, uint32_t expected_pc,
                              uint32_t expected_rd, uint32_t expected_data,
                              const std::string& name) {
    const cmodel_retire_trace trace = core.step();
    expect_equal(trace.pc, expected_pc, name + " pc");
    expect(trace.commit_valid, name + " did not commit a register write");
    expect_equal(trace.rd_addr, expected_rd, name + " rd");
    expect_equal(trace.rd_data, expected_data, name + " result");
    return trace;
}

cmodel_retire_trace expect_no_rd(mycore& core, uint32_t expected_pc,
                                 const std::string& name) {
    const cmodel_retire_trace trace = core.step();
    expect_equal(trace.pc, expected_pc, name + " pc");
    expect(!trace.commit_valid, name + " unexpectedly committed a register write");
    return trace;
}

void test_r_type_integer_operations() {
    mycore core;
    core.reset();
    uint32_t pc = 0;

    const auto check = [&](uint32_t funct7, uint32_t funct3, uint32_t lhs,
                           uint32_t rhs, uint32_t expected,
                           const std::string& name) {
        core.set_reg(1, lhs);
        core.set_reg(2, rhs);
        core.mem_write32(pc, encode_r(funct7, 2, 1, funct3, 3));
        expect_rd(core, pc, 3, expected, name);
        pc += 4;
    };

    check(0x00, 0x0, 10, 3, 13, "ADD");
    check(0x20, 0x0, 3, 10, 0xfffffff9u, "SUB");
    check(0x00, 0x1, 1, 31, 0x80000000u, "SLL");
    check(0x00, 0x2, 0xffffffffu, 1, 1, "SLT");
    check(0x00, 0x3, 0xffffffffu, 1, 0, "SLTU");
    check(0x00, 0x4, 0x0000f0f0u, 0x00000ff0u, 0x0000ff00u, "XOR");
    check(0x00, 0x5, 0x80000000u, 4, 0x08000000u, "SRL");
    check(0x20, 0x5, 0x80000000u, 4, 0xf8000000u, "SRA");
    check(0x00, 0x6, 0x0000f0f0u, 0x00000ff0u, 0x0000fff0u, "OR");
    check(0x00, 0x7, 0x0000f0f0u, 0x00000ff0u, 0x000000f0u, "AND");
}

void test_i_type_integer_operations() {
    mycore core;
    core.reset();
    uint32_t pc = 0;

    const auto check = [&](int32_t imm, uint32_t funct3, uint32_t lhs,
                           uint32_t expected, const std::string& name) {
        core.set_reg(1, lhs);
        core.mem_write32(pc, encode_i(imm, 1, funct3, 3));
        expect_rd(core, pc, 3, expected, name);
        pc += 4;
    };

    check(123, 0x0, 5, 128, "ADDI positive");
    check(-7, 0x0, 5, 0xfffffffeu, "ADDI negative");
    check(-1, 0x2, 0xfffffffeu, 1, "SLTI signed immediate");
    check(-1, 0x3, 1, 1, "SLTIU sign-extended immediate");
    check(-1, 0x4, 0x12345678u, 0xedcba987u, "XORI");
    check(-256, 0x6, 0x0000000fu, 0xffffff0fu, "ORI");
    check(0x0ff, 0x7, 0x12345678u, 0x00000078u, "ANDI");
    check(31, 0x1, 1, 0x80000000u, "SLLI");
    check(4, 0x5, 0x80000000u, 0x08000000u, "SRLI");
    check((0x20 << 5) | 4, 0x5, 0x80000000u, 0xf8000000u, "SRAI");
}

void expect_branch(uint32_t funct3, uint32_t lhs, uint32_t rhs,
                   bool should_take, const std::string& name) {
    mycore core;
    core.reset();
    core.set_reg(1, lhs);
    core.set_reg(2, rhs);
    core.mem_write32(0x00, encode_b(8, 2, 1, funct3));
    core.mem_write32(0x04, encode_i(0x11, 0, 0, 3));
    core.mem_write32(0x08, encode_i(0x22, 0, 0, 3));

    expect_no_rd(core, 0x00, name);
    expect_rd(core, should_take ? 0x08 : 0x04, 3,
              should_take ? 0x22 : 0x11, name + " target");
}

void test_branches() {
    expect_branch(0x0, 5, 5, true, "BEQ taken");
    expect_branch(0x0, 5, 6, false, "BEQ not taken");
    expect_branch(0x1, 5, 6, true, "BNE taken");
    expect_branch(0x1, 5, 5, false, "BNE not taken");
    expect_branch(0x4, 0xffffffffu, 1, true, "BLT taken");
    expect_branch(0x4, 1, 0xffffffffu, false, "BLT not taken");
    expect_branch(0x5, 1, 0xffffffffu, true, "BGE taken");
    expect_branch(0x5, 0xffffffffu, 1, false, "BGE not taken");
    expect_branch(0x6, 1, 0xffffffffu, true, "BLTU taken");
    expect_branch(0x6, 0xffffffffu, 1, false, "BLTU not taken");
    expect_branch(0x7, 0xffffffffu, 1, true, "BGEU taken");
    expect_branch(0x7, 1, 0xffffffffu, false, "BGEU not taken");

    mycore core;
    core.reset();
    core.set_pc(0x08);
    core.set_reg(1, 7);
    core.set_reg(2, 7);
    core.mem_write32(0x08, encode_b(-8, 2, 1, 0x0));
    core.mem_write32(0x00, encode_i(0x33, 0, 0, 4));
    expect_no_rd(core, 0x08, "BEQ negative displacement");
    expect_rd(core, 0x00, 4, 0x33, "BEQ negative target");
}

void test_jumps_and_upper_immediates() {
    {
        mycore core;
        core.reset();
        core.mem_write32(0x00, encode_j(8, 5));
        core.mem_write32(0x08, encode_i(0x44, 0, 0, 6));
        expect_rd(core, 0x00, 5, 0x04, "JAL link");
        expect_rd(core, 0x08, 6, 0x44, "JAL target");
    }

    {
        mycore core;
        core.reset();
        core.set_pc(0x10);
        core.mem_write32(0x10, encode_j(-8, 5));
        core.mem_write32(0x08, encode_i(0x55, 0, 0, 6));
        expect_rd(core, 0x10, 5, 0x14, "JAL negative displacement");
        expect_rd(core, 0x08, 6, 0x55, "JAL negative target");
    }

    {
        mycore core;
        core.reset();
        core.set_reg(1, 0x109);
        core.mem_write32(0x00, encode_i(-4, 1, 0x0, 5, 0x67));
        core.mem_write32(0x104, encode_i(0x66, 0, 0, 6));
        expect_rd(core, 0x00, 5, 0x04, "JALR link");
        expect_rd(core, 0x104, 6, 0x66, "JALR target and bit-zero clear");
    }

    {
        mycore core;
        core.reset();
        core.mem_write32(0x00, encode_u(0xabcde000u, 3, 0x37));
        core.mem_write32(0x04, encode_u(0x12345000u, 4, 0x17));
        expect_rd(core, 0x00, 3, 0xabcde000u, "LUI");
        expect_rd(core, 0x04, 4, 0x12345004u, "AUIPC");
    }
}

void test_loads_and_stores() {
    mycore core;
    core.reset();
    uint32_t pc = 0;

    core.set_reg(1, 0x100);
    core.set_reg(2, 0x12345680u);
    core.mem_write32(pc, encode_s(0, 2, 1, 0x0));
    cmodel_retire_trace trace = expect_no_rd(core, pc, "SB");
    expect(trace.is_write, "SB missing write trace");
    expect_equal(trace.addr, 0x100, "SB address");
    expect_equal(trace.wstrb, 0x1, "SB strobe");
    expect_equal(trace.wdata, 0x12345680u, "SB data");
    pc += 4;

    core.mem_write32(pc, encode_i(0, 1, 0x0, 3, 0x03));
    trace = expect_rd(core, pc, 3, 0xffffff80u, "LB sign extension");
    expect(trace.is_read, "LB missing read trace");
    expect_equal(trace.addr, 0x100, "LB address");
    pc += 4;

    core.mem_write32(pc, encode_i(0, 1, 0x4, 4, 0x03));
    trace = expect_rd(core, pc, 4, 0x00000080u, "LBU zero extension");
    expect(trace.is_read, "LBU missing read trace");
    pc += 4;

    core.set_reg(2, 0x12348001u);
    core.mem_write32(pc, encode_s(2, 2, 1, 0x1));
    trace = expect_no_rd(core, pc, "SH");
    expect(trace.is_write, "SH missing write trace");
    expect_equal(trace.addr, 0x102, "SH address");
    expect_equal(trace.wstrb, 0x3, "SH strobe");
    expect_equal(trace.wdata, 0x12348001u, "SH data");
    pc += 4;

    core.mem_write32(pc, encode_i(2, 1, 0x1, 5, 0x03));
    trace = expect_rd(core, pc, 5, 0xffff8001u, "LH sign extension");
    expect(trace.is_read, "LH missing read trace");
    pc += 4;

    core.mem_write32(pc, encode_i(2, 1, 0x5, 6, 0x03));
    trace = expect_rd(core, pc, 6, 0x00008001u, "LHU zero extension");
    expect(trace.is_read, "LHU missing read trace");
    pc += 4;

    core.set_reg(1, 0x108);
    core.set_reg(2, 0x89abcdefu);
    core.mem_write32(pc, encode_s(-4, 2, 1, 0x2));
    trace = expect_no_rd(core, pc, "SW negative offset");
    expect(trace.is_write, "SW missing write trace");
    expect_equal(trace.addr, 0x104, "SW address");
    expect_equal(trace.wstrb, 0xf, "SW strobe");
    expect_equal(trace.wdata, 0x89abcdefu, "SW data");
    pc += 4;

    core.mem_write32(pc, encode_i(-4, 1, 0x2, 7, 0x03));
    trace = expect_rd(core, pc, 7, 0x89abcdefu, "LW negative offset");
    expect(trace.is_read, "LW missing read trace");
    expect_equal(trace.addr, 0x104, "LW address");
}

void test_m_extension() {
    mycore core;
    core.reset();
    uint32_t pc = 0;

    const auto check = [&](uint32_t funct3, uint32_t lhs, uint32_t rhs,
                           uint32_t expected, const std::string& name) {
        core.set_reg(1, lhs);
        core.set_reg(2, rhs);
        core.mem_write32(pc, encode_r(0x01, 2, 1, funct3, 3));
        expect_rd(core, pc, 3, expected, name);
        pc += 4;
    };

    check(0x0, 0xfffffffeu, 3, 0xfffffffau, "MUL");
    check(0x1, 0x80000000u, 2, 0xffffffffu, "MULH");
    check(0x2, 0xffffffffu, 0xffffffffu, 0xffffffffu, "MULHSU");
    check(0x3, 0xffffffffu, 0xffffffffu, 0xfffffffeu, "MULHU");
    check(0x4, 0xfffffff9u, 3, 0xfffffffeu, "DIV");
    check(0x5, 7, 3, 2, "DIVU");
    check(0x6, 0xfffffff9u, 3, 0xffffffffu, "REM");
    check(0x7, 7, 3, 1, "REMU");
    check(0x4, 0x12345678u, 0, 0xffffffffu, "DIV by zero");
    check(0x5, 0x87654321u, 0, 0xffffffffu, "DIVU by zero");
    check(0x6, 0x12345678u, 0, 0x12345678u, "REM by zero");
    check(0x7, 0x87654321u, 0, 0x87654321u, "REMU by zero");
    check(0x4, 0x80000000u, 0xffffffffu, 0x80000000u,
          "DIV INT_MIN by -1");
    check(0x6, 0x80000000u, 0xffffffffu, 0, "REM INT_MIN by -1");
}

void test_x0_is_immutable() {
    mycore core;
    core.reset();
    core.set_reg(0, 0xffffffffu);
    core.mem_write32(0x00, encode_i(123, 0, 0x0, 0));
    core.mem_write32(0x04, encode_i(-1, 0, 0x0, 1));
    core.mem_write32(0x08, encode_r(0x00, 1, 0, 0x0, 2));

    expect_rd(core, 0x00, 0, 0, "write to x0");
    expect_rd(core, 0x04, 1, 0xffffffffu, "read x0 after write");
    core.set_reg(0, 0x12345678u);
    expect_rd(core, 0x08, 2, 0xffffffffu, "set_reg cannot change x0");
}

void test_separate_instruction_and_data_memories() {
    mycore core;
    core.reset();

    core.imem_write32(0x00, encode_i(7, 0, 0x0, 1));
    core.imem_write32(0x04, encode_i(9, 0, 0x0, 2));
    core.mem_write32(0x00, 0xdeadbeefu);
    expect_rd(core, 0x00, 1, 7,
              "separate instruction memory fetch");
    expect_rd(core, 0x04, 2, 9,
              "separate instruction memory continued fetch");
    expect_equal(core.get_reg(1), 7, "architectural register query");
    expect_equal(core.mem_peek8(0), 0xef, "data memory byte query");
    expect_equal(core.mem_peek32(0), 0xdeadbeefu,
                 "data memory word query");
    expect_equal(core.mem_peek8(4), 0, "unwritten data memory byte query");
}

} // namespace

int main() {
    test_r_type_integer_operations();
    test_i_type_integer_operations();
    test_branches();
    test_jumps_and_upper_immediates();
    test_loads_and_stores();
    test_m_extension();
    test_x0_is_immutable();
    test_separate_instruction_and_data_memories();
    std::cout << "PASS: C model RV32I/M execution-subset unit tests" << std::endl;
    return 0;
}
