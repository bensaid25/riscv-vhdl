from pathlib import Path

import rv32i as r
from rv32i_model import MASK, ModelError, RV32IModel

ROOT = Path(__file__).resolve().parent.parent


def hex_program(name):
    lines = (ROOT / "tb" / "data" / name).read_text().split()
    return [int(x, 16) for x in lines]


def run(program, **kw):
    m = RV32IModel(program + [r.HALT], **kw) if program[-1] != r.HALT else RV32IModel(program, **kw)
    m.run()
    return m


def expect_regs(m, expected):
    for n, v in expected.items():
        assert m.regs[n] == v & MASK, f"x{n} = {m.regs[n]:#010x}, expected {v & MASK:#010x}"


# 1-2. the two programs the CPU already runs: model and hardware must agree
m = RV32IModel(hex_program("prog_add.hex"))
assert m.run() == 0x10
expect_regs(m, {1: 15, 2: 5, 3: 10})
assert m.stores == [(0, 15, 4)] and m.word(0) == 15

m = RV32IModel(hex_program("prog_loop.hex"))
assert m.run() == 0x18
expect_regs(m, {1: 15, 2: 0})
assert m.stores == [(4, 15, 4)] and m.word(4) == 15

# 3. arithmetic and logic corners
prog = [
    r.addi(1, 0, -1),        # x1 = 0xFFFFFFFF
    r.addi(2, 0, 1),         # x2 = 1
    r.slt(3, 1, 2),          # -1 < 1 signed            -> 1
    r.sltu(4, 1, 2),         # 0xFFFFFFFF < 1 unsigned  -> 0
    r.srli(5, 1, 28),        # 0x0000000F
    r.srai(6, 1, 28),        # 0xFFFFFFFF (sign bits shifted in)
    r.lui(7, 0x80000),       # 0x80000000
    r.addi(8, 7, -1),        # 0x7FFFFFFF
    r.addi(9, 8, 1),         # 0x80000000 (wraps)
    r.add(10, 1, 2),         # 0xFFFFFFFF + 1 = 0
    r.sub(11, 0, 2),         # 0 - 1 = 0xFFFFFFFF
    r.addi(12, 0, 33),
    r.sll(13, 2, 12),        # only the low 5 bits of rs2 count: 1 << 1 = 2
    r.slti(14, 1, 0),        # -1 < 0 signed            -> 1
    r.sltiu(15, 1, -1),      # 0xFFFFFFFF < 0xFFFFFFFF  -> 0
    r.sltiu(16, 0, -1),      # 0 < 0xFFFFFFFF           -> 1
    r.addi(0, 0, 5),         # writes to x0 are discarded
    r.xori(17, 1, -1),       # ~0xFFFFFFFF = 0
    r.andi(18, 1, 0x7FF),    # 0x7FF
    r.ori(19, 0, -1),        # 0xFFFFFFFF
]
prog.append(r.auipc(20, 1))  # at its own address 4*len(prog) before this append
auipc_value = 4 * (len(prog) - 1) + 0x1000
m = run(prog)
expect_regs(m, {0: 0, 3: 1, 4: 0, 5: 0xF, 6: MASK, 7: 0x80000000, 8: 0x7FFFFFFF,
                9: 0x80000000, 10: 0, 11: MASK, 13: 2, 14: 1, 15: 0, 16: 1,
                17: 0, 18: 0x7FF, 19: MASK, 20: auipc_value})

# 4. memory: little-endian, partial stores, sign and zero extension on loads
m = run([
    r.addi(1, 0, -1),
    r.sw(1, 0, 0),           # mem[0..3] = FF FF FF FF
    r.sb(0, 0, 0),           # byte 0 = 00          -> 0xFFFFFF00
    r.lui(2, 0x12345),
    r.addi(2, 2, 0x678),     # x2 = 0x12345678
    r.sh(2, 2, 0),           # bytes 2..3 = 78 56   -> 0x5678FF00
    r.lb(3, 1, 0),           # byte 1 = 0xFF, sign-extended
    r.lbu(4, 1, 0),          # 0xFF
    r.lh(5, 0, 0),           # 0xFF00, sign-extended
    r.lhu(6, 0, 0),          # 0xFF00
    r.lw(7, 0, 0),           # 0x5678FF00
    r.lh(8, 2, 0),           # 0x5678
    r.lb(9, 3, 0),           # 0x56
])
expect_regs(m, {3: MASK, 4: 0xFF, 5: 0xFFFFFF00, 6: 0xFF00, 7: 0x5678FF00,
                8: 0x5678, 9: 0x56})
assert m.word(0) == 0x5678FF00
assert m.stores == [(0, MASK, 4), (0, 0, 1), (2, 0x12345678, 2)]

# 5. control flow: taken/not taken, jal, jalr (bit 0 cleared), backward loop
m = RV32IModel([
    r.addi(1, 0, 1),         # 0
    r.beq(0, 0, 8),          # 4   always taken -> 12
    r.addi(1, 0, 99),        # 8   skipped
    r.bne(0, 0, 8),          # 12  never taken
    r.addi(2, 0, 7),         # 16
    r.jal(3, 8),             # 20  x3 = 24, jump to 28
    r.addi(2, 0, 99),        # 24  skipped
    r.addi(4, 0, 40),        # 28
    r.jalr(5, 4, 1),         # 32  target (40+1)&~1 = 40, x5 = 36
    r.addi(2, 0, 98),        # 36  skipped
    r.addi(6, 0, 3),         # 40
    r.addi(7, 7, 1),         # 44  loop body
    r.addi(6, 6, -1),        # 48
    r.bne(6, 0, -8),         # 52  back to 44, three iterations
    r.addi(8, 0, -1),        # 56
    r.blt(8, 0, 8),          # 60  -1 < 0 signed: taken -> 68
    r.addi(9, 0, 99),        # 64  skipped
    r.bltu(8, 0, 8),         # 68  0xFFFFFFFF < 0 unsigned: not taken
    r.addi(10, 0, 5),        # 72
    r.bgeu(8, 0, 8),         # 76  taken -> 84
    r.addi(11, 0, 99),       # 80  skipped
    r.HALT,                  # 84
])
assert m.run() == 84
expect_regs(m, {1: 1, 2: 7, 3: 24, 4: 40, 5: 36, 6: 0, 7: 3, 8: MASK, 9: 0, 10: 5, 11: 0})

# 6. the model must refuse what the spec leaves undefined
def raises(program, **kw):
    try:
        RV32IModel(program, **kw).run(max_steps=1000)
    except ModelError:
        return True
    return False

assert raises([r.addi(1, 0, 2), r.lw(2, 0, 1), r.HALT]), "misaligned load accepted"
assert raises([r.addi(1, 0, -4), r.sw(0, 0, 1), r.HALT]), "out-of-range store accepted"
assert raises([r.addi(1, 0, 6), r.jalr(0, 1, 0), r.HALT]), "unaligned jump accepted"
assert raises([r.addi(1, 0, 1)]), "fetch outside the program accepted"
assert raises([r.beq(0, 0, 0), r.HALT]), "infinite loop not detected"
assert raises([0xFFFFFFFF, r.HALT]), "garbage instruction accepted"

print("rv32i model: 2 CPU programs, 3 directed programs and 6 error cases OK")
