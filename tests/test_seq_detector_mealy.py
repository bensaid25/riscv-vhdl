import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from helpers import run_ghdl


@cocotb.test()
async def random_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst.value = 1
    dut.din.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst.value = 0

    rng = random.Random(2)
    hist, hits = 0, 0
    for i in range(2000):
        b = rng.getrandbits(1)
        dut.din.value = b
        await Timer(1, unit="ns")          # Mealy: check BEFORE the edge
        hist = ((hist << 1) | b) & 0xF
        expected = int(hist == 0b1011)
        hits += expected
        assert int(dut.detected.value) == expected, f"mismatch at bit {i}"
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    assert hits > 0, "stream never contained the pattern"


def test_runner():
    run_ghdl("seq_detector_mealy", ["seq_detector_mealy.vhd"], "test_seq_detector_mealy")


if __name__ == "__main__":
    test_runner()
