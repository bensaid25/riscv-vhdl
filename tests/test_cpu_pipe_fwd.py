"""Directed forwarding test (step 2): dependent instructions back to back.
Branches and jumps stay out of the programs until the flush exists (step 4)."""
import cocotb
from cocotb.clock import Clock

import rv32i as r
from cpu_env import monitor_stores, run_and_compare
from helpers import CPU_SOURCES, run_ghdl

END = [r.HALT, r.NOP, r.NOP]      # the two NOPs absorb the wrong-path fetches after the halt jump

PROGRAMS = {
    "alu_chain": [
        r.addi(1, 0, 5),
        r.addi(2, 1, 3),          # x1 at distance 1 (EX/MEM)
        r.add(3, 2, 1),           # x2 distance 1, x1 distance 2 (MEM/WB)
        r.sub(4, 3, 2),           # x3 distance 1, x2 distance 2
        r.add(5, 4, 4),           # same register on both ports, distance 1
        r.or_(6, 1, 2),           # distances 5 and 4: register file
        r.addi(7, 0, 9),
        r.addi(8, 0, 1),
        r.addi(9, 0, 2),
        r.add(10, 7, 8),          # x7 distance 3 (regfile bypass), x8 distance 2
    ] + END,
    "priority_and_x0": [
        r.addi(11, 0, 1),
        r.addi(11, 0, 2),
        r.add(12, 11, 11),        # must see 2 from EX/MEM, not 1 from MEM/WB
        r.addi(0, 0, 5),          # write to x0 is discarded
        r.add(13, 0, 0),          # must be 0: no forwarding for x0
        r.addi(14, 0, 7),
        r.add(15, 0, 14),
    ] + END,
    "store_and_load": [
        r.addi(16, 0, 0x400),
        r.addi(17, 0, 0x55),
        r.sw(17, 0, 16),          # store data at distance 1, base at distance 2
        r.lw(18, 0, 16),
        r.addi(19, 0, 1),         # filler: keeps the load's consumer at distance 2
        r.add(20, 18, 18),        # load data forwarded from MEM/WB
        r.sh(20, 4, 16),          # store data at distance 1
    ] + END,
}


@cocotb.test()
async def forwarding(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))
    for name, words in PROGRAMS.items():
        await run_and_compare(dut, name, words, trace)


def test_runner():
    run_ghdl("cpu_sc", CPU_SOURCES, "test_cpu_pipe_fwd",
             parameters={"PIPELINED": "true"}, build_name="cpu_pipe")


if __name__ == "__main__":
    test_runner()
