li r0, 0x10000
li r1, 0
li r5, 1


pid r7
beq r7, r5, wait

stw r1, 0(r0)
stw r0, 0(r0)
ldw r4, 0(r0)

ldw r2, 20(r0)
stw r1, 20(r0)

nop
nop
nop
nop


wait:
pid r7
nop
beq r7, r5, wait


