ENTRY(_start)

MEMORY {
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 1M
}

SECTIONS {
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*)
  } > ram

  .data : {
    *(.data*)
  } > ram

  .bss : {
    *(.bss*)
    *(COMMON)
  } > ram

  . = ALIGN(16);
  _stack_top = ORIGIN(ram) + LENGTH(ram) - 16;
}
