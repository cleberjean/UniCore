;-----------------------------
; Unreal Mode Addressing Test
;-----------------------------

    use16
    org 100h

;    push  fs
;    jmp   teste
    ;-----------------------------------------------------------
    ; Calculate GDT Linear Address (DS * 16 + gdt_start)
    ;-----------------------------------------------------------
    xor   eax,eax
    mov   ax,cs                    ; Copies GDT segment to AX
    shl   eax,4                    ; Multiplies DS by 16
    add   eax,gdt_start            ; Adds GDT offset
    mov   [gdt_base_address],eax   ; Updates the pointer


    ;-----------------------------------------------------------
    ; Enter in Unreal Mode
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
    mov   cr0,eax                  ; Restores original CR0 content
    jmp   $+2                      ; Clears pipeline
    sti

teste:    
    mov   ebx,100000h              ; Testar o endere‡o (1GB)
    mov   ecx,55AA55AAh
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; Testa se FS:EBX ‚ igual ECX
    mov   dx,error1
    jne   mostra_msg    

    not   ecx                      ; Inverte ECX
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; Nova compara‡„o com bits invertidos
    mov   dx,error2
    jne   mostra_msg               ; FS:EBX ‚ diferente de ECX
    
    ; Alterar FS nao desfaz ou perde o Modo Irreal...
    pop   fs
    push  fs
    mov   ax,0FFFFh
    mov   fs,ax
    
    mov   ax,8
    mov   fs,ax                    ; ...Mas eh necessario mante-lo zerado
                                   ; para continuar usando o Modo Irreal.
                                   ; (Alterar FS novamente para 0008h tamb‚m
                                   ; nao retorna ao endere‡amento linear).
    sub   ebx,80h
    cmp   [fs:ebx],ecx             ; Testa novamente se FS:EBX ‚ igual ECX
    mov   dx,error3
    jne   mostra_msg               ;  diferente

    not   ecx                      ; Inverte ECX
    mov   [fs:ebx],ecx
    cmp   [fs:ebx],ecx             ; Nova compara‡„o com bits invertidos
    mov   dx,error4
    jne   mostra_msg               ; FS:EBX ‚ diferente de ECX
    
    mov   dx,success
    
mostra_msg:    
    pop   fs                       ; Restaura FS
    mov   ah,09h
    int   21h
    int   20h


error1    db 0Dh,0Ah,"[ERRO1] Mem¢ria com FS = 0008h ‚ diferente de 55AA55AAh",0Dh,0Ah,"$"
error2    db 0Dh,0Ah,"[ERRO2] Mem¢ria com FS = 0008h ‚ diferente de AA55AA55h",0Dh,0Ah,"$"
error3    db 0Dh,0Ah,"[ERRO3] Mem¢ria com FS = 0000h ‚ diferente de AA55AA55h",0Dh,0Ah,"$"
error4    db 0Dh,0Ah,"[ERRO4] Mem¢ria com FS = 0000h ‚ diferente de 55AA55AAh",0Dh,0Ah,"$"
success   db 0Dh,0Ah,"E' irrelevante zerar FS apos configura-lo para o Modo Irreal."
          db 0Dh,0Ah,"(Mas uma vez feito, passa a ser obrigatorio.)",0Dh,0Ah,"$"


;---------------------------------------------------------
; GDT Data
;---------------------------------------------------------
    section .data
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
