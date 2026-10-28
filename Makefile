GHDL := ghdl
STD  := --std=08
WORK := sim/work
TBS  := $(patsubst tb/%.vhd,%,$(wildcard tb/*_tb.vhd))

.PHONY: all test clean $(TBS)
all: test
test: $(TBS)

$(WORK)/.imported: $(wildcard rtl/*.vhd) $(wildcard tb/*.vhd)
	mkdir -p $(WORK)
	$(GHDL) -i $(STD) --workdir=$(WORK) rtl/*.vhd tb/*.vhd
	touch $@

$(TBS): %: $(WORK)/.imported
	$(GHDL) -m $(STD) --workdir=$(WORK) $@
	$(GHDL) -r $(STD) --workdir=$(WORK) $@ --assert-level=error --wave=sim/$@.ghw

clean:
	rm -rf sim/work sim/*.ghw work-obj08.cf