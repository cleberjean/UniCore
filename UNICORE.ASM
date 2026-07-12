;------------------------------------------------------------------------------
; UniCore - Parks All Extra (AP) Cores, Leaving Only the BSP Running
; Author: Cleber Jean Barranco [cleberjean@hotmail.com]
; Compile with: "nasm unicore.asm -o unicore.com -s"
; Released under MIT license.
; 12/jul/2026
;
; Error Codes Returned:
;     00 = Successfully and stayed resident
;     01 = Cores does not respond
;     02 = DOS not is 2.0 or earlier
;     03 = Bad processor
;     04 = Processor does not supports MONITOR/MWAIT instructions
;     05 = Processor does not supports C-states
;     06 = A20 line is locked
;     07 = Processor in Protected Mode
;
; History:
;     12jul2026
;         + Added several checkings (A20 line, Protected Mode, DOS 2.x,
;           MONITOR/MWAIT support, C-states support).
;
;------------------------------------------------------------------------------

    bits  16
    org   100h

    section .text

pgm_begin:
    push  cs
    pop   ds


;------------------------------------------------------------------------------
; Checks DOS Version
;------------------------------------------------------------------------------
check_dos:
    mov    ax,3000h
    int    21h                     ; get DOS version
    cmp    al,02h
    jae    check_processor

    ; DOS not is 2.0 or earlier
    mov   dx,bad_dos_msg
    mov   ah,09h
    int   21h
    mov   ax,4C02h                 ; Finish with error code 2
    int   21h


check_processor:
;    call  get_proc_id
;    cmp   al,NN
;    jae   check_mwait

;    ; Processor not is a Pentium 4
;    mov   dx,bad_proc_msg
;    mov   ah,09h
;    int   21h
;    mov   ax,4C03h                 ; Finish with error code 3
;    int   21h


;------------------------------------------------------------------------------
; Checks if Processor Supports MONITOR/MWAIT Instructions
;------------------------------------------------------------------------------
check_mwait:
    xor   eax,eax
    mov   al,01h
    cpuid
    bt    dx,3
    jc    check_c_states

    ; Processor does not supports MONITOR/MWAIT instructions
    mov   dx,no_mwait_msg
    mov   ah,09h
    int   21h
    mov   ax,4C04h                 ; Finish with error code 4
    int   21h

    
;------------------------------------------------------------------------------
; Checks if Processor Supports C-states, Ignoring C0
;------------------------------------------------------------------------------
check_c_states:
    xor   eax,eax
    mov   al,5
    cpuid
    test  edx,0xFFFFFFF0           ; Checks for C1-C7 C-states (ignoring C0)
    jnz   check_A20_line

    ; Processor does not supports C-states
    mov   dx,no_c_state_msg
    mov   ah,09h
    int   21h
    mov   ax,4C05h                 ; Finish with error code 5
    int   21h


;------------------------------------------------------------------------------
; Checks A20 Line
;------------------------------------------------------------------------------
check_A20_line:
    call  check_A20_sub           ; Checks A20 Line (Zero Flag = 1, A20 locked)
    jnz   check_protected_mode
     
    ; A20 Line is Locked
    mov   dx,a20_locked_msg
    mov   ah,09h
    int   21h
    mov   ax,4C06h                 ; Finish with error code 6
    int   21h


;------------------------------------------------------------------------------
; Checks Protected Mode
;------------------------------------------------------------------------------
check_protected_mode:
    pushf
    pop   ax                       ; Copies Flags register content in AX
    and   ax,0CFFFh                ; Force bits 13:12 (IOPL) to 00 (Protected 
                                   ; Mode does not will allow).
    push  ax
    popf                           ; Copies bits 13:12 cleaned to Flags reg.
    pushf
    pop   ax                       ; Copies Flags register content back in AX
    and   ah,30h                   ; Checks if bits 13:12 (IOPL) from Flags
                                   ; register are set. (bits 13:12 can not
                                   ; be cleaned in Protected Mode)
    jz    calc_physical_address    ; If 00, then system in Ring 0 (Real Mode)

    ; Processor is in Protected Mode
    mov   dx,pm_msg
    mov   ah,09h
    int   21h
    mov   ax,4C07h                 ; Finish with error code 7
    int   21h                     


;------------------------------------------------------------------------------
; Calculates Physical Address from Program End
;------------------------------------------------------------------------------
calc_physical_address:
    xor   eax,eax                  ; Clears high word of EAX
    mov   ax,cs                    ; EAX = code segment
    shl   eax,4                    ; Gets program base physical address
    add   eax,pgm_end              ; EAX = Code end physical address

    ; Finds the Next 4KB Page Boundary
    add   eax,0FFFh
    and   eax,0FFFFF000h           ; Alinha para uma p gina de 4KB

    ; Salves the Trampoline Code Segment (physical address / 16)
    shr   eax,4
    mov   [trampoline_seg],ax

    ; SIPI Vector already is in AH!
    ; (I.E.: If segment is 0x2100, AH is 0x21)
    mov   [sipi_vector],ah          ; Saves SIPI vector in memory


