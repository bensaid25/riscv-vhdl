# riscv-vhdl

A 5-stage pipelined RISC-V (RV32I) CPU written in VHDL, verified with
self-checking testbenches. Simulation-only: no FPGA board required.

## Status
- [x] Parameterized counter
- [x] ALU (RV32I operations)
- [ ] Register file
- [ ] FSMs (sequence detector, UART TX)
- [ ] cocotb tests and CI
- [ ] Single-cycle CPU
- [ ] 5-stage pipeline (forwarding, hazards, branches)
- [ ] C programs vs reference model
- [ ] Synthesis and timing report

## Tools
GHDL, GTKWave, cocotb, Yosys/nextpnr, RISC-V GCC, GitHub Actions

## Structure
rtl/  synthesizable VHDL
tb/   testbenches
sim/  generated waveforms (git-ignored)
docs/ proposal and design notes

## Run the tests
    ghdl -a --std=08 rtl/alu_pkg.vhd rtl/alu.vhd tb/alu_tb.vhd
    ghdl -e --std=08 alu_tb
    ghdl -r --std=08 alu_tb --assert-level=error

(`make` support coming soon.)