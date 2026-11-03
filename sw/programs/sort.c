int main(void) {
    volatile unsigned seed = 12345;
    unsigned a[16];
    unsigned x = seed;
    for (int i = 0; i < 16; i++) {
        x = x * 1103515245u + 12345u;
        a[i] = (x >> 16) & 0x7FFFu;
    }
    for (int i = 0; i < 15; i++)
        for (int j = 0; j < 15 - i; j++)
            if (a[j] > a[j + 1]) { unsigned t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }
    unsigned sum = 0;
    for (int i = 0; i < 16; i++) sum = sum * 31u + a[i];     /* order-sensitive */
    return (int)sum;
}