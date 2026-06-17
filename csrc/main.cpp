typedef unsigned int u32;
typedef int s32;
typedef unsigned char u8;
typedef signed char s8;
typedef unsigned short u16;
typedef signed short s16;

static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);
static volatile u32* const SCR32  = reinterpret_cast<volatile u32*>(0x00008100u);
static volatile u8*  const SCR8   = reinterpret_cast<volatile u8*>(0x00008100u);
static volatile u16* const SCR16  = reinterpret_cast<volatile u16*>(0x00008100u);
static volatile s8*  const SCRS8  = reinterpret_cast<volatile s8*>(0x00008100u);
static volatile s16* const SCRS16 = reinterpret_cast<volatile s16*>(0x00008100u);

static volatile u32 seed0 = 0x13579bdfu;
static volatile u32 seed1 = 0x2468ace0u;
static volatile s32 neg_seed = -12345;
static volatile u32 small_seed = 7;

static inline void record_fail(u32 slot, u32 code) {
    RESULT[slot] = code;
}

static inline void mix(volatile u32& sig, u32 value) {
    sig = (sig << 5) ^ (sig >> 2) ^ value ^ 0x9e3779b9u;
}

static __attribute__((noinline)) u32 jal_target_a(u32 x) {
    u32 y = x + 0x31u;
    y ^= (y << 3);
    return y + 0x102u;
}

static __attribute__((noinline)) u32 jal_target_b(u32 x, u32 y) {
    u32 z = x - y;
    z ^= (z >> 7);
    return z + y + 0x55u;
}

static __attribute__((noinline)) u32 jalr_target(u32 x) {
    u32 y = x ^ 0xa5a55a5au;
    y += (y << 1);
    return y ^ 0x00012345u;
}

static __attribute__((noinline)) u32 nested_call(u32 x) {
    u32 a = jal_target_a(x);
    u32 b = jal_target_b(a, x);
    u32 (*volatile fp)(u32) = jalr_target;
    return fp(b);
}

static void arithmetic_and_compare_tests(volatile u32& sig) {
    u32 a = seed0;
    u32 b = seed1;
    s32 n = neg_seed;
    u32 sh = small_seed & 31u;

    mix(sig, a + b);
    mix(sig, b - a);
    mix(sig, a ^ b);
    mix(sig, a | b);
    mix(sig, a & b);
    mix(sig, a << 3);
    mix(sig, b >> 5);
    mix(sig, static_cast<u32>(n >> 4));
    mix(sig, a << sh);
    mix(sig, b >> sh);
    mix(sig, static_cast<u32>(n >> sh));

    u32 slt_s = 0;
    u32 sltu_u = 0;
    u32 slti_s = 0;
    u32 sltiu_u = 0;
    asm volatile(
        "slt   %[slt_s],  %[neg], %[pos]\n"
        "sltu  %[sltu_u], %[neg], %[pos]\n"
        "slti  %[slti_s], %[neg], -1\n"
        "sltiu %[sltiu_u],%[pos], 31\n"
        : [slt_s] "=r"(slt_s),
          [sltu_u] "=r"(sltu_u),
          [slti_s] "=r"(slti_s),
          [sltiu_u] "=r"(sltiu_u)
        : [neg] "r"(static_cast<u32>(n)),
          [pos] "r"(small_seed));
    mix(sig, slt_s);
    mix(sig, sltu_u);
    mix(sig, slti_s);
    mix(sig, sltiu_u);

    u32 mul_lo = 0;
    u32 mulh_ss = 0;
    u32 mulh_su = 0;
    u32 mulh_uu = 0;
    u32 div_s = 0;
    u32 div_u = 0;
    u32 rem_s = 0;
    u32 rem_u = 0;
    asm volatile(
        "mul    %[mul_lo], %[lhs], %[rhs]\n"
        "mulh   %[mulh_ss],%[lhs], %[rhs]\n"
        "mulhsu %[mulh_su],%[lhs], %[rhs]\n"
        "mulhu  %[mulh_uu],%[lhs], %[rhs]\n"
        "div    %[div_s],  %[lhs], %[small]\n"
        "divu   %[div_u],  %[lhs], %[small]\n"
        "rem    %[rem_s],  %[lhs], %[small]\n"
        "remu   %[rem_u],  %[lhs], %[small]\n"
        : [mul_lo] "=r"(mul_lo),
          [mulh_ss] "=r"(mulh_ss),
          [mulh_su] "=r"(mulh_su),
          [mulh_uu] "=r"(mulh_uu),
          [div_s] "=r"(div_s),
          [div_u] "=r"(div_u),
          [rem_s] "=r"(rem_s),
          [rem_u] "=r"(rem_u)
        : [lhs] "r"(static_cast<u32>(n)),
          [rhs] "r"(b),
          [small] "r"(small_seed));
    mix(sig, mul_lo);
    mix(sig, mulh_ss);
    mix(sig, mulh_su);
    mix(sig, mulh_uu);
    mix(sig, div_s);
    mix(sig, div_u);
    mix(sig, rem_s);
    mix(sig, rem_u);

    u32 div_zero = 0;
    u32 rem_zero = 0;
    u32 div_overflow = 0;
    u32 rem_overflow = 0;
    asm volatile(
        "div %[div_zero], %[num], x0\n"
        "rem %[rem_zero], %[num], x0\n"
        "li  t0, 0x80000000\n"
        "li  t1, -1\n"
        "div %[div_overflow], t0, t1\n"
        "rem %[rem_overflow], t0, t1\n"
        : [div_zero] "=r"(div_zero),
          [rem_zero] "=r"(rem_zero),
          [div_overflow] "=r"(div_overflow),
          [rem_overflow] "=r"(rem_overflow)
        : [num] "r"(0x12345678u)
        : "t0", "t1");
    mix(sig, div_zero);
    mix(sig, rem_zero);
    mix(sig, div_overflow);
    mix(sig, rem_overflow);
}

