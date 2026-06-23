// Complex RV32IM regression test — no inline assembly
// Exercises arithmetic, bit manipulation, branches, function calls,
// memory access, and control flow entirely through C++ constructs.
typedef unsigned int   u32;
typedef signed int     s32;
typedef unsigned char  u8;
typedef signed char    s8;
typedef unsigned short     u16;
typedef signed short       s16;
typedef long long          s64;
typedef unsigned long long u64;

// Memory-mapped output: store results here for UVM scoreboard to check
static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);

// Memory-mapped scratch area: for load/store tests
static volatile u32* const MEM32 = reinterpret_cast<volatile u32*>(0x00008100u);
static volatile u16* const MEM16 = reinterpret_cast<volatile u16*>(0x00008100u);
static volatile u8*  const MEM8  = reinterpret_cast<volatile u8*>(0x00008100u);

// ---------- helper ----------
static inline void mix(volatile u32& sig, u32 v) {
    sig = (sig << 5) ^ (sig >> 2) ^ v ^ 0x9e3779b9u;
}

// ---------- div/rem edge cases (no asm) ----------
// signed division corner case: INT_MIN / -1
static const s32 DIV_OVERFLOW_LHS = static_cast<s32>(0x80000000u);
static const s32 DIV_OVERFLOW_RHS = -1;

__attribute__((noinline))
static u32 div_rem_edge_cases(u32 x) {
    volatile u32 local = x;
    volatile u32 zero = 0;
    // div by zero → result is all-ones (0xFFFFFFFF)
    u32 d0 = local / zero;
    // rem by zero → result is dividend
    u32 r0 = local % zero;
    // signed overflow div
    u32 d1 = static_cast<u32>(DIV_OVERFLOW_LHS / DIV_OVERFLOW_RHS);
    // signed overflow rem (should be 0)
    u32 r1 = static_cast<u32>(DIV_OVERFLOW_LHS % DIV_OVERFLOW_RHS);
    return (d0 ^ r0) + (d1 ^ r1);
}

// ---------- nested function calls (exercises jal / jalr) ----------
__attribute__((noinline))
static u32 leaf_a(u32 x) {
    u32 t = x + 0x31u;
    t ^= (t << 3);
    t += 0x102u;
    return t;
}

__attribute__((noinline))
static u32 leaf_b(u32 x, u32 y) {
    u32 t = x - y;
    t ^= (t >> 7);
    t += y + 0x55u;
    return t;
}

__attribute__((noinline))
static u32 leaf_c(u32 x, u32 y, u32 z) {
    u32 t = (x ^ y) & (z | 0xFFu);
    t = (t << 1) | (t >> 31);
    t *= 3u;
    return t;
}

__attribute__((noinline))
static u32 mid_layer(u32 a) {
    u32 b = leaf_a(a);
    u32 c = leaf_b(b, a);
    u32 d = leaf_c(b, c, a);
    return d;
}

__attribute__((noinline))
static u32 deep_call(u32 x) {
    return mid_layer(mid_layer(x) ^ 0x12345678u);
}

// indirect call via function pointer (generates jalr)
typedef u32 (*fnptr)(u32);
__attribute__((noinline))
static u32 indirect_call_test(u32 x, u32 sel) {
    // array of function pointers — compiler must pick one at runtime
    // each function in the array has the same signature
    static fnptr table[4];
    table[0] = leaf_a;
    table[1] = reinterpret_cast<fnptr>(leaf_b); // signature compatible enough
    table[2] = reinterpret_cast<fnptr>(mid_layer);
    table[3] = reinterpret_cast<fnptr>(deep_call);
    u32 idx = sel & 3u;
    return table[idx](x);
}

