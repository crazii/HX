
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
IOPORTTRAP ends

IOTP_COUNT equ 4

_DATA16 segment
traptable label byte
 IOPORTTRAP IOTP_COUNT dup(<>)
_DATA16 ends
endif

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
;---        si = port start
;---        di = number of ports
;---        out: NC if ok, handle in eax
;--- ax= 7: release IO port trap
;---        edx = handle
;---        out: NC if ok
;--- ax= 8: simulate IO (read/write trapped ports)
;--- ax= 9: virtualize IRQ
;--- ax=10: devirtualize IRQ

	@wofs is0006	; trap port range(s)
	@wofs is0007	; release trapped port range(s)
;	@wofs is0008	; read/write trapped ports
;	@wofs is0009	; virtualize IRQ

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

;--- todo: store handler routines and return handle in eax
;--- in a first step, it might be sufficient to have static storage for 4 port ranges.
	sub esi, edi
	lea ebx, [traptable]
@@:
	cmp dword ptr ss:[ebx], 0FFFFFFFFh
	je test2
	jmp fail_0006
test2:
	cmp dword ptr ss:[ebx + 4], 0FFFFFFFFh
	je test3
	jmp fail_0006
test3:
	cmp word ptr ss:[ebx + 8], 0FFFFh
	je @F
	add ebx, sizeof IOPORTTRAP
	cmp ebx, offset traptable + sizeof IOPORTTRAP * IOTP_COUNT
	jbe fail_0006
	loop @B
fail_0006:
	xor eax, eax
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
	mov eax, ebx ;use table entry addr as handle
	clc

done_0006:
	popad
	ret

is0007:
	pushad

	cmp edx, offset traptable ;check if handle is in the oitable
	jb fail_0007
	cmp edx, offset traptable + sizeof IOPORTTRAP * IOTP_COUNT
	jae fail_0007
	jmp @F
fail_0007:
	stc
	jmp done_0007
@@:
	mov ebx, offset taskseg
	movzx edx, ss:[ebx].TSSSEG.wOffs
	add ebx, edx
	movzx esi, si
	movzx ecx, di
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
	btr ss:[ebx], esi
	inc esi
	loop @B

	mov dword ptr ss:[edx], 0FFFFFFFFh
	mov dword ptr ss:[edx+4], 0FFFFFFFFh
	mov word ptr ss:[edx+8], 0FFFFh
	clc
done_0007:
	popad
	ret

is0008:
is0009:
	stc
	ret
 endif
 
_I2f168A_Hdpmi endp


if ?PMIOPL eq 0

IOPORTTRAPFRAME struct
		dd ? ; EBX. local. match the entry of _I2f168A_Hdpmi_InOutExcHandler
		dd ? ; ES. local. match the entry of _I2f168A_Hdpmi_InOutExcHandler
		dd ? ; return addr of _I2f168A_Hdpmi_InOutExcHandler's caller
