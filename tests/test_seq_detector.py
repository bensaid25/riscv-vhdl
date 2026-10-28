import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner


@cocotb.test()
async def random_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst.value = 1
    dut.din.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst.value = 0

    rng = random.Random(1)
    hist, hits = 0, 0
    for i in range(2000):
        b = rng.getrandbits(1)
        dut.din.value = b
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        hist = ((hist << 1) | b) & 0xF
        expected = int(hist == 0b1011)
        hits += expected
        assert int(dut.detected.value) == expected, f"mismatch at bit {i}"

    assert hits > 0, "stream never contained the pattern"


def test_runner():
    root = Path(__file__).resolve().parent.parent
    build_dir = root / "sim" / "cocotb_build"
    runner = get_runner("ghdl")
    runner.build(
        sources=[root / "rtl" / "seq_detector.vhd"],
        hdl_toplevel="seq_detector",
        build_args=["--std=08"],
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="seq_detector",
        test_module="test_seq_detector",
        test_args=["--std=08"],
        build_dir=build_dir,
        test_dir=build_dir,
    )


if __name__ == "__main__":
    test_runner()
