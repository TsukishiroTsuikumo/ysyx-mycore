    .option norvc
    .text
    .globl _start

_start:
    addi x1, x0, 5
    addi x2, x0, 5
    addi x3, x0, 7
    addi x4, x0, -1
    addi x5, x0, 1
    nop
    nop
    nop
    nop
    nop
    nop

    beq  x1, x2, beq_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 1
    jal  x0, finish
    nop
    nop
    nop
beq_taken_ok:
    beq  x1, x3, fail_beq_not_taken
    nop
    nop
    nop

    bne  x1, x3, bne_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 3
    jal  x0, finish
    nop
    nop
    nop
bne_taken_ok:
    bne  x1, x2, fail_bne_not_taken
    nop
    nop
    nop

    blt  x4, x0, blt_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 5
    jal  x0, finish
    nop
    nop
    nop
blt_taken_ok:
    blt  x0, x4, fail_blt_not_taken
    nop
    nop
    nop

    bge  x0, x4, bge_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 7
    jal  x0, finish
    nop
    nop
    nop
bge_taken_ok:
    bge  x4, x0, fail_bge_not_taken
    nop
    nop
    nop

    bltu x5, x4, bltu_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 9
    jal  x0, finish
    nop
    nop
    nop
bltu_taken_ok:
    bltu x4, x5, fail_bltu_not_taken
    nop
    nop
    nop

    bgeu x4, x5, bgeu_taken_ok
    nop
    nop
    nop
    nop
    nop
    nop
    addi x31, x0, 11
    jal  x0, finish
    nop
    nop
    nop
bgeu_taken_ok:
    bgeu x5, x4, fail_bgeu_not_taken
    nop
    nop
    nop

pass:
    addi x31, x0, 0
    jal  x0, finish
    nop
    nop
    nop

fail_beq_not_taken:
    addi x31, x0, 2
    jal  x0, finish
    nop
    nop
    nop
fail_bne_not_taken:
    addi x31, x0, 4
    jal  x0, finish
    nop
    nop
    nop
fail_blt_not_taken:
    addi x31, x0, 6
    jal  x0, finish
    nop
    nop
    nop
fail_bge_not_taken:
    addi x31, x0, 8
    jal  x0, finish
    nop
    nop
    nop
fail_bltu_not_taken:
    addi x31, x0, 10
    jal  x0, finish
    nop
    nop
    nop
fail_bgeu_not_taken:
    addi x31, x0, 12
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
