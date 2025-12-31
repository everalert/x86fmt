; WARNING: ONLY edit this file in an editor that does NOT format on save, as the
;  entire point of this file is to provide customized reference formatting state
;
; test case for `app.zig` tests. data for this file comes from:
;   `001.s`             everalert/x86-experiments -> 001 -> main.s
;   `005.s`             everalert/x86-experiments -> 005 -> main.s
;   `vbuf_text.s`       everalert/x86-experiments -> 005 -> vbuf_text.s
;   `win32.s`           everalert/x86-experiments -> 005 -> win32.s
;   `reverse_string.s`  funnydman/nasm-assembly-examples -> x86_64/exercises/reverse_string.asm
;
; file parameters
;   `app.base.s`        (no formatting, this is used for test input only)
;   `app.default.s`     no cosmetic cli opts. equivalent to:
;                           -ts 4 -mbl 2 -tcc 40 -tia 12 -toa 8 -dcc 60 -dia 16 
;                           -doa 32 -sin 0 -sid 0 -sit 0 -sio 0
;   `app.all.s`         all cli opts set to non-default values
;                           -ts 2 -mbl 1 -tcc 36 -tia 8 -toa 6 -dcc 72 -dia 20 
;                           -doa 36 -sin 2 -sid 4 -sit 6 -sio 8




; some dummy data for no section context

NONE_SECTION_CONSTANT						equ 0

extern _NoneSectionImport@16		; user32.dll

%macro NoneSectionMacro
    xor     eax, eax
%endmacro




; some dummy data for 'other' section context
section .definitely_not_a_normal_section

OTHER_SECTION_CONSTANT						equ 0

extern _OtherSectionImport@16		; user32.dll

%macro OtherSectionMacro
    xor     eax, eax
%endmacro




; 001.s
; ----------------
; minimal console print via win32 api
; 2025/11/16
;
; nasm -fwin32 main.s
; golink /entry _main main.obj user32.dll kernel32.dll
; main.exe
section .data


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




; 005.s
; ----------------
; win32 text/sprite drawing
; 2025/11/29
;
; ./build.bat
; ./run.bat
section .data


; FIXME: homogenize vbuf api wrt register size of x/y/w/h arguments. shapes take 
;  32-bit, while the sprite/text functions take 16-bit. leaning toward 16-bit for 
;  now but not decided.
; TODO: console-based error printing
; TODO: print error with error code message


global _main

%include "win32.s"
%include "string.s"
%include "stdio.s"
%include "math.s"
%include "vbuf.s"
%include "vbuf_sprite.s"
%include "vbuf_text.s"

	
DefaultW				equ 640
DefaultH				equ 360
bPrintDebug				equ 0
bPrintInWndProc			equ 0


section .data

	AppRunning						dd 1
	FrameTime						dq 1.6666666666666666435370e-02

	WavyTextTimescale				dd 1.5
	WavyTextFrequency				dd 0.2
	WavyTextOffset					dd 2.0
	BgPulseTimescale				dd 0.75
	BgPulseOffsetBase				dd 26	; 16+16/2
	BgPulseOffsetB					dd 6.0	; 16/2

    str_window_name					db "TestWindow",0
	str_wndclass_name				db "TestWndClass",0
	str_error						db "Error!",0
	str_errmsg_format				db "[ERROR] (00000000) ",0		; will be filled in and expanded by fn
	strlen_errmsg_format			equ $-str_errmsg_format-1
	strloc_errmsg_format_err		equ 9							; position of the start of the error code
	str_get_hinst					db "Getting HINSTANCE",0
	str_init_wndclass				db "Initializing Window Class",0
	str_reg_wndclass				db "Registering Window Class",0
	str_create_window				db "Creating Window",0
	str_show_window					db "Showing Window",0
	str_bbuf_render					db "BackBuffer Render",0

	str_gale						db "GALE WAS HERE!",0
	str_dom							db "DOM IS A LOSER!",0
	str_super						db "SUPERCALIFRAGILISTICEXPIALIDOCIOUS",0


section .bss

	AppDuration						resq 1
	AppDuration32					resd 1
	AppTimerCircle					resd 1

	ModuleHandle:					resd 1
	StdHandle:						resd 1
	WindowHandle:					resd 1
	WindowMessage:					resd 1
	WindowClass:					resb WNDCLASSEXA_size
	WindowSize:						resb RECT_size


section .text

_main:

; console init

	push	StdHandle
	call	stdio_init
	call	stdio_test

; window init

get_hinstance:
	push	str_get_hinst
	call	debug_println
	push	NULL						; lpModuleName
	call	_GetModuleHandleA@4
	mov		[ModuleHandle], eax
	cmp		eax, 0
	jnz		.success
    push	str_GetModuleHandleA
	call	show_error_and_exit
