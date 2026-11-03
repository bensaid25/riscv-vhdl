/* Comparison mix: slti, sltiu (small and sign-extended immediates), slt and sltu,
   folded into an order-sensitive checksum. xorshift32 inputs cover the whole range. */
int main(void) {
    volatile unsigned seed = 2463534242u;
    unsigned x = seed, acc = 0;
    for (int i = 0; i < 200; i++) {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        int sx = (int)x;
        unsigned y = (x << 3) ^ (x >> 5);
        unsigned lo = x & 0xFFu;
        acc = acc * 31u
            + (lo < 100u)                    /* sltiu, small immediate */
            + 2u * (sx < 20)                 /* slti */
            + 4u * (sx < -50)                /* slti, negative immediate */
            + 8u * (x < 0xFFFFFFCEu)         /* sltiu, sign-extended immediate */
            + 16u * (x < y)                  /* sltu */
            + 32u * (sx < (int)y);           /* slt */
    }
    return (int)acc;
}
