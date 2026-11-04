import re, sys
log = open(sys.argv[1]).read()
f_sc, f_pl = float(sys.argv[2]), float(sys.argv[3])      # MHz
pat = re.compile(r"(\w+) \((single-cycle|pipeline)\): result \d+, (\d+) instructions, (\d+) cycles")
d = {}
for n, k, i, c in pat.findall(log):
    d.setdefault(n, {})[k] = (int(i), int(c))
print(f"{'prog':8s}{'instr':>7s}{'cyc_sc':>8s}{'cyc_pl':>8s}{'CPI_pl':>8s}{'t_sc us':>9s}{'t_pl us':>9s}{'speedup':>9s}")
for n in sorted(d):
    i, cs = d[n]["single-cycle"]; _, cp = d[n]["pipeline"]
    ts, tp = cs / f_sc, cp / f_pl
    print(f"{n:8s}{i:7d}{cs:8d}{cp:8d}{cp/i:8.3f}{ts:9.1f}{tp:9.1f}{ts/tp:9.3f}")