.success:
	push	eax							; print HINSTANCE
	call	debug_print_h32

initialize_window_class:
	push	str_init_wndclass
	call	debug_println
	push	eax
	push	ebx
	push	ecx
	mov		ecx, [ModuleHandle]
	mov		ebx, WNDCLASSEXA_size
	mov		dword [WindowClass+WNDCLASSEXA.cbSize], ebx
	mov		dword [WindowClass+WNDCLASSEXA.style], CS_HREDRAW|CS_VREDRAW|CS_OWNDC
	mov		dword [WindowClass+WNDCLASSEXA.lpfnWndProc], wndproc
	mov		dword [WindowClass+WNDCLASSEXA.cbClsExtra], 0
	mov		dword [WindowClass+WNDCLASSEXA.cbWndExtra], 0
	mov		dword [WindowClass+WNDCLASSEXA.hInstance], ecx
	push	LR_DEFAULTSIZE				; fuLoad
	push	0							; cy
	push	0							; cx
	push	IMAGE_ICON					; type
	push	IDI_APPLICATION				; name
	push	ecx							; hInstance
    call	_LoadImageA@24
	push	eax							; print LoadImageA(Icon) result
	call	debug_print_h32
	mov		dword [WindowClass+WNDCLASSEXA.hIcon], eax
	mov		dword [WindowClass+WNDCLASSEXA.hIconSm], eax
	push	LR_DEFAULTSIZE				; fuLoad
	push	0							; cy
	push	0							; cx
	push	IMAGE_CURSOR				; type
	push	IDC_ARROW					; name
	push	ecx							; hInstance
    call	_LoadImageA@24
	push	eax							; print LoadImageA(Cursor) result
	call	debug_print_h32
	mov		dword [WindowClass+WNDCLASSEXA.hCursor], eax
	mov		dword [WindowClass+WNDCLASSEXA.hbrBackground], COLOR_WINDOWFRAME
	mov		dword [WindowClass+WNDCLASSEXA.lpszMenuName], 0
	mov		dword [WindowClass+WNDCLASSEXA.lpszClassName], str_wndclass_name
	pop		ecx
	pop		ebx
	pop		eax

register_wndclass:
	push	str_reg_wndclass
	call	debug_println
	push	WindowClass
	call	_RegisterClassExA@4
	push	eax	
	call	debug_print_h32
	cmp		eax, 0
	jnz		.success
    push	str_RegisterClassExA
	call	show_error_and_exit
.success:

; showing window

create_window:
	push	str_create_window
	call	debug_println
	push	ebx
	push	ecx
	sub		esp, RECT_size
	mov		ebx, esp
	mov		dword [ebx+RECT.Lf], 0
	mov		dword [ebx+RECT.Tp], 0
	mov		dword [ebx+RECT.Rt], DefaultW
	mov		dword [ebx+RECT.Bt], DefaultH
	push	0							;  bMenu
	push	WS_OVERLAPPEDWINDOW			;  dwStyle,
	push	ebx							;  lpRect,
	call	_AdjustWindowRect@12
	cmp		eax, 0
	jnz		.adjust_rect_success
    push	str_AdjustWindowRect
	call	show_error_and_exit
.adjust_rect_success:
	push	0							; lpParam 
	push 	[ModuleHandle]
	push 	0							; hMenu
	push 	0							; hWndParent
	mov		ecx, dword [ebx+RECT.Bt]
	sub		ecx, dword [ebx+RECT.Tp]
	push 	ecx							; nHeight
	mov		ecx, dword [ebx+RECT.Rt]
	sub		ecx, dword [ebx+RECT.Lf]
	push 	ecx							; nWidth
	push 	CW_USEDEFAULT				; Y
	push 	CW_USEDEFAULT				; X
	push 	WS_OVERLAPPEDWINDOW|WS_VISIBLE
	push 	str_window_name
	push 	str_wndclass_name
	push 	WS_EX_CLIENTEDGE
	call	_CreateWindowExA@48
	push	eax							; print HWND
	call	debug_print_h32
	cmp		eax, 0
	jnz		.success
    push	str_CreateWindowExA
	call	show_error_and_exit
.success:
	add		esp, RECT_size
	pop		ecx
	pop		ebx
	mov		[WindowHandle], eax

