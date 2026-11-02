"""Base-case test for the pipeline: NOP-padded programs. Every instruction is followed by
two NOPs, so every dependency is at distance 3 (served by the register file bypass alone,
no forwarding or stall involved) and the two slots after a branch or jump hold NOPs.
RV_CORE=single runs the same programs on the single-cycle CPU."""
import os

import cocotb
from cocotb.clock import Clock

import rv32i as r
from cpu_env import load_program, monitor_stores, read_reg, read_word, run_until_halt
from helpers import run_ghdl, CPU_SOURCES
from rv32i_model import RV32IModel

PIPE = os.environ.get("RV_CORE", "pipe") == "pipe"


def spaced(*instrs):
    """Each instruction followed by two NOPs: instruction k sits at byte address 12*k."""
    return [w for i in instrs for w in (i, r.NOP, r.NOP)]


PROGRAMS = {
    "straight": spaced(
        r.addi(1, 0, 5), r.addi(2, 1, 7), r.add(3, 1, 2), r.sub(4, 3, 1),
        r.slli(5, 4, 3), r.srai(6, 5, 1), r.lui(7, 0x12345), r.addi(7, 7, 0x678),
        r.auipc(8, 1), r.slt(9, 2, 1), r.sltu(10, 1, 2), r.xor(11, 3, 4),
        r.addi(12, 0, 0x400), r.sw(7, 0, 12), r.sh(1, 4, 12), r.sb(2, 6, 12),
        r.lw(13, 0, 12), r.lh(14, 4, 12), r.lbu(15, 6, 12), r.addi(16, 13, 1), r.HALT),
    "branches": spaced(
        r.addi(1, 0, 3), r.addi(2, 0, 3),
        r.beq(1, 2, 12 * 3),          # idx 2: taken, to idx 5
        r.addi(9, 0, 99), r.addi(9, 0, 98),
        r.bne(1, 2, 12 * 2),          # idx 5: not taken
        r.addi(10, 0, 7),
        r.blt(1, 2, 12 * 2),          # idx 7: not taken
        r.addi(11, 0, 8),
        r.bge(1, 2, 12 * 2),          # idx 9: taken, to idx 11
        r.addi(12, 0, 99),
        r.addi(13, 0, -1),
        r.bltu(1, 13, 12 * 2),        # idx 12: taken, to idx 14
        r.addi(14, 0, 99),
        r.blt(13, 1, 12 * 2),         # idx 14: taken, to idx 16
        r.addi(15, 0, 99),
        r.addi(16, 0, 16), r.HALT),
    "jumps": spaced(
        r.jal(1, 12 * 3),             # idx 0: to idx 3, x1 = 4
        r.addi(9, 0, 99), r.addi(9, 0, 98),
        r.auipc(5, 0),                # idx 3: x5 = 36
        r.jalr(6, 5, 12 * 3),         # idx 4: to idx 6, x6 = 52
        r.addi(9, 0, 97),
        r.addi(7, 0, 5),              # idx 6
        r.jalr(8, 5, 12 * 6 + 1),     # idx 7: bit 0 of the target set; to idx 9, x8 = 88
        r.addi(9, 0, 96),
        r.addi(10, 0, 10), r.HALT),
    "loop": spaced(
        r.addi(1, 0, 3), r.addi(6, 0, 0x400),
        r.addi(2, 2, 1),              # idx 2: loop start
        r.addi(1, 1, -1),
        r.bne(1, 0, 12 * -2),         # idx 4: back to idx 2
        r.sw(2, 0, 6), r.lw(3, 0, 6), r.HALT),
}


@cocotb.test()
async def padded_programs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))

    for name, words in PROGRAMS.items():
        await load_program(dut, words)
        model = RV32IModel(words)
        for n in range(1, 32):                    # start the model from the CPU's current registers
            model.regs[n] = await read_reg(dut, n)
        halt_pc = model.run()

        trace.clear()
        await run_until_halt(dut, halt_pc, max_cycles=10 * model.steps + 200)

        expected = [(a, d) for a, d, _ in model.stores]
        assert trace == expected, f"{name}: store trace {trace}, model {expected}"
        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], f"{name}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"
        for a in sorted({s[0] & ~3 for s in model.stores}):
            got = await read_word(dut, a)
            assert got == model.word(a), f"{name}: mem[{a:#x}] = {got:#010x}, model {model.word(a):#010x}"
        dut._log.info(f"{name}: {model.steps} instructions, CPU matches the model")


def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_pipe_skeleton",
             parameters={"PIPELINED": "true" if PIPE else "false"},
             build_name="cpu_pipe" if PIPE else "cpu_single")


if __name__ == "__main__":
    test_runner()