// ---------- arithmetic tests ----------
__attribute__((noinline))
static u32 arith_test(u32 a, u32 b, s32 n) {
    volatile u32 sig = 0x31415926u;

    // basic R-type
    mix(sig, a + b);
    mix(sig, b - a);
    mix(sig, a ^ b);
    mix(sig, a | b);
    mix(sig, a & b);

    // shifts (variable amount)
    u32 sh = b & 31u;
    mix(sig, a << sh);
    mix(sig, b >> sh);
    mix(sig, static_cast<u32>(n >> sh));

    // I-type immediate (compiler uses addi / andi / ori / xori)
    mix(sig, a + 77);
    mix(sig, b - 33);
    mix(sig, a & 0x0FFu);
    mix(sig, b | 0xF00u);
    mix(sig, a ^ 0x55555555u);

    // shifts with immediate (slli / srli / srai)
    mix(sig, a << 7);
    mix(sig, b >> 11);
    mix(sig, static_cast<u32>(n >> 3));

    // set-if-less-than via C comparison
    u32 slt_s  = static_cast<s32>(n) < static_cast<s32>(a) ? 1u : 0u;
    u32 sltu_u = b < a ? 1u : 0u;
    mix(sig, slt_s);
    mix(sig, sltu_u);

    // multiply
    u32 m0 = a * b;
    u32 m1 = static_cast<u32>(static_cast<s64>(static_cast<s32>(n)) * static_cast<s64>(static_cast<s32>(b)) >> 32);
    mix(sig, m0);
    mix(sig, m1);

    // divide & remainder (unsigned)
    u32 d_u = (b != 0u) ? a / b : 0xFFFFFFFFu;
    u32 r_u = (b != 0u) ? a % b : a;
    mix(sig, d_u);
    mix(sig, r_u);

    // divide & remainder (signed)
    s32 d_s = (b != 0u) ? static_cast<s32>(n) / static_cast<s32>(b) : 0;
    s32 r_s = (b != 0u) ? static_cast<s32>(n) % static_cast<s32>(b) : n;
    mix(sig, static_cast<u32>(d_s));
    mix(sig, static_cast<u32>(r_s));

    // lui / auipc — exercised by global variable references
    mix(sig, div_rem_edge_cases(a));

    return sig;
}

// ---------- branch-intensive tests ----------
__attribute__((noinline))
static u32 branch_maze(s32 x, s32 y, u32 z) {
    volatile u32 sig = 0;
    const u32 fail_base = 0xBAD00000u;

    // deeply nested if/else — exercises beq, bne, blt, bge, bltu, bgeu
    if (x == y) {
        sig += 1;
        if (static_cast<u32>(x) < static_cast<u32>(y)) {
            sig += 2;
        } else {
            sig += 4;
        }
    } else {
        sig ^= 8;
        if (x < y) {
            sig += 16;
            if (static_cast<u32>(x) > z) {
                sig += 32;
            } else {
                sig ^= 64;
            }
        } else if (x > y) {
            sig += 128;
            if (static_cast<u32>(static_cast<s32>(z)) >= static_cast<u32>(x)) {
                sig ^= 256;
            }
        } else {
            sig |= 512; // unreachable since x!=y and not (x<y or x>y)
        }
    }

    // branch with chained conditions
    if (x >= 0 && y <= 100 && z != 0xDEADu && (x + y) > 0) {
        sig += 1024;
    }

    // dense if/else-if chain (compiler uses bne chain)
    u32 selector = z & 7u;
    if (selector == 0u) {
        sig += 1;
    } else if (selector == 1u) {
        sig += 3;
    } else if (selector == 2u) {
        sig += 5;
    } else if (selector == 3u) {
        sig += 7;
    } else if (selector == 4u) {
        sig += 11;
    } else if (selector == 5u) {
        sig += 13;
    } else if (selector == 6u) {
        sig += 17;
    } else {
        sig += 19;
    }

    // ternary operator (generates branch or conditional move)
    u32 t = (x > y) ? (x - y) : (y - x);
    sig ^= t;

    return sig;
}

// ---------- loop tests ----------
__attribute__((noinline))
static u32 loop_tests(u32 seed) {
    volatile u32 acc = seed;

    // counted loop with memory read-modify-write
    for (u32 i = 0; i < 16; ++i) {
        MEM32[16 + i] = acc + i;
        u32 rd = MEM32[16 + i];
        MEM32[16 + i] = rd ^ (i * 0x101u);
        u32 rd2 = MEM32[16 + i];
        acc = (rd2 + (acc << 1)) ^ (i + 0x77u);
    }

    // while loop with early exit
    u32 counter = 31;
    while (counter > 0) {
        u32 val = MEM32[16 + (counter & 15u)];
        MEM32[32] = val;
        acc ^= MEM32[32];
        counter >>= 1;
        if (counter == 1) break;
    }

    // nested loops with word-aligned memory
    u32 matrix = 0;
    for (u32 row = 0; row < 4; ++row) {
        u32 row_sum = 0;
        for (u32 col = 0; col < 4; ++col) {
            u32 val = (row * col + acc) & 0xFFu;
            MEM32[16 + row * 4 + col] = val;
            row_sum += MEM32[16 + row * 4 + col];
        }
        matrix ^= row_sum;
    }
    acc ^= matrix;

    return acc;
}

