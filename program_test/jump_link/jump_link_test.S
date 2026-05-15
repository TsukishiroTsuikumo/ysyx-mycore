    .option norvc
    .text
    .globl _start

_start:
    jal  x5, jal_func
    nop
    nop
    nop
    nop
    nop
    nop

after_jal:
    addi x7, x0, 25
    nop
    nop
    nop
    bne  x11, x7, fail_jal
    nop
    nop
    nop

    addi x8, x0, 0xd4
    nop
    nop
    nop
    nop
    nop
    nop
    jalr x9, 0(x8)
    nop
    nop
    nop
    nop
    nop
    nop

after_jalr:
    addi x7, x0, 77
    nop
    nop
    nop
    bne  x12, x7, fail_jalr
    nop
    nop
    nop

pass:
    addi x31, x0, 0
    jal  x0, finish
    nop
    nop
    nop

jal_func:
    addi x11, x0, 25
    nop
    nop
    nop
    nop
    nop
    nop
    jalr x0, 0(x5)
    nop
    nop
    nop

jalr_target:
    addi x12, x0, 77
    nop
    nop
    nop
    nop
    nop
    nop
    jalr x0, 0(x9)
    nop
    nop
    nop

fail_jal:
    addi x31, x0, 1
    jal  x0, finish
    nop
    nop
    nop
fail_jalr:
    addi x31, x0, 2
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
