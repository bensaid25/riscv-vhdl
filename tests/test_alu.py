import random

import cocotb
from cocotb.triggers import Timer

from helpers import run_ghdl

OPS = {"ADD": 0, "SUB": 1, "AND": 2, "OR": 3, "XOR": 4, "SLL": 5,
       "SRL": 6, "SRA": 7, "SLT": 8, "SLTU": 9, "COPYB": 10}
MASK = 0xFFFFFFFF
CORNERS = [0x00000000, 0x00000001, 0x00000002, 0x0000001F, 0x00000020,
           0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF,
           0xAAAAAAAA, 0x55555555]


def signed(x):
    return x - (1 << 32) if x & 0x80000000 else x


def model(op, a, b):
    sh = b & 31                      # only the low 5 bits of b select the shift
    if op == "ADD":   return (a + b) & MASK
    if op == "SUB":   return (a - b) & MASK
    if op == "AND":   return a & b
    if op == "OR":    return a | b
    if op == "XOR":   return a ^ b
    if op == "SLL":   return (a << sh) & MASK
    if op == "SRL":   return a >> sh
    if op == "SRA":   return (signed(a) >> sh) & MASK
    if op == "SLT":   return int(signed(a) < signed(b))
    if op == "SLTU":  return int(a < b)
    if op == "COPYB": return b
    raise ValueError(op)


async def check(dut, op, a, b):
    dut.op.value = OPS[op]
    dut.a.value = a
    dut.b.value = b
    await Timer(1, unit="ns")
    got = int(dut.result.value)
    got_zero = int(dut.zero.value)
    exp = model(op, a, b)
    assert got == exp, (
        f"{op}: a={a:#010x} b={b:#010x} expected {exp:#010x} got {got:#010x}")
    assert got_zero == int(exp == 0), (
        f"{op}: a={a:#010x} b={b:#010x} wrong zero flag ({got_zero})")


@cocotb.test()
async def corner_cases(dut):
    for op in OPS:
        for a in CORNERS:
            for b in CORNERS:
                await check(dut, op, a, b)


@cocotb.test()
async def random_operands(dut):
    for op in OPS:
        for _ in range(2000):
            await check(dut, op, random.getrandbits(32), random.getrandbits(32))


@cocotb.test()
async def all_shift_amounts(dut):
    for op in ("SLL", "SRL", "SRA"):
        for sh in range(32):
            for a in (0x00000001, 0x80000000, 0xDEADBEEF, 0xFFFFFFFF):
                await check(dut, op, a, sh)
                await check(dut, op, a, 0xFFFFFFE0 | sh)   # upper bits must be ignored


def test_runner():
    run_ghdl("alu_wrap",
             ["alu_pkg.vhd", "alu.vhd", "../tests/hdl/alu_wrap.vhd"],
             "test_alu")


if __name__ == "__main__":
    test_runner()