; FIXME: remove white flash that appears before first frame renders; for some 
;  reason, switching from GetMessageA to PeekMessageA caused this to start
;  happening. is it because the window sleeps at the beginning? the white flash
;  is clearly shorter with a smaller sleep.
app_loop:
.msg_loop:
	push	PM_REMOVE					; wRemoveMsg
	push	0							; wMsgFilterMax
	push	0							; wMsgFilterMin
	push	[WindowHandle]				; hWnd
	push	WindowMessage				; lpMsg
	call	_PeekMessageA@20
	cmp		eax, 0
	jng		.msg_loop_end
.msg_loop_handle:
	push	WindowMessage
	call	_TranslateMessage@4
	push	WindowMessage
	call	_DispatchMessageA@4
.msg_loop_end:
	cmp		[AppRunning], 0
	je		exit
	call	app_inc_timer
	call	backbuffer_resize
	call	backbuffer_draw
	; getdc
	push	[WindowHandle]
	call	_GetDC@4	
	cmp		eax, 0
	jnz		.getdc_ok
	push	str_GetDC
	call	show_error_and_exit
.getdc_ok:
	; render
	push	eax							; DC from GetDC
	call	backbuffer_render
	; releasedc
	push	eax
	push	[WindowHandle]
	call	_ReleaseDC@8
	cmp		eax, 0
	jnz		.render_ok
	push	str_ReleaseDC
	call	show_error_and_exit
.render_ok:
	push	16							; 16=~60fps, 7=~143fps
	call	_Sleep@4
	jmp		app_loop

; end program
	
exit:
    push	0							; no error
    call	_ExitProcess@4 

; functions

; stdcall
; fn app_inc_timer() void
app_inc_timer:
	inc		dword [FrameCount]
	fld		qword [AppDuration]
	fadd	qword [FrameTime]
	fst		qword [AppDuration]
	fst		dword [AppDuration32]
	; misc
	fmul	dword [f32_tau]
	fstp	dword [AppTimerCircle]
	; epilogue
	ret

; stdcall
; LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
wndproc:
	; prologue
	push	ebp
	mov		ebp, esp
	push	ebx
	push	ecx
	push	edx
	mov		ebx, [ebp+12]				; msg
	; handle messages
	cmp		ebx, WM_PAINT
	jz		.wm_paint
	cmp		ebx, WM_CLOSE
	jz		.wm_close
	cmp		ebx, WM_DESTROY
	jz		.wm_destroy
	cmp		ebx, WM_GETMINMAXINFO
	jz		.wm_getminmaxinfo
	jmp		.default
.wm_paint:
	push	str_WM_PAINT
	call	wndproc_println
	; prep
	call	backbuffer_resize
	call	backbuffer_draw
	; beginpaint
	sub		esp, PAINTSTRUCT_size
	mov		edx, esp
	push	edx
	push	[WindowHandle]
	call	_BeginPaint@8
	cmp		eax, 0
	jnz		.wm_paint_beginpaint_ok
	push	str_BeginPaint
	call	show_error_and_exit
	; (re)draw
.wm_paint_beginpaint_ok:
	push	eax							; DC from BeginPaint
	call	backbuffer_render
	; endpaint
	push	edx
	push	[WindowHandle]
	call	_EndPaint@8
	add		esp, PAINTSTRUCT_size
	jmp		.return_handled
.wm_close:
	push	str_WM_CLOSE
	call	wndproc_println
	mov		[AppRunning], 0
	jmp		.return_handled
.wm_destroy:
	push	str_WM_DESTROY
	call	wndproc_println
	mov		[AppRunning], 0
	jmp		.return_handled
.wm_getminmaxinfo:
	push	str_WM_GETMINMAXINFO
	call	wndproc_println
	mov		ecx, [ebp+20]				; *MINMAXINFO
	add		[ecx+MINMAXINFO.ptMinTrackSize+POINT.x], 16
	add		[ecx+MINMAXINFO.ptMinTrackSize+POINT.y], 16
	jmp		.return_handled
.default:
	push	[ebp+20]
	push	[ebp+16]
	push	[ebp+12]
	push	[ebp+8]
	call	_DefWindowProcA@16
	jmp		.return						; eax should hold return value here
	; epilogue
.return_handled:
	mov		eax, 0
.return:
	pop		edx
	pop		ecx
	pop		ebx
	pop		ebp
	ret		16

; conditionally println based on wndproc toggle
; fn wndproc_println(str: [*:0]const u8) callconv(.stdcall) void
wndproc_println:
	%if	bPrintDebug & bPrintInWndProc
	push	[esp+4]
	call	println
	%endif
	ret		4

; conditionally println based on debug toggle
; fn debug_println(str: [*:0]const u8) callconv(.stdcall) void
debug_println:
	%if	bPrintDebug
	push	[esp+4]
	call	println
	%endif
	ret		4

