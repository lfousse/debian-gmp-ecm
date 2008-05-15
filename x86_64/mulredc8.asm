# mp_limb_t mulredc8(mp_limb_t * z, const mp_limb_t * x, const mp_limb_t * y,
#                 const mp_limb_t *m, mp_limb_t inv_m);
#
# z: %rdi, x: %rsi, y: %rdx, m: %rcx, inv_m: %r8



include(`config.m4')

	TEXT
.align 64 # Opteron L1 code cache line is 64 bytes long
	GLOBL GSYM_PREFIX`'mulredc8
	TYPE(GSYM_PREFIX`'mulredc`'8,`function')

/* Implements multiplication and REDC for two input numbers of 8 words */

# tmp[0 ... len+1] = 0
# for (i = 0; i < len; i++)
#   {
#     t = x[i] * y[0]; /* Keep and reuse this product */
#     u = ((t + tmp[0]) * invm) % 2^64
#     tmp[0] += (t + m[0]*u) / 2^64; /* put carry in cy. */
#     for (j = 1; j < len; j++)
#       {
#         tmp[j-1 ... j] += x[i]*y[j] + m[j]*u + (cy << BITS_PER_WORD);
#         /* put new carry in cy */
#       }
#     tmp[len] = cy;
#   }
# z[0 ... len-1] = tmp[0 ... len-1]
# return (tmp[len])


# Values that are referenced only once in the loop over j go into r8 .. r14,
# In the inner loop (over j), tmp, x[i], y, m, and u are constant.
# tmp[j], tmp[j+1], tmp[j+2] are updated frequently. These 8 values
# stay in registers and are referenced as
# TP = tmp, YP = y, MP = m, 
# XI = x[i], T0 = tmp[j], T1 = tmp[j+1], CY = carry


# Register vars: T0 = rsi, T1 = rbx, CY = rcx, XI = r14, U = r11
#                YP = r9, MP = r10, TP = rbp

# local variables: tmp[0 ... LENGTH] array, having LENGTH+1 8-byte words
# The tmp array needs LENGTH+1 entries, the last one is so that we can 
# store CY at tmp[j+1] for j == len-1



GSYM_PREFIX`'mulredc8:
	pushq	%rbx
	pushq	%rbp
	pushq	%r12
	pushq	%r13
	pushq	%r14
	subq	$72, %rsp	# subtract size of local vars
	movq	%rsi, %r13		# store x in XP
	movq	%rdx, %r9		# store y in YP
	movq	%rcx, %r10		# store m in MP


#########################################################################
# i = 0 pass
#########################################################################

# register values at loop entry: %TP = tmp, %I = i, %YP = y, %MP = m
# %CY < 255 (i.e. only low byte may be != 0)

# Pass for j = 0. We need to fetch x[i] from memory and compute the new u

	movq	(%r13), %r14		# XI = x[0]
	movq	(%r9), %rax		# rax = y[0]

	xorq	%rcx, %rcx		# set %CY to 0
	lea	(%rsp), %rbp		# store addr of tmp array in TP
	movq	%rcx, %r12			# Set %I to 0

	mulq	%r14			# rdx:rax = y[0] * x[i]
	addq	$1, %r12

	movq 	%rax, %rsi		# Move low word of product to T0
	movq	%rdx, %rbx		# Move high word of procuve to T1

	imulq	%r8, %rax		# %rax = ((x[i]*y[0]+tmp[0])*invm)%2^64
	movq	%rax, %r11		# this is the new u value

	mulq	(%r10)			# multipy u*m[0]
	addq	%rax, %rsi		# Now %T0 = 0, need not be stored
	movq	8(%r9), %rax		# Fetch y[1]
	adcq	%rdx, %rbx		# 
	setc	%cl
	# CY:T1:T0 <= 2*(2^64-1)^2 <= 2^2*128 - 4*2^64 + 2, hence
	# CY:T1 <= 2*2^64 - 4


# Now T0 = rbx, T1 = rsi


# Pass for j = 1
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi undefined 
# %rcx = carry into rsi (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rsi	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rbx	# Add low word to T0
	movq	8(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 0(%rbp)	# Store rbx in tmp[1-1]
	movq	16(%r9), %rax	# Fetch y[j+1] = y[2] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rsi, T1 = rbx


# Pass for j = 2
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx undefined 
# %rcx = carry into rbx (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rbx	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rsi	# Add low word to T0
	movq	16(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 8(%rbp)	# Store rsi in tmp[2-1]
	movq	24(%r9), %rax	# Fetch y[j+1] = y[3] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rbx, T1 = rsi


# Pass for j = 3
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi undefined 
# %rcx = carry into rsi (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rsi	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rbx	# Add low word to T0
	movq	24(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 16(%rbp)	# Store rbx in tmp[3-1]
	movq	32(%r9), %rax	# Fetch y[j+1] = y[4] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rsi, T1 = rbx


# Pass for j = 4
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx undefined 
# %rcx = carry into rbx (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rbx	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rsi	# Add low word to T0
	movq	32(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 24(%rbp)	# Store rsi in tmp[4-1]
	movq	40(%r9), %rax	# Fetch y[j+1] = y[5] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rbx, T1 = rsi


# Pass for j = 5
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi undefined 
# %rcx = carry into rsi (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rsi	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rbx	# Add low word to T0
	movq	40(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 32(%rbp)	# Store rbx in tmp[5-1]
	movq	48(%r9), %rax	# Fetch y[j+1] = y[6] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rsi, T1 = rbx


# Pass for j = 6
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx undefined 
# %rcx = carry into rbx (is <= 2)
# We have %CY:%T1 <= 2 * 2^64 - 2

	movq	%rcx, %rbx	# T1 = CY <= 1

	# Here, T1:T0 <= 2*2^64 - 2
	mulq	%r14		# y[j] * x[i]
	# rdx:rax <= (2^64-1)^2 <= 2^128 - 2*2^64 + 1
	addq	%rax, %rsi	# Add low word to T0
	movq	48(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	# T1:T0 <= 2^128 - 2*2^64 + 1 + 2*2^64 - 2 <= 2^128 - 1, no carry!
	
	mulq	%r11		# m[j]*u
	# rdx:rax <= 2^128 - 2*2^64 + 1, T1:T0 <= 2^128 - 1
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 40(%rbp)	# Store rsi in tmp[6-1]
	movq	56(%r9), %rax	# Fetch y[j+1] = y[7] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	setc	%cl		# %CY <= 1
	# CY:T1:T0 <= 2^128 - 1 + 2^128 - 2*2^64 + 1 <=
	#             2 * 2^128 - 2*2^64 ==> CY:T1 <= 2 * 2^64 - 2

# Now T0 = rbx, T1 = rsi


# Pass for j = 7. Don't fetch new data from y[j+1].

	movq	%rcx, %rsi	# T1 = CY <= 1
	
	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rbx	# Add low word to T0
	movq	56(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi 	# Add high word with carry to T1
	mulq    %r11		# m[j]*u
	addq	%rax, %rbx	# Add low word to T0
	movq	%rbx, 48(%rbp)	# Store T0 in tmp[j-1]
	adcq	%rdx, %rsi	# Add high word with carry to T1
	movq	%rsi, 56(%rbp)	# Store T1 in tmp[j]
	setc	%cl		# %CY <= 1
	movq	%rcx, 64(%rbp)	# Store CY in tmp[j+1]

#########################################################################
# i > 0 passes
#########################################################################

.align 32,,16
1:

# register values at loop entry: %TP = tmp, %I = i, %YP = y, %MP = m
# %CY < 255 (i.e. only low byte may be > 0)

# Pass for j = 0. We need to fetch x[i], tmp[i] and tmp[i+1] from memory
# and compute the new u

	movq	(%r13,%r12,8), %r14		# XI = x[i]
	movq	(%r9), %rax		# rax = y[0]
#init the register tmp ring buffer
        movq	(%rbp), %rbx		# Load tmp[0] into T0
	movq	8(%rbp), %rsi		# Load tmp[1] into T1

	mulq	%r14			# rdx:rax = y[0] * x[i]
	addq	$1, %r12

	addq	%rbx, %rax		# Add T0 to low word
	adcq	%rdx, %rsi		# Add high word with carry to T1
	setc	%cl			# %CY <= 1

	movq 	%rax, %rbx		# Save sum of low words in T0
	imulq	%r8, %rax		# %rax = ((x[i]*y[0]+tmp[0])*invm)%2^64
	movq	%rax, %r11		# this is the new u value

	mulq	(%r10)			# multipy u*m[0]
	addq	%rax, %rbx		# Now %T0 = 0, need not be stored
	adcq	%rdx, %rsi		# 

	movq	8(%r9), %rax		# Fetch y[1]


# Now T0 = rsi, T1 = rbx


# Pass for j = 1
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx value to store in 
# tmp[j+1], %rcx = carry into rbx, carry flag: also carry into rbx

	movq	%rcx, %rbx	# T1 = CY
	adcq	16(%rbp), %rbx	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rsi	# Add low word to T0
	movq	8(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 0(%rbp)	# Store rsi in tmp[1-1]
	adcq	%rdx, %rbx	# Add high word with carry to T1
	movq	16(%r9), %rax	# Fetch y[j+1] = y[2] into %rax

# Now T0 = rbx, T1 = rsi


# Pass for j = 2
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi value to store in 
# tmp[j+1], %rcx = carry into rsi, carry flag: also carry into rsi

	movq	%rcx, %rsi	# T1 = CY
	adcq	24(%rbp), %rsi	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rbx	# Add low word to T0
	movq	16(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 8(%rbp)	# Store rbx in tmp[2-1]
	adcq	%rdx, %rsi	# Add high word with carry to T1
	movq	24(%r9), %rax	# Fetch y[j+1] = y[3] into %rax

# Now T0 = rsi, T1 = rbx


# Pass for j = 3
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx value to store in 
# tmp[j+1], %rcx = carry into rbx, carry flag: also carry into rbx

	movq	%rcx, %rbx	# T1 = CY
	adcq	32(%rbp), %rbx	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rsi	# Add low word to T0
	movq	24(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 16(%rbp)	# Store rsi in tmp[3-1]
	adcq	%rdx, %rbx	# Add high word with carry to T1
	movq	32(%r9), %rax	# Fetch y[j+1] = y[4] into %rax

# Now T0 = rbx, T1 = rsi


# Pass for j = 4
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi value to store in 
# tmp[j+1], %rcx = carry into rsi, carry flag: also carry into rsi

	movq	%rcx, %rsi	# T1 = CY
	adcq	40(%rbp), %rsi	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rbx	# Add low word to T0
	movq	32(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 24(%rbp)	# Store rbx in tmp[4-1]
	adcq	%rdx, %rsi	# Add high word with carry to T1
	movq	40(%r9), %rax	# Fetch y[j+1] = y[5] into %rax

# Now T0 = rsi, T1 = rbx


# Pass for j = 5
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rsi = value to store in tmp[j], %rbx value to store in 
# tmp[j+1], %rcx = carry into rbx, carry flag: also carry into rbx

	movq	%rcx, %rbx	# T1 = CY
	adcq	48(%rbp), %rbx	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rsi	# Add low word to T0
	movq	40(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rsi, %rax	# Add T0 and low word
	movq	%rax, 32(%rbp)	# Store rsi in tmp[5-1]
	adcq	%rdx, %rbx	# Add high word with carry to T1
	movq	48(%r9), %rax	# Fetch y[j+1] = y[6] into %rax

# Now T0 = rbx, T1 = rsi


# Pass for j = 6
# Register values at entry: 
# %rax = y[j], %r14 = x[i], %r11 = u
# %rbp = tmp, %rbx = value to store in tmp[j], %rsi value to store in 
# tmp[j+1], %rcx = carry into rsi, carry flag: also carry into rsi

	movq	%rcx, %rsi	# T1 = CY
	adcq	56(%rbp), %rsi	# T1 += tmp[j+1]
	setc	%cl		# %CY <= 1

	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rbx	# Add low word to T0
	movq	48(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rsi	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	
	mulq	%r11		# m[j]*u
	addq	%rbx, %rax	# Add T0 and low word
	movq	%rax, 40(%rbp)	# Store rbx in tmp[6-1]
	adcq	%rdx, %rsi	# Add high word with carry to T1
	movq	56(%r9), %rax	# Fetch y[j+1] = y[7] into %rax

# Now T0 = rsi, T1 = rbx


# Pass for j = 7. Don't fetch new data from y[j+1].

	movq	%rcx, %rbx	# T1 = CY
	adcq	64(%rbp), %rbx	# T1 += tmp[j + 1]
	setc	%cl	    	# %CY <= 1
	
	mulq	%r14		# y[j] * x[i]
	addq	%rax, %rsi	# Add low word to T0
	movq	56(%r10), %rax	# Fetch m[j] into %rax
	adcq	%rdx, %rbx 	# Add high word with carry to T1
	adcb	$0, %cl	# %CY <= 2
	mulq    %r11		# m[j]*u
	addq	%rax, %rsi	# Add low word to T0
	movq	%rsi, 48(%rbp)	# Store T0 in tmp[j-1]
	adcq	%rdx, %rbx	# Add high word with carry to T1
	movq	%rbx, 56(%rbp)	# Store T1 in tmp[j]
	adcb	$0, %cl	# %CY <= 3
	movq	%rcx, 64(%rbp)	# Store CY in tmp[j+1]

	cmpq	$8, %r12
	jb	1b

# Copy result from tmp memory to z
	movq	(%rbp), %rax
	movq	8(%rbp), %rdx
	movq	%rax, (%rdi)
	movq	%rdx, 8(%rdi)
	movq	16(%rbp), %rax
	movq	24(%rbp), %rdx
	movq	%rax, 16(%rdi)
	movq	%rdx, 24(%rdi)
	movq	32(%rbp), %rax
	movq	40(%rbp), %rdx
	movq	%rax, 32(%rdi)
	movq	%rdx, 40(%rdi)
	movq	48(%rbp), %rax
	movq	56(%rbp), %rdx
	movq	%rax, 48(%rdi)
	movq	%rdx, 56(%rdi)

	movq	%rcx, %rax	# use carry as return value
	addq	$72, %rsp
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%rbp
	popq	%rbx
	ret
