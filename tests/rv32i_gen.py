"""Constrained-random RV32I program generator.

Every program is self-contained and always terminates:
  * a prologue writes x1..x31 and a 64-byte data region, so no state from an
    earlier program can leak in (x31 holds the data base and is never written again);
  * the body uses only forward branches/jumps (skipping a few simple instructions)
    and small counted loops (at most 4 iterations, never nested);
  * loads and stores stay inside the data region and are always aligned;
  * the last instruction is the halt loop `jal x0,0`.
"""
import random

import rv32i as r

BASE_REG = 31
DATA_BASE = 0x400
DATA_WORDS = 16                      # 64-byte data region

R_OPS = {"add": r.add, "sub": r.sub, "sll": r.sll, "slt": r.slt, "sltu": r.sltu,
         "xor": r.xor, "srl": r.srl, "sra": r.sra, "or": r.or_, "and": r.and_}
I_OPS = {"addi": r.addi, "slti": r.slti, "sltiu": r.sltiu, "xori": r.xori,
         "ori": r.ori, "andi": r.andi}
SHIFTS = {"slli": r.slli, "srli": r.srli, "srai": r.srai}
LOADS = {"lb": (r.lb, 1), "lh": (r.lh, 2), "lw": (r.lw, 4), "lbu": (r.lbu, 1), "lhu": (r.lhu, 2)}
STORES = {"sb": (r.sb, 1), "sh": (r.sh, 2), "sw": (r.sw, 4)}
BRANCHES = {"beq": r.beq, "bne": r.bne, "blt": r.blt, "bge": r.bge,
            "bltu": r.bltu, "bgeu": r.bgeu}

ALL_KINDS = (set(R_OPS) | set(I_OPS) | set(SHIFTS) | {"lui", "auipc"} | set(LOADS)
             | set(STORES) | set(BRANCHES) | {"jal", "jalr"})

SPECIAL_VALUES = [0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x80000001,
                  0x0000FFFF, 0xFFFF0000, 0x55555555, 0xAAAAAAAA]
SPECIAL_IMMS = [0, 1, -1, 2047, -2048, 31]


class Gen:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.words = []
        self.kinds = []

    def emit(self, kind, word):
        self.words.append(word)
        self.kinds.append(kind)

    # ---- random operands ----------------------------------------------
    def src(self):
        return self.rng.randrange(32)

    def dst(self, avoid=()):
        """x1..x30 (never the base register x31); x0 now and then, unless avoided."""
        if 0 not in avoid and self.rng.random() < 0.05:
            return 0
        return self.rng.choice([x for x in range(1, 31) if x not in avoid])

    def imm12(self):
        if self.rng.random() < 0.3:
            return self.rng.choice(SPECIAL_IMMS)
        return self.rng.randint(-2048, 2047)

    def shamt(self):
        if self.rng.random() < 0.2:
            return self.rng.choice([0, 31])
        return self.rng.randrange(32)

    def value(self):
        if self.rng.random() < 0.4:
            return self.rng.choice(SPECIAL_VALUES)
        return self.rng.getrandbits(32)

    # ---- building blocks -----------------------------------------------
    def load_const(self, rd, v):
        lo = v & 0xFFF
        lo = lo - 0x1000 if lo & 0x800 else lo
        hi = ((v - lo) >> 12) & 0xFFFFF
        self.emit("lui", r.lui(rd, hi))
        self.emit("addi", r.addi(rd, rd, lo))

    def prologue(self):
        for rd in range(1, 31):
            self.load_const(rd, self.value())
        self.emit("addi", r.addi(BASE_REG, 0, DATA_BASE))
        for i in range(DATA_WORDS):
            self.emit("sw", r.sw(self.rng.randrange(1, 31), 4 * i, BASE_REG))

    def simple(self, avoid=()):
        """One non-control instruction; `avoid` lists registers it must not write."""
        rng = self.rng
        kind = rng.choice(["alu_r"] * 3 + ["alu_i"] * 3 + ["shift"] + ["upper"]
                          + ["load"] * 2 + ["store"] * 2)
        if kind == "alu_r":
            name = rng.choice(sorted(R_OPS))
            self.emit(name, R_OPS[name](self.dst(avoid), self.src(), self.src()))
        elif kind == "alu_i":
            name = rng.choice(sorted(I_OPS))
            self.emit(name, I_OPS[name](self.dst(avoid), self.src(), self.imm12()))
        elif kind == "shift":
            name = rng.choice(sorted(SHIFTS))
            self.emit(name, SHIFTS[name](self.dst(avoid), self.src(), self.shamt()))
        elif kind == "upper":
            if rng.random() < 0.5:
                self.emit("lui", r.lui(self.dst(avoid), rng.getrandbits(20)))
            else:
                self.emit("auipc", r.auipc(self.dst(avoid), rng.getrandbits(20)))
        elif kind == "load":
            name = rng.choice(sorted(LOADS))
            fn, size = LOADS[name]
            self.emit(name, fn(self.dst(avoid), rng.randrange(0, 64, size), BASE_REG))
        else:
            name = rng.choice(sorted(STORES))
            fn, size = STORES[name]
            self.emit(name, fn(self.src(), rng.randrange(0, 64, size), BASE_REG))

    def branch(self):
        rng = self.rng
        k = rng.randint(1, 3)
        name = rng.choice(sorted(BRANCHES))
        rs1 = self.src()
        rs2 = rs1 if rng.random() < 0.25 else self.src()   # equal operands now and then
        self.emit(name, BRANCHES[name](rs1, rs2, 4 * (k + 1)))
        for _ in range(k):
            self.simple()

    def jal(self):
        k = self.rng.randint(0, 3)
        self.emit("jal", r.jal(self.dst(), 4 * (k + 1)))
        for _ in range(k):
            self.simple()

    def jalr(self):
        k = self.rng.randint(0, 3)
        rt = self.dst(avoid=(0,))
        self.emit("auipc", r.auipc(rt, 0))                  # rt = address of this instruction
        imm = 8 + 4 * k + self.rng.choice([0, 0, 1])       # +1: bit 0 must be cleared
        self.emit("jalr", r.jalr(self.dst(), rt, imm))
        for _ in range(k):
            self.simple()

    def loop(self):
        n = self.rng.randint(1, 4)
        m = self.rng.randint(1, 4)
        rc = self.dst(avoid=(0,))
        self.emit("addi", r.addi(rc, 0, n))
        for _ in range(m):
            self.simple(avoid=(rc,))                        # the body never touches the counter
        self.emit("addi", r.addi(rc, rc, -1))
        self.emit("bne", r.bne(rc, 0, -4 * (m + 1)))

    def step(self):
        x = self.rng.random()
        if x < 0.65:
            self.simple()
        elif x < 0.77:
            self.branch()
        elif x < 0.84:
            self.jal()
        elif x < 0.91:
            self.jalr()
        else:
            self.loop()


def generate(seed, body_len=80):
    """Return (program words, list of instruction names), deterministic for a seed."""
    g = Gen(seed)
    g.prologue()
    start = len(g.words)
    while len(g.words) - start < body_len:
        g.step()
    g.emit("jal", r.HALT)
    return g.words, g.kinds
