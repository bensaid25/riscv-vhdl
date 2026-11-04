#!/usr/bin/env bash
# usage: scripts/synth_sweep.sh [target_MHz] [num_seeds]   (ECP5 LFE5U-85F, CABGA381)
set -u
FREQ=${1:-100}; NS=${2:-5}; D=sim/synth
for P in false true; do
  scripts/synth.sh $P 1 $FREQ > $D/sweep_$P.out 2>&1 || { echo "synth failed for PIPELINED=$P"; tail -5 $D/sweep_$P.out; exit 1; }
  for s in $(seq 1 $NS); do
    nextpnr-ecp5 --85k --package CABGA381 --json $D/pipe_$P.json --freq $FREQ --seed $s \
      --lpf-allow-unconstrained --timing-allow-fail > $D/pipe_$P.s$s.log 2>&1
    f=$(grep "Max frequency" $D/pipe_$P.s$s.log | tail -1 | grep -oE '[0-9.]+ MHz' | head -1)
    echo "PIPELINED=$P seed=$s fmax=$f"
  done
  grep -E "TRELLIS_COMB:|TRELLIS_FF:|DP16KD:|TRELLIS_RAMW:" $D/pipe_$P.s1.log | tail -4
done
