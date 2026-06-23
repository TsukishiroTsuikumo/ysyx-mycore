// SB/LBU loop test — working baseline
typedef unsigned int u32;
typedef unsigned char u8;

static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);
static volatile u8*  const MEM8   = reinterpret_cast<volatile u8*>(0x00008100u);

extern "C" int main() {
    u32 acc = 0x31415926u;
    u32 matrix = 0;
    for (u32 row = 0; row < 4; ++row) {
        u32 row_sum = 0;
        for (u32 col = 0; col < 4; ++col) {
            MEM8[64 + row * 4 + col] = static_cast<u8>((row * col + acc) & 0xFFu);
            row_sum += MEM8[64 + row * 4 + col];
        }
        matrix ^= row_sum;
    }
    acc ^= matrix;

    RESULT[0] = 0x59535958u;
    RESULT[1] = acc;
    RESULT[2] = matrix;
    RESULT[3] = 0x00000001u;

    while (1) {
        asm volatile("nop");
    }
    return 0;
}
