#!/usr/bin/env python3
"""Compare tests/rv32i.py with the GNU assembler on random instructions.
usage: python scripts/check_encoder.py [rounds] [seed]"""
import random
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tests"))
import rv32i as r

AS = "riscv64-unknown-elf-as"
OBJCOPY = "riscv64-unknown-elf-objcopy"

R3 = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I3 = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH = ["slli", "srli", "srai"]
LD = ["lb", "lh", "lw", "lbu", "lhu"]
ST = ["sb", "sh", "sw"]
BR = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


def enc(name):
    """Encoder function for a mnemonic; reserved words may carry a trailing underscore."""
    return getattr(r, name, None) or getattr(r, name + "_")


def gen(rng, rounds):
    reg = lambda: rng.randrange(32)
    yield "nop", r.NOP
    yield "jal x0, .+0", r.HALT
    for _ in range(rounds):
        for m in R3:
            rd, a, b = reg(), reg(), reg()
            yield f"{m} x{rd}, x{a}, x{b}", enc(m)(rd, a, b)
        for m in I3:
            rd, a, i = reg(), reg(), rng.randrange(-2048, 2048)
            yield f"{m} x{rd}, x{a}, {i}", enc(m)(rd, a, i)
        for m in SH:
            rd, a, s = reg(), reg(), rng.randrange(32)
            yield f"{m} x{rd}, x{a}, {s}", enc(m)(rd, a, s)
        for m in LD:
            rd, a, i = reg(), reg(), rng.randrange(-2048, 2048)
            yield f"{m} x{rd}, {i}(x{a})", enc(m)(rd, i, a)
        for m in ST:
            b, a, i = reg(), reg(), rng.randrange(-2048, 2048)
            yield f"{m} x{b}, {i}(x{a})", enc(m)(b, i, a)
        for m in BR:
            a, b, off = reg(), reg(), rng.randrange(-2048, 2048) * 2
            yield f"{m} x{a}, x{b}, .{off:+d}", enc(m)(a, b, off)
        rd, off = reg(), rng.randrange(-(1 << 19), 1 << 19) * 2
        yield f"jal x{rd}, .{off:+d}", r.jal(rd, off)
        rd, a, i = reg(), reg(), rng.randrange(-2048, 2048)
        yield f"jalr x{rd}, {i}(x{a})", r.jalr(rd, a, i)
        rd, u = reg(), rng.randrange(1 << 20)
        yield f"lui x{rd}, {u}", r.lui(rd, u)
        yield f"auipc x{rd}, {u}", r.auipc(rd, u)


def edge():
    """Boundary operands: immediate extremes, shift amounts 0/31, upper-immediate
    extremes, register 0/31, branch and jump range limits."""
    for i in (-2048, -1, 0, 1, 2047):
        yield f"addi x5, x6, {i}", enc("addi")(5, 6, i)
        yield f"lw x5, {i}(x6)", enc("lw")(5, i, 6)
        yield f"sw x5, {i}(x6)", enc("sw")(5, i, 6)
        yield f"jalr x5, {i}(x6)", r.jalr(5, 6, i)
    for m in SH:
        for sh in (0, 31):
            yield f"{m} x5, x6, {sh}", enc(m)(5, 6, sh)
    for m in R3:
        yield f"{m} x0, x31, x31", enc(m)(0, 31, 31)
        yield f"{m} x31, x0, x0", enc(m)(31, 0, 0)
    for u in (0, 1, 0xFFFFF):
        yield f"lui x5, {u}", r.lui(5, u)
        yield f"auipc x5, {u}", r.auipc(5, u)
    for m in BR:
        for off in (-4096, -2, 0, 2, 4094):
            yield f"{m} x5, x6, .{off:+d}", enc(m)(5, 6, off)
    for off in (-(1 << 20), -2, 0, 2, (1 << 20) - 2):
        yield f"jal x1, .{off:+d}", r.jal(1, off)


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    items = list(gen(random.Random(seed), rounds)) + list(edge())

    with tempfile.TemporaryDirectory() as d:
        s, o, b = Path(d) / "t.s", Path(d) / "t.o", Path(d) / "t.bin"
        s.write_text(".option norvc\n.option norelax\n.text\n"
                     + "\n".join(text for text, _ in items) + "\n")
        subprocess.run([AS, "-march=rv32i", "-mabi=ilp32", str(s), "-o", str(o)], check=True)
        subprocess.run([OBJCOPY, "-O", "binary", "--only-section=.text", str(o), str(b)],
                       check=True)
        data = b.read_bytes()

    words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
    if len(words) != len(items):
        sys.exit(f"assembler produced {len(words)} words for {len(items)} instructions")

    bad = [(t, w, e) for (t, e), w in zip(items, words) if w != e]
    for t, w, e in bad[:15]:
        print(f"MISMATCH  {t:32}  assembler {w:#010x}  encoder {e:#010x}")
    print(f"{len(items)} instructions compared, {len(bad)} mismatches (seed {seed})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()