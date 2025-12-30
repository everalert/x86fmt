; x86-experiments -> 005 -> win32.s

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
