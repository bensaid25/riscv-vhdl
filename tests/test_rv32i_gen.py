from collections import Counter

from rv32i_gen import ALL_KINDS, generate
from rv32i_model import HALT_WORD, ModelError, RV32IModel

seen = set()
taken, not_taken = Counter(), Counter()
odd_jalr = 0
longest = 0

for seed in range(300):
    words, kinds = generate(seed)
    assert (words, kinds) == generate(seed), f"seed {seed} is not deterministic"
    assert words[-1] == HALT_WORD
    seen.update(kinds)
    m = RV32IModel(words)
    try:
        while m.imem[m.pc // 4] != HALT_WORD:
            w, old_pc = m.imem[m.pc // 4], m.pc
            m.step()
            if w & 0x7F == 0x63:
                (taken if m.pc != old_pc + 4 else not_taken)[(w >> 12) & 7] += 1
            elif w & 0x7F == 0x67 and (w >> 20) & 1:
                odd_jalr += 1
            assert m.steps < 5000, f"seed {seed}: program does not terminate"
    except (ModelError, IndexError) as e:
        raise AssertionError(f"seed {seed}: {e!r}")
    longest = max(longest, m.steps)

missing = ALL_KINDS - seen
assert not missing, f"never generated: {sorted(missing)}"
for f3 in (0, 1, 4, 5, 6, 7):
    assert taken[f3] and not_taken[f3], f"branch funct3={f3}: taken={taken[f3]} not taken={not_taken[f3]}"
assert odd_jalr, "no jalr with bit 0 set was generated"

print(f"rv32i generator: 300 programs (longest {longest} steps), all {len(ALL_KINDS)} "
      f"instructions, every branch taken and not taken, {odd_jalr} odd-target jalr OK")
