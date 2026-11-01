"""Reference model of RV32I (no CSRs, FENCE or ECALL), written from the spec.

Strict on purpose: misaligned or out-of-range accesses, unaligned branch targets,
fetches outside the program and unsupported instructions all raise ModelError.
"""
MASK = 0xFFFFFFFF
HALT_WORD = 0x0000006F          # jal x0,0


class ModelError(Exception):
    pass


def sext(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def _alu(name, a, b):
    sh = b & 31
    if name == "add":  return (a + b) & MASK
    if name == "sub":  return (a - b) & MASK
    if name == "sll":  return (a << sh) & MASK
    if name == "slt":  return int(sext(a, 32) < sext(b, 32))
    if name == "sltu": return int(a < b)
    if name == "xor":  return a ^ b
    if name == "srl":  return a >> sh
    if name == "sra":  return (sext(a, 32) >> sh) & MASK
    if name == "or":   return a | b
    if name == "and":  return a & b
    raise ModelError(f"unknown ALU op {name}")


R_OPS = {(0x00, 0): "add", (0x20, 0): "sub", (0x00, 1): "sll", (0x00, 2): "slt",
         (0x00, 3): "sltu", (0x00, 4): "xor", (0x00, 5): "srl", (0x20, 5): "sra",
         (0x00, 6): "or", (0x00, 7): "and"}
I_OPS = {0: "add", 2: "slt", 3: "sltu", 4: "xor", 6: "or", 7: "and"}
BRANCHES = {
    0: lambda a, b: a == b,
    1: lambda a, b: a != b,
    4: lambda a, b: sext(a, 32) < sext(b, 32),
    5: lambda a, b: sext(a, 32) >= sext(b, 32),
    6: lambda a, b: a < b,
    7: lambda a, b: a >= b,
}


class RV32IModel:
    def __init__(self, program, mem_bytes=4096):
        self.imem = list(program)            # word i lives at byte address 4*i
        self.mem = bytearray(mem_bytes)
        self.regs = [0] * 32
        self.pc = 0
        self.steps = 0
        self.stores = []                     # (address, rs2 value, size in bytes)

    # ---- helpers -------------------------------------------------------
    def _fetch(self):
        if self.pc % 4:
            raise ModelError(f"misaligned pc {self.pc:#x}")
        index = self.pc // 4
        if not 0 <= index < len(self.imem):
            raise ModelError(f"fetch outside the program at pc={self.pc:#x}")
        return self.imem[index]

    def _check(self, addr, size):
        if addr % size:
            raise ModelError(f"misaligned {size}-byte access at {addr:#010x}")
        if addr + size > len(self.mem):
            raise ModelError(f"access outside memory at {addr:#010x}")

    def _read(self, addr, size, signed):
        self._check(addr, size)
        v = int.from_bytes(self.mem[addr:addr + size], "little")
        return sext(v, 8 * size) & MASK if signed else v

    def _write(self, addr, size, value):
        self._check(addr, size)
        self.mem[addr:addr + size] = (value & ((1 << (8 * size)) - 1)).to_bytes(size, "little")

    def _set(self, rd, value):
        if rd != 0:
            self.regs[rd] = value & MASK

    def _target(self, target):
        target &= MASK
        if target % 4:
            raise ModelError(f"jump to unaligned target {target:#x}")
        return target

    def word(self, addr):
        return self._read(addr, 4, False)

    # ---- one instruction -----------------------------------------------
    def step(self):
        w = self._fetch()
        op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
        rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
        a, b = self.regs[rs1], self.regs[rs2]
        pc, next_pc = self.pc, (self.pc + 4) & MASK

        if op == 0x33:                                         # register-register
            if (f7, f3) not in R_OPS:
                raise ModelError(f"bad R-type {w:#010x}")
            self._set(rd, _alu(R_OPS[(f7, f3)], a, b))
        elif op == 0x13:                                       # register-immediate
            imm = sext(w >> 20, 12)
            if f3 == 1 and f7 == 0x00:
                self._set(rd, _alu("sll", a, rs2))
            elif f3 == 5 and f7 in (0x00, 0x20):
                self._set(rd, _alu("srl" if f7 == 0 else "sra", a, rs2))
            elif f3 in I_OPS:
                self._set(rd, _alu(I_OPS[f3], a, imm & MASK))
            else:
                raise ModelError(f"bad I-type {w:#010x}")
        elif op == 0x03:                                       # loads
            size = {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}.get(f3)
            if size is None:
                raise ModelError(f"bad load {w:#010x}")
            addr = (a + sext(w >> 20, 12)) & MASK
            self._set(rd, self._read(addr, size, f3 < 4))
        elif op == 0x23:                                       # stores
            size = {0: 1, 1: 2, 2: 4}.get(f3)
            if size is None:
                raise ModelError(f"bad store {w:#010x}")
            addr = (a + sext((f7 << 5) | ((w >> 7) & 31), 12)) & MASK
            self._write(addr, size, b)
            self.stores.append((addr, b, size))
        elif op == 0x63:                                       # branches
            if f3 not in BRANCHES:
                raise ModelError(f"bad branch {w:#010x}")
            imm = sext((((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11)
                       | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
            if BRANCHES[f3](a, b):
                next_pc = self._target(pc + imm)
        elif op == 0x6F:                                       # jal
            imm = sext((((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12)
                       | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)
            next_pc = self._target(pc + imm)
            self._set(rd, pc + 4)
        elif op == 0x67 and f3 == 0:                           # jalr
            next_pc = self._target((a + sext(w >> 20, 12)) & ~1)
            self._set(rd, pc + 4)
        elif op == 0x37:                                       # lui
            self._set(rd, w & 0xFFFFF000)
        elif op == 0x17:                                       # auipc
            self._set(rd, pc + (w & 0xFFFFF000))
        else:
            raise ModelError(f"unsupported instruction {w:#010x} at pc={pc:#x}")

        self.pc = next_pc
        self.steps += 1

    def run(self, max_steps=100_000):
        """Run until the program parks on `jal x0,0`; returns the halting pc."""
        while True:
            if self._fetch() == HALT_WORD:
                return self.pc
            if self.steps >= max_steps:
                raise ModelError(f"no halt after {max_steps} steps (non-terminating program?)")
            self.step()
