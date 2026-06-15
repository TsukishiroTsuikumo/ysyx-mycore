typedef unsigned int u32;
typedef int s32;

static volatile u32* const RESULT = reinterpret_cast<volatile u32*>(0x00008000u);

static u32 mix_func(u32 a, u32 b) {
    u32 x = a + b;
    x ^= (a << 3);
    x += (b >> 1);
    return x;
}

static u32 branch_func(s32 a, s32 b) {
    u32 score = 0;

    if (a < b) {
        score += 0x11;
    } else {
        score += 0x1000;
    }

    if (static_cast<u32>(a) > static_cast<u32>(b)) {
        score += 0x22;
    } else {
        score += 0x2000;
    }

    if ((a + b) == 4) {
        score += 0x44;
    } else {
        score += 0x4000;
    }

    return score;
}

extern "C" int main() {
    volatile u32 local[8];

    u32 a = 0x00000013u;
    u32 b = 0x00000007u;
    u32 c = 0;

    c = a + b;
    c = c * 3u;
    c = c - 5u;
    c = c ^ 0x55aa00ffu;
    c = c | 0x0000f000u;
    c = c & 0x7fffffff;

    local[0] = c;
    local[1] = mix_func(c, 0x12345678u);
    local[2] = branch_func(-3, 7);
    local[3] = local[0] + local[1] + local[2];
    local[4] = local[3] >> 3;
    local[5] = local[4] << 2;
    local[6] = local[5] / 3u;
    local[7] = local[6] % 97u;

    RESULT[0] = 0x59535958u; // "YSYX"
    RESULT[1] = local[0];
    RESULT[2] = local[1];
    RESULT[3] = local[2];
    RESULT[4] = local[3];
    RESULT[5] = local[4];
    RESULT[6] = local[5];
    RESULT[7] = local[6];
    RESULT[8] = local[7];
    RESULT[9] = 0x00000001u;

    while (1) {
    }

    return 0;
}
