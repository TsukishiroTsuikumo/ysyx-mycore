    .option norvc
    .text
    .globl _start

_start:
    addi x2, x0, 0
    nop
    nop
    nop
    nop
    nop

    lw   x3, 0(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    lui  x7, 0x11223
    nop
    nop
    nop
    nop
    nop
    nop
    addi x7, x7, 0x344
    nop
    nop
    nop
    bne  x3, x7, fail_lw
    nop
    nop
    nop

    lb   x4, 4(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    addi x7, x0, -128
    nop
    nop
    nop
    bne  x4, x7, fail_lb
    nop
    nop
    nop

    lbu  x5, 4(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    addi x7, x0, 128
    nop
    nop
    nop
    bne  x5, x7, fail_lbu
    nop
    nop
    nop

    lh   x6, 6(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    lui  x7, 0xffff8
    nop
    nop
    nop
    nop
    nop
    nop
    addi x7, x7, 1
    nop
    nop
    nop
    bne  x6, x7, fail_lh
    nop
    nop
    nop

    lhu  x8, 6(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    lui  x7, 0x8
    nop
    nop
    nop
    nop
    nop
    nop
    addi x7, x7, 1
    nop
    nop
    nop
    bne  x8, x7, fail_lhu
    nop
    nop
    nop

    sb   x5, 12(x2)
    nop
    nop
    nop
    lbu  x9, 12(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    bne  x9, x5, fail_sb
    nop
    nop
    nop

    sh   x8, 14(x2)
    nop
    nop
    nop
    lhu  x9, 14(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    bne  x9, x8, fail_sh
    nop
    nop
    nop

    sw   x3, 20(x2)
    nop
    nop
    nop
    lw   x9, 20(x2)
    nop
    nop
    nop
    nop
    nop
    nop
    bne  x9, x3, fail_sw
    nop
    nop
    nop

pass:
    addi x31, x0, 0
    jal  x0, finish
    nop
    nop
    nop

fail_lw:
    addi x31, x0, 1
    jal  x0, finish
    nop
    nop
    nop
fail_lb:
    addi x31, x0, 2
    jal  x0, finish
    nop
    nop
    nop
fail_lbu:
    addi x31, x0, 3
    jal  x0, finish
    nop
    nop
    nop
fail_lh:
    addi x31, x0, 4
    jal  x0, finish
    nop
    nop
    nop
fail_lhu:
    addi x31, x0, 5
    jal  x0, finish
    nop
    nop
    nop
fail_sb:
    addi x31, x0, 6
    jal  x0, finish
    nop
    nop
    nop
fail_sh:
    addi x31, x0, 7
    jal  x0, finish
    nop
    nop
    nop
fail_sw:
    addi x31, x0, 8
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
