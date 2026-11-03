static unsigned gcd(unsigned a, unsigned b) {
    while (b) { unsigned t = a % b; a = b; b = t; }
    return a;
}

int main(void) {
    volatile unsigned x = 1071, y = 462;
    unsigned g = gcd(x, y);                                   /* 21 */
    unsigned s = 0;
    for (unsigned i = 1; i <= 30; i++) s += gcd(i * 12u, 18u) + (i * 977u) / 13u;
    return (int)(g * 1000u + s % 1000u);
}