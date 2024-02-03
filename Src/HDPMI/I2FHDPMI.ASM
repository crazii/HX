
;--- int 2f, ax=168A, vendor HDPMI code

	.386

	include hdpmi.inc
	include external.inc

	option proc:private

if ?VENDORAPI

@wofs macro ofs
	dw offset ofs - offset start168a
endm

 ifdef _DEBUG
displayhdltab proto near
 endif

if ?PMIOPL eq 0
IOPORTTRAP struct
portS dw -1
portE dw -1
off dd -1
sel dw -1
dsel dw -1
IOPORTTRAP ends

IOPORTTRAPFRAME struct
rEBX	dd ? ; EBX. local. match the entry of _I2f168A_Hdpmi_InOutExcHandler
rES		dd ? ; ES. local. match the entry of _I2f168A_Hdpmi_InOutExcHandler
rDS		dd ? ; DS. local.
		dd ? ; return addr of _I2f168A_Hdpmi_InOutExcHandler's caller
rError	dd ? ; error code of 0D(#GP) except 
rEIP	dd ? ; faulted eip
rCSd	dd ? ; faulted cs
rEFL	dd ? ; eflags
rESP	dd ? ; ring 3 esp
rSSd	dd ? ; ring 3 ss
IOPORTTRAPFRAME ends

RMCSD   struct          ;real mode call structure
rEIP	dd ?
rESP	dd ?
rEFlags dd ?
RMCS <>
RMCSD   ends

;--- in a first step, it might be sufficient to have static storage for 4 port ranges.
?IOTP_COUNT equ 16
?USE_HOST_MEM equ 1 ;use host memory to store trapped stack frame. does not support trap recursion

_DATA16 segment
traptable label byte
 IOPORTTRAP ?IOTP_COUNT dup(<>)

if ?USE_HOST_MEM
trapstack label byte
PUSHADS <>
IOPORTTRAPFRAME <>
endif

intrcontext label byte
RMCSD <>
_DATA16 ends
endif ;if ?PMIOPL eq 0

_DATA32C segment
if ?IRQ_ROUTE
irqroutetable label R3PROC
R3PROC 16 dup({0,0})

irqroutetable_ivt label dword
dword 16 dup (0)
endif
_DATA32C ends

_TEXT32 segment

;*** callback for HDPMI extensions

_I2f168A_Hdpmi proc near public

	push offset iret_with_CF_mod
	cmp ax, MAX168A
	jb @F
	stc
	ret
@@:
	push ebx
	movzx ebx, ax
	mov bx, cs:[ebx*2+offset tab168a]
	add ebx, offset start168a
	xchg ebx,[esp]
	ret
	align 2
tab168a label word
 ifdef _DEBUG
	@wofs is0000
	@wofs is0001
	@wofs is0002
	@wofs is0003
 else
	@wofs error
	@wofs error
	@wofs error
	@wofs error
 endif
	@wofs is0004	; "disable" host

 if ?VM
	@wofs is0005	; set/reset HDPMI=32 (VM)
 else
	@wofs error
 endif

 if ?PMIOPL eq 0

;--- best might be to somewhat copy the API implemented by NTVDM ( see nt_vdd.inc )

;--- ax= 6: alloc IO port trap
;---        cx:e/dx = ring3 exception handler?
;---        bx = ring3 exception handler data seg
;---        si = port start
;---        di = number of ports
;---        out: NC if ok, handle in eax
;--- ax= 7: release IO port trap
;---        edx = handle
;---        out: NC if ok
;--- ax= 8: simulate/untrapped IO (read/write trapped ports)
;---		cl=out val
;---		al=in val (on return)
;---		dx=port
;---		ch=1(out),0(in)
;--- ax= 9: virtualize IRQ
;--- ax=10: devirtualize IRQ
;--- ax=11: install irq route handler
;---		esi = irq number
;---		ecx:edx = handler address
;---		ebx: real mode handler address (can be -1 to skip, 0 to reset)
;--- ax=12: get interrupt context
;---		dx=data segment
;---		edi=target buffer
;--- ax=13: get irq route handler
;---		esi = irq number
;--- return:
;---		ecx:edx = handler address
;---		ebx: real mode handler address (0 or valid)

	@wofs is0006	; trap port range(s)
	@wofs is0007	; release trapped port range(s)
	@wofs is0008	; read/write trapped ports
	@wofs is0009	; virtualize IRQ
	@wofs is000a	; devirtualize IRQ
	@wofs is000b	; irq route
	@wofs is000c	; interrupt context
	@wofs is000d

 endif
MAX168A equ ($ - offset tab168a) / sizeof word

start168a:
error:
	stc
	ret
 ifdef _DEBUG
is0000:
	and ss:fMode2,not FM2_LOG
	ret
is0001:
	or  ss:fMode2,FM2_LOG
	ret
is0002:
	mov ss:traceflgs,bx	;see HDPMI.INC, ?LOG_xxx for flags details
	ret
is0003:
	push ds
	push ss
	pop ds
	call displayhdltab
	pop ds
	ret
 endif
is0004:
	or ss:fMode, FM_DISABLED
	ret

 if ?VM

ENVF_VMB equ 5

is0005:
	test ss:[bEnvFlags], ENVF_VM
	setnz al
	push eax
	mov al, bl
	and al, 1
	shl al, ENVF_VMB
	and ss:bEnvFlags, not ENVF_VM
	or ss:bEnvFlags, al
	call updateclonesize
	pop eax
	ret
 endif

 if ?PMIOPL eq 0

;--- exception handler entered with error code:
;--- bit 0: 0=in, 1=out
;--- bit 1: 0=port in dx, 1= port in bits 8-15
;--- bit 2-3: access 00=byte, 01=word, 10=dword, 11=string
;--- bit 4-7: size of instruction
is0006:
	pushad
	mov ebx, offset taskseg
	movzx edx, ss:[ebx].TSSSEG.wOffs
	add ebx, edx
	movzx esi, si
	movzx ecx, di
	lea eax, [ecx+esi]
	cmp eax, 10000h
	cmc
	jc done_0006
	mov eax, esi
@@:
	bt ss:[ebx], esi; first check status of all ports -
	jc done_0006	; they must all be "untrapped"
	inc esi
	loop @B
	mov esi, eax	; ok, now repeat the loop, this time
	mov cx, di		; the bits are set.
@@:
	bts ss:[ebx], esi
	inc esi
	loop @B

;--- store handler routines and return handle in eax
	sub esi, edi
	lea ebx, [traptable]
@@:
	cmp dword ptr ss:[ebx], 0FFFFFFFFh
	je test2
	jmp next
test2:
	cmp dword ptr ss:[ebx + 4], 0FFFFFFFFh
	je test3
	jmp next
test3:
	cmp dword ptr ss:[ebx + 8], 0FFFFFFFFh
	je @F
next:
	add ebx, sizeof IOPORTTRAP
	cmp ebx, offset traptable + ?IOTP_COUNT * sizeof IOPORTTRAP
	jae fail_0006
	;@printf <"next",lf>
	loop @B
fail_0006:
	mov [esp].PUSHADS.rEAX, 0
	stc
	jmp done_0006
@@: ;found empty slot
	mov ss:[ebx].IOPORTTRAP.portS, si
	add si, di ;end port = start port + count - 1
	dec si
	mov ss:[ebx].IOPORTTRAP.portE, si
	mov eax, [esp].PUSHADS.rECX
	mov ss:[ebx].IOPORTTRAP.sel, ax
	mov eax, [esp].PUSHADS.rEDX
	mov ss:[ebx].IOPORTTRAP.off, eax
	mov eax, [esp].PUSHADS.rEBX
	mov ss:[ebx].IOPORTTRAP.dsel, ax
	mov [esp].PUSHADS.rEAX, ebx ;use table entry addr as handle
	clc

done_0006:
	popad
	ret

is0007:
	pushad

	cmp edx, offset traptable ;check if handle is in the oitable
	jb fail_0007
	cmp edx, offset traptable + ?IOTP_COUNT * sizeof IOPORTTRAP
	jae fail_0007
	jmp @F
fail_0007:
	stc
	jmp done_0007
@@:
	;@printf <"test iobitmap", lf>
	mov ebx, offset taskseg
	movzx ecx, ss:[ebx].TSSSEG.wOffs
	add ebx, ecx
	movzx esi, ss:[edx].IOPORTTRAP.portS
	movzx ecx, ss:[edx].IOPORTTRAP.portE
	lea edi, [ecx+1]
	sub edi, esi
	mov ecx, edi
	lea eax, [ecx+esi]
	cmp eax, 10000h
	cmc
	jc done_0007
	mov eax, esi
@@:
	bt ss:[ebx], esi; first check status of all ports -
	cmc
	jc done_0007	; they must all be "trapped"
	inc esi
	loop @B
	mov esi, eax	; ok, now repeat the loop, this time
	mov cx, di		; the bits are reset.
@@:
	;@printf <"reset ports in iobitmap", lf>
	btr ss:[ebx], esi
	inc esi
	loop @B

	mov dword ptr ss:[edx], 0FFFFFFFFh
	mov dword ptr ss:[edx+4], 0FFFFFFFFh
	mov dword ptr ss:[edx+8], 0FFFFFFFFh
	;@printf <"uninstall done",lf>
	clc
done_0007:
	popad
	ret

is0008:
	test ch, ch
	jz in_0008
	;@printf <"untrapped out %X %b",lf>, dx, cx
	xchg al, cl
	out dx, al
	xchg al, cl
	jmp done_0008
in_0008:
	in al, dx
	;@printf <"untrapped in %X %b",lf>, dx, ax
done_0008:
	stc
	ret

is0009:
is000a:
	stc
	ret
is000b:
ife ?IRQ_ROUTE
	jmp error
endif
	cmp esi, 15
	ja error
	push es
	push byte ptr _CSALIAS_
	pop es
	mov es:[irqroutetable+esi*sizeof R3PROC].R3PROC._Cs, ecx
	mov es:[irqroutetable+esi*sizeof R3PROC].R3PROC._Eip, edx
	cmp ebx, 0FFFFFFFFh
	je @F
	mov es:[irqroutetable_ivt + esi*4], ebx
@@:
	pop es
	clc
	ret
is000c:
	push ds
	push es
	push esi
	push edi
	push ecx

	mov es, dx
	push ss
	pop ds
	mov esi, offset intrcontext
	mov ecx, sizeof RMCSD
	cld
	rep movsb

	pop ecx
	pop edi
	pop esi
	pop es
	pop ds
	clc
	ret
is000d:
	cmp esi, 15
	ja error
	push es
	push byte ptr _CSALIAS_
	pop es
	mov ecx, es:[irqroutetable+esi*sizeof R3PROC].R3PROC._Cs
	mov edx, es:[irqroutetable+esi*sizeof R3PROC].R3PROC._Eip
	mov ebx, es:[irqroutetable_ivt + esi*4]
	pop es
	clc
	ret
 endif ;if ?PMIOPL eq 0
_I2f168A_Hdpmi endp


if ?PMIOPL eq 0

; get operande size from selector type (32/64) in ES, and prefix flag in CH (1 if has prefix, 0 if not)
; input:
;	BL: instruction
;	ES: client CS
;	CH: 66h prefix (1: with prefix, 0: without prefix)
; return operand size (1/2/4) in CH
_I2f168A_Hdpmi_GetOprandSize proc near
	pushf

	test bl, 01h ;0E5 0E7 0ED 0EF ? (AL)
	jnz @F
	mov ch, 1
	jmp _I2f168A_Hdpmi_GetOprandSize_End
@@: ;for AX/EAX, need to check the descriptor type(16/32) of faulted cs sel, and the oprand size prefix 66h
	push ebx
	push eax
	push ds

	push byte ptr _FLATSEL_
	pop ds
	push byte ptr _LDTSEL_
	pop eax
	mov ebx, offset pdGDT.dwBase ;get ldtr in gdt
	mov ebx, ss:[ebx]
	add ebx, eax

	mov ah, [ebx].DESCRPTR.A2431 ;read ldt base addr
	mov al, [ebx].DESCRPTR.A1623
	shl eax, 16
	mov ax, [ebx].DESCRPTR.A0015
	xor ebx, ebx
	mov bx, es
	and bx, 0FFF8h ;get es sel's descriptor in ldt
	add ebx, eax

	test [ebx].DESCRPTR.lim_gr, 040h	;32 bit descritor?
	jnz @F
	;16bit: ch = ch*2 + 2
	shl ch, 1
	add ch, 2
@@: ;32bit ch = 4 - ch*2
	shl ch, 1
	neg ch
	add ch, 4
	
	pop ds
	pop eax
	pop ebx
_I2f168A_Hdpmi_GetOprandSize_End:
	popf
	ret
_I2f168A_Hdpmi_GetOprandSize endp

;check falted CS:EIP if it is IN/OUT instruction
;and find the port operand in traptable to call the handler
;finnally advance EIP with opcode size to skip the instruction and return to client execution
_I2f168A_Hdpmi_InOutExcHandler proc near public
	push ds
	push es
	push ebx ;end of IOPORTTRAPFRAME
	xor ebx, ebx
	pushad
	xor ecx, ecx

	mov ebx, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rCSd ;check instructions for IN/OUT. TODO: check [REP] INS/OUTS
	mov es, bx
	mov ebx, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rEIP
	mov ebx, es:[ebx] 

	cmp bl, 066h ;check prefix
	jne @F
	shr ebx, 8
	mov ecx, 0100h ;ch=1, prefix used.
@@:
	cmp bl, 0E4h	;in al, imm8
	je setdx
	cmp bl, 0E5h	;in ax/eax, imm8
	je setdx
	cmp bl, 0E6h	;out imm8, al
	je setdxout
	cmp bl, 0E7h	;out imm8, ax/eax
	je setdxout
	cmp bl, 0ECh	;in al, dx
	je dxset
	cmp bl, 0EDh	;in ax/eax, dx
	je dxset
	cmp bl, 0EEh	;out dx, al
	je dxsetout
	cmp bl, 0EFh	;out dx, ax/eax
	je dxsetout
	jmp _I2f168A_Hdpmi_InOutExcHandler_done ;nothing todo
setdxout:
	mov cl, 1 ;out=1
setdx:
	xor dh, dh ;set imm8 port to dx
	mov dl, bh
	add ch, 2  ;1 byte op + 1 byte oprand(imm8) + prefix byte(if exist)
	mov byte ptr [esp].PUSHADS.rEBX, ch
	sub ch, 2
	jmp @F
dxsetout:
	mov cl, 1
dxset: ;dx already set
	inc ch ;1 byte op + prefix byte(if exist)
	mov byte ptr [esp].PUSHADS.rEBX, ch
	dec ch
@@:

	call _I2f168A_Hdpmi_GetOprandSize ;get oprand size in ch (1/2/4) (al/ax/eax)
	mov ebx, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rSSd ;load ring3 ss for later use
	mov es, bx
	lea ebx, [traptable]
tableloop:
	cmp dx, ss:[ebx].IOPORTTRAP.portS ;check port >= portS && port+count-1 <= portE. don't handle ports across traptable entry
	jb tablenext
	movzx esi, ch
	dec si
	add si, dx
	cmp si, ss:[ebx].IOPORTTRAP.portE
	ja tablenext
	jmp @F
tablenext:
	add ebx, sizeof IOPORTTRAP
	cmp ebx, offset traptable + ?IOTP_COUNT * sizeof IOPORTTRAP
	jae _I2f168A_Hdpmi_InOutExcHandler_notfound ;not found in table
	jmp tableloop
 _I2f168A_Hdpmi_InOutExcHandler_notfound:
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done
@@:

	; copy stack to client. 
	; note: after trap handler returns from ring3 to _I2f168A_Hdpmi_InOutExcHandler_back,
	; the original ring0 stack was lost (new entering). so save the stack frame to ring3 stack.
if ?USE_HOST_MEM
	mov edi, ss
	mov es, di
	mov edi, offset trapstack + sizeof PUSHADS + sizeof IOPORTTRAPFRAME
else
	mov edi, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rSSd ;es:edi
	mov es, di
	mov edi, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rESP
endif
	mov esi, esp ; ds:esi
	push eax ;do not copy these
	push ecx
	push ds
	push ss
	pop ds

	mov ecx, (sizeof PUSHADS + sizeof IOPORTTRAPFRAME) / 4
	sub edi, (sizeof PUSHADS + sizeof IOPORTTRAPFRAME)
	rep movsd

	pop ds
	pop ecx
	pop eax

	mov ebp, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rESP
if ?USE_HOST_MEM
	mov edi, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rSSd
	mov es, di
else
	sub ebp, sizeof PUSHADS + sizeof IOPORTTRAPFRAME ;now es:ebp == ring3 stack top
	;mov [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rESP, ebp
endif

	add esp, sizeof PUSHADS + sizeof IOPORTTRAPFRAME ;stack vals not used after copy.

	movzx edx, dx
	movzx esi, ch
	movzx ecx, cl; ch: counter:0

	mov es:[ebp-4], edx
	mov es:[ebp-8], ecx
	sub ebp, 8

	push dword ptr ss:[ebx].IOPORTTRAP.dsel ;setup handler DS
	pop ds

portloop: ;iterate ports and do 1 byte at a time.

	;call the registerred handler by simluate a IRET frame.
	;INPUT: eax=val (out), edx=port, ecx=out. 
	;OUTPUT: return eax for IN, or original eax for OUT (compatible parameters for EMM386)
	push es ;ring 3 ss
	push ebp ;ring 3 esp
if ?USE_HOST_MEM
	push ss:[trapstack + sizeof PUSHADS].IOPORTTRAPFRAME.rEFL
else
	push es:[ebp + 8 + sizeof PUSHADS].IOPORTTRAPFRAME.rEFL ;eflags (skip pushad + edx + ecx on stack)
endif
	;or dword ptr [esp], 03000h ;change IOPL to 3. Allow handler to do the actually port IO if needed, otherwise it's a recursion -- UPDATE: now use untrapped IO functions, don't use IOPL3
	and dword ptr [esp], not 0300h ;disable interrupt & trap
	push dword ptr ss:[ebx].IOPORTTRAP.sel
	push ss:[ebx].IOPORTTRAP.off

	;put _I2f168A_Hdpmi_InOutExcHandler_back onto the ring 3 stack
	;so that the port trap handler can return to _I2f168A_Hdpmi_InOutExcHandler_back with RETF
	mov word ptr es:[ebp-4], _INTSEL_
	mov dword ptr es:[ebp-8], _I2F168A_HDPMI_IOTP_BACK
	sub dword ptr [esp+12], 8 ;ring 3 esp -= 8

	;need set ES too, or something will be wrong.
	;the handler can set its own SS:ESP or use trapped client's stack
	push ds
	pop es

	iretd ;execution path will eventually get to _I2f168A_Hdpmi_InOutExcHandler_back
_I2f168A_Hdpmi_InOutExcHandler_back::
	push [esp + 16] ; restore ring3 SS
	pop es
	add esp, 20 ; clear call stack, not needed

	mov ecx, es:[ebp]
	test cl, cl ;don't save eax for OUT
	jnz @F
	movzx cx, ch ;IN
	shl cx, 3;imul cx, cx, 8
	and eax, 0FFh ;eax = (eax&0xFF) << 8*ch.
	shl eax, cl
	mov edx, 0FFh
	shl edx, cl
	not edx
if ?USE_HOST_MEM
	and ss:[trapstack].PUSHADS.rEAX, edx
	or ss:[trapstack].PUSHADS.rEAX, eax
else
	and es:[ebp+8].PUSHADS.rEAX, edx
	or es:[ebp+8].PUSHADS.rEAX, eax ;IN: save returned value to stack
endif
	mov ecx, es:[ebp]
@@:
	shr eax, 8 ; OUT: for an OUT instruction, eax should not be changed by handler. TODO: save eax
	inc ch ;counter
	mov es:[ebp], ecx
	movzx ecx, cl
	mov edx, es:[ebp+4]
	inc edx ;next port
	mov es:[ebp+4], edx
	dec esi
	jnz portloop

	;pushf ;change IOPL flag to 0 ;original trapped flag is IOPL0
	;and word ptr [esp], 0CFFFh
	;popf

	;copy ring3 stack back to ring0 stack
if ?USE_HOST_MEM
	mov esi, ss
	mov ds, si
	mov esi, offset trapstack
else
	push es ;ds:esi
	pop ds
	lea esi, [ebp + 8]
endif
	push ss ;es:edi
	pop es
	mov edi, esp

	mov ecx, (sizeof PUSHADS + sizeof IOPORTTRAPFRAME) / 4
	sub edi, (sizeof PUSHADS + sizeof IOPORTTRAPFRAME)
	mov esp, edi
	rep movsd

_I2f168A_Hdpmi_InOutExcHandler_done:
	popad
	add [esp].IOPORTTRAPFRAME.rEIP, ebx ;advance (e)ip
	test ebx, ebx
	pop ebx
	pop es
	pop ds
	jnz @F
	ret
@@:
	add esp, 8 ;skip return addr + error code
	iretd
_I2f168A_Hdpmi_InOutExcHandler endp


_I2f168A_Hdpmi_CaptureContext proc near public
	mov ss:[intrcontext].RMCSD.rEAX, eax
	mov ss:[intrcontext].RMCSD.rECX, ecx
	mov ss:[intrcontext].RMCSD.rEDX, edx
	mov ss:[intrcontext].RMCSD.rEBX, ebx
	mov ss:[intrcontext].RMCSD.rEBP, ebp
	mov ss:[intrcontext].RMCSD.rESI, esi
	mov ss:[intrcontext].RMCSD.rEDI, edi
	;@printf <"segments",lf>
	push word ptr [esp+4].IRET32.rCS
	pop word ptr ss:[intrcontext].RMCSD.rCS
	push word ptr [esp+4].IRET32.rSS
	pop word ptr ss:[intrcontext].RMCSD.rSS
	push [esp+4].IRET32.rFL
	pop ss:[intrcontext].RMCSD.rEFlags

	;@printf <"EFLAGS: %lX",lf>, dword ptr [esp+4].IRET32.rFL
	test [esp+4].IRET32.rFL, 20000h ; VM?
	jz pmsave
	;@printf <"rmsave",lf>
	push word ptr [esp+4].IRET32.rFL
	pop word ptr ss:[intrcontext].RMCSD.rFlags
	push word ptr [esp+4].IRET32.rSP
	pop word ptr ss:[intrcontext].RMCSD.rSP
	push word ptr [esp+4].IRET32.rIP
	pop word ptr ss:[intrcontext].RMCSD.rIP

	push word ptr [esp+4+IRET32]
	pop word ptr ss:[intrcontext].RMCSD.rES
	push word ptr [esp+4+IRET32+4]
	pop word ptr ss:[intrcontext].RMCSD.rDS
	push word ptr [esp+4+IRET32+8]
	pop word ptr ss:[intrcontext].RMCSD.rFS
	push word ptr [esp+4+IRET32+12]
	pop word ptr ss:[intrcontext].RMCSD.rGS
	jmp done
pmsave:
	;@printf <"pmsave",lf>
	push [esp+4].IRET32.rSP
	pop ss:[intrcontext].RMCSD.rESP
	push [esp+4].IRET32.rIP
	pop ss:[intrcontext].RMCSD.rEIP
	push eax
	mov eax, ds
	mov ss:[intrcontext].RMCSD.rDS, ax
	mov eax, es
	mov ss:[intrcontext].RMCSD.rES, ax
	mov eax, fs
	;@printf <"FS: %X",lf>, ax
	mov ss:[intrcontext].RMCSD.rFS, ax
	mov eax, gs
	;@printf <"GS: %X",lf>, ax
	mov ss:[intrcontext].RMCSD.rGS, ax
	pop eax
done:
	ret
_I2f168A_Hdpmi_CaptureContext endp

_I2f168A_Hdpmi_CaptureContextV86 proc public
	mov ss:[intrcontext].RMCSD.rEAX, eax
	mov ss:[intrcontext].RMCSD.rECX, ecx
	mov ss:[intrcontext].RMCSD.rEDX, edx
	mov ss:[intrcontext].RMCSD.rEBX, ebx
	mov ss:[intrcontext].RMCSD.rEBP, ebp
	mov ss:[intrcontext].RMCSD.rESI, esi
	mov ss:[intrcontext].RMCSD.rEDI, edi

	push eax
	mov eax, ss:[v86iret].rEFL
	mov ss:[intrcontext].RMCSD.rFlags, ax
	;or eax, 20000h ;VM must be set
	mov ss:[intrcontext].RMCSD.rEFlags, eax
	mov ax, ss:[v86iret].rCS
	mov ss:[intrcontext].RMCSD.rCS, ax
	mov ax, ss:[v86iret].rSS
	mov ss:[intrcontext].RMCSD.rSS, ax

	mov ax, ss:[v86iret].rIP
	mov ss:[intrcontext].RMCSD.rIP, ax
	mov ax, ss:[v86iret].rSP
	mov ss:[intrcontext].RMCSD.rSP, ax

	mov ax, ss:[v86iret].rDS
	mov ss:[intrcontext].RMCSD.rDS, ax
	mov ax, ss:[v86iret].rES
	mov ss:[intrcontext].RMCSD.rES, ax
	mov ax, ss:[v86iret].rFS
	mov ss:[intrcontext].RMCSD.rFS, ax
	mov ax, ss:[v86iret].rGS
	mov ss:[intrcontext].RMCSD.rGS, ax
	pop eax
	ret
_I2f168A_Hdpmi_CaptureContextV86 endp

endif ;if ?PMIOPL eq 0

if ?IRQ_ROUTE
_I2f168A_Hdpmi_UpdateIRQRoute proc near public
	push es
	pushfd
	push edx
	push eax
	push ebx
	push ecx
	push edi
	cli

	push byte ptr _CSALIAS_
	pop es

	mov dx, 4D1h
	in al, dx
	mov ah, al
	dec dx
	in al, dx
	test ax, 2107h
	jnz done
	
	mov ecx, 16
@@:
	dec cl
	bt ax, cx
	jnc next
	mov ebx, ecx
	@dprintf <"BX: %b ">, bx

	;irq will be skipped if already set
	cmp es:[irqroutetable + ebx*sizeof R3PROC].R3PROC._Cs, 0
	jne skippm

	;load pm vector from r3vectxx and store to irqroutetable
	mov edx, ebx
	cmp ebx, 07h
	ja slavepm
	@dprintf <"MPM %X ">, dx
	mov edi, es:[r3vect08 + edx*sizeof R3PROC].R3PROC._Cs
	mov edx, es:[r3vect08 + edx*sizeof R3PROC].R3PROC._Eip
	jmp setpmvec
slavepm:
	sub edx, 8
	@dprintf <"SPM %X ">, dx
	mov edi, es:[r3vect70 + edx*sizeof R3PROC].R3PROC._Cs
	mov edx, es:[r3vect70 + edx*sizeof R3PROC].R3PROC._Eip
setpmvec:
	@dprintf <"DI: %X, EDX: %lX ">, di, edx

	mov es:[irqroutetable + ebx*sizeof R3PROC].R3PROC._Cs, edi
	mov es:[irqroutetable + ebx*sizeof R3PROC].R3PROC._Eip, edx
skippm:

	cmp es:[irqroutetable_ivt + ebx*4], 0
	jne skiprm

	;load rm vector from IVT and store to irqroutetable_ivt
	mov edx, ebx
	cmp ebx, 07h
	ja slaverm
	add edx, 8 ; irq to vec
	@dprintf <"MRM %X ">, dx
	jmp setrmvec
slaverm:
	add edx, 68h
	@dprintf <"SRM %X ">, dx
setrmvec:
	shl edx, 2 ;*4
	sub edx, ss:[dwSSBase]
	mov edx, ss:[edx]

	@dprintf <"EDX: %lX",lf>, edx

	mov es:[irqroutetable_ivt + ebx*4], edx
skiprm:


next:
	test cl, cl
	jnz @B
done:
	pop edi
	pop ecx
	pop ebx
	pop eax
	pop edx
	popfd
	pop es
	ret
_I2f168A_Hdpmi_UpdateIRQRoute endp
endif ;if ?IRQ_ROUTE

_TEXT32 ends


endif ;if ?VENDORAPI

end