static void load_store_tests(volatile u32& sig) {
    SCR32[0] = 0x11223344u;
    SCR32[1] = 0xaabbccddu;
    SCR32[2] = 0x01020304u;
    SCR32[3] = 0xdeadbeefu;

    u32 raw0 = SCR32[0];
    SCR32[0] = raw0 ^ 0xffffffffu;
    u32 raw1 = SCR32[0];
    SCR32[0] = 0x55667788u;
    u32 raw2 = SCR32[0];
    mix(sig, raw0);
    mix(sig, raw1);
    mix(sig, raw2);

    SCR8[4] = 0x80u;
    SCR8[5] = 0x7fu;
    SCR8[6] = 0x01u;
    SCR8[7] = 0xffu;
    mix(sig, static_cast<u32>(SCRS8[4]));
    mix(sig, static_cast<u32>(SCR8[5]));
    mix(sig, static_cast<u32>(SCRS8[7]));

    SCR16[4] = 0x8001u;
    SCR16[5] = 0x7ffeu;
    mix(sig, static_cast<u32>(SCRS16[4]));
    mix(sig, static_cast<u32>(SCR16[5]));

    SCR8[12] = 0x12u;
    u32 b0 = SCR8[12];
    SCR8[12] = static_cast<u8>(b0 + 0x34u);
    u32 b1 = SCR8[12];
    SCR16[6] = static_cast<u16>((b1 << 8) | b0);
    u32 h0 = SCR16[6];
    SCR32[4] = h0 | 0xaaaa0000u;
    u32 w0 = SCR32[4];
    mix(sig, b0);
    mix(sig, b1);
    mix(sig, h0);
    mix(sig, w0);
}

