; x86-experiments -> 005 -> vbuf_text.s

%ifndef _VBUF_TEXT_S_
%define _VBUF_TEXT_S_


%include "vbuf.s"
%include "vbuf_sprite.s"
%include "math.s"


struc ScreenFont
	.GlyphW					resb 1
	.GlyphH					resb 1
	.AdvanceX				resb 1
	.AdvanceY				resb 1
	.pGlyphs				resd 1
endstruc

struc ScreenGlyphAdvance
	; lower bytes not used, so you can AND against whole structure
	VB_SGA_RESET_X			equ 0x00010000
	VB_SGA_RESET_Y			equ 0x00020000
	VB_SGA_NULL				equ 0x80000000

	.X						resb 1	; al
	.Y						resb 1	; ah
	.Flags					resw 1
endstruc


section .data

	GlyphsTitle				incbin "ftitle.bin"
	GlyphsBody				incbin "fbody.bin"

	FontTitle:
	istruc ScreenFont
		at ScreenFont.GlyphW,		db 7
		at ScreenFont.GlyphH,		db 12
		at ScreenFont.AdvanceX,		db 8
		at ScreenFont.AdvanceY,		db 16
		at ScreenFont.pGlyphs,		dd GlyphsTitle
	iend

	FontBody:
	istruc ScreenFont
		at ScreenFont.GlyphW,		db 6
		at ScreenFont.GlyphH,		db 8
		at ScreenFont.AdvanceX,		db 7
		at ScreenFont.AdvanceY,		db 12
		at ScreenFont.pGlyphs,		dd GlyphsBody
	iend
	
	vbuftest_strtitle		db "Test Title String!",0x0A,0xB0,"...with a newline~~~",0xDF,0x0A,"shorty L3",0
	vbuftest_strbody		db "Test Body String!",0x0A,0xB0, "...with a newline~~~ yep xd",0


section .text

; fn vbuf_test_draw_text() callconv(.stdcall) void
vbuf_test_draw_text:
	push	eax
	push	ebx
	; test sprite
	push	spr_test_8bit
	push	sprlen_test_8bit
	push	word 16
	push	word 16
	push	0xFFFFFF
	call	vbuf_draw_sprite_1b8
	; test char
	push	0					; flags
	push	FontBody
	push	65
	push	word 16
	push	word 32
	push	0xFFFFFF
	call	vbuf_draw_char
	; test string (body)
	push	FontBody
	push	vbuftest_strbody
	call	vbuf_measure_text
	mov		ebx, eax
	shr		ebx, 16
	and		ebx, 0xFFFF
	push	ebx					; h
	mov		ebx, eax
	and		ebx, 0xFFFF
	push	ebx					; w
	push	32 					; y
	push	16 					; x
	push	0x8080FF			; color
	call	vbuf_draw_rect
	push	FontBody
	push	vbuftest_strbody
	push	word 32
	push	word 16
	push	0xB0B0FF
	call	vbuf_draw_text
	; test string (title)
	push	FontTitle
	push	vbuftest_strtitle
	call	vbuf_measure_text
	mov		ebx, eax
	shr		ebx, 16
	and		ebx, 0xFFFF
	push	ebx					; h
	mov		ebx, eax
	and		ebx, 0xFFFF
	push	ebx					; w
	push	64 					; y
	push	16 					; x
	push	0x8080FF			; color
	call	vbuf_draw_rect
	push	FontTitle
	push	vbuftest_strtitle
	push	word 64
	push	word 16
	push	0xB0B0FF
	call	vbuf_draw_text
	; epilogue
	pop		ebx
	pop		eax
	ret


VB_CHR_NODRAW		equ 0x00000001
; TODO: configurable scale
; TODO: configurable offset based on sin, noise, etc.?
; TODO: toggle to actually draw or not (e.g. to calculate drawing size without drawing)
; stdcall
; fn vbuf_draw_char(color: u32, x: i16, y: i16, char: u8, font: *ScreenFont, flags: u32) ScreenGlyphAdvance
vbuf_draw_char:
	push	ebp
	mov		ebp, esp
	push	ebx
	push	ecx
	push	edx
	push	edi
	; draw
	mov		edx, [ebp+20]			; font
	xor		eax, eax
	xor		ecx, ecx
	mov		cl,	byte [ebp+16]		; char
	; check special chars
	cmp		cl, 0
	jne		.check_null_ok
	or		eax, VB_SGA_NULL		; FIXME: pessimized? remove?
	jmp		.return
