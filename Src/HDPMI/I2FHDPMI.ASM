
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
sel dw -1
off dd -1
IOPORTTRAP ends
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
IOTP_COUNT equ 4
iotable label byte
 IOPORTTRAP IOTP_COUNT dup(<>)

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
	lea ebx, [iotable]
@@:
	mov eax, [ebx]
	cmp eax, 0FFFFFFFFh
	je test2
	jmp fail_0006
test2:
	mov eax, [ebx + 4]
	cmp eax, 0FFFFFFFFh
	je @F
	add ebx, sizeof IOPORTTRAP
	lea eax, [iotable + sizeof IOPORTTRAP * IOTP_COUNT]
	cmp eax, ebx
	jbe fail_0006
	loop @B
fail_0006:
	xor eax, eax
	stc
	jmp done_0006
@@: ;found empty slot
	mov [ebx].IOPORTTRAP.portS, si
	add si, di ;end port = start port + count - 1
	dec si
	mov [ebx].IOPORTTRAP.portE, si
	mov eax, [esp].PUSHADS.rECX
	mov [ebx].IOPORTTRAP.sel, ax
	mov [ebx].IOPORTTRAP.off, edx
	mov eax, ebx ;use table entry addr as handle
	clc

done_0006:
	popad
	ret

is0007:
	pushad

	cmp edx, offset iotable ;check if handle is in the oitable
	jb fail_0007
	cmp edx, offset iotable + sizeof IOPORTTRAP * IOTP_COUNT
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

	mov dword ptr [edx], 0FFFFFFFFh
	mov dword ptr [edx+4], 0FFFFFFFFh
	mov word ptr [edx+8], 0FFFFh
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

; get operande size from selector type (32/64) in ES, and prefix flag in CH (1 if has prefix, 0 if not)
; input:
;	ES
;	CH
; return operand size in CH
_I2f168A_Hdpmi_GetOprandSize proc near
	pushf
	push ebx
	push ds

	sldt bx
	mov ds, bx
	mov bx, es
	and bx, 0FFF8h
	test [bx].DESCRPTR.lim_gr, 040h	;32 bit descritor?
	jnz @F
	;16bit: ch = ch*2 + 2
	shl ch, 1
	add ch, 2
@@: ;32bit ch = 4 - ch*2
	shl ch, 1
	neg ch
	add ch, 4
	
	pop ds
	pop ebx
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
; we can assume a 32bit cs for dhpmi32 (and dpmi16 vice versa) but it is not always the case.
_I2f168A_Hdpmi_InOutExcHandler proc near public
	pushad
	and ecx, 0100h ;CL:in=0, CH:prefix/count
	cmp bl, 0E4h	;in al, imm8
	mov ch, 1
	je setdx
	cmp bl, 0E5h	;in ax/eax, imm8
	call _I2f168A_Hdpmi_GetOprandSize
	je setdx
	cmp bl, 0E6h	;out imm8, al
	mov ch, 1
	je setdxout
	cmp bl, 0E7h	;out imm8, ax/eax
	call _I2f168A_Hdpmi_GetOprandSize
	je setdxout
	cmp bl, 0ECh	;in al, dx
	mov ch, 1
	je dxset
	cmp bl, 0EDh	;in ax/eax, dx
	call _I2f168A_Hdpmi_GetOprandSize
	je dxset
	cmp bl, 0EEh	;out dx, al
	mov ch, 1
	je dxsetout
	cmp bl, 0EFh	;out dx, ax/eax
	call _I2f168A_Hdpmi_GetOprandSize
	je dxsetout
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done ;nothing todo
setdxout:
	mov cl, 1 ;out=1
setdx:
	xor dh, dh
	mov dl, bh
	mov [esp].PUSHADS.rEBX, 2 ;1 byte opcode + 1 byte oprand
	mov ch, 1 ;count
	jmp @F
dxsetout:
	mov cl, 1
dxset: ;dx already set
	mov [esp].PUSHADS.rEBX, 1 ;1 byte opcode
@@:
	lea ebx, [iotable]
tableloop:
	cmp dx, [ebx].IOPORTTRAP.portS ;check dx(port) >= portS && dx(port)+count <= portE
	jb tablenext
	push dx
	push cx
	xor cl, cl
	xchg cl, ch
	add dx, cx
	cmp dx, [ebx].IOPORTTRAP.portE
	pop cx
	pop dx
	ja tablenext
	jmp @F
tablenext:
	add ebx, sizeof IOPORTTRAP
	cmp ebx, offset iotable + sizeof IOPORTTRAP * IOTP_COUNT
	jae _I2f168A_Hdpmi_InOutExcHandler_notfound ;not found in table
	jmp tableloop
 _I2f168A_Hdpmi_InOutExcHandler_notfound:
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done
@@:
	movzx edx, dx
	movzx ebp, ch
	xor ch, ch

	pushf ;change IOPL flag to 3
	or word ptr [esp], 03000h
	popf

	test cl, cl ;IN?
	jnz portloop
	mov [esp].PUSHADS.rEAX, 0

portloop: ;iterate ports and do 1 byte at a time. don't handle ports across iotable entry
	push eax ;those are not stack parameters, just save them
	push edx
	push ecx
	xor ch, ch
	call far ptr [ebx].IOPORTTRAP.sel ;call the registerred handler, eax=val (out), edx=port, ecx=out. return eax for IN
	pop ecx
	push ecx

	push eax
	movzx eax, ch
	imul ax, ax, 8
	mov cl, al
	pop eax
	and eax, 0FFh ;eax = (eax&0xFF) << 8*ch
	shl eax, cl

	pop ecx
	inc ch
	pop edx
	test cl, cl ;don't save eax for OUT
	jnz @F
	or [esp+4].PUSHADS.rEAX, eax ;IN: save returned value to stack
	mov [esp], eax
@@:
	pop eax ;OUT, keep old eax
	inc edx ;next port
	dec ebp
	jo _I2f168A_Hdpmi_InOutExcHandler_done
	jmp portloop

	pushf ;change IOPL flag to 0
	and word ptr [esp], 0CFFFh
	popf

_I2f168A_Hdpmi_InOutExcHandler_done:
	popad
	ret
_I2f168A_Hdpmi_InOutExcHandler endp
endif

_TEXT32 ends

endif

end
