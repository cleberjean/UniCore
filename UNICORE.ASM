;------------------------------------------------------------------------------
; UniCore - Put to Sleep All Extra (AP) Cores, Leaving Only the BSP Active
; ------------------------------------------------------------------------
; Author      : Cleber Jean Barranco [cleberjean@hotmail.com]
; Repository  : https://github.com/cleberjean/UniCore
; Compile with: nasm -f bin unicore.asm -o unicore.com -s
;
; Released under MIT license.
; Free to use, copy, modify or fork (only let me know).
;
; Last alteration on 20/jul/2026.
;
;
; Error Codes Returned:
;     00 = Successfully finish and stayed resident
;     01 = TSR already loaded
;     02 = Cores didn't respond
;     03 = Bad processor
;     04 = Processor does not support MONITOR/MWAIT instructions
;     05 = Processor does not support C-states
;     06 = A20 line is locked
;     07 = Processor in Protected Mode
;     08 = Windows loaded
;     09 = DOSBox(-X) environment
;
;
; History:
;     12jul2026
;         + Added several checkings (A20 line, Protected Mode, DOS 2.x,
;           MONITOR/MWAIT support, C-states support).
;         + Added Windows checking.
;         * Translated some comments.
;     13jul2026
;         * Changed label check_A20_sub to check_A20.
;         + Added TSR loaded checking routine.
;     14jul2026
;         + Made changes on memory allocated for trampoline code. 
;         + Created Error Codes Contants.
;     15jul2026
;         * Changed done_msg_num label to done_msg_count.
;         * Adjusted more some comments.
;     16jul2026
;         + Added processor checking for support of CPUID instruction
;           (returns bad_proc_msg)
;     19jul2026
;         * Changed title alignment.
;     20jul2026
;         * Fixed interrupt for return to DOS on DOS Ver. < 2.x.
;         - Removed error code for unsupported DOS version.
;           DOS 1.x does not supports error codes (AX=4Ch, INT 21h).
;         + Addded DOSBox(-X) checking.
;
;------------------------------------------------------------------------------

    bits  16                       ; Use 66h prefix on 32-bit instructions
    org   100h                     ; Program is a DOS .COM file


;------------------------------------------------------------------------------
; Error Codes (EC)
;------------------------------------------------------------------------------
    EC_EXIT_SUCCESS   equ 0x00
    EC_ALREADY_LOADED equ 0x01
    EC_NO_RESPONSE    equ 0x02
    EC_BAD_PROCESSOR  equ 0x03
    EC_NO_MONIT_MWAIT equ 0x04
    EC_NO_C_STATES    equ 0x05
    EC_A20_DISABLED   equ 0x06
    EC_PROTECTED_MODE equ 0x07
    EC_WINDOWS_LOADED equ 0x08
    EC_DOSBOX         equ 0x09


    section .text


pgm_begin:                         ; This label is used to calculate
                                   ; the code size to stay resident
    push  cs
    pop   ax
    mov   ds,ax                    ; Ensures DS = CS
    mov   es,ax                    ; Ensures ES = CS


;------------------------------------------------------------------------------
; Show Program Title
;------------------------------------------------------------------------------
    mov    dx,title_msg
    mov    ah,09h
    int    21h


;------------------------------------------------------------------------------
; Checks if Is Running in DOSBox(-X)
;------------------------------------------------------------------------------
check_dosbox:
    push  ds                       ; Preserves DS segment
    mov   ax,0F000h                ; BIOS segment
    mov   ds,ax                    ; DS = DOSBox BIOS segment
    mov   eax,[0E061h]             ; Address F000:E061 has "DOSBox" string
    pop   ds                       ; Restores original DS segment
    cmp   eax,'DOSB'               ; 4 chars is enough
    jne   check_dos

    ; Program is running in DOSBox
    mov   dx,dosbox_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_DOSBOX
    int   21h                      ; Backs for DOSBox prompt with error code 9


;------------------------------------------------------------------------------
; Checks DOS Version
;------------------------------------------------------------------------------
check_dos:
    mov    ax,3000h
    int    21h                     ; get DOS version
    cmp    al,02h
    jae    check_loaded

    ; DOS not is 2.0 or is earlier
    mov   dx,bad_dos_msg
    mov   ah,09h
    int   21h
    int   20h                      ; Back to DOS (1.x)


