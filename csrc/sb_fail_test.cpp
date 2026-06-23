// Exact reproduction of the failing memory_tests SB/SH code
typedef unsigned int   u32;
typedef signed int     s32;
typedef unsigned char  u8;
typedef signed char    s8;
typedef unsigned short u16;
typedef signed short   s16;

static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);
static volatile u32* const MEM32  = reinterpret_cast<volatile u32*>(0x00008100u);
static volatile u16* const MEM16  = reinterpret_cast<volatile u16*>(0x00008100u);
static volatile u8*  const MEM8   = reinterpret_cast<volatile u8*>(0x00008100u);
static volatile s8*  const MEMS8  = reinterpret_cast<volatile s8*>(0x00008100u);
static volatile s16* const MEMS16 = reinterpret_cast<volatile s16*>(0x00008100u);

static inline void mix(volatile u32& sig, u32 v) {
    sig = (sig << 5) ^ (sig >> 2) ^ v ^ 0x9e3779b9u;
}

// Exact copy of the original failing memory_tests
__attribute__((noinline))
static u32 mem_tests_original(u32 pattern) {
    volatile u32 sig = 0;
    u32 hi = pattern >> 16;
    u32 lo = pattern & 0xFFFFu;

    // word stores/loads
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
    mix(sig, w0); mix(sig, w1); mix(sig, w2); mix(sig, w3); mix(sig, w4);

    // halfword stores/loads
    MEM16[16] = static_cast<u16>(hi);
    MEM16[17] = static_cast<u16>(lo);
    u16 h0 = MEM16[16];
    u16 h1 = MEM16[17];
    MEM16[18] = h0 + h1;
    u16 h2 = MEM16[18];
    mix(sig, static_cast<u32>(h0));
    mix(sig, static_cast<u32>(h1));
    mix(sig, static_cast<u32>(h2));

    // byte stores/loads
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

    // unaligned-ish access via byte manipulation
    u32 unaligned = (static_cast<u32>(MEM8[32]))
                  | (static_cast<u32>(MEM8[33]) << 8)
                  | (static_cast<u32>(MEM8[34]) << 16)
                  | (static_cast<u32>(MEM8[35]) << 24);
    mix(sig, unaligned);

    return sig;
}

extern "C" int main() {
    for (u32 i = 0; i < 32; ++i) RESULT[i] = 0;

    volatile u32 sig = mem_tests_original(0xABCD1234u);

    RESULT[0] = 0x59535958u;
    RESULT[1] = sig;
    RESULT[2] = 0x00000001u;

    while (1) {}
    return 0;
}
