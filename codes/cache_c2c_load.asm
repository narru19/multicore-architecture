li r0, 0x10000
li r1, 1
li r3, 0

pid r7
beq r7, r1, wait

stw r1, 0(r0)
beq r7, r3, endmodify

wait:
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
nop
nop
nop
ldw r6, 0(r0)

endmodify:
nop
nop
beq r7, r3, endmodify