;------------------------------------------------------------------------------
; Checks if the Code was Already Loaded
;------------------------------------------------------------------------------
check_loaded:
    mov   ax,0C400h
    mov   bx,'UC'                  ; BX = password for the handler
    int   2Fh
    cmp   al,0FFh
    jne   check_processor

    ; Checks the handler confirmation
    cmp   bx,'OK'                  ; Confirms 
    jne   check_processor          ; if different, code did not loaded yet
    
    ; Code already loaded
    mov   dx,loaded_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_ALREADY_LOADED
    int   21h


;------------------------------------------------------------------------------
; Checks if Processor Supports CPUID Instruction
;------------------------------------------------------------------------------
check_processor:
    call  check_cpuid_support      ; Returns CY = 0 if support
    jnc   check_mwait              ; Processor supports CPUID instruction

    ; Processor not has CPUID instruction (then not is a Pentium 4)
    mov   dx,bad_proc_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_BAD_PROCESSOR
    int   21h


;------------------------------------------------------------------------------
; Checks if Processor Supports MONITOR/MWAIT Instructions
;------------------------------------------------------------------------------
check_mwait:
    xor   eax,eax
    mov   al,01h
    cpuid
    bt    cx,3
    jc    check_c_states

    ; Processor does not supports MONITOR/MWAIT instructions
    mov   dx,no_mwait_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_NO_MONIT_MWAIT
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
    mov   ax,4C00h + EC_NO_C_STATES
    int   21h


;------------------------------------------------------------------------------
; Checks A20 Line
;------------------------------------------------------------------------------
check_A20_line:
    call  check_A20                ; Checks A20 Line (Zero Flag = 1, A20 locked)
    jnz   check_protected_mode
     
    ; A20 line is disabled
    mov   dx,a20_locked_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_A20_DISABLED
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
    jz    check_windows            ; If 00, then system in Ring 0 (Real Mode)

    ; Processor is in Protected Mode
    mov   dx,pm_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_PROTECTED_MODE
    int   21h                     


;------------------------------------------------------------------------------
; Checks if UniCore was Called Into Windows
;------------------------------------------------------------------------------
check_windows:
    mov   ax,160Ah
    int   2Fh
    test  ax,ax
    jnz   calc_physical_address
    
    ; Windows is running
    mov   dx,windows_msg
    mov   ah,09h
    int   21h
    mov   ax,4C00h + EC_WINDOWS_LOADED
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
    mov   [sipi_vector],ah         ; Saves SIPI vector in memory


;------------------------------------------------------------------------------
; Copy the Trampoline Code to the Aligned Space
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
    
    
    ; INIT IPI (Prepares the cores to SIPI)
    xor   eax,eax
    mov   fs:[edi + 310h],eax      ; ICR_HIGH
    mov   eax,000C4500h            ; Comando INIT (Broadcast, Assert)
    mov   fs:[edi + 300h],eax      ; Triggers the INIT on ICR_LOW

wait_init:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    wait_init                ; Waits INIT to finish

    ; Intel recommends waiting 10 ms before sending a SIPI after the INIT
    mov   ax,11932                 ; 11932 x 0.838 us = 10.001 ms
    call  delay_0838us

    ; Sends SIPI by first time
    mov   eax,000C4600h
    or    al,[sipi_vector]
    mov   fs:[edi + 300h],eax      ; ICR_LOW (Triggers the 1st SIPI)

.wait_sipi1:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    .wait_sipi1              ; Waits SIPI to finish

    ; Wait 200 microseconds (Intel recommendation)
    push  eax                      ; Preserves ICR_LOW
    mov   ax,239                   ; 239 x 0.838 us ~ 200.3 us
    call  delay_0838us
    pop   eax                      ; Restores ICR_LOW

    ; Sends SIPI by second time
    mov   fs:[edi + 300h],eax      ; ICR_LOW (Triggers the 2nd SIPI)

