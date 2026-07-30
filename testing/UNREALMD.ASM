;-----------------------------
; Unreal Mode Addressing Test
;-----------------------------

    use16                          ; Prefixes 66h/67h on 32-bit instructions
    org   100h                     ; .COM file

    ; Test for non Unreal Mode
;    push  fs
;    jmp   test
    
    
    ;-----------------------------------------------------------
    ; Calculate GDT Linear Address (DS * 16 + gdt_start)
    ;-----------------------------------------------------------
    xor   eax,eax
    mov   ax,cs                    ; Copies GDT segment to AX
    shl   eax,4                    ; Multiplies DS by 16
    add   eax,gdt_start            ; Adds GDT offset
    mov   [gdt_base_address],eax   ; Updates the pointer


    ;-----------------------------------------------------------
    ; Sets up the Unreal Mode in FS Register
    ;-----------------------------------------------------------
    cli                            ; Clears interrupts (MANDATORY!)
    push  fs                       ; Saves FS Real Mode value

    lgdt  [gdt_descriptor]         ; Loads GDT with the absolute address

    mov   eax,cr0
    push  eax                      ; Saves CR0 content
    or    al,1                     ; EAX Bit 0 (PE) = 1
    mov   cr0,eax                  ; Turn on Protected Mode
    jmp   $+2                      ; Clears pipeline

    mov   ax,0008h
    mov   fs,ax                    ; Loads FS with the Cache Descriptor Selector

;    mov   eax,cr0
;    and   al,0FEh
    pop   eax
    mov   cr0,eax                  ; Restores the original CR0 PE bit
    jmp   $+2                      ; Clears pipeline
    sti

test:    
    mov   ebx,10000000h            ; Test address 256 MB
                                   ; (An alleatory address higher that 64 MB)
    mov   ecx,55AA55AAh
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; Tests if FS:EBX is equal ECX
    mov   dx,error1_msg
    jne   show_msg    

    not   ecx                      ; Inverts ECX value
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; New comparating with inverted value
    mov   dx,error2_msg
    jne   show_msg                 ; FS:EBX is different of ECX
    
    ; Reload FS with another value in Real Mode DOES NOT destroys
    ; the Unreal Mode from register, but the Real Mode starts to
    ; use the segment pointed by the register, exiting from the
    ; segment reference zero, turning the register to be reloaded
    ; with zero to return for the linear addressing (reference 0).
    pop   fs
    push  fs
    mov   ax,0FFFFh
    mov   fs,ax
    
    ;mov   ax,0                    ; To remove SUB EBX,80h, that is below, 
                                   ; if you to use this value.
    mov   ax,8                     ; Bring back the value 8 to FS register
    mov   fs,ax                    ; ...but one time made is necessary let
                                   ; it cleared (0h) to keep the aligment.
                                   ; (Reload FS with 0008h again also not
                                   ; returns the original aligment).
    sub   ebx,80h                  ; Now the value 8 is read by the Real Mode
                                   ; shifting the aligment from Real Mode 
                                   ; segmenting. (TO REMOVE IF FS = 0)
    cmp   [fs:ebx],ecx             ; Test again if FS:EBX is equal ECX
    mov   dx,error3_msg
    jne   show_msg                 ; Is different

    not   ecx                      ; Inverts ECX value
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; New comparating with inverted value
    mov   dx,error4_msg
    jne   show_msg                 ; FS:EBX is different of ECX
    
    mov   dx,success_msg
    
show_msg:    
    pop   fs                       ; Restores FS Real Mode value
    mov   ah,09h
    int   21h
    int   20h


;---------------------------------------------------------
; Error Messages
;---------------------------------------------------------
 error1_msg  db 0Dh,0Ah,"[ERROR1] Memory access with FS = 0008h is different of 55AA55AAh",0Dh,0Ah,"$"
 error2_msg  db 0Dh,0Ah,"[ERROR2] Memory access with FS = 0008h is different of AA55AA55h",0Dh,0Ah,"$"
 error3_msg  db 0Dh,0Ah,"[ERROR3] Memory access with FS = 0008h (Real Mode) is different of AA55AA55h",0Dh,0Ah,"$"
 error4_msg  db 0Dh,0Ah,"[ERROR4] Memory access with FS = 0000h is different of 55AA55AAh",0Dh,0Ah,"$"
success_msg  db 0Dh,0Ah,"Is unnecessary clear a segment register in"
             db 0Dh,0Ah,"Real Mode after set up it for Unreal Mode.",0Dh,0Ah
             db 0Dh,0Ah,"(Whenever, one time which this was made in Real Mode, is mandatory it be 0h)",0Dh,0Ah,"$"


;---------------------------------------------------------
; GDT Data
;---------------------------------------------------------
    section .data                  ; Nasm directive (to fill the alignment with zeroes)
    align 4                        ; Must be aligned in 4 bytes group

gdt_start:
    ; --- INPUT 0: The Null Descriptor (Offset 00h) ---
    ; The x86 arch REQUIRES that first entry of the table be all zero (0).
    ; If you try load 0 in a segment register, the CPU generates an error.
    dd 00000000h
    dd 00000000h

    ; --- INPUT 1: The 4GB Data Descriptor (Offset 08h) ---
    ; This will load the "Shadow Register" from FS with total access.
    dw 0FFFFh       ; Range [15:0]   -> 65535
    dw 0000h        ; Base [15:0]    -> Starts at physical address 0
    db 00h          ; Base [23:16]
    db 10010010b    ; Access Byte    -> Actual Segment, Ring 0, Data Type (Read/Write)
    db 11001111b    ; Flags & Limite -> Granularity 4KB (Bit 7), Size 32-bit (Bit 6) + Border [19:16] (0Fh)
    db 00h          ; Base [31:24]
gdt_end:

gdt_descriptor:
    dw (gdt_end - gdt_start) - 1   ; GDT Limite

gdt_base_address:
    dd 0                           ; GDT Base Address