static void branch_matrix_tests(volatile u32& sig) {
    const u32 fail_marker = 0xbad00000u;
    u32 a = 10;
    u32 b = 20;
    s32 sn = -5;
    s32 sp = 5;

    if (a == a) {
        mix(sig, 0x0101u);
    } else {
        record_fail(20, fail_marker | 0x01u);
    }

    if (a == b) {
        record_fail(21, fail_marker | 0x02u);
    } else {
        mix(sig, 0x0102u);
    }

    if (a != b) {
        mix(sig, 0x0103u);
    } else {
        record_fail(22, fail_marker | 0x03u);
    }

    if (a != a) {
        record_fail(23, fail_marker | 0x04u);
    } else {
        mix(sig, 0x0104u);
    }

    if (sn < sp) {
        mix(sig, 0x0105u);
    } else {
        record_fail(24, fail_marker | 0x05u);
    }

    if (sp < sn) {
        record_fail(25, fail_marker | 0x06u);
    } else {
        mix(sig, 0x0106u);
    }

    if (sp >= sn) {
        mix(sig, 0x0107u);
    } else {
        record_fail(26, fail_marker | 0x07u);
    }

    if (sn >= sp) {
        record_fail(27, fail_marker | 0x08u);
    } else {
        mix(sig, 0x0108u);
    }

    if (static_cast<u32>(sn) > static_cast<u32>(sp)) {
        mix(sig, 0x0109u);
    } else {
        record_fail(28, fail_marker | 0x09u);
    }

    if (static_cast<u32>(sp) > static_cast<u32>(sn)) {
        record_fail(29, fail_marker | 0x0au);
    } else {
        mix(sig, 0x010au);
    }
}

static void explicit_control_flow_tests(volatile u32& sig) {
    u32 fail_addr = reinterpret_cast<u32>(&RESULT[32]);
    u32 same_a = 0x55aa55aau;
    u32 same_b = 0x55aa55aau;

    asm volatile(
        "li   t0, 0xc0010001\n"
        "beq  %[a], %[b], 1f\n"
        "sw   t0, 0(%[fail])\n"
        "1:\n"
        "addi %[sig], %[sig], 0x11\n"
        : [sig] "+r"(sig)
        : [a] "r"(same_a),
          [b] "r"(same_b),
          [fail] "r"(fail_addr)
        : "t0", "memory");

    asm volatile(
        "li   t0, 0xc0010002\n"
        "jal  1f\n"
        "sw   t0, 4(%[fail])\n"
        "1:\n"
        "addi %[sig], %[sig], 0x22\n"
        : [sig] "+r"(sig)
        : [fail] "r"(fail_addr)
        : "t0", "memory");

    asm volatile(
        "li   t0, 0xc0010003\n"
        "la   t1, 1f\n"
        "ori  t1, t1, 1\n"
        "jalr t2, 0(t1)\n"
        "sw   t0, 8(%[fail])\n"
        "1:\n"
        "xor  %[sig], %[sig], t2\n"
        : [sig] "+r"(sig)
        : [fail] "r"(fail_addr)
        : "t0", "t1", "t2", "memory");

    u32 call_a = jal_target_a(sig);
    u32 call_b = jal_target_b(call_a, sig);
    u32 call_c = nested_call(call_b);
    mix(sig, call_a);
    mix(sig, call_b);
    mix(sig, call_c);
}

static void loop_and_dependency_tests(volatile u32& sig) {
    u32 acc = 0x31415926u;
    for (u32 i = 0; i < 32; ++i) {
        SCR32[8] = acc + i;
        u32 r0 = SCR32[8];
        SCR32[8] = r0 ^ (i * 0x10203u);
        u32 r1 = SCR32[8];
        acc = (r1 + (acc << 1)) ^ (i + 0x77u);
        if ((i & 3u) == 0u) {
            acc += 0x101u;
        } else if ((i & 3u) == 1u) {
            acc ^= 0x202u;
        } else if ((i & 3u) == 2u) {
            acc -= 0x303u;
        } else {
            acc = (acc << 1) ^ (acc >> 3);
        }
    }
    mix(sig, acc);
}

extern "C" int main() {
    for (u32 i = 0; i < 64; ++i) {
        RESULT[i] = 0;
    }

    volatile u32 sig = 0x59535958u;

    arithmetic_and_compare_tests(sig);
    load_store_tests(sig);
    branch_matrix_tests(sig);
    explicit_control_flow_tests(sig);
    loop_and_dependency_tests(sig);

    RESULT[0] = 0x59535958u;
    RESULT[1] = sig;
    RESULT[2] = SCR32[0];
    RESULT[3] = SCR32[4];
    RESULT[4] = static_cast<u32>(SCRS8[4]);
    RESULT[5] = static_cast<u32>(SCRS16[4]);
    RESULT[6] = SCR32[8];
    RESULT[7] = 0x00000001u;

    while (1) {
        asm volatile("nop");
    }

    return 0;
}