; conditionally println based on debug toggle
; fn debug_println(str: [*:0]const u8) callconv(.stdcall) void
debug_print_h32:
	%if	bPrintDebug
	push	[esp+4]
	call	print_h32
	%endif
	ret		4

; fn backbuffer_resize() callconv(.stdcall) void
backbuffer_resize:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	sub		esp, RECT_size
	; size
	mov		eax, esp
	push	eax
	push	[WindowHandle]
	call	_GetClientRect@8
	mov		eax, esp
	mov		ebx, dword [eax+RECT.Bt]
	mov		ecx, dword [eax+RECT.Rt]
	cmp		[WindowSize+RECT.Bt], ebx
	jnz		.resize_ok
	cmp		[WindowSize+RECT.Rt], ecx
	jnz		.resize_ok
	jmp		.resize_end
.resize_ok:
	push	ebx	
	push	ecx	
	push	BackBuffer
	call	set_screen_size
	mov		[WindowSize+RECT.Bt], ebx
	mov		[WindowSize+RECT.Rt], ecx
	; epilogue
.resize_end:
	add		esp, RECT_size
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret

; fn backbuffer_draw() callconv(.stdcall) void
backbuffer_draw:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	push	edx
	sub		esp, 8
	mov		edx, esp
	; clear
	push	[BgPulseTimescale]				; frequency
	push	[BgPulseOffsetB]				; amplitude
	push	[AppTimerCircle]				; phase
	push	[f32_0]							; t
	call	sinwave
	push	eax
	call	f32toi
	add		eax, [BgPulseOffsetBase]
	push	eax
	call	vbuf_flood			
	; test drawing
	;call	vbuf_test_draw_text
	; get midpoint
	mov		eax, [BackBuffer+ScreenBuffer.Width]
	shr		eax, 1
	mov		[esp+0], eax
	mov		eax, [BackBuffer+ScreenBuffer.Height]
	shr		eax, 1
	mov		[esp+4], eax
	; funny xd title
	push	FontTitle
	push	str_gale
	push	FontTitle
	push	str_gale
	call	vbuf_measure_text
	mov		bx, word [edx+4]
	mov		ecx, eax
	shr		ecx, 16
	sub		bx, cx
	push	bx					; h
	mov		bx, word [edx+0]
	mov		ecx, eax
	shr		cx, 1
	sub		bx, cx
	push	bx					; w
	push	0xD0D0FF
	call	vbuf_draw_text
	; funny xd body
	push	[AppTimerCircle]
	push	[WavyTextTimescale]
	call	f32mul
	push	[WavyTextFrequency]				; frequency
	push	[WavyTextOffset]				; amplitude
	push	eax								; t
	push	FontBody
	push	str_dom
	push	FontBody
	push	str_dom
	call	vbuf_measure_text
	mov		bx, word [edx+4]
	mov		ecx, eax
	shr		ecx, 17
	add		bx, cx
	push	bx					; h
	mov		bx, word [edx+0]
	mov		ecx, eax
	shr		cx, 1
	sub		bx, cx
	push	bx					; w
	push	0xB0B0FF
	call	vbuf_draw_text_wave
	; epilogue
	add		esp, 8
	pop		edx
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret

; NOTE: might need to flush GDI at the top or bottom of this. apparently writing
;  to the pixel buffer can cause an error if you don't
; assumes the backbuffer is the same size as the client rect, i.e. set_screen_size
;  has already been called in response to any window size change
; fn backbuffer_render(hdc: HANDLE) callconv(.stdcall) void
backbuffer_render:
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx									; memory dc handle
	push	ecx									; "old bitmap" handle
	; memory dc
	push	[ebp+8]
	call	_CreateCompatibleDC@4				; FIXME: error handling
	mov		ebx, eax
	push	[BackBuffer+ScreenBuffer.hBitmap]
	push	ebx
	call	_SelectObject@8						; FIXME: error handling
	mov		ecx, eax
	push	ROP_SRCCOPY							; rop
	push	[BackBuffer+ScreenBuffer.Height]	; hSrc
	push	[BackBuffer+ScreenBuffer.Width]		; wSrc
	push	0									; ySrc
	push	0									; xSrc
	push	ebx									; hdcSrc
	push	[WindowSize+RECT.Bt]				; hDest
	push	[WindowSize+RECT.Rt]				; wDest
	push	0                   				; yDest
	push	0                   				; xDest
	push	[ebp+8]								; hdcDest
	call	_StretchBlt@44						; eax <- BOOL
	cmp		eax, 0
	jne		.stretchdibits_ok					; TODO: check for GDIERROR
	push	str_StretchBlt
	call	show_error_and_exit					; WARN: might close without showing message, unsure