;------------------------------------------------------------------------------
; Copia o Codigo do Trampolim para o Espa‡o Alinhado
;------------------------------------------------------------------------------
    mov   si,trampoline_code_start
    push  es                       ; Preserves ES
    mov   es,ax                    ; ES = Segmento Alinhado (trampoline_seg)
    xor   di,di                    ; Offset 0
    mov   cx,(trampoline_code_end - trampoline_code_start)
    cld
    rep   movsb
    pop   es                       ; Restores original ES content


    ;-----------------------------------------------------------
    ; Calculate GDT Linear Address (DS * 16 + gdt_start)
    ;-----------------------------------------------------------
    xor   eax,eax
    mov   ax,cs                    ; Copies GDT segment to AX
    shl   eax,4                    ; Multiplies DS by 16
    add   eax,gdt_start            ; Adds GDT offset
    mov   [gdt_base_address],eax   ; Atualiza o ponteiro fisicamente na RAM


    ;-----------------------------------------------------------
    ; Enter in Unreal Mode
    ;-----------------------------------------------------------
    cli                            ; Clears interrupts (MANDATORY!)
    push  fs                       ; Saves FS even on Real Mode

    lgdt  [gdt_descriptor]         ; Loads GDT with the absolute address

    mov   eax,cr0
    push  eax                      ; Saves CR0 content
    or    al,1                     ; EAX Bit 0 = 1
    mov   cr0,eax                  ; Turn on Protected Mode
    jmp   $+2                      ; Clears pipeline

    mov   ax,0008h
    mov   fs,ax                    ; FS engole o limite de 4GB no Shadow Cache!

;    mov   eax,cr0
;    and   al,0FEh
    pop   eax
    mov   cr0,eax                  ; Restores original CR0 content
    jmp   $+2                      ; Clears pipeline

    xor   ax,ax
    mov   fs,ax                    ; FS points to the base of 4GB address


;-------------------------------------------------------------------------------
; Puts the Cores to Sleep (INIT-SIPI-SIPI Sequence)
;-------------------------------------------------------------------------------
    xor   ecx,ecx
    mov   cl,1Bh                   ; ECX = 0000001Bh
    rdmsr                          ; Gets APIC Base Pointer
    and   eax,0FFFFF000h           ; Mask
    mov   edi,eax                  ; Base Pointer to EDI
    
    
    ; INIT IPI (Prepara os n£cleos para o SIPI)
    xor   eax,eax
    mov   fs:[edi + 310h],eax      ; ICR_HIGH
    mov   eax,000C4500h            ; Comando INIT (Broadcast, Assert)
    mov   fs:[edi + 300h],eax      ; Dispara o INIT no ICR_LOW

.wait_init:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    .wait_init               ; Waits INIT to finish

    ; A Intel recomenda aguardar 10 ms antes de enviar um SIPI ap¢s o INIT
    mov   ax,11932                 ; 11932 x 0.838 us = 10.001 ms
    call  delay_0838us

    ; Envia SIPI pela 1¦ vez
    mov   eax,000C4600h
    or    al,[sipi_vector]
    mov   fs:[edi + 300h],eax      ; ICR_LOW (Dispara 1o. SIPI)

.wait_sipi1:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    .wait_sipi1              ; Waits SIPI to finish

    ; Wait 200 microseconds
    push  eax                      ; Preserves ICR_LOW
    mov   ax,239                   ; 239 x 0.838 us ~ 200.3 us
    call  delay_0838us
    pop   eax                      ; Restores ICR_LOW

    ; Envia SIPI pela 2¦ vez
    mov   fs:[edi + 300h],eax      ; ICR_LOW (Dispara 2o. SIPI)

.wait_sipi2:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    .wait_sipi2              ; Waits SIPI to finish


;-------------------------------------------------------------------------------
; Restores Original FS Value and Re-Enable Interrupts
;-------------------------------------------------------------------------------
    pop   fs                       ; Restaura o limite original de 64KB no FS (Modo Real)
    sti                            ; Religa as interrup‡”es do BIOS/DOS


;-------------------------------------------------------------------------------
; Get Number of Cores Sleeping
;-------------------------------------------------------------------------------
    mov   ax,[trampoline_seg]
    mov   es,ax
    mov   al,es:[(ap_counter - trampoline_code_start)]
    cmp   al,0                      ; Checks how much cores responded
    je    sleep_fail                ; None core responded (exits without stay resident)