// ---------- load/store tests (32-bit only, avoids sub-word store hazards) ----------
__attribute__((noinline))
static u32 memory_tests(u32 pattern) {
    volatile u32 sig = 0;
    u32 hi = pattern >> 16;
    u32 lo = pattern & 0xFFFFu;

    // word (32-bit) stores and loads — read-modify-write
    MEM32[0] = 0xA5A55A5Au;
    MEM32[1] = pattern;
    MEM32[2] = hi ^ lo;
    u32 w0 = MEM32[0];
    u32 w1 = MEM32[1];
    u32 w2 = MEM32[2];
    MEM32[0] = w0 ^ w1;
    u32 w3 = MEM32[0];
    MEM32[1] = w3 + w2;
    u32 w4 = MEM32[1];
    mix(sig, w0);
    mix(sig, w1);
    mix(sig, w2);
    mix(sig, w3);
    mix(sig, w4);

    // halfword (16-bit) stores and loads
    MEM16[16] = static_cast<u16>(hi);
    MEM16[17] = static_cast<u16>(lo);
    u16 h0 = MEM16[16];
    u16 h1 = MEM16[17];
    MEM16[18] = h0 + h1;
    u16 h2 = MEM16[18];
    mix(sig, static_cast<u32>(h0));
    mix(sig, static_cast<u32>(h1));
    mix(sig, static_cast<u32>(h2));

    // byte (8-bit) stores and loads
    MEM8[32] = 0x7Fu;
    MEM8[33] = 0x80u;
    MEM8[34] = 0x01u;
    MEM8[35] = 0xFFu;
    u8 b0 = MEM8[32];
    u8 b1 = MEM8[33];
    u8 b2 = MEM8[34];
    u8 b3 = MEM8[35];
    mix(sig, b0 | (static_cast<u32>(b1) << 8) | (static_cast<u32>(b2) << 16) | (static_cast<u32>(b3) << 24));

    // signed byte/halfword extension
    s8 sb0 = static_cast<s8>(MEM8[33]);
    s16 sh0 = static_cast<s16>(MEM16[16]);
    mix(sig, static_cast<u32>(static_cast<s32>(sb0)));
    mix(sig, static_cast<u32>(static_cast<s32>(sh0)));

    // byte manipulation — reconstruct 32-bit word
    u32 assembled = (static_cast<u32>(MEM8[32]))
                  | (static_cast<u32>(MEM8[33]) << 8)
                  | (static_cast<u32>(MEM8[34]) << 16)
                  | (static_cast<u32>(MEM8[35]) << 24);
    mix(sig, assembled);

    // more 32-bit stores with computed addresses
    for (u32 i = 0; i < 8; ++i) {
        MEM32[4 + i] = (w0 * i) ^ (w1 >> i) ^ w2;
    }
    u32 accum = 0;
    for (u32 i = 0; i < 8; ++i) {
        accum += MEM32[4 + i];
    }
    mix(sig, accum);

    return sig;
}

// ---------- bit manipulation ----------
__attribute__((noinline))
static u32 bitfield_tests(u32 x, u32 pos) {
    volatile u32 sig = 0;
    u32 sh = pos & 31u;

    // extract bit field
    u32 field = (x >> sh) & 0x1Fu;
    mix(sig, field);

    // insert bit
    u32 inserted = x | (1u << sh);
    mix(sig, inserted);

    // clear bit
    u32 cleared = x & ~(1u << sh);
    mix(sig, cleared);

    // toggle bit
    u32 toggled = x ^ (1u << sh);
    mix(sig, toggled);

    // rotate emulation
    u32 rotated = (x << sh) | (x >> (32u - sh));
    mix(sig, rotated);

    return sig;
}

// ---------- global / static variables ----------
static u32 g_counter = 0;
static volatile u32 g_guard = 0xDEADBEEFu;

__attribute__((noinline))
static u32 global_var_test(u32 step) {
    g_counter += step;
    if (g_counter > 1000u) {
        g_guard ^= g_counter;
        g_counter = 0;
    }
    return g_guard ^ g_counter;
}

// ---------- struct on stack ----------
struct Point {
    u32 x;
    u32 y;
    u32 z;
};

