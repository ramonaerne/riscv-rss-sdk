# Test program for the minimal Spike MMIO plugin.
.text
.global _start
_start:

# Do a load and a store of address 0x10000000 to exercise the MMIO plugin.
li t0, 0x10000000

# Poll register 0x10000000 until not zero
1:
lw t1, 0(t0)
beq t1, zero, 1b
# t1 contains the number of 32bit words written
slli t1, t1, 2
add t1, t1, t0

# Read the number of bytes written into this polling register
2:
addi t0, t0, 4
lw t2, 0(t0)
# sw t1, 0(t0)
blt t0, t1, 2b

# Write the value 1 to tohost, telling Spike to quit with an exit code of 0.
li t0, 1
la t1, tohost
sw t0, 0(t1)

# Spin until Spike terminates the run.
1: j 1b

# Expose tohost and fromhost to Spike so we can communicate with it.
.data

.align 3
.global tohost
tohost:
.dword 0

.align 3
.global fromhost
fromhost:
.dword 0