;-------------------------------------------------------------------------------
; Show Number of Cores Sleeping
;-------------------------------------------------------------------------------
    aam   0Ah
    or    ax,3030h                  ; Converts value to ASCII
    xchg  ah,al
    mov   [done_msg_num],ax         ; Injects value in ASCII format into the message
    mov   dx,done_msg               ; Success message
    mov   ah,09h
    int   21h                       ; Imprime na tela


;-------------------------------------------------------------------------------
; Terminate and Stay Resident   
;-------------------------------------------------------------------------------
    ; Calcula o tamanho da mem¢ria a ser mantida blindada pelo DOS
    ; Limite isolado = trampoline_seg + 100h (Soma 4096 bytes convertidos para segmento)
stay_resident:
    mov   ax,[trampoline_seg]
    add   ax,0100h
    mov   bx,cs
    sub   ax,bx                     ; AX = Paragrafos totais do nosso c¢digo + trampolim
    mov   dx,ax                     ; DX = Par grafos a manter na mem¢ria
    mov   ax,3100h                  ; TSR (Terminate and Stay Resident) interrupt
    int   21h                       ; Backs to DOS


;------------------------------------------------------------------------------
; None Core Responded (Exits without Stay Resident)
;------------------------------------------------------------------------------
sleep_fail:
    mov   dx,sleep_fail_msg         ; Fail message
    mov   ah,09h
    int   21h                       ; Show message
    mov   ax,4C01h                  ; Finish with error code 1
    int   21h                       ; Backs to DOS


;------------------------------------------------------------------------------
; Checks if A20 Line is Enabled
; Returns: Zero Flag = 0 = A20 Enabled
;          Zero Flag = 1 = A20 Disabled
;
; Destroys AL.
;------------------------------------------------------------------------------
check_A20_sub:
    push  ds                       ; Saves DS
    push  es                       ; Saves ES
    xor   ax,ax
    mov   ds,ax                    ; DS = 0
    not   ax
    mov   es,ax                    ; ES = 0FFFFh
    mov   al,[0500h]               ; Gets the contents of address 0000:0500h
    cmp   al,[es:0510h]            ; Compares it with the contents of address
                                   ; 100500h
    jne   check_A20_sub_return     ; Returns with Z flag = 0 if values are 
                                   ; different (A20 is enabled)
    cli                            ; Disable interrupts to prevent changes
                                   ; to 0000:0500h
    not   byte [0500h]             ; Inverts address 0000:0500h content
    mov   al,[0500h]               ; Gets the inverted value
    cmp   al,[es:0510h]            ; Compares it with the contents of address
                                   ; 100500h
    not   byte [0500h]             ; Restores address 0000:0500h content
    sti                            ; Re-enable interrupts

; Returns Z Flag = 0 = A20 Enabled, Z Flag = 1 = A20 Disabled
check_A20_sub_return:
    pop   es                       ; Restores ES
    pop   ds                       ; Restores DS
    ret                            ; Returns with ZF clear if A20 is enabled


;---------------------------------------------------------
; 0.838 us Delay Routine
; Input  : AX = Desired Multiplier (from 1 up to 65535)
; Example: AX = 239 to ~200 us
; Output : Destroy AX, BX
;---------------------------------------------------------
delay_0838us:
    ; Saves the multiplier in BX and sets PIT to Pulse Mode
    mov   bx,ax                    ; Saves multiplier
    mov   al,0B4h                  ; Channell 2, LSB/MSB, Pulse Mode
    out   43h,al                   ; Sends command to PIT

    ; Sends divider (BX) to the Channel 2
    mov   al,bl
    out   42h,al
    mov   al,bh
    out   42h,al

    ; Activates GATE 2 (bit 0) without turn on the speaker (bit 1)
    in    al,61h                   ; Get port status
    and   al,0FCh                  ; Mute speaker
    or    al,01h                   ; Turn on timer
    out   61h,al                   ; Updates port status

    ; Listen Channel 2 (Bit 5)
.wait_loop:
    in    al,61h
    test  al,20h
    jnz   .wait_loop               ; Enquanto for 1, o tempo não acabou

    ; 5. Disable GATE 2
    in    al,61h
    and   al,0FEh                  ; Desliga o bit 0
    out   61h,al
    ret


;---------------------------------------------------------
; DATA AREA
;---------------------------------------------------------
    section .data

sipi_vector    db 0
trampoline_seg dw 0