.check_null_ok:
	cmp		cl, 10					; \n
	jne		.check_newline_ok
	mov		ah, byte [edx+ScreenFont.AdvanceY]
	or		eax, VB_SGA_RESET_X
	jmp		.return
.check_newline_ok:
.checks_ok:
	mov		edi, [ebp+24]
	and		edi, VB_CHR_NODRAW
	jnz		.draw_done
	mov		ebx, [edx+ScreenFont.pGlyphs]
	mov		al, byte [edx+ScreenFont.GlyphH]
	mul		ecx, eax
	add		ecx, ebx
	push	ecx						; sprite
	push	eax						; h
	push	word [ebp+14]			; y
	push	word [ebp+12]			; x
	push	[ebp+8]					; color
	call	vbuf_draw_sprite_1b8
.draw_done:
	; build ScreenGlyphAdvance
	mov		al, byte [edx+ScreenFont.AdvanceX]
	;mov	ah, byte [edx+ScreenFont.AdvanceY]
.return:
	; epilogue
	pop		edi
	pop		edx
	pop		ecx
	pop		ebx
	pop		ebp
	ret		20

; stdcall
; fn vbuf_draw_text(color: u32, x: i16, y: i16, str: [*:0]const u8, font: *ScreenFont) void
vbuf_draw_text:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	edx
	sub		esp, 4
	; draw text
	mov		eax, [ebp+12]
	mov		[esp], eax
	mov		eax, [ebp+16]		; str
	lea		ebx, [esp+0]
	lea		edx, [esp+2]
.oloop:
	push	eax
	mov		al, byte [eax]
	cmp		al, 0
	je		.oloop_end
	and		eax, 0xFF
	push	0					; flags
	push	[ebp+20]			; font
	push	eax					; char
	push	[ebx]				; x and y -- equivalent to:  push word [edx], push word [ebx]
	push	[ebp+8]				; color
	call	vbuf_draw_char
	; handle advance conditions
	push	edx
	push	ebx
	push	[ebp+12]			; 0xXXXXYYYY (should be fine since it matches fn sig)
	call	vbuf_parse_advance
	; prep next iteration
	pop		eax
	inc		eax
	jmp		.oloop
.oloop_end:
	pop		eax
	; epilogue
	add		esp, 4
	pop		edx
	pop		ebx
	pop		eax
	pop		ebp
	ret		16

; stdcall
; fn vbuf_draw_text_wave(
;      color: u32, x: i16, y: i16, str: [*:0]const u8, font: *ScreenFont, t: f32, a: f32, f: f32
; ) void
vbuf_draw_text_wave:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	push	edx
	sub		esp, 4
	; work
	mov		ecx, [ebp+12]
	mov		[esp], ecx
	mov		ecx, [ebp+16]		; str
	lea		ebx, [esp+0]
	lea		edx, [esp+2]
.oloop:
	push	ecx
	mov		cl, byte [ecx]
	cmp		cl, 0
	je		.oloop_end
	and		ecx, 0xFF
	; generate y-offset for wave pattern
	xor		eax, eax
	mov		ax, [ebx]
	push	eax
	call	i32tof				; eax <- phase (from x-pos)
	push	[f32_tau]
	push	eax
	call	f32div				; looks like crap without this
	push	[ebp+32]
	push	[ebp+28]
	push	eax
	push	[ebp+24]
	call	sinwave				; eax <- y-off (f32)
	push	eax
	call	f32toi
	add		ax, word [edx]		; combine with normal y
	; draw
	push	0					; flags
	push	[ebp+20]			; font
	push	ecx					; char
	push	ax					; y (with offset)
	push	word [ebx]			; x
	push	[ebp+8]				; color
	call	vbuf_draw_char
	; handle advance conditions
	push	edx
	push	ebx
	push	[ebp+12]			; 0xXXXXYYYY (should be fine since it matches fn sig)
	call	vbuf_parse_advance
	; prep next iteration
	pop		ecx
	inc		ecx
	jmp		.oloop
