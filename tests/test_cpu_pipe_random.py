"""Random-program regression for the pipelined CPU: hazard-heavy programs, compared with the
reference model on stores, registers and data memory, plus an exact cycle-count check:
    cycles = instructions + load-use stalls + 2 * redirects + OVERHEAD
(stalls and redirects are counted from the model's execution; the formula was established
by the directed tests). The final pc is not compared: in the halt loop the pc keeps cycling
through the halt address and the two flushed wrong-path addresses."""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

import rv32i as r
from cpu_env import load_program, monitor_stores, read_reg, read_word
from helpers import CPU_SOURCES, run_ghdl
from rv32i_gen import DATA_BASE, DATA_WORDS, generate
from rv32i_model import HALT_WORD, RV32IModel

N_PROGRAMS = int(os.environ.get("RV_PROGRAMS", "40"))
SEED0 = int(os.environ.get("RV_SEED0", "1000"))
HAZARD = float(os.environ.get("RV_HAZARD", "0.6"))
OVERHEAD = 1          # pipeline fill, measured by the directed cycle-count tests


def run_model(words):
    """Run the model and count what the pipeline pays for: load-use stalls and redirects."""
    m = RV32IModel(words)
    prev = None                                   # (rd, is_load) of the previously executed instruction
    stalls = redirects = 0
    while m.imem[m.pc // 4] != HALT_WORD:
        assert m.steps < 100_000, "model: no halt"
        w, pc, op = m.imem[m.pc // 4], m.pc, m.imem[m.pc // 4] & 0x7F
        if prev and prev[1] and prev[0] != 0:     # the previous instruction was a load
            uses1 = op not in (0x37, 0x17, 0x6F)  # lui, auipc, jal read no register
            uses2 = op in (0x33, 0x23, 0x63)      # register-register, stores, branches
            if (uses1 and (w >> 15) & 31 == prev[0]) or (uses2 and (w >> 20) & 31 == prev[0]):
                stalls += 1
        m.step()
        if op in (0x6F, 0x67) or (op == 0x63 and m.pc != pc + 4):
            redirects += 1                        # jal, jalr, taken branch
        prev = ((w >> 7) & 31, op == 0x03)
    return m, stalls, redirects


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
async def random_programs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))
    tot = dict(instr=0, cycles=0, stalls=0, redirects=0)

    for seed in range(SEED0, SEED0 + N_PROGRAMS):
        words, _ = generate(seed, hazard=HAZARD)
        assert words[-1] == r.HALT
        words = words[:-1] + [r.NOP] * 3 + [r.HALT]
        model, stalls, redirects = run_model(words)
        where = (f"seed {seed} (reproduce: RV_HAZARD={HAZARD} RV_SEED0={seed} RV_PROGRAMS=1 "
                 f"python tests/test_cpu_pipe_random.py)")

        await load_program(dut, words)
        trace.clear()
        cycles = await run_counting(dut, model.pc, max_cycles=6 * model.steps + 200)

        expected = [(a, d) for a, d, _ in model.stores]
        assert trace == expected, f"{where}: store trace differs (CPU {len(trace)} stores, model {len(expected)})"
        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], f"{where}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"
        for i in range(DATA_WORDS):
            addr = DATA_BASE + 4 * i
            got = await read_word(dut, addr)
            assert got == model.word(addr), f"{where}: mem[{addr:#x}] = {got:#010x}, model {model.word(addr):#010x}"

        predicted = model.steps + stalls + 2 * redirects + OVERHEAD
        assert cycles == predicted, (f"{where}: {cycles} cycles, predicted {predicted} "
                                     f"({model.steps} instructions + {stalls} stalls + 2*{redirects} redirects + {OVERHEAD})")
        tot["instr"] += model.steps
        tot["cycles"] += cycles
        tot["stalls"] += stalls
        tot["redirects"] += redirects

    dut._log.info(f"{N_PROGRAMS} random programs (hazard {HAZARD}): pipeline and model agree on stores, "
                  f"registers, memory and cycle count")
    dut._log.info(f"CPI = {tot['cycles'] / tot['instr']:.3f}  ({tot['instr']} instructions, {tot['cycles']} cycles, "
                  f"{tot['stalls']} load-use stalls = {100 * tot['stalls'] / tot['instr']:.1f}%, "
                  f"{tot['redirects']} redirects = {100 * tot['redirects'] / tot['instr']:.1f}%)")


def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_pipe_random",
             parameters={"PIPELINED": "true"}, build_name="cpu_pipe")


if __name__ == "__main__":
    test_runner()
