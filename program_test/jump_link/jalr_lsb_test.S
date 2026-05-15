    .option norvc
    .text
    .globl _start

_start:
    addi x8, x0, 0x41
    nop
    nop
    nop
    nop
    nop
    nop
    jalr x0, 0(x8)
    nop
    nop
    nop

fail:
    addi x31, x0, 1
    jal  x0, finish
    nop
    nop
    nop

target:
    addi x31, x0, 0
    jal  x0, finish
    nop
    nop
    nop

finish:
    lui  x10, 0x1
    nop
    nop
    nop
    nop
    nop
    sw   x31, 0(x10)
done_loop:
    jal  x0, done_loop
    nop
    nop
    nop
