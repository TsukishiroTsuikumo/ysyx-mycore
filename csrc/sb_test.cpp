// SB/LW stress test — reproduces sub-word store + load interaction bug
typedef unsigned int u32;
typedef unsigned char u8;

static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);
static volatile u32* const MEM32  = reinterpret_cast<volatile u32*>(0x00008100u);
static volatile u8*  const MEM8   = reinterpret_cast<volatile u8*>(0x00008100u);

extern "C" int main() {
    // Test 1: 4 SBs then 1 LW to same 32-bit word
    MEM8[0] = 0x7F;
    MEM8[1] = 0x80;
    MEM8[2] = 0x01;
    MEM8[3] = 0xFF;
    volatile u32 r1 = MEM32[0];                // should be 0xFF01807F

    // Test 2: interleaved SB / LW in a loop (like the original failure)
    for (u32 i = 0; i < 4; ++i) {
        MEM8[4 + i] = static_cast<u8>(0x10u * (i + 1u));
        volatile u32 check = MEM32[1];         // read full word — forces dm_req
        RESULT[16 + i] = check;                // save to prevent optimization
    }

    // Test 3: adjacent SB writes across 32-bit boundaries
    MEM8[8]  = 0xAA;
    MEM8[9]  = 0xBB;
    MEM8[10] = 0xCC;
    MEM8[11] = 0xDD;
    volatile u32 r2 = MEM32[2];

    RESULT[0] = 0x59535958u;
    RESULT[1] = r1;
    RESULT[2] = r2;
    RESULT[3] = 0x00000001u;

    while (1) {}
    return 0;
}
