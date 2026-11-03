int main(void) {
    volatile unsigned seed = 7;
    unsigned a[16], b[16], c[16];
    unsigned x = seed;
    for (int i = 0; i < 16; i++) {
        x = x * 75u + 74u;
        a[i] = x & 0xFFu;
        x = x * 75u + 74u;
        b[i] = x & 0xFFu;
    }
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            unsigned s = 0;
            for (int k = 0; k < 4; k++) s += a[i * 4 + k] * b[k * 4 + j];
            c[i * 4 + j] = s;
        }
    unsigned sum = 0;
    for (int i = 0; i < 16; i++) sum = sum * 31u + c[i];
    return (int)sum;
}
