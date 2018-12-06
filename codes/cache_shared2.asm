li r0, 0x10000
li r1, 0
li r2, 1
li r6, 0x20000
ldw r1, 0(r0)


pid r7
beq r7, r2, wait

ldw r1, 16(r0)
ldw r1, 32(r0)
ldw r1, 48(r0)
ldw r1, 64(r0)
ldw r1, 80(r0)
ldw r1, 96(r0)
ldw r1, 112(r0)
ldw r1, 128(r0)
ldw r1, 144(r0)
ldw r1, 160(r0)
ldw r1, 176(r0)
ldw r1, 192(r0)
ldw r1, 208(r0)
ldw r1, 224(r0)
ldw r1, 240(r0)
ldw r1, 256(r0)
ldw r1, 272(r0)
ldw r1, 288(r0)
ldw r1, 304(r0)
ldw r1, 320(r0)
ldw r1, 336(r0)
ldw r1, 352(r0)
ldw r1, 368(r0)
ldw r1, 384(r0)
ldw r1, 400(r0)
ldw r1, 416(r0)
ldw r1, 432(r0)


wait:
pid r7
nop
beq r7, r2, wait
