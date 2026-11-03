OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 8K
  DMEM (rw) : ORIGIN = 0x00002000, LENGTH = 8K
}

SECTIONS
{
  .text   : { *(.text.init) *(.text .text.*) } > IMEM

  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) . = ALIGN(4); } > DMEM
  .data   : { *(.data .data.* .sdata .sdata.*) . = ALIGN(4); } > DMEM
  .bss    : { __bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON) . = ALIGN(4); __bss_end = .; } > DMEM

  __dmem_base = ORIGIN(DMEM);
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) *(.note*) }
}