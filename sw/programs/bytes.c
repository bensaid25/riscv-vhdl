int main(void) {
    volatile unsigned seed = 77;
    signed char sb[24];
    unsigned char ub[24];
    short sh[12];
    unsigned short uh[12];
    unsigned x = seed;
    for (int i = 0; i < 24; i++) {
        x = x * 1664525u + 1013904223u;
        sb[i] = (signed char)(x >> 24);
        ub[i] = (unsigned char)(x >> 16);
    }
    for (int i = 0; i < 12; i++) {
        x = x * 1664525u + 1013904223u;
        sh[i] = (short)(x >> 16);
        uh[i] = (unsigned short)(x >> 8);
    }
    int s = 0;
    unsigned u = 0;
    for (int i = 0; i < 24; i++) { s += sb[i]; u = u * 3u + ub[i]; }
    for (int i = 0; i < 12; i++) { s += sh[i]; u = u * 5u + uh[i]; }
    return (int)(u ^ (unsigned)s);
}