.wait_sipi2:
    bt    dword fs:[edi + 300h],12 ; Checks Delivery Status bit (12)
    jc    .wait_sipi2              ; Waits SIPI to finish


;-------------------------------------------------------------------------------
; Restores Original FS Value and Re-Enable Interrupts
;-------------------------------------------------------------------------------
    pop   fs                       ; Restores the original FS content (Real Mode)
    sti                            ; Restores the interrupts


;-------------------------------------------------------------------------------
; Gets the Number of Sleeping Cores
;-------------------------------------------------------------------------------
    mov   ax,[trampoline_seg]
    mov   es,ax
    mov   al,es:[(ap_counter - trampoline_code_start)]
    cmp   al,0                     ; Checks how much cores responded
    je    sleep_fail               ; No cores responded (exits without stay resident)


;-------------------------------------------------------------------------------
; Show Number of Cores Sleeping
;-------------------------------------------------------------------------------
    aam   0Ah
    or    ax,3030h                 ; Converts value to ASCII
    xchg  ah,al
    mov   [done_msg_count],ax      ; Injects value in ASCII format into the message
    mov   dx,done_msg              ; Success message
    mov   ah,09h
    int   21h                      ; Imprime na tela


;-------------------------------------------------------------------------------
; Terminate and Stay Resident   
;-------------------------------------------------------------------------------
    ; Calcula o tamanho da mem¢ria a ser mantida blindada pelo DOS
;    ; Limite isolado = trampoline_seg + 100h (Soma 4096 bytes convertidos para segmento)
    ; Limite isolado 2 = trampoline_seg + 10h (Soma 256 bytes convertidos para segmento)
stay_resident:
    call  install_int2f_handler    ; Installs a new handler for INT 2Fh
    mov   ah,49h                   ; Free environment vars memory allocation
    mov   es,[cs:002Ch]            ; CS = segment of block to free (environment vars)
    int   21h                      ; Free environment vars
    mov   ax,[trampoline_seg]      ; 
    add   ax,0010h                 ; Adds 16 segments of 16 bytes (256 bytes) (trampoline code + vars has 75 bytes)
    mov   bx,cs                    ; Copies initial segment to BX
    sub   ax,bx                    ; AX = Paragrafos totais do nosso c¢digo + trampolim
    mov   dx,ax                    ; DX = Par grafos a manter na mem¢ria
    mov   ax,3100h                 ; Stay resident and exit with error code 0
    int   21h                      ; Backs to DOS


;------------------------------------------------------------------------------
; No Core Responded (Exits without Stay Resident)
;------------------------------------------------------------------------------
sleep_fail:
    mov   dx,sleep_fail_msg        ; Fail message
    mov   ah,09h
    int   21h                      ; Show message
    mov   ax,4C00h + EC_NO_RESPONSE
    int   21h                      ; Backs to DOS


;-------------------------------------------------------------------------------
; Checks for CPUID Instruction Support
; Returns CY = 0 if supported, otherwise CY= 1
; --------------------------------------------
; Code taken from Intel Pentium Processor User's Manual, Volume 3,
; Chapter 5.3 - SAMPLE CPUID IDENTIFICATION/FPU DETECTION CODE, pages 129 to
; 123, from 1993. Example 5-1. CPU Identification and FPU Detection.
;
; AUTHOR NOTE: Only CX register was changed to BX.
;-------------------------------------------------------------------------------
check_cpuid_support:

;-------------------------------------------------------------------------------
; 8086/8088 Double Checking Detection
; -----------------------------------
; Processors later of 8086 always push SP to stack, and then decrement SP
; by 2. 8086 always decrement SP by 2 and then push it on stack.
; Also bits 12..15 are always set on the 8086 processor.
; [MODIFIED] Test only bits 14 and 15, due detection fail when in Protected
;            Mode (bits 12 and 13 (IOPL) is always 11).
;-------------------------------------------------------------------------------
    ; Checks SP (1st test)
    push  sp                       ; Push SP
    pop   ax                       ; And restore in AX
    sub   ax,sp                    ; Will clear AX if CPU is an 80286 or later
    jnz   .no_cpuid_near_jump      ; Processor is an 80186 or early

    ; Checks FLAGS register (2nd test)
    pushf
    pop   bx                       ; Preserves original FLAGS in BX
    mov   ax,bx                    ; Copy flags to AX
    and   ax,0FFFh                 ; Clear bits 12..15
    push  ax
    popf                           ; Clear bits 12..15 in FLAGS
    pushf
    pop   ax                       ; Copy flags again to AX
    and   ax,0C000h                ; Check only if bits 15:14 still remains clean
                                   ; (Protected Mode locks bits 13:12 (IOPL) in 1)
    jnz   .no_cpuid_near_jump      ; Bits 14 and 15 from Flags Register remain set (processor is an 8086/80186)