.stretchdibits_ok:
	push	ecx
	push	ebx
	call	_SelectObject@8						; FIXME: error handling
	push	ebx
	call	_DeleteDC@4							; FIXME: error handling
	; epilogue
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret		4

; NOTE: expects vbuf to be zero-init'd
; TODO: maybe floodfill black by default in set_screen_size to clear screen?
; update screen buffer resource for use in WM_SIZE etc.
; fn set_screen_size(vbuf: *ScreenBuffer, w: i32, h: i32) callconv(.stdcall) void
set_screen_size:
	; prologue
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	push	edx
	; free existing memory if needed
	mov		eax, [BackBuffer+ScreenBuffer.hBitmap]
	cmp		eax, 0
	jz		.free_ok
	push	eax
	call	_DeleteObject@4
	cmp		eax, 0
	jnz		.free_ok
    push	str_DeleteObject
	call	show_error_and_exit
.free_ok:
	mov		[BackBuffer+ScreenBuffer.hBitmap], 0
	mov		[BackBuffer+ScreenBuffer.Memory], 0
	; fill in the buffer info and alloc new memory
	mov		ecx, [ebp+12]
	mov		edx, [ebp+16]
	mov		dword [BackBuffer+ScreenBuffer.Width], ecx
	mov		dword [BackBuffer+ScreenBuffer.Height], edx
	mov		dword [BackBuffer+ScreenBuffer.BytesPerPixel], 4
	lea		ebx, [BackBuffer+ScreenBuffer.Info]
	mov		dword [ebx+BITMAPINFOHEADER.biSize], BITMAPINFOHEADER_size
	mov		dword [ebx+BITMAPINFOHEADER.biWidth], ecx
	mov		dword [ebx+BITMAPINFOHEADER.biHeight], 0
	sub		dword [ebx+BITMAPINFOHEADER.biHeight], edx
	mov		word [ebx+BITMAPINFOHEADER.biPlanes], 1
	mov		word [ebx+BITMAPINFOHEADER.biBitCount], 32
	mov		dword [ebx+BITMAPINFOHEADER.biCompression], BI_RGB
	shl		ecx, 2											; bitmap size = Width * BytesPerPixel(4)
	mov		dword [BackBuffer+ScreenBuffer.Pitch], ecx
	mul		ecx, edx										; bitmap size = Width * Height * BytesPerPixel(4)
	push	NULL											; offset
	push	NULL											; hSection
	push	BackBuffer+ScreenBuffer.Memory					; **ppvBits
	push	DIB_RGB_COLORS									; usage
	push	BackBuffer+ScreenBuffer.Info					; *pbmi
	push	NULL											; hdc
	call	_CreateDIBSection@24							; eax <- HBITMAP
	cmp		eax, 0
	jnz		.alloc_ok
    push	str_CreateDIBSection
	call	show_error_and_exit
.alloc_ok:
	mov		[BackBuffer+ScreenBuffer.hBitmap], eax
	; epilogue
	pop		edx
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret		12

; TODO: output formatted message containing error code
;  see: GetLastError, FormatMessageA
; display error message with error code in a messagebox and exit
; fn show_error_and_exit(message: [*:0]const u8) callconv(.stdcall) noreturn
show_error_and_exit:
	; prologue
	push	ebp
	mov		ebp, esp
	push	eax
	push	ebx
	push	ecx
	sub		esp, 256				; [256]u8
	; show message
	mov		ebx, esp
	mov		ecx, esp
	push	str_errmsg_format		; src
	push	ebx						; dst
	call	strcpy
	add		ebx, strloc_errmsg_format_err
	call	_GetLastError@0
	push	ebx
	push	eax
	call	htoa
	mov		ebx, ecx
	add		ebx, strlen_errmsg_format
	push	[ebp+8]					; src
	push	ebx						; dst
	call	strcpy
    push	MB_OK|MB_ICONEXCLAMATION
	push	str_error
    push	ecx						; message
    push	[ModuleHandle]
    call	_MessageBoxA@16
    push	0						; no error
    call	_ExitProcess@4 
	; epilogue
	add		esp, 256
	pop		ecx
	pop		ebx
	pop		eax
	pop		ebp
	ret		4

; fn memcpy(dst: [*]u8, src: [*]const u8, len: u32) callconv(.stdcall) void
memcpy:
	push	esi
	push	edi
	push	ecx
	mov		edi, [esp+16]
	mov		esi, [esp+20]
	mov		ecx, [esp+24]
	rep		movsb
	pop		ecx
	pop		edi
	pop		esi
	ret		12




; reverse_string.asm
; ----------------
; make it more readable and accurate
section .data


section .data
string db "NewBoston"
stringLen equ ($-string)

