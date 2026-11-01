from collections import Counter

from rv32i_gen import DATA_WORDS, generate
from rv32i_model import HALT_WORD, RV32IModel

PROLOGUE = 2 * 30 + 1 + DATA_WORDS      # 30 lui/addi pairs, the base register, the data region


def paths(w):
    """Registers this instruction reads, tagged with the forwarding path they use."""
    op, rs1, rs2 = w & 0x7F, (w >> 15) & 31, (w >> 20) & 31
    out = set()
    if op == 0x33:
        out |= {("alu_a", rs1), ("alu_b", rs2)}
    elif op in (0x13, 0x03):
        out.add(("alu_a", rs1))
    elif op == 0x23:
        out.add(("store_data", rs2))     # the base register of a store is never written in the body
    elif op == 0x63:
        out |= {("branch", rs1), ("branch", rs2)}
    return {(p, r) for p, r in out if r != 0}


def writes(w):
    op, rd = w & 0x7F, (w >> 7) & 31
    return None if op in (0x23, 0x63) or rd == 0 else rd


def measure(hazard, seeds=range(300)):
    """Dynamic dependency counts in the program body, from running each program on the model."""
    c = Counter()
    for seed in seeds:
        words, kinds = generate(seed, hazard=hazard)
        assert kinds[PROLOGUE - DATA_WORDS - 1] == "addi"
        assert kinds[PROLOGUE - DATA_WORDS:PROLOGUE] == ["sw"] * DATA_WORDS
        m = RV32IModel(words)
        hist = [None, None]              # (rd, is_load) of the two previous executed instructions
        while m.imem[m.pc // 4] != HALT_WORD:
            w, pc = m.imem[m.pc // 4], m.pc
            if pc >= 4 * PROLOGUE:
                c["body_instr"] += 1
                for path, reg in paths(w):
                    for d in (1, 2):
                        h = hist[-d]
                        if h and h[0] == reg:
                            c[f"{path}_d{d}"] += 1
                            if d == 1 and h[1]:
                                c["load_use"] += 1
                                if path == "store_data":
                                    c["load_use_store"] += 1
                if w & 0x7F == 0x63:
                    c["branches"] += 1
            m.step()
            if w & 0x7F == 0x63 and m.pc != pc + 4 and pc >= 4 * PROLOGUE:
                c["taken"] += 1
            rd = writes(w)
            hist = [hist[-1], (rd, w & 0x7F == 0x03) if rd else None]
            assert m.steps < 5000, f"seed {seed}: program does not terminate"
    return c


KEYS = ["alu_a_d1", "alu_b_d1", "store_data_d1", "branch_d1",
        "alu_a_d2", "alu_b_d2", "store_data_d2", "branch_d2",
        "load_use", "load_use_store", "taken"]
FLOOR = {k: 100 for k in KEYS}
FLOOR["load_use"], FLOOR["load_use_store"], FLOOR["taken"] = 200, 30, 300

base, mix = measure(0.0), measure(0.6)
print(f"{'dependency (loop body only)':<30}{'baseline':>10}{'hazard 0.6':>12}")
for k in ["body_instr", "branches"] + KEYS:
    print(f"{k:<30}{base[k]:>10}{mix[k]:>12}")

for k in KEYS:
    assert mix[k] >= FLOOR[k], f"{k}: only {mix[k]} in hazard mode (floor {FLOOR[k]})"
for k in ("alu_a_d1", "alu_b_d1", "store_data_d1", "branch_d1", "load_use"):
    assert mix[k] > base[k], f"{k}: hazard mode ({mix[k]}) is not above the baseline ({base[k]})"

print("hazard mix OK: every forwarding path, load-use and taken branches are well covered")
