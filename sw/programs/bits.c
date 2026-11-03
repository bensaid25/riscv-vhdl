static unsigned popcount(unsigned v) {
    unsigned c = 0;
    while (v) { c += v & 1u; v >>= 1; }
    return c;
}

int main(void) {
    volatile int seed = -123456;
    unsigned u = (unsigned)seed;
    unsigned acc = 0;
    for (int i = 0; i < 40; i++) {
        u = u * 3u + 1u;
        int v = (int)u;
        int a = v >> (i & 15);                 /* arithmetic shift, variable amount */
        unsigned b = u >> (i & 15);            /* logical shift, variable amount */
        acc += popcount((unsigned)a ^ b);
        acc += (unsigned)(a < 0) + 3u * (unsigned)(b < 0x1000u) + ((a < (int)b) ? 7u : 0u);
        acc ^= u << (i & 7);
        acc ^= 0x5Au;                          /* xori */
        acc |= ((unsigned)(i & 1) << 9) | 0x100u;   /* ori */
        acc += (unsigned)(v >> 3);             /* constant arithmetic shift: srai */
        acc += (unsigned)(a < 100) * 11u;      /* slti: signed compare with a small constant */
        acc += (unsigned)(b < 2000u) * 13u;    /* sltiu: unsigned compare with a small constant */
    }
    return (int)acc;
}