;-------------------------------------------------------------------------------
; Intel 286 CPU Checking
; ----------------------
; Bits 12-15 are always clear on the Intel 286 processor.
;-------------------------------------------------------------------------------
.test_286:
    mov   ax,bx                    ; Copy flags to AX
    or    ax,0F000h                ; Set bits 12..15
    push  ax
    popf
    pushf
    pop   ax
    and   ax,0F000h                ; If bits 12..15 are cleared, then CPU=80286
    jnz   .test_386                ; Processor is an 80386


;-------------------------------------------------------------------------------
; Conditional Near Jump Fix for the 16 bits Processors
; Processors 8086/8088, 80186 and 80286 has Conditional Short Jumps Only.
;-------------------------------------------------------------------------------
.no_cpuid_near_jump:
    jmp   .no_cpuid


            ;----------------------------------------------------;
            ; Starting here, is safe to use 32 bits instructions ;
            ;----------------------------------------------------;

;-------------------------------------------------------------------------------
; Intel386 CPU Checking
; ---------------------
; The AC bit, bit #18, is a new bit introduced in the EFLAGS
; register on the Intel486 DX CPU to generate alignment faults.
; This bit can not be set on the Intel386 CPU.
;-------------------------------------------------------------------------------
.test_386:
    push   bx
    popf                           ; Restore original FLAGS
    pushfd
    pop   ebx                      ; Preserves original EFLAGS in EBX
    mov   eax,ebx                  ; Copy original EFLAGS to EAX
    xor   eax,40000h               ; Flip AC bit in EFLAGS
    push  eax
    popfd
    pushfd
    pop   eax                      ; Get new EFLAGS value
    xor   eax,ebx                  ; Compare original EFLAGS with new EFLAGS. Can't
                                   ; toggle AC bit, CPU=80386
    jz    .no_cpuid


;-------------------------------------------------------------------------------
; Check 80486 with CPUID Instruction (bit 21 from EFLAGS)
;-------------------------------------------------------------------------------
    mov   eax,ebx                  ; Copy original EFLAGS to EAX
    xor   eax,200000h              ; Flip ID bit in EFLAGS
    push  eax
    popfd
    pushfd
    pop   eax                      ; Get new EFLAGS value
    xor   eax,ebx                  ; Compare original EFLAGS with new EFLAGS
    jz    .no_cpuid                ; If ID bit cannot be changed, CPU=80486
                                   ; without CPUID instruction functionality

;-------------------------------------------------------------------------------
; CPUID Instruction is Supported (returns CY = 0)
;-------------------------------------------------------------------------------
    push  ebx
    popfd                          ; Restores EFLAGS to original content
    clc                            ; Processor has CPUID (CY = 0)
    ret

;-------------------------------------------------------------------------------
; CPUID Instruction not is Supported (returns CY = 1)
;-------------------------------------------------------------------------------
.no_cpuid:
    push  ebx
    popfd                          ; Restores EFLAGS to original content
    stc                            ; Processor has not CPUID instruction (CY = 1)
    ret


