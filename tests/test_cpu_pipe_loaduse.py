"""Directed load-use tests for the pipeline (step 5). Straight-line programs only (no taken
branches yet). Besides the final state, the cycle count is checked:
    cycles = instructions executed + declared stalls + a constant (pipeline fill)
so a missing stall changes a result, and a spurious one changes the cycle count."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

import rv32i as r
from cpu_env import load_program, monitor_stores, read_reg, read_word
from helpers import run_ghdl
from rv32i_model import RV32IModel

SOURCES = ["alu_pkg.vhd", "alu.vhd", "ctrl_pkg.vhd", "control.vhd", "immgen.vhd",
           "regfile.vhd", "branch_unit.vhd", "forward_unit.vhd", "cpu_core.vhd",
           "cpu_pipe.vhd", "imem.vhd", "dmem.vhd", "cpu_sc.vhd"]
NOP = r.NOP

# x10 = 0x400 (data base), x1 = 0x123. Memory: [0x400] = 0x123, [0x404] = 0x408, [0x408] = 0x400
SETUP = [r.addi(10, 0, 0x400), r.addi(1, 0, 0x123), r.addi(2, 10, 8),
         r.sw(1, 0, 10), r.sw(2, 4, 10), r.sw(10, 8, 10), NOP, NOP, NOP]

PROGRAMS = {    # name: (instructions, expected number of load-use stalls)
    "alu_operand_a":   ([r.lw(3, 0, 10), r.add(4, 3, 1)], 1),
    "alu_operand_b":   ([r.lw(3, 0, 10), r.add(4, 1, 3)], 1),
    "immediate_use":   ([r.lw(3, 0, 10), r.addi(4, 3, 5)], 1),
    "store_data":      ([r.lw(3, 0, 10), r.sw(3, 16, 10)], 1),
    "store_address":   ([r.lw(3, 4, 10), r.sw(1, 0, 3)], 1),
    "load_address":    ([r.lw(3, 4, 10), r.lw(4, 0, 3)], 1),
    "load_chain":      ([r.lw(3, 4, 10), r.lw(4, 0, 3), r.add(5, 4, 4)], 2),
    "branch_rs1":      ([r.lw(3, 0, 10), r.beq(3, 0, 8), r.addi(7, 0, 7)], 1),
    "branch_rs2":      ([r.lw(3, 0, 10), r.beq(0, 3, 8), r.addi(7, 0, 7)], 1),
    "two_loads":       ([r.lw(3, 0, 10), r.lw(4, 4, 10), r.add(5, 3, 4)], 1),
    "used_twice":      ([r.lw(3, 0, 10), r.add(4, 3, 3), r.add(5, 4, 3)], 1),
    "distance_2":      ([r.lw(3, 0, 10), r.addi(6, 0, 1), r.add(4, 3, 6)], 0),
    "distance_3":      ([r.lw(3, 0, 10), NOP, NOP, r.add(4, 3, 1)], 0),
    "no_consumer":     ([r.lw(3, 0, 10), r.add(4, 1, 1)], 0),
    "x0_destination":  ([r.lw(0, 0, 10), r.add(4, 0, 0)], 0),
    # lui's immediate bits 19:15 equal the load's rd (x5), but lui reads no register
    "lui_not_a_use":   ([r.lw(5, 0, 10), r.lui(6, 0x28)], 0),
}


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
async def load_use(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    trace = []
    cocotb.start_soon(monitor_stores(dut, trace))
    overhead = {}

    for name, (body, stalls) in PROGRAMS.items():
        # three NOPs drain the body; two NOPs after the halt fill the slots the pipeline
        # fetches before the halt jump redirects (no flush yet)
        words = SETUP + body + [NOP] * 3 + [r.HALT, NOP, NOP]
        await load_program(dut, words)
        model = RV32IModel(words)
        for n in range(1, 32):                    # start the model from the CPU's current registers
            model.regs[n] = await read_reg(dut, n)
        halt_pc = model.run()

        trace.clear()
        cycles = await run_counting(dut, halt_pc, max_cycles=10 * model.steps + 200)

        expected = [(a, d) for a, d, _ in model.stores]
        assert trace == expected, f"{name}: store trace {trace}, model {expected}"
        for n in range(32):
            got = await read_reg(dut, n)
            assert got == model.regs[n], f"{name}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"
        for a in sorted({s[0] & ~3 for s in model.stores}):
            got = await read_word(dut, a)
            assert got == model.word(a), f"{name}: mem[{a:#x}] = {got:#010x}, model {model.word(a):#010x}"

        overhead[name] = cycles - model.steps - stalls
        dut._log.info(f"{name}: {model.steps} instructions, {stalls} stall(s), {cycles} cycles")

    assert len(set(overhead.values())) == 1, \
        f"stall counts do not match the cycle counts (cycles - instructions - stalls): {overhead}"
    dut._log.info(f"all {len(PROGRAMS)} programs match the model; fixed pipeline overhead = "
                  f"{set(overhead.values()).pop()} cycles")


def test_runner():
    run_ghdl("cpu_sc", SOURCES, "test_cpu_pipe_loaduse",
             parameters={"PIPELINED": "true"}, build_name="cpu_pipe")


if __name__ == "__main__":
    test_runner()
