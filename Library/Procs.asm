; -----------------------------------------------------------
; This file contains procedures for sound, screen clearing,
; and other utility functions.
; -----------------------------------------------------------

CODESEG
include "Library/Macros.asm"

; ---------------------------------------------------------------------------------------
; Filling the entire screen (graphic mode 320x200) with black (standard palette, index 0)
; ---------------------------------------------------------------------------------------
proc ClearScreen
	push ax cx di es
	mov ax, 0A000h
	mov es, ax

	xor di, di
	mov cx, 320*200/2
	xor ax, ax
	rep stosw

	pop es di cx ax

	ret
endp ClearScreen

; ----------------------------------------------------------------------
; Gets amount of ticks to wait (each tick is 1/18 of a second) from sack
; Creating a delay in the length it got
; ----------------------------------------------------------------------
proc Delay
	push bp
	mov bp, sp

	mov ax, 40h
	mov es, ax

	
	mov cx, [bp + 4]

	cmp cx, 0
	je @@procEnd

	mov ax, [es:6Ch]

@@delayLoop:
	cmp ax, [es:6Ch]
	je @@delayLoop

	mov ax, [es:6Ch]
	loop @@delayLoop

@@procEnd:
	pop bp
	ret 2
endp Delay


; ---------------------------------------------------------------------
; Get a number from stack
; Returns a 'Random' number in range 0 - (number - 1) to ax
; Using a randomized data file to eliminate timer-based random problems
; ---------------------------------------------------------------------
proc Random
	push bp
	mov bp, sp

	xor ax, ax

	cmp [word ptr bp + 4], 0
	je @@procEnd
	
; ---------------------------
; Stack State:
; | bp | bp + 2 |   bp + 4  |
; | bp |   sp   | maxNumber |
; ---------------------------
	
	push offset RandomFileName
	push offset RandomFileHandle
	call OpenFile

	;set file pointer:
	xor ah, ah
	int 1Ah

	xor cx, cx
	and dh, 00111111b

	mov ax, 4200h
	mov bx, [RandomFileHandle]
	int 21h
	jc @@planB ;in case of error

	mov bx, [RandomFileHandle]
	mov cx, 1
	mov dx, offset FileReadBuffer
	mov ah, 3Fh
	int 21h
	jc @@planBAndClose ;in case of error

	push [RandomFileHandle]
	call CloseFile

	mov al, [FileReadBuffer]
	xor ah, ah
	xor dx, dx
	mov bx, [bp + 4]
	div bx

	mov ax, dx

	jmp @@procEnd

@@planBAndClose:
	push [RandomFileHandle]
	call CloseFile

@@planB:
	;in case random operation fails
	;number was selected with a fair dice roll.
	mov ax, 6

	cmp [word ptr bp + 4], 6 ;make sure 6 is in range
	ja @@procEnd

	mov ax, 1

@@procEnd:
	pop bp
	ret 2
endp Random


; ---------------------------------------
; Check if the PSP is holding an argument
; and the argument is ' -dbg'
; If true, ax=1, else ax=0
; ---------------------------------------
proc CheckDebug
	mov ah, 2
	xor bh, bh
	xor dx, dx
	int 10h

	mov ah, 51h
	int 21h

	mov es, bx

	cmp [byte ptr es:80h], 5
	jne @@returnFalse

	cmp [word ptr es:81h], '- '
	jne @@returnFalse
	cmp [word ptr es:83h], 'bd'
	jne @@returnFalse
	cmp [byte ptr es:85h], 'g'
	jne @@returnFalse

	mov ax, 1
	ret


@@returnFalse:
	xor ax, ax
	ret
endp CheckDebug


; ---------------------------------------------------------
; Get a number from stack, return 4 decimal digits to dx:ax
; thousands in dh, hundreds in dl, tens in ah, units in al
; ---------------------------------------------------------
proc HexToDecimal
	push bp
	mov bp, sp

	mov ax, [bp + 4]

	mov cx, 4
@@findDigit:
	mov bl, 10
	div bl
	mov dx, ax
	shr dx, 8
	push dx
	xor ah, ah
	loop @@findDigit

	pop cx
	mov dh, cl
	pop cx
	mov dl, cl
	pop cx
	mov ah, cl
	pop cx
	mov al, cl

	;Convert to ASCII chars
	add dx, 3030h
	add ax, 3030h

	pop bp
	ret 2
endp HexToDecimal

