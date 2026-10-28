PYTHON ?= python
GHDL := ghdl
STD  := --std=08
WORK := sim/work
TBS  := $(patsubst tb/%.vhd,%,$(wildcard tb/*_tb.vhd))

.PHONY: all test clean cocotb $(TBS)
all: test
test: $(TBS) cocotb

$(WORK)/.imported: $(wildcard rtl/*.vhd) $(wildcard tb/*.vhd)
	mkdir -p $(WORK)
	$(GHDL) -i $(STD) --workdir=$(WORK) rtl/*.vhd tb/*.vhd
	touch $@

$(TBS): %: $(WORK)/.imported
	$(GHDL) -m $(STD) --workdir=$(WORK) $@
	$(GHDL) -r $(STD) --workdir=$(WORK) $@ --assert-level=error --wave=sim/$@.ghw

clean:
	rm -rf sim/work sim/cocotb_build sim/*.ghw work-obj08.cf

cocotb:
	@for t in tests/test_*.py; do echo "== $$t"; $(PYTHON) $$t || exit 1; done
