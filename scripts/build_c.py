#!/usr/bin/env python3
"""Compile C programs for the RV32I CPU and produce the images the testbenches load.
usage: python scripts/build_c.py sw/programs/sum.c [more.c ...]
Outputs in sim/c/: <name>.elf  <name>.dis  <name>.hex (instruction memory, one word per line)
                   <name>.data.hex (initial data image, may be empty)  <name>.json"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SW = ROOT / "sw"
OUT = ROOT / "sim" / "c"
PFX = "riscv64-unknown-elf-"

CFLAGS = ["-march=rv32i", "-mabi=ilp32", "-O1", "-ffreestanding", "-fno-pic", "-mno-relax",
          "-fno-tree-loop-distribute-patterns", "-Wall", "-Wextra"]
LDFLAGS = ["-nostdlib", "-nostartfiles", f"-T{SW / 'link.ld'}"]
FORBIDDEN = re.compile(r"ecall|ebreak|fence.*|csr.*|mul.*|div.*|rem.*|c\..*")


def run(cmd):
    p = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"command failed: {' '.join(map(str, cmd))}\n{p.stdout}{p.stderr}")
    if p.stderr.strip():
        print(p.stderr.strip())
    return p.stdout


def hex_words(data):
    data += b"\0" * (-len(data) % 4)
    return [f"{int.from_bytes(data[i:i + 4], 'little'):08X}" for i in range(0, len(data), 4)]


def mnemonics(dis):
    for line in dis.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and re.match(r"\s*[0-9a-f]+:", parts[0]) and parts[2].split():
            yield parts[2].split()[0]


def symbols(elf):
    table = {}
    for line in run([PFX + "nm", elf]).splitlines():
        f = line.split()
        if len(f) == 3:
            table[f[2]] = int(f[0], 16)
    return table


def host_value(src):
    """Compile the same C with the host compiler and return what main() returns."""
    obj, main_obj, exe = (OUT / f"{src.stem}.host.o", OUT / "host_main.o", OUT / f"{src.stem}.host")
    steps = [
        ["gcc", "-O1", "-Dmain=prog_main", "-c", str(src), "-o", str(obj)],
        ["gcc", "-O1", "-c", str(SW / "host_main.c"), "-o", str(main_obj)],
        ["gcc", str(obj), str(main_obj), "-o", str(exe)],
    ]
    for cmd in steps:
        cc = subprocess.run(cmd, capture_output=True, text=True)
        if cc.returncode != 0:
            print(f"  (no host reference: {cc.stderr.strip()})")
            return None
    return int(subprocess.run([str(exe)], capture_output=True, text=True).stdout.strip())


def build(src):
    name = src.stem
    OUT.mkdir(parents=True, exist_ok=True)
    elf = OUT / f"{name}.elf"
    run([PFX + "gcc", *CFLAGS, *LDFLAGS, SW / "crt0.S", src, "-lgcc", "-o", elf])

    dis = run([PFX + "objdump", "-d", elf])
    (OUT / f"{name}.dis").write_text(dis)
    bad = sorted({m for m in mnemonics(dis) if FORBIDDEN.fullmatch(m)})
    if bad:
        sys.exit(f"{name}: instructions outside RV32I base found: {bad} (see {name}.dis)")

    text_bin, data_bin = OUT / f"{name}.text.bin", OUT / f"{name}.data.bin"
    run([PFX + "objcopy", "-O", "binary", "-j", ".text", elf, text_bin])
    run([PFX + "objcopy", "-O", "binary", "-j", ".rodata", "-j", ".data", elf, data_bin])
    text, data = hex_words(text_bin.read_bytes()), hex_words(data_bin.read_bytes())
    (OUT / f"{name}.hex").write_text("\n".join(text) + "\n")
    (OUT / f"{name}.data.hex").write_text("".join(w + "\n" for w in data))

    sym = symbols(elf)
    info = {"name": name, "halt_pc": sym["_halt"], "data_base": sym["__dmem_base"],
            "stack_top": sym["__stack_top"], "text_words": len(text),
            "data_words": len(data), "expected": host_value(src)}
    (OUT / f"{name}.json").write_text(json.dumps(info, indent=2) + "\n")
    print(f"{name}: {len(text)} instruction words, {len(data)} data words, "
          f"halt at {info['halt_pc']:#x}, host result {info['expected']}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        build(Path(path))