; ------------------------------------------------------------------------------------------------------------
; Sort the text file containing player scores in descending order.
; Higher scores should be ranked higher.
; If two scores are equal, the player who was originally ranked higher should retain the higher position, 
; while the other player moves to the next lower position.
; The file contains a maximum of 5 players.
; ------------------------------------------------------------------------------------------------------------
proc SortScoresFile
	push offset ScoresFileName
	push offset ScoresFileHandle
	call OpenFile

	;Set file pointer to start:
	mov ah, 42h
	xor al, al
	mov bx, [ScoresFileHandle]
	xor cx, cx
	xor dx, dx
	int 21h

	;read amount of scores in file:
	mov ah, 3Fh
	mov bx, [ScoresFileHandle]
	mov cx, 1
	mov dx, offset FileReadBuffer
	int 21h

	cmp [byte ptr FileReadBuffer], 1
	jbe @@checkNoSortDebug ;if 0 or 1 score in table, no need to sort..


	xor ch, ch
	mov cl, [FileReadBuffer]
	dec cx ;for x scores, need max amount of x-1 replaces


@@compareScores:
	push cx

	;set to beginning of higher rank:
	mov al, cl
	dec al
	mov bl, 10    ; Each record is now 10 bytes (8 name + 2 score)
	mul bl

	mov dx, ax
	inc dx        ; ignore first byte (amount of scores in file)
	mov ah, 42h
	xor al, al
	mov bx, [ScoresFileHandle]
	xor cx, cx
	int 21h

	;read two ranks info:
	mov ah, 3Fh
	mov bx, [ScoresFileHandle]
	mov cx, 20    ; Read 2 records × 10 bytes each = 20 bytes
	mov dx, offset FileReadBuffer + 1
	int 21h

	;check if scores need to be replaced:
	mov ax, [word ptr FileReadBuffer + 8]  ; higher rank score (2 bytes)
	cmp ax, [word ptr FileReadBuffer + 18] ; compare with lower rank score (2 bytes)
	jae @@stopComparing

	;replace both values:
	pop cx
	push cx

	;set to beginning of lower rank:
	mov al, cl
	mov bl, 10    ; Use 10 instead of 9 for record size
	mul bl

	mov dx, ax
	inc dx ;ignore first byte (amount of scores in file)
	mov ah, 42h
	xor al, al
	mov bx, [ScoresFileHandle]
	xor cx, cx
	int 21h

	;move previously higher rank to lower rank:
	mov ah, 40h
	mov bx, [ScoresFileHandle]
	mov cx, 10    ; Copy 10 bytes instead of 9
	mov dx, offset FileReadBuffer + 1 ;start of saved higher rank
	int 21h

	pop cx
	push cx

	;set to beginning of higher rank:
	mov al, cl
	dec al
	mov bl, 10    ; Use 10 instead of 9 for record size
	mul bl

	mov dx, ax
	inc dx ;ignore first byte (amount of scores in file)
	mov ah, 42h
	xor al, al
	mov bx, [ScoresFileHandle]
	xor cx, cx
	int 21h

	;move previously lower rank to higher rank:
	mov ah, 40h
	mov bx, [ScoresFileHandle]
	mov cx, 10    ; Copy 10 bytes instead of 9
	mov dx, offset FileReadBuffer + 11 ;start of saved lower rank
	int 21h

	pop cx

	cmp [byte ptr DebugBool], 1
	jne @@skipReplacedDebugPrint

	push cx

	mov ah, 2
	xor bh, bh
	xor dx, dx
	int 10h

	mov ah, 9
	mov dx, offset ReplacedRanksString
	int 21h

	mov ah, 2
	mov dl, cl
	add dl, 30h
	int 21h

	mov ah, 9
	mov dx, offset AndWordString
	int 21h

	mov ah, 2
	mov dl, cl
	add dl, 31h
	int 21h

	push 36
	call Delay

	pop cx

@@skipReplacedDebugPrint:
	loop_Far @@compareScores

	jmp @@procEnd


@@stopComparing:
	pop cx ;clear stack from pushed value
	jmp @@procEnd

@@checkNoSortDebug:
	cmp [DebugBool], 1
	jne @@procEnd

	mov ah, 2
	xor bh, bh
	xor dx, dx
	int 10h

	mov ah, 9
	mov dx, offset NoNeedToSortString
	int 21h

	push 36
	call Delay

@@procEnd:
	push [ScoresFileHandle]
	call CloseFile
	ret
endp SortScoresFile

