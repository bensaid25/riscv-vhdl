"""C programs (built by scripts/build_c.py) on the single-cycle and pipelined CPUs.
Per program: model a0 vs the host gcc result (independent check), then CPU vs model on the store
trace, all registers, stored memory words and the initial data image, CPU a0 vs the host result
and, on the pipeline, the exact cycle formula. Run with: make c_regress"""
import json
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

from cpu_env import load_program, monitor_stores, read_reg, read_word
from helpers import CPU_SOURCES, run_ghdl
from rv32i_model import HALT_WORD, RV32IModel

ROOT = Path(__file__).resolve().parent.parent
C_DIR = ROOT / "sim" / "c"
IMEM_WORDS = 2048           # 8 KiB, matches sw/link.ld
DMEM_BYTES = 16384          # data region 0x2000-0x3FFF, stack top 0x4000
OVERHEAD = 1
PIPELINED = os.environ.get("RV_CORE", "pipe") == "pipe"
# Published check values: they come from outside every tool in this repository.
KNOWN = {"crc": 0xCBF43926}     # CRC-32 of "123456789"


def load(name):
    path = C_DIR / f"{name}.json"
    assert path.exists(), f"{path} missing: run scripts/build_c.py first"
    info = json.loads(path.read_text())
    words = [int(w, 16) for w in (C_DIR / f"{name}.hex").read_text().split()]
    data = [int(w, 16) for w in (C_DIR / f"{name}.data.hex").read_text().split()]
    assert len(data) == info["data_words"], f"{name}: data image size differs from the build record"
    assert info["expected"] is not None, f"{name}: no host reference value"
    assert len(words) <= IMEM_WORDS, f"{name}: {len(words)} words do not fit in instruction memory"
    assert info["data_base"] + 4 * len(data) <= DMEM_BYTES, f"{name}: data image does not fit in data memory"
    return info, words, data


def run_model(words, regs, data=(), data_base=0):
    """Run the model from the CPU's current registers; count load-use stalls and redirects."""
    m = RV32IModel(words, mem_bytes=DMEM_BYTES)
    m.regs = list(regs)
    for i, w in enumerate(data):                      # initial .rodata/.data image
        m.mem[data_base + 4 * i:data_base + 4 * i + 4] = w.to_bytes(4, "little")
    prev = None
    stalls = redirects = 0
    while m.imem[m.pc // 4] != HALT_WORD:
        assert m.steps < 1_000_000, "model: no halt"
        w, pc, op = m.imem[m.pc // 4], m.pc, m.imem[m.pc // 4] & 0x7F
        if prev and prev[1] and prev[0] != 0:
            uses1 = op not in (0x37, 0x17, 0x6F)
            uses2 = op in (0x33, 0x23, 0x63)
            if (uses1 and (w >> 15) & 31 == prev[0]) or (uses2 and (w >> 20) & 31 == prev[0]):
                stalls += 1
        m.step()
        if op in (0x6F, 0x67) or (op == 0x63 and m.pc != pc + 4):
            redirects += 1
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
async def c_programs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))
    names = sorted(p.stem for p in (ROOT / "sw" / "programs").glob("*.c"))
    assert names, "no programs in sw/programs"
    core = "pipeline" if PIPELINED else "single-cycle"

    for name in names:
        info, words, data = load(name)
        expected = info["expected"] & 0xFFFFFFFF
        if name in KNOWN:
            assert expected == KNOWN[name], (f"{name}: host gcc gives {expected:#x}, "
                                             f"the published value is {KNOWN[name]:#x}")
        await load_program(dut, words, data, info["data_base"])
        regs = [0] + [await read_reg(dut, n) for n in range(1, 32)]
        model, stalls, redirects = run_model(words, regs, data, info["data_base"])
        assert model.pc == info["halt_pc"], f"{name}: model halts at {model.pc:#x}, ELF says {info['halt_pc']:#x}"
        assert model.regs[10] == expected, (
            f"{name}: model a0 = {model.regs[10]}, host gcc = {expected} "
            f"(the model or the build flow is wrong, not the CPU)")

        trace.clear()
        cycles = await run_counting(dut, model.pc, max_cycles=6 * model.steps + 200)

        want = [(a, d) for a, d, _ in model.stores]
        assert trace == want, f"{name} ({core}): store trace differs (CPU {len(trace)}, model {len(want)})"
        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], f"{name} ({core}): x{n} = {got:#010x}, model {model.regs[n]:#010x}"
        for a in sorted({s[0] & ~3 for s in model.stores}):
            got = await read_word(dut, a)
            assert got == model.word(a), f"{name} ({core}): mem[{a:#x}] = {got:#010x}, model {model.word(a):#010x}"
        for i in range(len(data)):                    # the initial data image: loader and later writes
            a = info["data_base"] + 4 * i
            got = await read_word(dut, a)
            assert got == model.word(a), (f"{name} ({core}): data image word {i} at {a:#x} = {got:#010x}, "
                                          f"model {model.word(a):#010x}")
        a0 = await read_reg(dut, 10)
        assert a0 == expected, f"{name} ({core}): a0 = {a0}, host gcc = {expected}"
        if PIPELINED:
            predicted = model.steps + stalls + 2 * redirects + OVERHEAD
            assert cycles == predicted, (f"{name}: {cycles} cycles, predicted {predicted} "
                                         f"({model.steps} + {stalls} stalls + 2*{redirects} redirects + {OVERHEAD})")
        dut._log.info(f"{name} ({core}): result {a0}, {model.steps} instructions, {cycles} cycles, "
                      f"CPI {cycles / model.steps:.3f}; host, model and CPU agree")


def test_runner():
    for pipelined in (False, True):
        os.environ["RV_CORE"] = "pipe" if pipelined else "single"
        run_ghdl("cpu_sc", CPU_SOURCES, "cpu_c_programs",
                 parameters={"PIPELINED": "true" if pipelined else "false",
                             "IMEM_WORDS": str(IMEM_WORDS), "DMEM_BYTES": str(DMEM_BYTES)},
                 build_name="cpu_c_pipe" if pipelined else "cpu_c_single")


if __name__ == "__main__":
    test_runner()
