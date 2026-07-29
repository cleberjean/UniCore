use16
org 100h

pgm_start:
    mov   [fs:edi + 310h],eax
    mov   fs:[edi + 310h],eax
    mov   al,[es:(pgm_end - pgm_start)]
    mov   al,es:[(pgm_end - pgm_start)]
    mov   al,[es:pgm_end - pgm_start]
    mov   al,es:[pgm_end - pgm_start]
pgm_end:
