;
; Christian Groessler, May-2000
;
; fd indirection table & helper functions
;

	.include "atari.inc"
	.importzp tmp1,tmp2,tmp3,ptr4,sp
	.import	subysp,addysp
	.export	fdtoiocb
	.export	fdtoiocb_down
	.export	fd_table
	.export	fddecusage
	.export	newfd
	.export	getfd

	.export	_fd_table,_fd_index

	.data
MAX_FD_INDEX	=	12
_fd_index:
fd_index:	; fd number is index into this table, entry's value specifies the fd_table entry
	.res	MAX_FD_INDEX,$ff

_fd_table:
fd_table:	; each entry represents an open iocb
	.byte	0,0,'E',0	; system console, app starts with opened iocb #0 for E:
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0
	.byte	0,$ff,0,0

MAX_FD_VAL	=	(* - fd_table) / 4

ft_entrylen = 4	; length of table entry (it's not sufficient to change here!
		; the code sometimes does two bit shifts to multiply/divide by
		; this length)

ft_usa  = 0	; usage counter
ft_iocb	= 1	; iocb index (0,$10,$20,etc.), $ff for empty entry
ft_dev  = 2	; device of open iocb (0 - device not remembered, eg. filename specified)
ft_flag = 3	; flags
		; lower 3 bits: device number (for R: and D:)

	.code

; gets fd in ax, decrements usage counter
; return iocb index in X
; return N bit set for invalid fd
; return Z bit set if last user
; all registers destroyed
.proc	fdtoiocb_down

	cpx	#0
	bne	inval
	cmp	#MAX_FD_INDEX
	bcs	inval
	tax
	lda	fd_index,x		; get index
	tay
	lda	#$ff
	sta	fd_index,x		; clear entry
	tya
	asl	a			; create index into fd table
	asl	a
	tax
	lda	#$ff
	cmp	fd_table+ft_iocb,x	; entry in use?
	beq	inval			; no, return error
	lda	fd_table+ft_usa,x	; get usage counter
	beq	ok_notlast		; 0?
	sec
	sbc	#1			; decr usage counter
	sta	fd_table+ft_usa,x
retiocb:php
	txa
	tay
	lda	fd_table+ft_iocb,x	; get iocb
	tax
	plp
	bne	cont
	php
	lda	#$ff
	sta	fd_table+ft_iocb,y	; clear table entry
	plp
cont:	rts

ok_notlast:
	lda	#1			; clears Z
	jmp	retiocb

.endproc

inval:	ldx	#$ff			; sets N
	rts


; gets fd in ax
; return iocb index in X
; return N bit set for invalid fd
; all registers destroyed
.proc	fdtoiocb

	cpx	#0
	bne	inval
	cmp	#MAX_FD_INDEX
	bcs	inval
	tax
	lda	fd_index,x
	asl	a			; create index into fd table
	asl	a
	tax
	lda	#$ff
	cmp	fd_table+ft_iocb,x	; entry in use?
	beq	inval			; no, return error
	lda	fd_table+ft_usa,x	; get usage counter
	beq	inval			; 0? should not happen
	lda	fd_table+ft_iocb,x	; get iocb
	rts

.endproc

; decrements usage counter for fd
; if 0 reached, it's marked as unused
; get fd index in tmp2
; Y register preserved
.proc	fddecusage

	lda	tmp2			; get fd
	cmp	#MAX_FD_INDEX
	bcs	ret			; invalid index, do nothing
	tax
	lda	fd_index,x
	pha
	lda	#$ff
	sta	fd_index,x
	pla
	asl	a			; create index into fd table
	asl	a
	tax
	lda	#$ff
	cmp	fd_table+ft_iocb,x	; entry in use?
	beq	ret			; no, do nothing
	lda	fd_table+ft_usa,x	; get usage counter
	beq	ret			; 0? should not happen
	sec
	sbc	#1			; decrement by one
	sta	fd_table+ft_usa,x
	bne	ret			; not 0
	lda	#$ff			; 0, table entry unused now
	sta	fd_table+ft_iocb,x	; clear table entry
ret:	rts

.endproc

; newfd
;
; called from open() function
; finds a fd to use for an open request
; checks whether it's a device or file (file: characters follow the ':')
; files always get an exclusive slot
; for devices it is checked whether the device is already open, and if yes,
; a link to this open device is returned
;
; Calling parameters:
;	tmp3 - length of filename + 1
;	AX   - points to filename
;	Y    - iocb to use (if we need a new open)
; Return parameters:
;	tmp2 - fd num ($ff and C=0 in case of error - no free slot)
;	C    - 0/1 for no open needed/open should be performed
; all registers preserved!

; local variables:
;   AX     - 0 (A-0,X-1)
;   Y      - 2
;   ptr4   - 3,4  (backup)
;   devnum - 5

;loc_A      = 0
;loc_X      = 1
loc_Y      = 0
loc_ptr4_l = 1
loc_ptr4_h = 2
loc_tmp1   = 3
loc_devnum = 4
loc_size   = 5

.proc	newfd

	pha
	txa
	pha
	tya
	pha

	ldy	#loc_size
	jsr	subysp
	ldy	#loc_devnum
	lda	#0
	sta	(sp),y		; loc_devnum
	dey
	lda	tmp1
	sta	(sp),y		; loc_tmp1
	lda	#0
	sta	tmp1		; init tmp1
	sta	tmp2		; init tmp2
	dey
	lda	ptr4+1
	sta	(sp),y		; loc_ptr4_h
	dey
	lda	ptr4
	sta	(sp),y		; loc_ptr4_l
	dey
	pla
	sta	(sp),y		; loc_Y
