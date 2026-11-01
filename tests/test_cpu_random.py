import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from helpers import run_ghdl, CPU_SOURCES
from rv32i_gen import DATA_BASE, DATA_WORDS, generate
from rv32i_model import RV32IModel

N_PROGRAMS = int(os.environ.get("RV_PROGRAMS", "40"))
SEED0 = int(os.environ.get("RV_SEED0", "1000"))
HAZARD = float(os.environ.get("RV_HAZARD", "0.0"))


async def monitor_stores(dut, trace):
    """Record (address, data) of every store; sampled mid-cycle, when signals are stable."""
    while True:
        await FallingEdge(dut.clk)
        if str(dut.st_valid.value) == "1":
            trace.append((int(dut.st_addr.value), int(dut.st_data.value)))


async def read_reg(dut, n):
    dut.dbg_raddr.value = n
    await Timer(1, unit="ns")
    return int(dut.dbg_rdata.value)


async def read_word(dut, addr):
    dut.dbg_maddr.value = addr
    await Timer(1, unit="ns")
    return int(dut.dbg_mdata.value)


def first_store_diff(got, exp):
    for i, (g, e) in enumerate(zip(got, exp)):
        if g != e:
            return (f"store {i}: CPU addr={g[0]:#x} data={g[1]:#010x}, "
                    f"model addr={e[0]:#x} data={e[1]:#010x}")
    return f"CPU made {len(got)} stores, model made {len(exp)}"


@cocotb.test()
async def random_programs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))

    for seed in range(SEED0, SEED0 + N_PROGRAMS):
        words, _ = generate(seed, hazard=HAZARD)
        model = RV32IModel(words)
        halt_pc = model.run()
        where = f"seed {seed} (reproduce: RV_HAZARD={HAZARD} RV_SEED0={seed} RV_PROGRAMS=1 python tests/test_cpu_random.py)"

        # load the program while the CPU is held in reset
        dut.rst.value = 1
        dut.load_we.value = 0
        await ClockCycles(dut.clk, 2)
        for i, w in enumerate(words):
            dut.load_addr.value = 4 * i
            dut.load_data.value = w
            dut.load_we.value = 1
            await RisingEdge(dut.clk)
        dut.load_we.value = 0
        await ClockCycles(dut.clk, 2)

        trace.clear()
        dut.rst.value = 0
        await ClockCycles(dut.clk, model.steps + 10)     # one instruction per cycle
        await Timer(1, unit="ns")

        pc = int(dut.pc_out.value)
        assert pc == halt_pc, f"{where}: final pc {pc:#x}, model {halt_pc:#x}"

        expected = [(a, d) for a, d, _ in model.stores]
        assert trace == expected, f"{where}: {first_store_diff(trace, expected)}"

        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], \
                f"{where}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"

        for i in range(DATA_WORDS):
            addr = DATA_BASE + 4 * i
            got = await read_word(dut, addr)
            assert got == model.word(addr), \
                f"{where}: mem[{addr:#x}] = {got:#010x}, model {model.word(addr):#010x}"

    dut._log.info(f"{N_PROGRAMS} random programs: CPU and model agree "
                  f"on registers, memory, store trace and final pc")


def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_random")


if __name__ == "__main__":
    test_runner()
