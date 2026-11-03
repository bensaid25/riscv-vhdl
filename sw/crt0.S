    .section .text.init, "ax"
    .globl _start
    .globl _halt
_start:
    lui   sp, %hi(__stack_top)
    addi  sp, sp, %lo(__stack_top)

    # zero .bss (the testbench keeps data memory contents between programs)
    lui   t0, %hi(__bss_start)
    addi  t0, t0, %lo(__bss_start)
    lui   t1, %hi(__bss_end)
    addi  t1, t1, %lo(__bss_end)
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:
    jal   ra, main
    # three NOPs: the pipeline fetches (and flushes) the words after the jal, and the
    # halt loop must not be one of them or the testbench sees the halt address too early
    nop
    nop
    nop
_halt:
    j     _halt             # jal x0, 0: the halt loop the model and testbenches expect