;	dey
	pla
;	sta	(sp),y		; loc_X
	sta	ptr4+1
;	dey
	pla
;	sta	(sp),y		; loc_A
	sta	ptr4

	; ptr4 points to filename

	ldy	#1
	lda	#':'
	cmp	(ptr4),y	; "X:"
	beq	colon1
	iny
	cmp	(ptr4),y	; "Xn:"
	beq	colon2

	; no colon there!? OK, then we use a fresh iocb....
	; return error here? no, the subsequent open call should fail

do_open_nd:	; do open and don't remember device
	lda	#2
	sta	tmp1
do_open:lda	tmp1
	ora	#1
	sta	tmp1		; set flag to return 'open needed' : C = 1
	ldx	#ft_iocb
	ldy	#$ff
srchfree:
	tya
	cmp	fd_table,x
	beq	freefnd		; found a free slot
	txa
	clc
	adc	#ft_entrylen
	tax
	cmp	#(MAX_FD_VAL*4)+ft_iocb	; end of table reached?
	bcc	srchfree

; error: no free slot found
noslot:	ldx	#0
	stx	tmp1		; return with C = 0
	dex
	stx	tmp2		; iocb:	$ff marks error
	jmp	finish

; found a free slot
freefnd:txa
	sec
	sbc	#ft_iocb	; normalize
	tax
	lsr	a
	lsr	a
	sta	tmp2		; return fd
	lda	#2
	bit	tmp1		; remember device?
	beq	l1		; yes
	lda	#0		; no, put 0 in field
	beq	l2

l1:	ldy	#0
	lda	(sp),y			; get device
l2:	sta	fd_table+ft_dev,x	; set device
	lda	#1
	sta	fd_table+ft_usa,x	; set usage counter
	ldy	#loc_Y
	lda	(sp),y
	sta	fd_table+ft_iocb,x	; set iocb index
	ldy	#loc_devnum
	lda	(sp),y			; get (optional) device number
	and	#7			; only 3 bits
	sta	fd_table+ft_flag,x
	lda	tmp2
	jsr	fdt_to_fdi		; get new index
	bcs	noslot			; no one available
	;cmp	#$ff			; no one available
	;beq	noslot	;@@@ cleanup needed
	sta	tmp2			; return index
	jmp	finish

; string in "Xn:xxx" format
colon2:	dey
	lda	(ptr4),y	; get device number
	sec
	sbc	#'0'
	and	#7
	ldy	#loc_devnum
	sta	(sp),y		; save it
	sta	tmp2		; save it for speed later here also
	lda	#4		; max. length if only  device + number ("Xn:")
	cmp	tmp3
	bcc	do_open_nd	; string is longer -> contains filename
	bcs	check_dev	; handle device only string

; string in "X:xxx" format
colon1:	lda	#3		; max. length if device only ("X:")
	cmp	tmp3
	bcc	do_open_nd	; string is longer -> contains filename

; get device and search it in fd table
check_dev:
	ldy	#0
	lda	(ptr4),y	; get device id
	tay
	ldx	#(MAX_FD_VAL*4) - ft_entrylen
srchdev:lda	#$ff
	cmp	fd_table+ft_iocb,x	; is entry valid?
	beq	srch2			; no, skip this entry
	tya
	cmp	fd_table+ft_dev,x
	beq	fnddev
srch2:	txa
	sec
	sbc	#ft_entrylen+1
	tax
	bpl	srchdev

; not found, open new iocb
	jmp	do_open

; helper for branch out of range
noslot1:jmp	noslot

; found device in table, check device number (e.g R0 - R3)
fnddev:	lda	fd_table+ft_flag,x
	and	#7
	cmp	tmp2			; contains devnum
	bne	srch2			; different device numbers

; found existing open iocb with same device
	txa
	lsr	a
	lsr	a
	sta	tmp2
	inc	fd_table+ft_usa,x	; increment usage counter
	jsr	fdt_to_fdi		; get new index
	bcs	noslot1			; no one available
	sta	tmp2			; return index

; clean up and go home
finish:	lda	ptr4
	pha
	lda	ptr4+1
	pha
	ldy	#loc_Y
	lda	(sp),y
	pha
	lda	tmp1
	pha
	ldy	#loc_tmp1
	lda	(sp),y
	sta	tmp1
	ldy	#loc_size
	jsr	addysp
	pla
	lsr	a			; set C as needed

	pla
	tay
	pla
	tax
	pla
	rts

.endproc

; ftp_to_fdi
; returns a fd_index entry pointing to the given ft_table entry
; get fd_table entry in A
; return C = 0/1 for OK/error
; return fd_index entry in A if OK
; registers destroyed
.proc	fdt_to_fdi

	tay
	lda	#$ff
	tax
	inx
loop:	cmp	fd_index,x
	beq	found
	inx
	cpx	#MAX_FD_INDEX
	bcc	loop
	rts

found:	tya
	sta	fd_index,x
	txa
	clc
	rts

.endproc

; getfd
; get a new fd pointing to a ft_table entry
; usage counter of ft_table entry incremented
; A - fd_table entry
; return C = 0/1 for OK/error
; returns fd in A if OK
; registers destroyed, tmp1 destroyed
.proc	getfd

	sta	tmp1		; save fd_table entry
	jsr	fdt_to_fdi
	bcs	error

	pha
	lda	tmp1
	asl	a
	asl	a			; also clears C
	tax
	inc	fd_table+ft_usa,x	; increment usage counter
	pla
error:	rts

.endproc
