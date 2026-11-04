#!/usr/bin/env bash
# usage: scripts/synth.sh <true|false> [seed]   (ECP5 LFE5U-85F, CABGA381, 50 MHz target)
set -u
P=${1:?usage: synth.sh true|false [seed]}; SEED=${2:-1}
SRC="rtl/alu_pkg.vhd rtl/alu.vhd rtl/ctrl_pkg.vhd rtl/control.vhd rtl/immgen.vhd rtl/regfile.vhd \
 rtl/branch_unit.vhd rtl/forward_unit.vhd rtl/cpu_core.vhd rtl/cpu_pipe.vhd \
 rtl/imem.vhd rtl/dmem.vhd rtl/cpu_sc.vhd synth/synth_top.vhd"
D=sim/synth; N=pipe_$P; mkdir -p $D
ghdl --synth --std=08 --out=verilog -gPIPELINED=$P -gIMEM_FILE=sim/c/sort.hex $SRC -e synth_top \
  > $D/$N.v 2> $D/$N.ghdl.err || { echo "GHDL FAILED"; tail -20 $D/$N.ghdl.err; exit 1; }
grep "found RAM" $D/$N.ghdl.err
yosys -p "read_verilog $D/$N.v; synth_ecp5 -top synth_top -json $D/$N.json; stat" > $D/$N.yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 $D/$N.yosys.log; exit 1; }
grep -E "LUT4|TRELLIS_FF|TRELLIS_DPR16X4|DP16KD|CCU2C|MULT18X18D|Number of cells" $D/$N.yosys.log | tail -12
nextpnr-ecp5 --85k --package CABGA381 --json $D/$N.json --freq 50 --seed $SEED \
  --lpf-allow-unconstrained --timing-allow-fail > $D/$N.pnr.log 2>&1
echo "nextpnr exit: $?"
grep -E "Max frequency|ERROR" $D/$N.pnr.log | tail -3
