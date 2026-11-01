import rv32i as r

VECTORS = [
    # from your own programs (tb/data/*.hex), which the CPU already runs
    ("addi x2,x0,5",    r.addi(2, 0, 5),     0x00500113),
    ("addi x3,x0,10",   r.addi(3, 0, 10),    0x00A00193),
    ("add x1,x2,x3",    r.add(1, 2, 3),      0x003100B3),
    ("sw x1,0(x0)",     r.sw(1, 0, 0),       0x00102023),
    ("sw x1,4(x0)",     r.sw(1, 4, 0),       0x00102223),
    ("jal x0,0",        r.jal(0, 0),         0x0000006F),
    ("addi x1,x0,0",    r.addi(1, 0, 0),     0x00000093),
    ("add x1,x1,x2",    r.add(1, 1, 2),      0x002080B3),
    ("addi x2,x2,-1",   r.addi(2, 2, -1),    0xFFF10113),
    ("bne x2,x0,-8",    r.bne(2, 0, -8),     0xFE011CE3),
    ("addi x1,x1,1",    r.addi(1, 1, 1),     0x00108093),
    # worked out by hand from the spec
    ("sub x1,x2,x3",    r.sub(1, 2, 3),      0x403100B3),
    ("srai x1,x2,3",    r.srai(1, 2, 3),     0x40315093),
    ("lw x5,8(x2)",     r.lw(5, 8, 2),       0x00812283),
    ("jalr x1,x2,0",    r.jalr(1, 2, 0),     0x000100E7),
    ("beq x1,x2,8",     r.beq(1, 2, 8),      0x00208463),
    ("lui x5,0x12345",  r.lui(5, 0x12345),   0x123452B7),
    ("auipc x1,0",      r.auipc(1, 0),       0x00000097),
]

for text, got, want in VECTORS:
    assert got == want, f"{text}: got {got:#010x}, expected {want:#010x}"

# out-of-range operands must be rejected, not silently truncated
for bad in (lambda: r.addi(1, 0, 2048), lambda: r.addi(32, 0, 0), lambda: r.beq(1, 2, 3),
            lambda: r.slli(1, 2, 32), lambda: r.jal(0, 1 << 20), lambda: r.sw(1, -2049, 0)):
    try:
        bad()
    except ValueError:
        pass
    else:
        raise AssertionError("out-of-range operand was accepted")

print(f"rv32i encoder: {len(VECTORS)} encodings and 6 range checks OK")