section .text
global main
main:
    mov rbp, rsp; for correct debugging
    mov eax, string  ; Address of the first element
    lea ebx, [string + stringLen-1] ; Address of the last element
    mov ecx, stringLen/2 ; condition for our loop
reverse:
    movzx rdi, byte [eax] ; now contain "N" char
    movzx rsi, byte [ebx] ; now contain "n" char
    mov [eax],sil
    mov [ebx],dil 
    
    inc eax
    dec ebx
    dec ecx
    cmp ecx, 0
    jne reverse




; x86-experiments -> 005 -> vbuf_text.s
; ----------------
section .data

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




; x86-experiments -> 005 -> win32.s
; ----------------
section .data

%ifndef	_WIN32_S_
%define	_WIN32_S_


; FUNCTIONS

extern _GetModuleHandleA@4			; kernel32.lib
extern _GetStdHandle@4				; kernel32.lib
extern _AttachConsole@4				; kernel32.lib
extern _GetConsoleWindow@0			; kernel32.lib
extern _WriteConsoleA@20			; kernel32.lib
extern _ExitProcess@4				; kernel32.lib
extern _VirtualAlloc@16				; kernel32.lib
extern _VirtualFree@12				; kernel32.lib
extern _GetLastError@0				; kernel32.lib
extern _SetLastError@4				; kernel32.lib
extern _FormatMessageA@28			; kernel32.lib
extern _Sleep@4						; kernel32.lib

extern _MessageBoxA@16				; user32.lib
extern _CreateWindowExA@48			; user32.lib
extern _DestroyWindow@4				; user32.lib
extern _GetMessageA@16				; user32.lib
extern _PeekMessageA@20				; user32.lib
extern _TranslateMessage@4			; user32.lib
extern _DispatchMessageA@4			; user32.lib
extern _PostQuitMessage@4			; user32.lib
extern _DefWindowProcA@16			; user32.lib
extern _LoadImageA@24				; user32.lib
extern _RegisterClassExA@4			; user32.lib
extern _AdjustWindowRect@12			; user32.lib
extern _ValidateRect@8				; user32.lib
extern _InvalidateRect@12			; user32.lib
extern _BeginPaint@8				; user32.lib
extern _EndPaint@8					; user32.lib
extern _GetDC@4						; user32.lib
extern _ReleaseDC@8					; user32.lib
extern _GetClientRect@8				; user32.lib
extern _GetSystemMetrics@4			; user32.lib
extern _SetTimer@16					; user32.lib
extern _RegisterRawInputDevices@12	; user32.lib
extern _GetRawInputData@20			; user32.lib
extern _GetRawInputBuffer@12		; user32.lib
extern _GetRawInputDeviceInfoA@16	; user32.lib

extern _CreateCompatibleDC@4		; gdi32.lib
extern _DeleteDC@4					; gdi32.lib
extern _GetObject@12				; gdi32.lib
extern _DeleteObject@4				; gdi32.lib
extern _SelectObject@8				; gdi32.lib
extern _SetDIBits@28				; gdi32.lib
extern _StretchDIBits@52			; gdi32.lib
extern _StretchBlt@44				; gdi32.lib
extern _CreateDIBSection@24			; gdi32.lib

extern _HidP_GetCaps@8				; hidparse.lib
extern _HidP_GetValueCaps@16		; hidparse.lib
extern _HidP_GetButtonCaps@16		; hidparse.lib
extern _HidP_GetUsages@32			; hidparse.lib
extern _HidP_GetUsageValue@32		; hidparse.lib


; STRUCTURES

struc WNDCLASSEXA
	.cbSize							resd 1
	.style							resd 1
	.lpfnWndProc					resd 1
	.cbClsExtra						resd 1
	.cbWndExtra						resd 1
	.hInstance						resd 1
	.hIcon							resd 1
	.hCursor						resd 1
	.hbrBackground					resd 1
	.lpszMenuName					resd 1
	.lpszClassName					resd 1
	.hIconSm						resd 1
endstruc

struc BITMAPINFO
	.bmiHeader						resb BITMAPINFOHEADER_size
	.bmiColors						resd 0	; VLA of RGBQUAD
endstruc

struc BITMAPINFOHEADER
	.biSize							resd 1
	.biWidth						resd 1
	.biHeight						resd 1
	.biPlanes						resw 1
	.biBitCount						resw 1
	.biCompression					resd 1
	.biSizeImage					resd 1
	.biXPelsPerMeter				resd 1
	.biYPelsPerMeter				resd 1
	.biClrUsed						resd 1
	.biClrImportant					resd 1
endstruc

