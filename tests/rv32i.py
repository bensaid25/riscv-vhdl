"""RV32I instruction encoder: every function returns a 32-bit unsigned int.

Argument order follows assembly:
  R: add(rd, rs1, rs2)        I: addi(rd, rs1, imm)      shifts: slli(rd, rs1, shamt)
  loads: lw(rd, imm, rs1)     stores: sw(rs2, imm, rs1)
  branches: beq(rs1, rs2, byte_offset)     jal(rd, byte_offset)    jalr(rd, rs1, imm)
  U: lui(rd, imm20), auipc(rd, imm20)
"""


def _reg(r):
    if not 0 <= r <= 31:
        raise ValueError(f"bad register x{r}")
    return r


def _chk(v, lo, hi, what, even=False):
    if not lo <= v <= hi:
        raise ValueError(f"{what} {v} out of range [{lo}, {hi}]")
    if even and v % 2:
        raise ValueError(f"{what} {v} must be even")
    return v


def _r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (_reg(rs2) << 20) | (_reg(rs1) << 15) | (f3 << 12) | (_reg(rd) << 7) | op


def _i(imm, rs1, f3, rd, op):
    _chk(imm, -2048, 2047, "I-immediate")
    return ((imm & 0xFFF) << 20) | (_reg(rs1) << 15) | (f3 << 12) | (_reg(rd) << 7) | op


def _s(imm, rs2, rs1, f3):
    _chk(imm, -2048, 2047, "S-immediate")
    imm &= 0xFFF
    return (((imm >> 5) << 25) | (_reg(rs2) << 20) | (_reg(rs1) << 15)
            | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23)


def _b(off, rs2, rs1, f3):
    _chk(off, -4096, 4094, "branch offset", even=True)
    o = off & 0x1FFF
    return ((((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (_reg(rs2) << 20)
            | (_reg(rs1) << 15) | (f3 << 12) | (((o >> 1) & 0xF) << 8)
            | (((o >> 11) & 1) << 7) | 0x63)


def _u(imm20, rd, op):
    _chk(imm20, 0, 0xFFFFF, "U-immediate")
    return (imm20 << 12) | (_reg(rd) << 7) | op


def _j(off, rd):
    _chk(off, -(1 << 20), (1 << 20) - 2, "jump offset", even=True)
    o = off & 0x1FFFFF
    return ((((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20)
            | (((o >> 12) & 0xFF) << 12) | (_reg(rd) << 7) | 0x6F)


def _rop(f7, f3):
    return lambda rd, rs1, rs2: _r(f7, rs2, rs1, f3, rd, 0x33)


def _iop(f3):
    return lambda rd, rs1, imm: _i(imm, rs1, f3, rd, 0x13)


def _shift(f7, f3):
    return lambda rd, rs1, shamt: _r(f7, _chk(shamt, 0, 31, "shamt"), rs1, f3, rd, 0x13)


def _load(f3):
    return lambda rd, imm, rs1: _i(imm, rs1, f3, rd, 0x03)


def _store(f3):
    return lambda rs2, imm, rs1: _s(imm, rs2, rs1, f3)


def _branch(f3):
    return lambda rs1, rs2, off: _b(off, rs2, rs1, f3)


# register-register
add, sub = _rop(0x00, 0), _rop(0x20, 0)
sll, slt, sltu, xor = _rop(0x00, 1), _rop(0x00, 2), _rop(0x00, 3), _rop(0x00, 4)
srl, sra = _rop(0x00, 5), _rop(0x20, 5)
or_, and_ = _rop(0x00, 6), _rop(0x00, 7)

# register-immediate
addi, slti, sltiu = _iop(0), _iop(2), _iop(3)
xori, ori, andi = _iop(4), _iop(6), _iop(7)
slli, srli, srai = _shift(0x00, 1), _shift(0x00, 5), _shift(0x20, 5)

# memory
lb, lh, lw, lbu, lhu = _load(0), _load(1), _load(2), _load(4), _load(5)
sb, sh, sw = _store(0), _store(1), _store(2)

# control flow
beq, bne, blt = _branch(0), _branch(1), _branch(4)
bge, bltu, bgeu = _branch(5), _branch(6), _branch(7)


def jal(rd, off):
    return _j(off, rd)


def jalr(rd, rs1, imm):
    return _i(imm, rs1, 0, rd, 0x67)


def lui(rd, imm20):
    return _u(imm20, rd, 0x37)


def auipc(rd, imm20):
    return _u(imm20, rd, 0x17)


NOP = addi(0, 0, 0)       # 0x00000013
HALT = jal(0, 0)          # jump to itself: parks the CPU, 0x0000006F
