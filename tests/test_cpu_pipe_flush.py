"""Directed branch/jump flush tests for the pipeline (step 6). The two wrong-path slots after a
taken branch or jump hold poison (a register write and a store); the words after the halt are
poison too. Cycle count: executed instructions + stalls + 2 per redirect + a fixed overhead."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

import rv32i as r
from cpu_env import load_program, monitor_stores, read_reg, read_word
from helpers import CPU_SOURCES, run_ghdl
from rv32i_model import RV32IModel

NOP = r.NOP
# x10 = 0x400 (data base), x1 = 0x123. Memory: [0x400] = 0x123, [0x404] = 0x408, [0x408] = 0x400
SETUP = [r.addi(10, 0, 0x400), r.addi(1, 0, 0x123), r.addi(2, 10, 8),
         r.sw(1, 0, 10), r.sw(2, 4, 10), r.sw(10, 8, 10), NOP, NOP, NOP]
POISON = [r.addi(9, 0, 99), r.sw(9, 32, 10)]       # wrong-path slots: a register write and a store
TARGET = r.addi(4, 0, 4)
AFTER_HALT = [r.addi(9, 0, 77), r.sw(9, 48, 10)]   # must never execute

PROGRAMS = {    # name: (instructions, load-use stalls, redirects: taken branches and jumps)
    "beq_taken":   ([r.beq(1, 1, 12)] + POISON + [TARGET], 0, 1),
    "bne_taken":   ([r.bne(1, 0, 12)] + POISON + [TARGET], 0, 1),
    "blt_taken":   ([r.blt(0, 1, 12)] + POISON + [TARGET], 0, 1),
    "bge_taken":   ([r.bge(1, 0, 12)] + POISON + [TARGET], 0, 1),
    "bltu_taken":  ([r.bltu(0, 1, 12)] + POISON + [TARGET], 0, 1),
    "bgeu_taken":  ([r.bgeu(1, 0, 12)] + POISON + [TARGET], 0, 1),
    "not_taken":   ([r.beq(1, 0, 12)] + POISON + [TARGET], 0, 0),      # the poison really executes
    "jal":         ([r.jal(5, 12)] + POISON + [TARGET], 0, 1),
    "jal_x0":      ([r.jal(0, 12)] + POISON + [TARGET], 0, 1),
    "jalr":        ([r.auipc(6, 0), r.jalr(7, 6, 16)] + POISON + [TARGET], 0, 1),
    "jalr_odd":    ([r.auipc(6, 0), r.jalr(7, 6, 17)] + POISON + [TARGET], 0, 1),
    # a taken branch sits in the wrong-path slot of another one and must not execute
    "branch_in_shadow": ([r.beq(1, 1, 16), r.beq(0, 0, 8), r.addi(9, 0, 99),
                          r.addi(9, 0, 98), TARGET], 0, 1),
    # the target of one taken branch is another taken branch
    "taken_chain": ([r.beq(1, 1, 8), r.addi(9, 0, 97), r.beq(1, 1, 12),
                     r.addi(9, 0, 96), r.addi(9, 0, 95), TARGET], 0, 2),
    "shadow_load": ([r.beq(1, 1, 12), r.lw(9, 0, 10), r.add(9, 9, 9), TARGET], 0, 1),
    "branch_after_load": ([r.lw(3, 0, 10), r.beq(3, 1, 12)] + POISON + [TARGET], 1, 1),
    "branch_forwarded": ([r.addi(6, 0, 5), r.addi(7, 0, 5), r.beq(6, 7, 12)] + POISON + [TARGET], 0, 1),
    "load_after_redirect": ([r.beq(1, 1, 12)] + POISON + [r.lw(3, 0, 10), r.add(4, 3, 1)], 1, 1),
    # backward branch taken twice; the fall-through instructions must run exactly once
    "loop": ([r.addi(6, 0, 3), r.addi(7, 7, 1), r.addi(6, 6, -1), r.bne(6, 0, -8),
              r.addi(8, 8, 1), r.addi(8, 8, 10)], 0, 2),
}


async def run_counting(dut, halt_pc, max_cycles):
    dut.rst.value = 0
    for cycles in range(1, max_cycles + 1):
        await RisingEdge(dut.clk)
        if int(dut.pc_out.value) == halt_pc:
            break
    else:
        raise AssertionError(f"pc never reached the halt address {halt_pc:#x} in {max_cycles} cycles")
    await ClockCycles(dut.clk, 12)
    await Timer(1, unit="ns")
    return cycles


@cocotb.test()
async def flush(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))
    overhead = {}

    for name, (body, stalls, redirects) in PROGRAMS.items():
        words = SETUP + body + [NOP] * 3 + [r.HALT] + AFTER_HALT
        await load_program(dut, words)
        model = RV32IModel(words)
        for n in range(1, 32):                    # start the model from the CPU's current registers
            model.regs[n] = await read_reg(dut, n)
        halt_pc = model.run()

        trace.clear()
        cycles = await run_counting(dut, halt_pc, max_cycles=10 * model.steps + 200)

        expected = [(a, d) for a, d, _ in model.stores]
        assert trace == expected, f"{name}: store trace {trace}, model {expected}"
        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], f"{name}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"
        for a in sorted({s[0] & ~3 for s in model.stores}):
            got = await read_word(dut, a)
            assert got == model.word(a), f"{name}: mem[{a:#x}] = {got:#010x}, model {model.word(a):#010x}"

        overhead[name] = cycles - model.steps - stalls - 2 * redirects
        dut._log.info(f"{name}: {model.steps} instructions, {stalls} stall(s), "
                      f"{redirects} redirect(s), {cycles} cycles")

    assert len(set(overhead.values())) == 1, \
        f"counts do not match (cycles - instructions - stalls - 2*redirects): {overhead}"
    dut._log.info(f"all {len(PROGRAMS)} programs match the model; fixed pipeline overhead = "
                  f"{set(overhead.values()).pop()} cycles")


def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_pipe_flush",
             parameters={"PIPELINED": "true"}, build_name="cpu_pipe")


if __name__ == "__main__":
    test_runner()
