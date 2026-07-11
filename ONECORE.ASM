;------------------------------------------------------------------------------
; OneCore - Parks All Extra (AP) Cores, Leaving Only the BSP Running
; Author: cleberjean@hotmail.com
; Compile with: "nasm onecore.asm -o onecore.com"
; Released under MIT license
;------------------------------------------------------------------------------

    bits  16
    org   100h

    section .text

program_begin:
    push  cs
    pop   ds

    ; Calcula o Endere‡o Fisico do final do programa
    xor   eax,eax
    mov   ax,cs
    shl   eax,4                    ; EAX = Endereço físico base do programa
    add   eax,program_end          ; EAX = Endereço físico do fim do código

    ; Encontra a proxima fronteira de 4KB (Page Boundary)
    add   eax,0FFFh
    and   eax,0FFFFF000h           ; Alinha para uma p gina de 4KB

    ; Salva o Segmento do Trampolim (Endere‡o F¡sico / 16)
    shr   eax,4
    mov   [trampoline_seg],ax

    ; O vetor SIPI j  est  "de gra‡a" em AH!
    ; (Ex: Se o segmento for 0x2100, AH ser  0x21)
    mov   [sipi_vector],ah


;------------------------------------------------------------------------------
; Copia o Codigo do Trampolim para o Espa‡o Alinhado
;------------------------------------------------------------------------------
    mov   si,trampoline_code_start
    push  es
    mov   es,ax                     ; ES = Segmento Alinhado (trampoline_seg)
    xor   di,di                     ; Offset 0
    mov   cx,(trampoline_code_end - trampoline_code_start)
    cld
    rep   movsb
    pop   es


    ;----------------------------------------------------------------
    ; PASSO 1: Calcular Endere‡o Linear da GDT (DS * 16 + gdt_start)
    ;----------------------------------------------------------------
    xor   eax,eax
    mov   ax,cs                    ; Copy GDT segment to ax
    shl   eax,4                    ; Multiplica DS por 16
    add   eax,gdt_start            ; Soma o offset da GDT
    mov   [gdt_base_address],eax   ; Atualiza o ponteiro fisicamente na RAM


    ;-----------------------------------------------------
    ; PASSO 2: Entrar no Unreal Mode
    ;-----------------------------------------------------
    cli                            ; 1. PERIGO MAXIMO: Desliga interrup‡”es AGORA.
    push  fs                       ; 2. Salva o FS do DOS enquanto estamos no Modo Real

    lgdt  [gdt_descriptor]         ; 3. Carrega a GDT com o endere‡o absoluto corrigido

    mov   eax,cr0
    or    al,1
    mov   cr0,eax                  ; 4. PM ON (Fronteira cruzada)
    jmp   $+2                      ; 5. Limpa pipeline

    mov   ax,0008h
    mov   fs,ax                    ; 6. FS engole o limite de 4GB no Shadow Cache!

    mov   eax,cr0
    and   al,0FEh
    mov   cr0,eax                  ; 7. PM OFF (De volta ao Modo Real)
    jmp   $+2                      ; 8. Limpa pipeline

    xor   ax,ax
    mov   fs,ax                    ; Now FS will point to the base of 4GB address


    ; * BEM-VINDO AO UNREAL MODE *
    ; A partir daqui estamos seguros no DOS, mas FS enxerga 4GB.

;-----------------------------------------------------
; Sleep Cores (INIT-SIPI-SIPI Sequence)
;-----------------------------------------------------
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


;-----------------------------------------------------
; Restores Original FS Value and Re-Enable Interrupts
;-----------------------------------------------------
    pop   fs                       ; Restaura o limite original de 64KB no FS (Modo Real)
    sti                            ; Religa as interrup‡”es do BIOS/DOS


; Get Number of Cores Sleeping
    mov   ax,[trampoline_seg]
    mov   es,ax
    mov   al,es:[(ap_counter - trampoline_code_start)]
    cmp   al,0                      ; Checks how much cores responded
    je    .fail                     ; None core responded

    ; Se chegou aqui, AL tem o numero de nucleos (ex: 5)
    aam   0Ah
    or    ax,3030h                  ; Converte o valor 5 no caractere '5'
    xchg  ah,al
    mov   [msg_done_num],ax         ; Injeta o '5' no meio da mensagem

    mov   dx,msg_done               ; Prepara a mensagem de sucesso
    jmp   .show_message

.fail:
    mov   dx, msg_fail              ; Fail message

.show_message:
    mov   ah,09h
    int   21h                       ; Imprime na tela

;    mov   ax,4C00h
;    int   21h                       ; Volta para o DOS


;---------------------------------------------------------
; Terminate and Stay Resident Routine    
;---------------------------------------------------------
    ; Calcula o tamanho da memória a ser mantida blindada pelo DOS
    ; Limite isolado = trampoline_seg + 100h (Soma 4096 bytes convertidos para segmento)
    mov   ax,[trampoline_seg]
    add   ax,0100h
    mov   bx,cs
    sub   ax,bx                     ; AX = Paragrafos totais do nosso c¢digo + trampolim

    mov   dx,ax                     ; DX = Par grafos a manter na mem¢ria
    mov   ax,3100h                  ; TSR (Terminate and Stay Resident) interrupt
    int   21h                       ; Backs to DOS


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

msg_fail       db 0Dh, 0Ah, "FALHA: Nenhum n£cleo respondeu.", 0Dh, 0Ah, "$"
msg_done       db 0Dh, 0Ah, "SUCESSO! "
msg_done_num   db "00", " n£cleos suspensos.", 0Dh, 0Ah, "$"
msg_no_support db 0Dh, 0Ah, "Not supported processor.", 0Dh, 0Ah, "$"
msg_no_mwait   db 0Dh, 0Ah, "Processor does not has monitor/mwait instructions!", 0Dh, 0Ah, "$"


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
    mov   cl,7                     ; Only 7 highest C-states will checked.
                                   ; (We does not need C0)
.c_states_count_loop:
    rol   edx,4                    ; Moves the highest C-state to DL low nibble
    test  dl,0Fh                   ; C-state supported?
    loopz .c_states_count_loop     ; No. Then checks next C-state
;    dec   cl                       ; Converts to MWAIT C-state hint (use with CL = 8)
    shl   cl,4                     ; Moves the highest C-state to CL high nibble
                                   ; Example: C5 = 40h
    mov   bl,cl                    ; Saves C-state hint in BL


;------------------------------------------------------------------------------
; Sleep Routine Loop
;------------------------------------------------------------------------------
.sleep_loop:
    cli                            ; Disable interrupts
    mov   eax,(dummy_var - trampoline_code_start)
    xor   ecx,ecx                  ; Must be 0
    xor   edx,edx                  ; Must be 0
    monitor

    xor    eax,eax                 ; EAX = 0 = C1 state (see Intel ISA SDM Vol.2 "MWAIT Hints Register (EAX)" table)
    mov    al,bl                   ; EAX = Highest supported C-state
    xor    ecx,ecx
    mwait
    jmp    .sleep_loop             ; Reexecutes the routine if core wake up


ap_counter  db 0                   ; Cores counter
    
; Dummy Variable for the Trampoline Code    
    align   64
dummy_var   db 0

trampoline_code_end:

program_end:                       ; For program size calculus
