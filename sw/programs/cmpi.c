/* slti with edge immediates, and bge taken / not taken. GCC does not choose these at -O1,
   so the RISC-V build forces them with inline asm; the host build uses plain C, so the host
   result is still the reference for what the instructions must compute. */
#ifdef __riscv
#define SLTI(out, v, imm) __asm__("slti %0, %1, " #imm : "=r"(out) : "r"(v))
#else
#define SLTI(out, v, imm) ((out) = ((int)(v) < (imm)))
#endif

int main(void) {
    volatile unsigned seed = 88172645u;
    unsigned x = seed, acc = 0;
    for (int i = 0; i < 300; i++) {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        int v = (int)x;
        int w = (int)((x << 7) ^ (x >> 9));
        int a, b, c, d, e;
        SLTI(a, v, 20);
        SLTI(b, v, -50);
        SLTI(c, v, -2048);
        SLTI(d, v, 2047);
        SLTI(e, v, 0);
        int g = 0;
#ifdef __riscv
        __asm__("bge %1, %2, 1f\n\taddi %0, %0, 1\n1:" : "+r"(g) : "r"(v), "r"(w));
#else
        if (!(v >= w)) g += 1;
#endif
        acc = acc * 31u + (unsigned)(a + 2 * b + 4 * c + 8 * d + 16 * e + 32 * g);
    }
    return (int)acc;
}
