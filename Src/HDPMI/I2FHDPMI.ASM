
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
ports dw -1
porte dw -1
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
	mov [ebx].IOPORTTRAP.ports, si
	mov [ebx].IOPORTTRAP.porte, di
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

	lea ebx, [iotable] ;check if handle is in the oitable
	cmp edx, ebx
	jb fail_0007
	lea ebx, [iotable + sizeof IOPORTTRAP * IOTP_COUNT]
	cmp edx, ebx
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


; bl: opcode
; bh: oprand (if exist)
; eax: in/out value
; dx: port
; return: ebx: 0 if not handled, > 0 used to advance cs:eip 
; return eax for IN value if ebx > 0, otherwise not modified
; for ax/eax, need to check the descriptor type(16/32) of faulted cs sel, and the oprand size prefix 66h
; we can assume a 32bit cs for dhpmi32 (and dpmi16 vice versa)
_I2f168A_Hdpmi_InOutExcHandler proc near public
	pushad
	lea ebp, [iotable + sizeof IOPORTTRAP * IOTP_COUNT]
	xor ecx, ecx ;in=0
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
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done ;nothing todo
setdxout:
	mov ecx, 1 ;out=1
setdx:
	xor dh, dh
	mov dl, bh
	mov [esp].PUSHADS.rEBX, 2 ;1 byte opcode + 1 byte oprand
	jmp @F
dxsetout:
	mov ecx, 1
dxset: ;dx already set
	mov [esp].PUSHADS.rEBX, 1 ;1 byte opcode
@@:
	lea ebx, [iotable]
tableloop:
	cmp [ebx].IOPORTTRAP.ports, dx
	ja tablenext
	cmp [ebx].IOPORTTRAP.porte, dx
	jbe tablenext
	jmp @F
tablenext:
	add ebx, sizeof IOPORTTRAP
	cmp ebp, ebx
	jae _I2f168A_Hdpmi_InOutExcHandler_notfound ;not found in table
	jmp tableloop
 _I2f168A_Hdpmi_InOutExcHandler_notfound:
	mov [esp].PUSHADS.rEBX, 0
	jmp _I2f168A_Hdpmi_InOutExcHandler_done
@@:
	movzx edx, dx
	push ecx
	; TODO: change IOPL flag to 3
	; TODO: use errorcode to indicate operand size (byte/word/dw/string)
	call far ptr [ebx].IOPORTTRAP.sel ;call the registerred handler, eax=val (out), edx=port, ecx=out. return eax for IN
	pop ecx
	test ecx, ecx ;don't save eax for OUT
	jnz _I2f168A_Hdpmi_InOutExcHandler_done
	mov [esp].PUSHADS.rEAX, eax ;save returned value to stack

_I2f168A_Hdpmi_InOutExcHandler_done:
	popad
	ret
_I2f168A_Hdpmi_InOutExcHandler endp

_TEXT32 ends

endif

end
