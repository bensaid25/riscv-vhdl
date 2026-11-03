#!/usr/bin/env python3
"""Dynamic instruction coverage: which of the 37 RV32I instructions the model executes in the
compiled C programs, and how often each branch outcome occurs.
usage: python scripts/c_exec_coverage.py   (run scripts/build_c.py first)"""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from rv32i_model import HALT_WORD, RV32IModel

C_DIR = ROOT / "sim" / "c"
DMEM_BYTES = 16384
RV32I = ("lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw "
         "addi slti sltiu xori ori andi slli srli srai add sub sll slt sltu xor srl sra or and").split()
BRANCHES = ("beq", "bne", "blt", "bge", "bltu", "bgeu")
R_NAMES = {(0, 0): "add", (0x20, 0): "sub", (0, 1): "sll", (0, 2): "slt", (0, 3): "sltu",
           (0, 4): "xor", (0, 5): "srl", (0x20, 5): "sra", (0, 6): "or", (0, 7): "and"}
I_NAMES = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}


def mnemonic(w):
    op, f3, f7 = w & 0x7F, (w >> 12) & 7, w >> 25
    if op == 0x37: return "lui"
    if op == 0x17: return "auipc"
    if op == 0x6F: return "jal"
    if op == 0x67: return "jalr"
    if op == 0x63: return BRANCHES[{0: 0, 1: 1, 4: 2, 5: 3, 6: 4, 7: 5}[f3]]
    if op == 0x03: return {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}[f3]
    if op == 0x23: return {0: "sb", 1: "sh", 2: "sw"}[f3]
    if op == 0x13:
        if f3 == 1: return "slli"
        if f3 == 5: return "srai" if f7 == 0x20 else "srli"
        return I_NAMES[f3]
    if op == 0x33: return R_NAMES[(f7, f3)]
    raise ValueError(f"cannot decode {w:#010x}")


def run(name):
    info = json.loads((C_DIR / f"{name}.json").read_text())
    words = [int(x, 16) for x in (C_DIR / f"{name}.hex").read_text().split()]
    data = [int(x, 16) for x in (C_DIR / f"{name}.data.hex").read_text().split()]
    m = RV32IModel(words, mem_bytes=DMEM_BYTES)
    for i, w in enumerate(data):
        a = info["data_base"] + 4 * i
        m.mem[a:a + 4] = w.to_bytes(4, "little")
    ran, taken = Counter(), Counter()
    while m.imem[m.pc // 4] != HALT_WORD:
        assert m.steps < 1_000_000, f"{name}: no halt"
        w, pc = m.imem[m.pc // 4], m.pc
        n = mnemonic(w)
        m.step()
        ran[n] += 1
        if n in BRANCHES and m.pc != pc + 4:
            taken[n] += 1
    assert m.regs[10] == info["expected"] & 0xFFFFFFFF, f"{name}: a0 differs from the host result"
    return ran, taken


def main():
    names = sorted(p.stem for p in C_DIR.glob("*.json"))
    assert names, "no programs in sim/c: run scripts/build_c.py first"
    per = {n: run(n) for n in names}
    ran, taken = Counter(), Counter()
    for r, t in per.values():
        ran.update(r)
        taken.update(t)
    print(f"{'instr':8} {'executed':>9} {'taken':>8} {'not taken':>9}   programs")
    for m in RV32I:
        progs = ",".join(n for n, (r, _) in per.items() if r[m])
        if m in BRANCHES:
            print(f"{m:8} {ran[m]:9} {taken[m]:8} {ran[m] - taken[m]:9}   {progs}")
        else:
            print(f"{m:8} {ran[m]:9} {'':8} {'':9}   {progs}")
    missing = [m for m in RV32I if not ran[m]]
    one_sided = [m for m in BRANCHES if ran[m] and (taken[m] == 0 or taken[m] == ran[m])]
    print(f"\nexecuted {len(RV32I) - len(missing)}/37; never executed: {' '.join(missing) or 'none'}")
    print(f"branches seen with only one outcome: {' '.join(one_sided) or 'none'}")


if __name__ == "__main__":
    main()
