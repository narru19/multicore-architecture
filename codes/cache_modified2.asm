li r0, 0x10000
li r1, 0
li r5, 1

ldw r2, 0(r0)
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

pid r7
beq r7, r5, wait

stw r1, 0(r0)
nop
nop
nop
nop


wait:
pid r7
nop
beq r7, r5, wait


