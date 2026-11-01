import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parent.parent

# Files that make up the CPU, in compile order (paths relative to rtl/).
CPU_SOURCES = ["alu_pkg.vhd", "alu.vhd", "ctrl_pkg.vhd", "control.vhd", "immgen.vhd",
               "regfile.vhd", "branch_unit.vhd", "forward_unit.vhd", "cpu_core.vhd",
               "cpu_pipe.vhd", "imem.vhd", "dmem.vhd", "cpu_sc.vhd"]


def run_ghdl(toplevel, sources, test_module, parameters=None, build_name=None):
    """Build `sources` (paths relative to rtl/), run a cocotb test module,
    and exit non-zero if any cocotb test failed. `parameters` sets top-level generics."""
    build_dir = ROOT / "sim" / f"cocotb_{build_name or toplevel}"
    runner = get_runner("ghdl")
    runner.build(
        sources=[ROOT / "rtl" / s for s in sources],
        hdl_toplevel=toplevel,
        build_args=["--std=08"],
        build_dir=build_dir,
        parameters=parameters or {},
    )
    runner.test(
        hdl_toplevel=toplevel,
        test_module=test_module,
        test_args=["--std=08"],
        build_dir=build_dir,
        test_dir=build_dir,
    )
    results = build_dir / "results.xml"
    if not results.exists():
        sys.exit(f"cocotb produced no results file at {results}")
    failed = [
        tc.get("name")
        for tc in ET.parse(results).getroot().iter("testcase")
        if tc.find("failure") is not None or tc.find("error") is not None
    ]
    if failed:
        sys.exit(f"cocotb tests failed: {failed}")
