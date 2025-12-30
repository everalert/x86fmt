; x86-experiments -> 005 -> main.s
; 
; win32 text/sprite drawing
; 2025/11/29
;
; ./build.bat
; ./run.bat


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