;------------------------------------------------------------------------------
; Checks if A20 Line is Enabled
; Returns: Zero Flag = 0 = A20 Enabled
;          Zero Flag = 1 = A20 Disabled
;
; Destroys AL.
;------------------------------------------------------------------------------
check_A20:
    push  ds                       ; Saves DS
    push  es                       ; Saves ES
    xor   ax,ax                    ; 
    mov   ds,ax                    ; DS = segment 0
    not   ax                       ; AX = 0FFFFh
    mov   es,ax                    ; ES = 0FFFFh (1MB boundary)
    mov   al,[0500h]               ; Gets the contents of address 0000:0500h
    cmp   al,[es:0510h]            ; Compares it with the contents of address
                                   ; 100500h
    jne   .check_A20_return        ; Returns with Z flag = 0 if values are
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
.check_A20_return:
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

    ; Activates GATE 2 (bit 0)
    in    al,61h                   ; Get port status
    and   al,0FCh                  ; Mute speaker (bit 1)
    or    al,01h                   ; Turn on timer
    out   61h,al                   ; Updates port status

    ; Listen Channel 2 (Bit 5)
.delay_wait_loop:
    in    al,61h
    test  al,20h
    jnz   .delay_wait_loop         ; While is 1, the time does not has ended

    ; 5. Disable GATE 2
    in    al,61h
    and   al,0FEh                  ; Turn off bit 0 (disable Gate 2)
    out   61h,al
    ret


;------------------------------------------------------------------------------
; Installs New INT 2Fh Handler
;------------------------------------------------------------------------------
install_int2f_handler:
    mov   ax,352Fh                 ; AL = interrupt to request vector (2Fh)
    int   21h                      ; Gets interrupt 2Fh vector in ES:BX
    mov   [old_int2f],bx           ; Saves old handler vector offset
    mov   [old_int2f + 2],es       ; Saves old handler vector segment
    push  cs
    pop   ds                       ; Ensures DS = code segment
    mov   dx,int2f_handler
    mov   ax,252Fh                 ; AL = interrupt to change (2Fh)
    int   21h                      ; Installs new handler into interrupt 2Fh
    ret


;------------------------------------------------------------------------------
; New INT 2Fh Handler
;------------------------------------------------------------------------------
int2f_handler:
    pushf                          ; Preserves flags register
    cmp   ax,0C400h                ; Checks if was function C400h that was called
    jne   .chain                   ; Wasn't function 4C00h called
    cmp   bx,"UC"                  ; Confirms the caller program
    jne   .chain                   ; Wasn't UniCore program that called
    
    popf                           ; Restores flags register
    mov   bx,"OK"                  ; Confirmation characters
    mov   al,0FFh                  ; Function supported flag (MANDATORY!)
    iret                           ; 
  
.chain:
    popf                           ; Restores original flags register content
                                   ; to the old interrupt 2Fh handler.
    jmp   far[cs:old_int2f]        ; Skips to the old handler


; Old Interrupt 2Fh Handler Vector
old_int2f dd 0

;------------------------------------------------------------------------------


;---------------------------------------------------------
; DATA AREA
;---------------------------------------------------------
    section .data

sipi_vector    db 0
trampoline_seg dw 0


;------------------------------------------------------------------------------
; Messages
;------------------------------------------------------------------------------
title_msg      db 0Dh, 0Ah, "==========================================="
               db 0Dh, 0Ah, "= Unicore      Version 1.0      20jul2026 ="
               db 0Dh, 0Ah, "= Put to Sleep All Secundary Cores on DOS ="
               db 0Dh, 0Ah, "==========================================="
               db 0Dh, 0Ah, "(C)2026 Cleber Jean Barranco.", 0Dh, 0Ah, "$"
done_msg       db 0Dh, 0Ah, "[MWAIT] "
done_msg_count db "00", " cores sleeping."
               db 0Dh, 0Ah, "Unicore is resident.", 0Dh, 0Ah, "$"
