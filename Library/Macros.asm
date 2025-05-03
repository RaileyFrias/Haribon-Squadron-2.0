; -----------------------------------------------------------
; This file contains macro to bypass the limited range of 
; the loop instruction of the 8086 processor.
; -----------------------------------------------------------

macro loop_Far label
	local SKIP
	dec cx
	jz SKIP
	jmp label

SKIP:
endm