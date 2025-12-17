; minimal console print via win32 api
; 2025/11/16
;
; nasm -fwin32 main.s
; golink /entry _main main.obj user32.dll kernel32.dll
; main.exe


extern _GetStdHandle@4		; kernel32.dll
extern _AttachConsole@4		; kernel32.dll
extern _WriteConsoleA@20	; kernel32.dll
extern _ExitProcess@4		; kernel32.dll
extern _MessageBoxA@16		; user32.dll

; %1  error message string
%macro ShowErrorMessage 1
    push	MB_OK|MB_ICONEXCLAMATION
    push	str_error
    push	%1
    push	[HINSTANCE]
    call	_MessageBoxA@16
	jmp		exit
%endmacro

; %1  string len
; %2  string
%macro WriteConsole 2
	push	eax
	push	ecx
	mov		ecx, %1
	push	ebx
	mov		ebx, %2
	push	NULL					; lpVoidReserved
	push	StdOutCharsWritten		; lpNumberOfCharsWritten
	push	ecx						; nNumberOfCharsToWrite
	push	ebx						; lpBuffer
	push	[HSTDOUT]				; hConsoleOutput
	call	_WriteConsoleA@20
	cmp		eax, NULL
	pop		ebx
	pop		ecx
	pop		eax
	jnz		%%success
	ShowErrorMessage str_err_write_console
	%%success:
%endmacro

global _main

section .data
	; win32 constants
	NULL						equ 0
	ATTACH_PARENT_PROCESS		equ -1
	INVALID_VALUE_HANDLE		equ -1
	STD_OUTPUT_HANDLE			equ -11
	MB_OK						equ 0x00
	MB_ICONEXCLAMATION			equ 0x30
	; our stuff
	str_newline					db 10,0
	str_error					db "Error!",0
	str_err_attach_console		db "AttachConsole Failed!",0
	str_err_get_std_handle		db "GetStdHandle Failed!",0
	str_err_get_console_window	db "GetConsoleWindow Failed!",0
	str_err_write_console		db "WriteConsoleA Failed!",0
	str_console_test			db "Console Output Test",10,0
	strlen_console_test			dd $-str_console_test
	str_get_hinst				db "Getting HINSTANCE",10,0
	strlen_get_hinst			dd $-str_get_hinst

section .bss
	HINSTANCE:					resd 1
	HSTDOUT:					resd 1
	StdOutCharsWritten			resd 1
 
section .text

_main:

; console init

console_setup:
	push	ATTACH_PARENT_PROCESS
	call	_AttachConsole@4
	cmp		eax, 0
	jnz		console_get_handle
	ShowErrorMessage str_err_attach_console
console_get_handle:
	push	STD_OUTPUT_HANDLE
	call	_GetStdHandle@4
	mov		[HSTDOUT], eax
	cmp		eax, INVALID_VALUE_HANDLE
	jnz		console_setup_done
	ShowErrorMessage str_err_get_std_handle
console_setup_done:

;write_console_test:
;	WriteConsole [strlen_console_test], str_console_test

test_htoa:
	sub		esp, 8						; [8]u8		output buffer
	lea		eax, [esp]
	push	eax
	push	dword 0x01234567
	call	htoa
	WriteConsole 8, eax
	WriteConsole 1, str_newline
	push	eax
	push	dword 0x0123ABCD
	call	htoa
	WriteConsole 8, eax
	WriteConsole 1, str_newline
	push	eax
	push	dword 0xDEADBEEF
	call	htoa
	WriteConsole 8, eax
	WriteConsole 1, str_newline
	add		esp, 8
	jmp		exit

exit:
    push	0							; no error
    call	_ExitProcess@4 

; convert 4-byte u32 value to hex string
; fn htoa(val: u32, out: *[8]u8) callconv(.stdcall) void
htoa:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	push	edx
	mov		ebx, [ebp+8]				; val
	mov		eax, [ebp+12]				; out
	mov		ecx, 8						; ecx = i
htoa_it:
	sub		ecx, 1
	mov		edx, ebx					; val
	and		edx, 0xF
	add		edx, 0x30					; edx += '0' 
	cmp		edx, 0x39
	jle		htoa_it_out					; char < A
	add		edx, 0x07					; edx += 'A'-':'
htoa_it_out:
	mov		byte [eax+ecx], dl			; out[i]
	shr		ebx, 4						; val >> 4
	cmp		ecx, 0
	jge		htoa_it
	pop		edx
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	; NOTE: not sure why the following crashes
	;  add esp, 8
	;  ret
	ret		8