sleep_fail_msg db 0Dh, 0Ah, "FAIL!: No cores response.", 0Dh, 0Ah, "$"
loaded_msg     db 0Dh, 0Ah, "[C400] Unicore is already resident.", 0Dh, 0Ah, "$"
bad_dos_msg    db 0Dh, 0Ah, "Requires DOS 2.0 or later.", 0Dh, 0Ah, "$"
bad_proc_msg   db 0Dh, 0Ah, "Requires a Core 2 or newer processor.", 0Dh, 0Ah, "$"
no_mwait_msg   db 0Dh, 0Ah, "[CPUID] Processor does not has monitor/mwait instructions.", 0Dh, 0Ah, "$"
no_c_state_msg db 0Dh, 0Ah, "[CPUID] Processor does not support C-states.", 0Dh, 0Ah, "$"
a20_locked_msg db 0Dh, 0Ah, "FAIL!: The A20 line is disabled.", 0Dh, 0Ah, "$"
pm_msg         db 0Dh, 0Ah, "[IOPL] Processor in Protected Mode.", 0Dh, 0Ah, "$"
windows_msg    db 0Dh, 0Ah, "[160A] Quit Windows and run me again.", 0Dh, 0Ah, "$"
dosbox_msg     db 0Dh, 0Ah, "[DOSBox] Requires a real machine to work.", 0Dh, 0Ah, "$"


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
    dd 00000000h

    ; --- ENTRADA 1: O Descritor de Dados de 4GB (Offset 08h) ---
    ; Isto carregar  o "Shadow Register" do FS com acesso total.
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
; Must have 256 bytes reserved for it (code + ap_counter has 75 bytes).
; Will be copied for start of next 4KB page after the UniCore. 
;------------------------------------------------------------------------------
    section .text

trampoline_code_start:
    ; Initializes registers
    mov   ax,cs
    mov   ds,ax
    mov   es,ax
    mov   ss,ax
    mov   sp,0100h                 ; Top of trampoline space memory (256)

    ; Counts the number of cores put to sleep
    lock inc byte [(ap_counter - trampoline_code_start)]  ; Increments the core counter at each core initialized

    ; Gets Maximum C-States Supported by Processor
    xor   eax,eax
    mov   al,5
    cpuid


;------------------------------------------------------------------------------
; Gets Hint (C-state - 1) to MWAIT Instruction
;; Converts EDX (Maximum C-state) to a Value 6:-1 (C7-C0) and store in BL
; Converts EDX (Maximum C-state) to a Value 6-0 (C7-C1) and store in BL
;------------------------------------------------------------------------------
;    mov   cl,8
    mov   cl,7                     ; Only C7-C1 C-states will checked.
                                   ; (less significant nibble C0 is uselles)
.c_states_count_loop:
    rol   edx,4                    ; Moves the highest C-state to DL low nibble
    test  dl,0Fh                   ; C-state supported?
    loopz .c_states_count_loop     ; No. Then checks next C-state
;    dec   cl                       ; Turns CL on MWAIT hint (6 to -1)
    and   dl,0Fh                   ; Isolates the number of sub-states supported
    dec   dl                       ; Converts the sub-state count to the
                                   ; highest MWAIT sub-state hint.
                                   ; (Intel SDM does not explicitly define
                                   ;  this mapping.)
    shl   cl,4                     ; Moves the highest C-state to CL high nibble
                                   ; Example: C5 = 40h
    mov   bl,cl                    ; Saves C-state hint in BL
    or    bl,dl                    ; BL = C-state hint + highest sub-state (i.e. 51h)


;------------------------------------------------------------------------------
; Sleep Routine Loop
;------------------------------------------------------------------------------
.sleep_loop:
    cli                            ; Disable interrupts
    
    ; Starts MONITOR instruction
    xor   eax,eax
    mov   al,80h                   ; Address to monitoring (128 bytes after 
                                   ; offset 0), allowing a cache granularity 
                                   ; up to 128 bytes.    
    xor   ecx,ecx                  ; Must be 0
    xor   edx,edx                  ; Must be 0
    monitor

    ; Call MWAIT instruction
    xor    eax,eax                 ; EAX = 0 = C1 state (see Intel ISA SDM Vol.2 "MWAIT Hints Register (EAX)" table)
    mov    al,bl                   ; EAX = Highest supported C-state and sub-state
    xor    ecx,ecx
    mwait
    
    jmp    .sleep_loop             ; Reexecutes the routine if core wake up


;------------------------------------------------------------------------------
; Trampoline Cores Counter Var
;------------------------------------------------------------------------------
ap_counter     db 0                ; Cores counter (will incremented for each
                                   ; core suspended)

trampoline_code_end:               ; Marker for trampoline code copy

pgm_end:                           ; Marker for program size calculation

