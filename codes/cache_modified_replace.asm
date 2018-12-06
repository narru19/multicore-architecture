li r0, 0x10000
li r1, 1
li r2, 10

pid r7
beq r7, r1, wait

stw r2, 0(r0)
ldw r3, 16(r0)
ldw r4, 32(r0)
stw r2, 0(r0)
ldw r5, 48(r0)
ldw r6, 64(r0)
stw r2, 0(r0)
ldw r7, 80(r0)
ldw r8, 96(r0)
stw r2, 0(r0)
ldw r9, 112(r0)
ldw r9, 128(r0)
stw r2, 0(r0)
ldw r3, 144(r0)
ldw r4, 160(r0)
stw r2, 0(r0)
ldw r5, 176(r0)
ldw r6, 192(r0)
stw r2, 0(r0)
ldw r7, 208(r0)
ldw r8, 224(r0)
stw r2, 0(r0)
ldw r9, 240(r0)
ldw r9, 256(r0)
stw r2, 0(r0)
ldw r3, 272(r0)
ldw r4, 288(r0)
stw r2, 0(r0)
ldw r5, 304(r0)
ldw r6, 320(r0)
stw r2, 0(r0)
ldw r7, 336(r0)
ldw r8, 352(r0)
stw r2, 0(r0)
ldw r9, 368(r0)
ldw r9, 384(r0)

wait:
pid r7
nop
beq r7, r1, wait