struc RGBQUAD
	.rgbBlue						resb 1
	.rgbGreen						resb 1
	.rgbRed							resb 1
	.rgbReserved					resb 1
endstruc

struc MINMAXINFO
	.ptReserved						resb POINT_size
	.ptMaxSize						resb POINT_size
	.ptMaxPosition					resb POINT_size
	.ptMinTrackSize					resb POINT_size
	.ptMaxTrackSize					resb POINT_size
endstruc

struc POINT
	.x								resd 1
	.y								resd 1
endstruc

struc RECT
	.Lf								resd 1
	.Tp								resd 1
	.Rt								resd 1
	.Bt								resd 1
endstruc

struc PAINTSTRUCT
	.hDC							resd 1
	.fErase							resd 1
	.rcPaint						resb RECT_size
	.fRestore						resd 1
	.fIncUpdate						resd 1
	.rgbReserved					resb 32
endstruc

; rawinput

struc RAWINPUTDEVICE
	.usUsagePage					resw 1
	.usUsage						resw 1
	.dwFlags						resd 1
	.hwndTarget						resd 1
endstruc

struc RAWINPUT
	.header							resb RAWINPUTHEADER_size
	.data.mouse						resd 0				; RAWMOUSE   
	.data.keyboard					resd 0 				; RAWKEYBOARD
	.data.hid						resd 0 				; RAWHID     
	.data							resb RAWMOUSE_size	; union
endstruc

struc RAWINPUTHEADER
	.dwType							resd 1
	.dwSize							resd 1
	.hDevice						resd 1
	.wParam							resd 1
endstruc

struc RAWHID
	.dwSizeHid						resd 1
	.dwCount						resd 1
	.bRawData						resb 0 ; VLA of bytes
endstruc

struc RAWKEYBOARD
	.MakeCode						resw 1
	.Flags							resw 1
	.Reserved						resw 1
	.VKey							resw 1
	.Message						resd 1
	.ExtraInformation				resd 1
endstruc

struc RAWMOUSE
	.usFlags						resw 1
	._								resw 1 ; padding
	.ulButtons						resd 0 ; buttons union
	.usButtonFlags					resw 1 ; buttons union
	.usButtonData					resw 1
	.ulRawButtons					resd 1
	.lLastX							resd 1
	.lLastY							resd 1
	.ulExtraInformation				resd 1
endstruc

struc HIDP_CAPS
	.Usage							resw 1
	.UsagePage						resw 1
	.InputReportByteLength			resw 1
	.OutputReportByteLength			resw 1
	.FeatureReportByteLength		resw 1
	.Reserved						resw 17
	.NumberLinkCollectionNodes		resw 1
	.NumberInputButtonCaps			resw 1
	.NumberInputValueCaps			resw 1
	.NumberInputDataIndices			resw 1
	.NumberOutputButtonCaps			resw 1
	.NumberOutputValueCaps			resw 1
	.NumberOutputDataIndices		resw 1
	.NumberFeatureButtonCaps		resw 1
	.NumberFeatureValueCaps			resw 1
	.NumberFeatureDataIndices		resw 1
endstruc


; CONSTANTS

