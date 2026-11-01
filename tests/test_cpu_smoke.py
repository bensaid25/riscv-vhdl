import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from helpers import run_ghdl, CPU_SOURCES



PROG_ADD = [0x00500113, 0x00A00193, 0x003100B3, 0x00102023, 0x0000006F]
PROG_LOOP = [0x00000093, 0x00500113, 0x002080B3, 0xFFF10113,
             0xFE011CE3, 0x00102223, 0x0000006F]


async def run_program(dut, words, cycles=60):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1                       # hold the CPU in reset while loading
    dut.load_we.value = 0
    await ClockCycles(dut.clk, 2)
    for i, w in enumerate(words):
        dut.load_addr.value = 4 * i
        dut.load_data.value = w
        dut.load_we.value = 1
        await RisingEdge(dut.clk)
    dut.load_we.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0
    await ClockCycles(dut.clk, cycles)


async def reg(dut, n):
    dut.dbg_raddr.value = n
    await Timer(1, unit="ns")
    return int(dut.dbg_rdata.value)


async def mem_word(dut, addr):
    dut.dbg_maddr.value = addr
    await Timer(1, unit="ns")
    return int(dut.dbg_mdata.value)


@cocotb.test()
async def load_and_run_add(dut):
    await run_program(dut, PROG_ADD)
    assert int(dut.pc_out.value) == 0x10, "CPU not parked at the halt loop"
    assert await reg(dut, 0) == 0
    assert await reg(dut, 1) == 15
    assert await reg(dut, 2) == 5
    assert await reg(dut, 3) == 10
    assert await mem_word(dut, 0) == 15


@cocotb.test()
async def reload_and_run_loop(dut):
    await run_program(dut, PROG_LOOP)       # a second program, same simulation
    assert int(dut.pc_out.value) == 0x18, "CPU not parked at the halt loop"
    assert await reg(dut, 1) == 15
    assert await mem_word(dut, 4) == 15



def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_smoke")

if __name__ == "__main__":
    test_runner()