; Messages
done_msg       db 0Dh, 0Ah, "[MWAIT] "
done_msg_num   db "00", " cores suspended. TSR loaded.", 0Dh, 0Ah, "$"
sleep_fail_msg db 0Dh, 0Ah, "FAIL!: None core has been responded.", 0Dh, 0Ah, "$"
bad_dos_msg    db 0Dh, 0Ah, "Requires DOS 2.0 or later.", 0Dh, 0Ah, "$"
bad_proc_msg   db 0Dh, 0Ah, "Requires a Pentium 4 or later processor.", 0Dh, 0Ah, "$"
no_mwait_msg   db 0Dh, 0Ah, "[CPUID] Processor does not has monitor/mwait instructions.", 0Dh, 0Ah, "$"
no_c_state_msg db 0Dh, 0Ah, "[CPUID] Processor not supports C-states.", 0Dh, 0Ah, "$"
a20_locked_msg db 0Dh, 0Ah, "FAIL!: A20 line is locked.", 0Dh, 0Ah, "$"
pm_msg         db 0Dh, 0Ah, "[IOPL] Processor in Protected Mode.", 0Dh, 0Ah, "$"


;---------------------------------------------------------
; GDT Data
;---------------------------------------------------------
    align 4

gdt_start:
    ; --- ENTRADA 0: O Null Descriptor (Offset 00h) ---
    ; A arquitetura x86 EXIGE que a primeira entrada da tabela seja toda 
    ; zerada.
    ; Se vocˆ tentar carregar 00h em um registrador de segmento, a CPU gera 
    ; um erro.
    dd 00000000h
    dd 00000000; Aponta o ES para o trampolim roubado

    ; --- ENTRADA 1: O Descritor de Dados de 4GB (Offset 08h) ---
    ; Este ‚ o cara que vai carregar o "Shadow Register" do FS com 
    ; acesso total.
    dw 0FFFFh       ; Limite [15:0]  -> Todos os bits em 1
    dw 0000h        ; Base [15:0]    -> Come‡a no endere‡o f¡sico 0
    db 00h          ; Base [23:16]
    db 10010010b    ; Access Byte    -> Segmento Presente, Ring 0, Tipo Dado (Leitura/Escrita)
    db 11001111b    ; Flags & Limite -> Granularidade 4KB (Bit 7), Tamanho 32-bit (Bit 6) + Limite [19:16] (Fh)
    db 00h          ; Base [31:24]
gdt_end:

gdt_descriptor:
    dw (gdt_end - gdt_start) - 1   ; GDT Limite

gdt_base_address:
    dd 0                           ; GDT Base Address


;------------------------------------------------------------------------------
; Trampoline Code for All Cores    
;------------------------------------------------------------------------------
    section .text

trampoline_code_start:
    ; Initializes registers
    mov   ax,cs
    mov   ds,ax
    mov   es,ax
    mov   ss,ax
    mov   sp,1000h                 ; 4KB Page RAM top + 1

    lock inc byte [(ap_counter - trampoline_code_start)]  ; Increments the core counter at each core initialized

    ; Gets Maximum C-States Supported by Processor
    xor   eax,eax
    mov   al,5
    cpuid

; Converts EDX to a Value 6-0 (C7-C1)
;    mov   cl,8
    mov   cl,7                     ; Only C7-C1 C-states will checked.
                                   ; (less significant nibble C0 is uselles)
.c_states_count_loop:
    rol   edx,4                    ; Moves the highest C-state to DL low nibble
    test  dl,0Fh                   ; C-state supported?
    loopz .c_states_count_loop     ; No. Then checks next C-state
    and   dl,0Fh                   ; Isolates the number of sub-states supported
    dec   dl                       ; Gets highest supported sub-state

;    dec   cl                       ; Converts to MWAIT C-state hint (use with CL = 8)
    shl   cl,4                     ; Moves the highest C-state to CL high nibble
                                   ; Example: C5 = 40h
    mov   bl,cl                    ; Saves C-state hint in BL
    or    bl,dl                    ; BL = C-state hint + highest sub-state (i.e. 51h)


;------------------------------------------------------------------------------
; Sleep Routine Loop
;------------------------------------------------------------------------------
.sleep_loop:
    cli                            ; Disable interrupts
    mov   eax,(monitored_addr - trampoline_code_start)
    xor   ecx,ecx                  ; Must be 0
    xor   edx,edx                  ; Must be 0
    monitor

    xor    eax,eax                 ; EAX = 0 = C1 state (see Intel ISA SDM Vol.2 "MWAIT Hints Register (EAX)" table)
    mov    al,bl                   ; EAX = Highest supported C-state and sub-state
    xor    ecx,ecx
    mwait
    jmp    .sleep_loop             ; Reexecutes the routine if core wake up


;------------------------------------------------------------------------------
; Trampoline Code Vars
;------------------------------------------------------------------------------
ap_counter     db 0                ; Cores counter (will incremented for each
                                   ; core suspended)
    align   64                     ; Must be aligned with 64 bytes
monitored_addr db 0                ; Monitoring Address for MONITOR instruction

trampoline_code_end:               ; Marker for trampoline code copy

pgm_end:                           ; Marker for program size calculation

