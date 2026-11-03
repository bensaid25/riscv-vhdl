#!/usr/bin/env python3
"""Which of the 37 RV32I instructions appear in the compiled C programs (static count)."""
import re
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RV32I = ("lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw "
         "addi slti sltiu xori ori andi slli srli srai add sub sll slt sltu xor srl sra or and").split()


def mnemonics(elf):
    out = subprocess.run(["riscv64-unknown-elf-objdump", "-d", "-M", "no-aliases", str(elf)],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and re.match(r"\s*[0-9a-f]+:", parts[0]) and parts[2].split():
            yield parts[2].split()[0]


def main():
    per_prog = {}
    for elf in sorted((ROOT / "sim" / "c").glob("*.elf")):
        per_prog[elf.stem] = Counter(m for m in mnemonics(elf) if m in RV32I)
    total = Counter()
    for c in per_prog.values():
        total.update(c)
    print(f"{'instr':8} {'total':>6}   programs")
    for m in RV32I:
        progs = ",".join(p for p, c in per_prog.items() if c[m])
        print(f"{m:8} {total[m]:6}   {progs}")
    missing = [m for m in RV32I if not total[m]]
    print(f"\ncovered {len(RV32I) - len(missing)}/37; never appear: {' '.join(missing) or 'none'}")


if __name__ == "__main__":
    main()