.oloop_end:
	pop		ecx
	; epilogue
	add		esp, 4
	pop		edx
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret		28

; stdcall
; fn vbuf_measure_text(str: [*:0]const u8, font: *ScreenFont) ScreenSize
vbuf_measure_text:
	push	ebp
	mov		ebp, esp
	push	ebx
	push	ecx
	push	edx
	push	edi
	sub		esp, 8
	; draw text
	mov		ecx, [ebp+12]		; font
	mov		[esp], dword 0
	mov		[esp+4], dword 0
	mov		eax, [ebp+8]		; str
	lea		ebx, [esp+0]
	lea		edx, [esp+2]
.oloop:
	push	eax
	mov		al, byte [eax]
	cmp		al, 0
	je		.oloop_end
	and		eax, 0xFF
	push	VB_CHR_NODRAW		; flags
	push	ecx					; font
	push	eax					; char
	push	[ebx]				; x and y -- equivalent to:  push word [edx], push word [ebx]
	push	0					; color
	call	vbuf_draw_char
	; handle advance conditions
	push	edx
	push	ebx
	push	0					; 0xXXXXYYYY (should be fine since it matches fn sig)
	call	vbuf_parse_advance
	; update ScreenSize
	mov		di, word [edx]
	cmp		di, word [ebx+4+ScreenSize.H]
	jle		.max_h_ok	
	mov		word [ebx+4+ScreenSize.H], di
.max_h_ok:
	mov		di, word [ebx]		; w second, so it's still in di after last iteration
	cmp		di, word [ebx+4+ScreenSize.W]
	jle		.max_w_ok	
	mov		word [ebx+4+ScreenSize.W], di
.max_w_ok:
	; prep next iteration
	pop		eax
	inc		eax
	jmp		.oloop
.oloop_end:
	pop		eax
	; finalize ScreenSize
	xor		edx, edx
	cmp		di, 0	; if last row actually drew a character, add glyph h to max size
	jle		.final_y_ok
	mov		dl, byte [ecx+ScreenFont.GlyphH]
	add		word [ebx+4+ScreenSize.H], dx
	jmp		.final_x	; if we had to do this, we already know the output w is > 0
.final_y_ok:
	cmp		word [ebx+4+ScreenSize.W], 0	
	jle		.final_x_ok
.final_x:
	mov		di, word [ebx+4+ScreenSize.W]
	mov		dl, byte [ecx+ScreenFont.AdvanceX]
	sub		di, dx
	mov		dl, byte [ecx+ScreenFont.GlyphW]
	add		di, dx
	mov		word [ebx+4+ScreenSize.W], di
.final_x_ok:
	mov		eax, [ebx+4]		; eax <- ScreenSize
	; epilogue
	add		esp, 8
	pop		edi
	pop		edx
	pop		ecx
	pop		ebx
	pop		ebp
	ret		8

; update x- and y-position based on given SGA
; stdcall-like -- expects: eax=adv, remainder on stack (callee-cleaned)
; fn vbuf_parse_advance(adv: ScreenGlyphAdvance, base_x: i16, base_y: i16, x: *i16, y: *i16) void
vbuf_parse_advance:
	push	ebp
	mov		ebp, esp
	push	ebx
	push	ecx
	push	edx
	push	edi
	push	esi
	; setup
	mov		edi, [ebp+12]		; *x
	mov		esi, [ebp+16]		; *y
	; parse
	mov		ecx, eax
	and		ecx, VB_SGA_RESET_X
	jz		.reset_x_ok
	mov		bx, word [ebp+08]	; x-base
	mov		word [edi], bx		; x
.reset_x_ok:
	mov		ecx, eax
	and		ecx, VB_SGA_RESET_Y
	jz		.reset_y_ok
	mov		dx, word [ebp+10]	; y-base
	mov		word [esi], dx		; y
.reset_y_ok:
	mov		ecx, eax
	and		ecx, 0xFF
	add		word [edi], cx		; x
	mov		ecx, eax
	shr		ecx, 8
	and		ecx, 0xFF
	add		word [esi], cx		; y
	; epilogue
	pop		esi
	pop		edi
	pop		edx
	pop		ecx
	pop		ebx
	pop		ebp
	ret		12


%endif
