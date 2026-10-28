import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from helpers import run_ghdl

CLKS = 434  # default CLKS_PER_BIT of uart_tx


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.tx_start.value = 0
    dut.tx_data.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)
    assert int(dut.tx.value) == 1, "line must idle high"
    assert int(dut.busy.value) == 0


async def receive_byte(dut):
    """Software UART receiver: sample every bit in the middle of its period."""
    await FallingEdge(dut.tx)
    await ClockCycles(dut.clk, CLKS // 2)
    assert int(dut.tx.value) == 0, "start bit not low at its midpoint"
    value = 0
    for i in range(8):
        await ClockCycles(dut.clk, CLKS)
        value |= int(dut.tx.value) << i          # LSB first
    await ClockCycles(dut.clk, CLKS)
    assert int(dut.tx.value) == 1, "stop bit not high"
    return value


async def send(dut, byte):
    dut.tx_data.value = byte
    dut.tx_start.value = 1
    await RisingEdge(dut.clk)
    dut.tx_start.value = 0


async def wait_idle(dut):
    while int(dut.busy.value):
        await RisingEdge(dut.clk)


@cocotb.test()
async def random_bytes(dut):
    await setup(dut)
    rng = random.Random(3)
    data = [0x00, 0xFF] + [rng.randrange(256) for _ in range(20)]
    for b in data:
        rx = cocotb.start_soon(receive_byte(dut))
        await send(dut, b)
        got = await rx
        assert got == b, f"received {got:#04x}, expected {b:#04x}"
        await wait_idle(dut)


@cocotb.test()
async def start_while_busy_is_ignored(dut):
    await setup(dut)
    rx = cocotb.start_soon(receive_byte(dut))
    await send(dut, 0xA5)
    await ClockCycles(dut.clk, 50)
    await send(dut, 0xFF)                        # must be ignored
    got = await rx
    assert got == 0xA5, f"received {got:#04x}, expected 0xa5"
    await wait_idle(dut)
    for _ in range(3 * CLKS):                    # no second frame may follow
        await RisingEdge(dut.clk)
        assert int(dut.tx.value) == 1, "unexpected second transmission"


def test_runner():
    run_ghdl("uart_tx", ["uart_tx_fsm.vhd", "uart_tx.vhd"], "test_uart_tx")


if __name__ == "__main__":
    test_runner()