__attribute__((noinline))
static u32 struct_stack_test(u32 bx, u32 by, u32 bz) {
    Point p;
    p.x = bx;
    p.y = by;
    p.z = bz;
    // Force stack spill/reload
    volatile u32 sum = p.x + p.y + p.z;
    Point q;
    q.x = p.y;
    q.y = p.z;
    q.z = p.x;
    volatile u32 sum2 = q.x ^ q.y ^ q.z;
    return sum + sum2;
}

// ---------- recursive function (limited depth) ----------
__attribute__((noinline))
static u32 fibonacci(u32 n) {
    if (n <= 1u) return n;
    return fibonacci(n - 1u) + fibonacci(n - 2u);
}

// ---------- switch-case (jump table or branch chain) ----------
__attribute__((noinline))
static u32 switch_dispatch(u32 op, u32 a, u32 b) {
    switch (op & 15u) {
        case 0:  return a + b;
        case 1:  return a - b;
        case 2:  return a ^ b;
        case 3:  return a | b;
        case 4:  return a & b;
        case 5:  return a << (b & 31u);
        case 6:  return a >> (b & 31u);
        case 7:  return (b != 0u) ? a / b : 0;
        case 8:  return (b != 0u) ? a % b : 0;
        case 9:  return a * b;
        case 10: return ~a;
        case 11: return a + 1u;
        case 12: return a - 1u;
        case 13: return (a > b) ? a : b;
        case 14: return (a < b) ? a : b;
        default: return a;
    }
}

// ---------- pointer-like indirection ----------
__attribute__((noinline))
static u32 pointer_chase() {
    // Build lookup table: address -> value pairs
    for (u32 i = 0; i < 8; ++i) {
        MEM32[48 + i * 2] = i;                    // index
        MEM32[48 + i * 2 + 1] = 0x01010101u * i; // value
    }
    // Accumulate all values through indexed access
    u32 sum = 0;
    u32 order[8] = {3, 7, 1, 5, 0, 6, 2, 4};
    for (u32 step = 0; step < 8; ++step) {
        u32 idx = order[step];
        sum += MEM32[48 + idx * 2 + 1];           // read value at index
        sum ^= MEM32[48 + idx * 2];               // read stored index
        MEM32[48 + idx * 2] = sum & 0xFFu;        // write-back through pointer
    }
    return sum;
}

// ---------- main ----------
extern "C" int main() {
    // Clear result area
    for (u32 i = 0; i < 64; ++i) {
        RESULT[i] = 0;
    }

    volatile u32 sig = 0x59535958u;
    u32 slot = 0;

    // 1) arithmetic
    sig ^= arith_test(0x13579BDFu, 0x2468ACE0u, -12345);
    RESULT[slot++] = sig;

    // 2) branch maze
    sig ^= branch_maze(-5, 10, 7);
    RESULT[slot++] = sig;

    // 3) loops
    sig ^= loop_tests(sig);
    RESULT[slot++] = sig;

    // 4) memory
    sig ^= memory_tests(sig);
    RESULT[slot++] = sig;

    // 5) bitfield
    sig ^= bitfield_tests(sig, 7);
    RESULT[slot++] = sig;

    // 6) global variables
    for (u32 k = 0; k < 5; ++k) {
        sig ^= global_var_test(k * 17u + 1u);
    }
    RESULT[slot++] = sig;

    // 7) struct on stack
    sig ^= struct_stack_test(sig, sig >> 16, sig & 0xFFFFu);
    RESULT[slot++] = sig;

    // 8) fibonacci (recursion depth 8 → 21)
    sig ^= fibonacci(8u);
    RESULT[slot++] = sig;

    // 9) switch dispatch
    for (u32 op = 0; op < 16; ++op) {
        sig ^= switch_dispatch(op, sig, op * 3u);
    }
    RESULT[slot++] = sig;

    // 10) nested function calls
    sig ^= deep_call(sig & 0x0FFFFFFFu);
    RESULT[slot++] = sig;

    // 11) indirect call
    sig ^= indirect_call_test(sig, sig & 3u);
    RESULT[slot++] = sig;

    // 12) pointer chasing
    sig ^= pointer_chase();
    RESULT[slot++] = sig;

    // 13) div/rem edge
    sig ^= div_rem_edge_cases(sig);
    RESULT[slot++] = sig;

    // final marker — UVM scoreboard checks this
    RESULT[slot++] = 0x59535958u;   // start marker = expected
    RESULT[slot++] = sig;           // accumulated signature
    RESULT[slot++] = 0x00000001u;   // done flag

    // infinite loop
    while (1) {}
    return 0;
}