rError	dd ? ; error code of 0D(#GP) except 
rEIP	dd ? ; faulted eip
rCSd	dd ? ; faulted cs
rEFL	dd ? ; eflags
rESP	dd ? ; ring 3 esp
rSSd	dd ? ; ring 3 ss
IOPORTTRAPFRAME ends

; get operande size from selector type (32/64) in ES, and prefix flag in CH (1 if has prefix, 0 if not)
; input:
;	BL opcode
;	ES
;	CH
; return operand size in CH
_I2f168A_Hdpmi_GetOprandSize proc near
	pushf

	test bl, 01h ;0E5 0E7 0ED 0EF ?
	jnz @F
	mov ch, 1
	jmp _I2f168A_Hdpmi_GetOprandSize_End
@@:
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

; input:
; 	bl: opcode
; 	bh: oprand (if exist)
; 	eax: in/out value
;	ch: prefix (066h)
; 	dx: port (or not used for immediate oprand)
; 	es: trapped cs
;return:
; 	ebx: 0 if not handled, > 0 used to advance cs:eip 
; 	eax for IN value if ebx > 0, otherwise not modified
; for ax/eax, need to check the descriptor type(16/32) of faulted cs sel, and the oprand size prefix 66h
; note: keep esi/edi available for strring ops
_I2f168A_Hdpmi_InOutExcHandler proc near public
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
	add ch, 2  ;1 byte opcode + 1 byte oprand + prefix byte(if exist)
	mov byte ptr [esp].PUSHADS.rEBX, ch
	sub ch, 2
	jmp @F
dxsetout:
	mov cl, 1
dxset: ;dx already set
	add ch, 1 ;1 byte opcode + prefix byte(if exist)
	mov byte ptr [esp].PUSHADS.rEBX, ch
	dec ch
@@:
	call _I2f168A_Hdpmi_GetOprandSize ;get oprand size in ch (1/2/4) (al/ax/eax)
	mov ebx, [esp + sizeof PUSHADS].IOPORTTRAPFRAME.rSSd ;load ring3 ss for later use
	mov es, bx
	lea ebx, [traptable]
tableloop:
	cmp dx, ss:[ebx].IOPORTTRAP.portS ;check port >= portS && port+count <= portE. don't handle ports across traptable entry
	jb tablenext
	push dx
	push cx
	movzx cx, ch
	add dx, cx
	cmp dx, ss:[ebx].IOPORTTRAP.portE
	pop cx
	pop dx
	ja tablenext
	jmp @F
tablenext:
	add ebx, sizeof IOPORTTRAP
	cmp ebx, offset traptable + sizeof IOPORTTRAP * IOTP_COUNT
	jae _I2f168A_Hdpmi_InOutExcHandler_notfound ;not found in table
	jmp tableloop
 _I2f168A_Hdpmi_InOutExcHandler_notfound:
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done
@@:
	movzx edx, dx
	movzx ebp, ch
	xor ch, ch ; counter:0

	test cl, cl ;IN?
	jnz portloop
	mov [esp].PUSHADS.rEAX, 0

portloop: ;iterate ports and do 1 byte at a time.
	push edx
	push ecx
	xor ch, ch

	;call the registerred handler by simluate a IRET frame.
	;INPUT: eax=val (out), edx=port, ecx=out. 
	;OUTPUT: return eax for IN, or original eax for OUT (compatible parameters for EMM386)
	push es ;ring 3 ss
	push [esp + sizeof PUSHADS + 8 + 4].IOPORTTRAPFRAME.rESP ;ring 3 esp  (skip pushad + edx + ecx on stack)
	push [esp + sizeof PUSHADS + 8 + 4 + 4].IOPORTTRAPFRAME.rEFL ;eflags
	or dword ptr [esp], 03000h ;change IOPL to 3
	push dword ptr ss:[ebx].IOPORTTRAP.sel
	push ss:[ebx].IOPORTTRAP.off

	;put cs:back2ring0 and a ring 3 return address(cs3:_I2f168A_Hdpmi_InOutExcHandlerWrapper) onto the ring 3 stack
	;so that the port trap handler can return to back2ring0 with RETF
	push ebx
	mov ebx, [esp+16] ;load ring3 esp
	mov word ptr es:[ebx-4], cs
	mov dword ptr es:[ebx-8], offset back2ring0
	mov word ptr es:[ebx-12], _CSR3SEL_
	;push byte ptr _CSR3SEL_
	;pop dword ptr es:[ebx-12]
	mov dword ptr es:[ebx-16], offset _I2f168A_Hdpmi_InOutExcHandlerWrapper
	sub dword ptr [esp+16], 16
	pop ebx

	iretd
back2ring0:
	add esp, 16 ; clear call stack, not needed

	mov ecx, [esp]
	movzx cx, ch
	imul cx, cx, 8
	and eax, 0FFh ;eax = (eax&0xFF) << 8*ch.
	shl eax, cl ; for an OUT instruction, eax should not change by handler, so that we shift both in/out data here

	pop ecx
	inc ch ;counter
	pop edx
	test cl, cl ;don't save eax for OUT
	jnz @F
	or [esp].PUSHADS.rEAX, eax ;IN: save returned value to stack
@@:
	inc edx ;next port
	dec ebp
	jo @F
	jmp portloop
@@:
	pushf ;change IOPL flag to 0
	and word ptr [esp], 0CFFFh
	popf

_I2f168A_Hdpmi_InOutExcHandler_done:
	popad
	add [esp].IOPORTTRAPFRAME.rEIP, ebx ;advance (e)ip
	test ebx, ebx
	pop ebx
	pop es
	jnz @F
	ret
@@:
	add esp, 8 ;skip return addr + error code
	iretd
_I2f168A_Hdpmi_InOutExcHandler endp
endif

_TEXT32 ends


_TEXT32R3 segment

_I2f168A_Hdpmi_InOutExcHandlerWrapper proc near ;handler exiting wrapper, need a far return from handler

	add esp, 8 ;need pop the stack
	call fword ptr [esp-8] ;call back to ring 0

_I2f168A_Hdpmi_InOutExcHandlerWrapper endp

_TEXT32R3 ends


endif

end
