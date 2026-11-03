static unsigned fib(unsigned n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void) {
    volatile unsigned n = 15;
    return (int)fib(n);                        /* 610 */
}
