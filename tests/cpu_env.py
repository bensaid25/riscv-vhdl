"""Helpers shared by the CPU cocotb tests (program loading, state read-back, run control)."""
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from rv32i_model import RV32IModel


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


async def load_program(dut, words, data=(), data_base=0):
    """Write the program into instruction memory, and optional initial words into data
    memory, while the CPU is held in reset."""
    dut.rst.value = 1
    dut.load_we.value = 0
    dut.dload_we.value = 0
    await ClockCycles(dut.clk, 2)
    for i, w in enumerate(words):
        dut.load_addr.value = 4 * i
        dut.load_data.value = w
        dut.load_we.value = 1
        await RisingEdge(dut.clk)
    dut.load_we.value = 0
    for i, w in enumerate(data):
        dut.dload_addr.value = data_base + 4 * i
        dut.dload_data.value = w
        dut.dload_we.value = 1
        await RisingEdge(dut.clk)
    dut.dload_we.value = 0
    await ClockCycles(dut.clk, 2)


async def run_until_halt(dut, halt_pc, max_cycles, drain=12):
    """Release reset, wait until the PC reaches the halt loop, then let the pipeline drain."""
    dut.rst.value = 0
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.pc_out.value) == halt_pc:
            break
    else:
        raise AssertionError(f"pc never reached the halt address {halt_pc:#x} in {max_cycles} cycles")
    await ClockCycles(dut.clk, drain)
    await Timer(1, unit="ns")


async def run_and_compare(dut, name, words, trace):
    """Load `words`, run model and CPU, compare stores, registers and memory."""
    await load_program(dut, words)
    model = RV32IModel(words)
    for n in range(1, 32):                    # the CPU keeps its registers between programs
        model.regs[n] = await read_reg(dut, n)
    halt_pc = model.run()

    trace.clear()
    await run_until_halt(dut, halt_pc, max_cycles=10 * model.steps + 200)

    expected = [(a, d) for a, d, _ in model.stores]
    assert trace == expected, f"{name}: store trace {trace}, model {expected}"
    for n in range(32):
        got = await read_reg(dut, n)
        assert got == model.regs[n], f"{name}: x{n} = {got:#010x}, model {model.regs[n]:#010x}"
    for a in sorted({s[0] & ~3 for s in model.stores}):
        got = await read_word(dut, a)
        assert got == model.word(a), f"{name}: mem[{a:#x}] = {got:#010x}, model {model.word(a):#010x}"
    dut._log.info(f"{name}: {model.steps} instructions, CPU matches the model")
