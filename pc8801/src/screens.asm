; =====================================================================
; screens.asm - ゲームオーバー / デモ  (タイトルは title.asm)
; =====================================================================

; ---------------------------------------------------------------------
; GAMEOVERSCREEN
; ---------------------------------------------------------------------
GAMEOVERSCREEN:
        LD      A,BGM_OVER
        CALL    BGMSTART
        LD      HL,S_GAMEOVER
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,C_RED
        LD      (GFX_COL),A
        LD      HL,S_GAMEOVER
        LD      B,10
        LD      C,96
        CALL    DRAWSTR
        LD      B,3*TICKHZ
.lp:
        PUSH    BC
        CALL    WAITVSYNC
        CALL    READKEYS
        CALL    ACHTOAST
        CALL    ANYKEY
        POP     BC
        JR      NZ,.done
        DJNZ    .lp
.done:
        RET

; ---------------------------------------------------------------------
; DEMOPLAY - デモ (柴犬も AI が動かす)
; ---------------------------------------------------------------------
DEMOPLAY:
        LD      A,1
        LD      (DEMOMODE),A
        LD      A,3
        LD      (STAGE),A
        LD      A,3
        LD      (LIVES),A
        XOR     A
        LD      (BONUSMODE),A
        LD      (GAMEOVER),A
        LD      HL,0
        LD      (SCORE),HL
        XOR     A
        LD      (SCORE+2),A
        CALL    PALNORMAL
        CALL    STAGEINIT
        CALL    CLS
        CALL    DIRTYRESET
        CALL    DIRTYALL
        CALL    FLUSHDIRTY
        CALL    HUDALL
        LD      HL,30*TICKHZ            ; 30 秒ほど
        LD      (IDLETIMER),HL
.loop:
        CALL    WAITVSYNC
        LD      HL,(FRAMECNT)
        INC     HL
        LD      (FRAMECNT),HL
        CALL    READKEYS
        XOR     A
        LD      (BFSUSED),A
        LD      A,0xFF
        LD      (HELDDIR),A
        XOR     A
        LD      (ACTPRESS),A
        CALL    SPRCLEAR
        CALL    WORLDTICK
        CALL    CARSMARK
        CALL    FLUSHDIRTY
        CALL    DRAWCARS
        CALL    DRAWDOGS
        LD      A,(NEEDHUD)
        OR      A
        JR      Z,.nh
        XOR     A
        LD      (NEEDHUD),A
        CALL    HUDVALUES
.nh:
        CALL    FLOODSTEP
        CALL    ANYKEY
        JR      NZ,.quit
        LD      A,(FINISHED)
        OR      A
        JR      NZ,.quit
        LD      A,(GAMEOVER)
        OR      A
        JR      NZ,.quit
        LD      HL,(IDLETIMER)
        DEC     HL
        LD      (IDLETIMER),HL
        LD      A,H
        OR      L
        JR      NZ,.loop
.quit:
        XOR     A
        LD      (DEMOMODE),A
        LD      (GAMEOVER),A
        RET