section .data

	; error codes
	ERROR_ACCESS_DENIED				equ 0x00000005
	; misc	
	NULL							equ 0
	ATTACH_PARENT_PROCESS			equ -1
	INVALID_VALUE_HANDLE			equ -1
	STD_OUTPUT_HANDLE				equ -11
	IDI_APPLICATION					equ 0x7F00
	IDC_ARROW						equ 0x7F00
	COLOR_WINDOWFRAME				equ 6
	LR_DEFAULTSIZE					equ 0x00000040
	; window messages
	WM_DESTROY						equ 0x0002
	WM_SIZE							equ 0x0005
	WM_PAINT						equ 0x000F
	WM_CLOSE						equ 0x0010
	WM_ACTIVATEAPP					equ 0x001C
	WM_GETMINMAXINFO				equ 0x0024
	WM_INPUT						equ 0x00FF
	WM_EXITSIZEMOVE					equ 0x0232
	; peek message	
	PM_NOREMOVE						equ 0x0000
	PM_REMOVE						equ 0x0001
	PM_NOYIELD						equ 0x0002
	; wndclass
	CS_VREDRAW						equ	0x0001
	CS_HREDRAW						equ	0x0002
	CS_OWNDC						equ	0x0020
	CW_USEDEFAULT					equ	0x80000000
	; window styles
	WS_SHOWNORMAL					equ 1
	WS_VISIBLE						equ 0x10000000
	WS_OVERLAPPEDWINDOW				equ 0x00CF0000
	WS_EX_CLIENTEDGE				equ 0x00000200
	; messagebox flags
	MB_OK							equ 0x00
	MB_ICONEXCLAMATION				equ 0x30
	; virtualalloc
	MEM_COMMIT						equ 0x00001000
	MEM_RESERVE						equ 0x00002000
	MEM_DECOMMIT					equ 0x00004000
	MEM_RELEASE						equ 0x00008000
	PAGE_READONLY					equ 0x02
	PAGE_READWRITE					equ 0x04
	; window image resources
	IMAGE_BITMAP					equ 0 ; C:\Program Files (x86)\Windows Kits\10\Include\<ver>\um\winuser.h
	IMAGE_ICON						equ 1
	IMAGE_CURSOR					equ 2
	; gdi
	DIB_RGB_COLORS					equ 0
	DIB_PAL_COLORS					equ 1
	BI_RGB							equ 0
	ROP_SRCCOPY						equ	0x00CC0020 ; just SRCCOPY in wingdi.h
	GDI_ERROR						equ	0xFFFFFFFF
	; formatmessage
	FORMAT_MESSAGE_ALLOCATE_BUFFER	equ 0x00000100
	FORMAT_MESSAGE_IGNORE_INSERTS	equ 0x00000200
	FORMAT_MESSAGE_FROM_STRING		equ 0x00000400
	FORMAT_MESSAGE_FROM_SYSTEM		equ 0x00001000
	; hid (human interface device)
	HID_USAGE_PAGE_GENERIC			equ 0x0001
	HID_USAGE_PAGE_GAME				equ 0x0005
	HID_USAGE_PAGE_LED				equ 0x0008
	HID_USAGE_PAGE_BUTTON			equ 0x0009
	HID_USAGE_GENERIC_POINTER		equ 0x0001
	HID_USAGE_GENERIC_MOUSE			equ 0x0002
	HID_USAGE_GENERIC_JOYSTICK		equ 0x0004
	HID_USAGE_GENERIC_GAMEPAD		equ 0x0005
	HID_USAGE_GENERIC_KEYBOARD		equ 0x0006
	HID_USAGE_GENERIC_KEYPAD		equ 0x0007
	HID_USAGE_GENERIC_MULTI_AXIS_CONTROLLER	equ 0x0008
	; rid (raw input device)
	RID_INPUT						equ 0x10000003
	RID_HEADER						equ 0x10000005
	RIDI_PREPARSEDDATA				equ 0x20000005
	RIDI_DEVICENAME					equ 0x20000007
	RIDI_DEVICEINFO					equ 0x2000000B
	RIDEV_REMOVE					equ 0x00000001
	RIDEV_EXCLUDE					equ 0x00000010
	RIDEV_PAGEONLY					equ 0x00000020
	RIDEV_NOLEGACY					equ 0x00000030
	RIDEV_INPUTSINK					equ 0x00000100
	RIDEV_CAPTUREMOUSE				equ 0x00000200
	RIDEV_NOHOTKEYS					equ 0x00000200
	RIDEV_APPKEYS					equ 0x00000400
	RIDEV_EXINPUTSINK				equ 0x00001000
	RIDEV_DEVNOTIFY					equ 0x00002000

	str_RegisterClassExA			db "RegisterClassExA",0
	str_CreateWindowExA				db "CreateWindowExA",0
	str_GetModuleHandleA			db "GetModuleHandleA",0
	str_AttachConsole				db "AttachConsole",0
	str_GetStdHandle				db "GetStdHandle",0
	str_GetConsoleWindow			db "GetConsoleWindow",0
	str_WriteConsoleA				db "WriteConsoleA",0
	str_VirtualAlloc				db "VirtualAlloc",0
	str_VirtualFree					db "VirtualFree",0
	str_AdjustWindowRect			db "AdjustWindowRect",0
	str_GetDC						db "GetDC",0
	str_ReleaseDC					db "ReleaseDC",0
	str_DeleteObject				db "DeleteObject",0
	str_StretchDIBits				db "StretchDIBits",0
	str_StretchBlt					db "StretchBlt",0
	str_CreateDIBSection			db "CreateDIBSection",0
	str_BeginPaint					db "BeginPaint",0

	str_WM_EXITSIZEMOVE				db "WM_EXITSIZEMOVE",0
	str_WM_SIZE						db "WM_SIZE",0
	str_WM_ACTIVATEAPP				db "WM_ACTIVATEAPP",0
	str_WM_CLOSE					db "WM_CLOSE",0
	str_WM_DESTROY					db "WM_DESTROY",0
	str_WM_PAINT					db "WM_PAINT",0
	str_WM_INPUT					db "WM_INPUT",0
	str_WM_GETMINMAXINFO			db "WM_GETMINMAXINFO",0


%endif
