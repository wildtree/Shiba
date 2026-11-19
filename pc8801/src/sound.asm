; =====================================================================
; sound.asm - YM2203 (OPN) の BGM と効果音
; =====================================================================
; ポート 44h にレジスタ番号、45h にデータを書く。
;   BGM  : FM 3 声 (チャンネル 0,1,2 = 主旋律 / 和音 / ベース)
;   効果音: SSG のチャンネル A
; SSG の I/O ポートはジョイスティック用に入力のままにしておく。
; =====================================================================

; 効果音の番号
; ==== sfxgen.py ここから (効果音の番号) ====
SFX_STEP        EQU 0
SFX_MARK        EQU 1
SFX_INVALID     EQU 2
SFX_OVERWRITE   EQU 3
SFX_TERRITORY   EQU 4
SFX_ENEMYTERR   EQU 5
SFX_ENEMYOUT    EQU 6
SFX_MISS        EQU 7
SFX_CARHIT      EQU 8
SFX_ITEM        EQU 9
SFX_RAIN        EQU 10
SFX_THUNDER     EQU 11
SFX_KICKED      EQU 12
SFX_BARK        EQU 13
SFX_PEEDRIP     EQU 14
SFX_SELECT      EQU 15
SFX_START       EQU 16
SFX_EXTEND      EQU 17
SFX_ACHIEVE     EQU 18
SFX_NAMEOK      EQU 19
SFX_NSFX        EQU 20
; ==== sfxgen.py ここまで (効果音の番号) ====

; BGM の番号
BGM_TITLE       EQU 0
BGM_STAGE       EQU 1
BGM_BONUS       EQU 2
BGM_BOSS        EQU 3
BGM_CLEAR       EQU 4
BGM_OVER        EQU 5
BGM_FAIL        EQU 6
BGM_NONE        EQU 0xFF

; ---------------------------------------------------------------------
; OPNW - OPN のレジスタ A に E を書く
;   YM2203 はアドレスとデータの間に少し待つ必要がある
; ---------------------------------------------------------------------
OPNW:
        OUT     (P_OPN_ADDR),A
        EX      (SP),HL
        EX      (SP),HL
        LD      A,E
        OUT     (P_OPN_DATA),A
        EX      (SP),HL
        EX      (SP),HL
        EX      (SP),HL
        EX      (SP),HL
        RET

; ---------------------------------------------------------------------
; SNDINIT - 音源の初期化
; ---------------------------------------------------------------------
SNDINIT:
        ; SSG: 全部切って、I/O ポートは入力のまま
        LD      A,0x3F
        LD      (MIXER),A
        LD      E,A
        LD      A,0x07
        CALL    OPNW
        LD      B,3
        LD      C,0x08
.ssgvol:
        LD      A,C
        LD      E,0
        CALL    OPNW
        INC     C
        DJNZ    .ssgvol
        ; FM: 3 声ともキーオフ
        LD      B,3
        LD      C,0
.fmoff:
        LD      A,0x28
        LD      E,C
        CALL    OPNW
        INC     C
        DJNZ    .fmoff
        ; 音色を積み込む
        CALL    FMLOADALL
        XOR     A
        LD      (SFXTIMER),A
        LD      (BGMWAIT),A
        LD      A,BGM_NONE
        LD      (BGMTUNE),A
        LD      HL,0
        LD      (SFXPTR),HL
        LD      (BGMPTR),HL
        RET

; ---------------------------------------------------------------------
; FMLOADALL - 3 つのチャンネルに音色を積む
; ---------------------------------------------------------------------
FMLOADALL:
        LD      C,0
        LD      HL,FMPATCH0
        CALL    FMLOAD
        LD      C,1
        LD      HL,FMPATCH1
        CALL    FMLOAD
        LD      C,2
        LD      HL,FMPATCH2
        JP      FMLOAD

; ---------------------------------------------------------------------
; FMLOAD - チャンネル C に HL の音色を積む
;   音色は 4 オペレータ x 6 バイト (DT|MUL, TL, KS|AR, AM|D1R, D2R, D1L|RR)
;   のあとに FB|ALG が 1 バイト。
;   OPN のレジスタは op1,op3,op2,op4 の順に +0,+4,+8,+12 で並ぶ。
; ---------------------------------------------------------------------
FMLOAD:
        LD      B,4                     ; オペレータ 4 つ
        LD      D,0                     ; スロットのオフセット (0,4,8,12)
.op:
        PUSH    BC
        ; 0x30 + slot + ch : DT|MUL
        LD      A,0x30
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,0x40
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,0x50
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,0x60
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,0x70
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,0x80
        ADD     A,D
        ADD     A,C
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    OPNW
        POP     HL
        LD      A,D
        ADD     A,4
        LD      D,A
        POP     BC
        DJNZ    .op
        ; フィードバックとアルゴリズム
        LD      A,0xB0
        ADD     A,C
        LD      E,(HL)
        JP      OPNW

; ---------------------------------------------------------------------
; FMKEY - チャンネル (SND_CH) を 音階 (SND_NOTE) で鳴らす
;   SND_NOTE = 0 ならキーオフ
; ---------------------------------------------------------------------
FMKEY:
        LD      A,(SND_NOTE)
        OR      A
        JR      NZ,.on
        LD      A,(SND_CH)
        LD      E,A
        LD      A,0x28
        JP      OPNW
.on:
        DEC     A
        LD      C,12
        LD      D,0
.div:
        CP      C
        JR      C,.divdone
        SUB     C
        INC     D
        JR      .div
.divdone:
        ; A = 音階 (0..11), D = オクターブ
        ADD     A,A
        LD      E,A
        LD      HL,FNUMTBL
        LD      B,0
        LD      C,E
        ADD     HL,BC
        LD      A,(HL)
        LD      (SND_FL),A              ; F-Num 下位
        INC     HL
        LD      A,(HL)                  ; F-Num 上位
        LD      C,A
        LD      A,D
        ADD     A,2
        AND     7
        ADD     A,A
        ADD     A,A
        ADD     A,A                     ; ブロック << 3
        OR      C
        LD      (SND_FH),A
        ; キーオフ -> 周波数 -> キーオン
        LD      A,(SND_CH)
        LD      E,A
        LD      A,0x28
        CALL    OPNW
        LD      A,(SND_FH)              ; 上位を先に書く決まり
        LD      E,A
        LD      A,(SND_CH)
        ADD     A,0xA4
        CALL    OPNW
        LD      A,(SND_FL)
        LD      E,A
        LD      A,(SND_CH)
        ADD     A,0xA0
        CALL    OPNW
        LD      A,(SND_CH)
        OR      0xF0
        LD      E,A
        LD      A,0x28
        JP      OPNW

; ---------------------------------------------------------------------
; SNDTICK - 1 ティック分
; ---------------------------------------------------------------------
SNDTICK:
        CALL    SFXTICK
        JP      BGMTICK

; ---------------------------------------------------------------------
; SFXPLAY - 効果音 A を鳴らす (優先度が高いものだけ差し替える)
; ---------------------------------------------------------------------
SFXPLAY:
        CP      SFX_NSFX
        RET     NC
        LD      (SFXREQ),A
        LD      HL,SFXPRIO
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      C,(HL)
        LD      A,(SFXTIMER)
        OR      A
        JR      Z,.go
        LD      A,(SFXCUR)
        LD      HL,SFXPRIO
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      A,(HL)
        CP      C
        RET     NC
.go:
        LD      A,(SFXREQ)
        LD      (SFXCUR),A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,SFXTBL
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      (SFXPTR),HL
        JP      SFXNEXT

SFXTICK:
        LD      A,(SFXTIMER)
        OR      A
        RET     Z
        DEC     A
        LD      (SFXTIMER),A
        RET     NZ
        ; つづき
SFXNEXT:
        LD      HL,(SFXPTR)
        LD      A,(HL)
        CP      0xFF
        JP      Z,SFXSTOP
        LD      B,(HL)
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      A,(HL)
        INC     HL
        LD      (SFXVOL),A
        LD      A,(HL)
        INC     HL
        LD      (SFXTIMER),A
        LD      (SFXPTR),HL
        ; 周期
        LD      A,0x00
        LD      E,C
        CALL    OPNW
        LD      A,0x01
        LD      E,B
        CALL    OPNW
        ; ミキサ (bit7 が立っていたらノイズ)
        LD      A,(SFXVOL)
        AND     0x80
        JR      Z,.tone
        LD      A,C                     ; ノイズの行は「周期下位」がノイズ周期
        AND     0x1F
        LD      E,A
        LD      A,0x06
        CALL    OPNW
        LD      A,(MIXER)
        AND     0xC0
        OR      0x37                    ; ch A はノイズだけ
        LD      E,A
        LD      A,0x07
        CALL    OPNW
        JR      .vol
.tone:
        LD      A,(MIXER)
        AND     0xC0
        OR      0x3E                    ; ch A はトーンだけ
        LD      E,A
        LD      A,0x07
        CALL    OPNW
.vol:
        LD      A,(SFXVOL)
        AND     0x0F
        LD      E,A
        LD      A,0x08
        JP      OPNW

SFXSTOP:
        XOR     A
        LD      (SFXTIMER),A
        LD      E,0
        LD      A,0x08
        CALL    OPNW
        LD      A,(MIXER)
        LD      E,A
        LD      A,0x07
        JP      OPNW

; ---------------------------------------------------------------------
; BGMSTART - 曲 A をかける (A = BGM_NONE なら止める)
; ---------------------------------------------------------------------
BGMSTART:
        LD      (BGMTUNE),A
        CP      BGM_NONE
        JP      Z,BGMSTOP
        PUSH    AF
        LD      A,(MUSICON)
        OR      A
        JR      NZ,.on
        POP     AF
        JP      BGMSTOP
.on:
        POP     AF
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,BGMTBL
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      (BGMHEAD),HL
        LD      (BGMPTR),HL
        XOR     A
        LD      (BGMWAIT),A
        RET

BGMSTOP:
        LD      HL,0
        LD      (BGMPTR),HL
        LD      B,3
        LD      C,0
.off:
        LD      A,0x28
        LD      E,C
        CALL    OPNW
        INC     C
        DJNZ    .off
        RET

; ---------------------------------------------------------------------
; BGMTICK - BGM を 1 ティック進める
;   データ: 主旋律, 和音, ベース, 長さ   (音階 0 = 休み / 0xFE = そのまま
;           / 先頭が 0xFF なら最初に戻る)
; ---------------------------------------------------------------------
BGMTICK:
        LD      HL,(BGMPTR)
        LD      A,H
        OR      L
        RET     Z
        LD      A,(BGMWAIT)
        OR      A
        JR      Z,.next
        DEC     A
        LD      (BGMWAIT),A
        RET
.next:
        LD      HL,(BGMPTR)
        LD      A,(HL)
        CP      0xFD
        JP      Z,BGMSTOP               ; ジングルの終わり: 鳴らしっぱなしにしない
        CP      0xFF
        JR      NZ,.play
        LD      HL,(BGMHEAD)
        LD      (BGMPTR),HL
.play:
        LD      HL,(BGMPTR)
        LD      B,3
        LD      C,0                     ; チャンネル
.chlp:
        PUSH    BC
        LD      A,(HL)
        INC     HL
        CP      0xFE
        JR      Z,.hold
        PUSH    HL
        LD      (SND_NOTE),A
        LD      A,C
        LD      (SND_CH),A
        CALL    FMKEY
        POP     HL
.hold:
        POP     BC
        INC     C
        DJNZ    .chlp
        LD      A,(HL)
        INC     HL
        LD      (BGMWAIT),A
        LD      (BGMPTR),HL
        RET

; =====================================================================
; データ
; =====================================================================

; --- FM の音色 -------------------------------------------------------
; 4 オペレータ x (DT|MUL, TL, KS|AR, AM|D1R, D2R, D1L|RR) + FB|ALG
; 並びは op1, op3, op2, op4 (OPN のレジスタの並びと同じ)

; 主旋律: 少し明るいリード
FMPATCH0:
        DB      0x01, 0x20, 0x1F, 0x0A, 0x00, 0x27   ; op1 (変調)
        DB      0x02, 0x2C, 0x1F, 0x0C, 0x00, 0x37   ; op3 (変調)
        DB      0x01, 0x0E, 0x1F, 0x08, 0x02, 0x2A   ; op2 (出力)
        DB      0x01, 0x10, 0x1F, 0x07, 0x02, 0x2A   ; op4 (出力)
        DB      0x1C                                 ; FB=3 ALG=4

; 和音: やわらかい音
FMPATCH1:
        DB      0x01, 0x28, 0x1A, 0x08, 0x00, 0x18
        DB      0x02, 0x30, 0x1A, 0x08, 0x00, 0x18
        DB      0x01, 0x18, 0x1A, 0x06, 0x02, 0x1A
        DB      0x02, 0x1A, 0x1A, 0x06, 0x02, 0x1A
        DB      0x0C                                 ; FB=1 ALG=4

; ベース: 太く短め
FMPATCH2:
        DB      0x01, 0x1C, 0x1F, 0x0E, 0x00, 0x3A
        DB      0x00, 0x30, 0x1F, 0x0E, 0x00, 0x3A
        DB      0x01, 0x0C, 0x1F, 0x0A, 0x04, 0x3A
        DB      0x00, 0x14, 0x1F, 0x0A, 0x04, 0x3A
        DB      0x14                                 ; FB=2 ALG=4

; --- 音階の F-Number (1 オクターブ分、ブロックで上下させる) ----------
; クロック 3.9936MHz のとき f = fnum * 3993600 / (72 * 2^17)
FNUMTBL:
        DW      618, 655, 694, 735, 779, 825
        DW      874, 926, 981, 1040, 1101, 1167

; 音階番号: 1..12 = オクターブ2, 13..24 = オクターブ3,
;           25..36 = オクターブ4, 37..48 = オクターブ5
N_C2    EQU 1
N_D2    EQU 3
N_E2    EQU 5
N_F2    EQU 6
N_G2    EQU 8
N_A2    EQU 10
N_B2    EQU 12
N_C3    EQU 13
N_D3    EQU 15
N_E3    EQU 17
N_F3    EQU 18
N_G3    EQU 20
N_A3    EQU 22
N_B3    EQU 24
N_C4    EQU 25
N_D4    EQU 27
N_E4    EQU 29
N_F4    EQU 30
N_G4    EQU 32
N_A4    EQU 34
N_B4    EQU 36
N_C5    EQU 37
N_D5    EQU 39
N_E5    EQU 41
N_G5    EQU 44
HOLD    EQU 0xFE

BGMTBL:
        DW      BGM_D_TITLE, BGM_D_STAGE, BGM_D_BONUS
        DW      BGM_D_BOSS, BGM_D_CLEAR, BGM_D_OVER, BGM_D_FAIL

; --- タイトル: ゆったり ---
BGM_D_TITLE:
        DB      N_C4, N_E3, N_C2, 8
        DB      N_E4, HOLD, HOLD, 8
        DB      N_G4, N_G3, N_G2, 8
        DB      N_E4, HOLD, HOLD, 8
        DB      N_F4, N_A3, N_F2, 8
        DB      N_A4, HOLD, HOLD, 8
        DB      N_G4, N_G3, N_G2, 8
        DB      N_E4, HOLD, HOLD, 8
        DB      N_D4, N_F3, N_D2, 8
        DB      N_F4, HOLD, HOLD, 8
        DB      N_A4, N_A3, N_A2, 8
        DB      N_F4, HOLD, HOLD, 8
        DB      N_G4, N_B3, N_G2, 8
        DB      N_B4, HOLD, HOLD, 8
        DB      N_C5, N_C4, N_C2, 16
        DB      0, 0, 0, 8
        DB      0xFF

; --- ステージ: はずむ感じ ---
BGM_D_STAGE:
        DB      N_C4, N_E3, N_C2, 4
        DB      N_E4, HOLD, HOLD, 4
        DB      N_G4, HOLD, N_G2, 4
        DB      N_E4, HOLD, HOLD, 4
        DB      N_F4, N_A3, N_F2, 4
        DB      N_A4, HOLD, HOLD, 4
        DB      N_G4, HOLD, N_C3, 4
        DB      N_E4, HOLD, HOLD, 4
        DB      N_D4, N_F3, N_D2, 4
        DB      N_F4, HOLD, HOLD, 4
        DB      N_A4, HOLD, N_A2, 4
        DB      N_F4, HOLD, HOLD, 4
        DB      N_G4, N_B3, N_G2, 4
        DB      N_B4, HOLD, HOLD, 4
        DB      N_C5, HOLD, N_C3, 8
        DB      N_G4, HOLD, HOLD, 4
        DB      N_E4, N_C4, N_C2, 4
        DB      N_C5, HOLD, HOLD, 4
        DB      N_B4, N_B3, N_G2, 4
        DB      N_G4, HOLD, HOLD, 4
        DB      N_A4, N_A3, N_F2, 4
        DB      N_F4, HOLD, HOLD, 4
        DB      N_G4, N_G3, N_G2, 4
        DB      N_E4, HOLD, HOLD, 4
        DB      N_F4, N_F3, N_F2, 4
        DB      N_D4, HOLD, HOLD, 4
        DB      N_E4, N_E3, N_E2, 4
        DB      N_C4, HOLD, HOLD, 4
        DB      N_D4, N_D3, N_G2, 8
        DB      N_C4, N_C3, N_C2, 12
        DB      0xFF

; --- 夜のボーナス: 静か ---
BGM_D_BONUS:
        DB      N_A3, N_C3, N_A2, 12
        DB      N_C4, HOLD, HOLD, 12
        DB      N_E4, N_E3, N_E2, 12
        DB      N_C4, HOLD, HOLD, 12
        DB      N_D4, N_D3, N_D2, 12
        DB      N_B3, HOLD, HOLD, 12
        DB      N_A3, N_A3, N_A2, 24
        DB      0, 0, 0, 8
        DB      0xFF

; --- ボス: 低くて急く ---
BGM_D_BOSS:
        DB      N_C3, N_C3, N_C2, 3
        DB      N_C3, HOLD, HOLD, 3
        DB      N_E3, HOLD, N_C2, 3
        DB      N_C3, HOLD, HOLD, 3
        DB      N_F3, N_F3, N_F2, 3
        DB      N_C3, HOLD, HOLD, 3
        DB      N_G3, HOLD, N_G2, 3
        DB      N_C3, HOLD, HOLD, 3
        DB      N_A3, N_A3, N_A2, 3
        DB      N_G3, HOLD, HOLD, 3
        DB      N_F3, HOLD, N_F2, 3
        DB      N_E3, HOLD, HOLD, 3
        DB      N_D3, N_D3, N_D2, 6
        DB      N_C3, N_C3, N_C2, 6
        DB      0xFF

; ==== sfxgen.py ここから (ジングル) — 直接編集しないこと ====
; 主旋律, 主旋律の 1 オクターブ下, ベース, 長さ-1   (0xFD で止まる)
BGM_D_CLEAR:
        DB      37, 25, 25, 2
        DB      37, 25, HOLD, 2
        DB      37, 25, HOLD, 2
        DB      41, 29, 32, 5
        DB      44, 32, 25, 5
        DB      41, 29, 29, 2
        DB      44, 32, 32, 2
        DB      49, 37, 37, 17
        DB      0xFD
BGM_D_FAIL:
        DB      29, 17, 5, 7
        DB      28, 16, 4, 7
        DB      27, 15, 3, 7
        DB      26, 14, 2, 23
        DB      0xFD
BGM_D_OVER:
        DB      37, 25, 13, 7
        DB      32, 20, HOLD, 7
        DB      29, 17, HOLD, 7
        DB      34, 22, 18, 3
        DB      36, 24, HOLD, 3
        DB      34, 22, HOLD, 3
        DB      33, 21, HOLD, 7
        DB      32, 20, 13, 23
        DB      0, 0, HOLD, 7
        DB      0xFD
; ==== sfxgen.py ここまで (ジングル) ====

; --- 効果音 ---------------------------------------------------------
; ==== sfxgen.py ここから (効果音) — 直接編集しないこと ====
; 優先度 (大きいほど強い。鳴っている音以下の優先度の音は鳴らない)
SFXPRIO:
        DB      1       ; STEP
        DB      5       ; MARK
        DB      5       ; INVALID
        DB      6       ; OVERWRITE
        DB      7       ; TERRITORY
        DB      2       ; ENEMYTERR
        DB      6       ; ENEMYOUT
        DB      8       ; MISS
        DB      8       ; CARHIT
        DB      6       ; ITEM
        DB      5       ; RAIN
        DB      7       ; THUNDER
        DB      5       ; KICKED
        DB      4       ; BARK
        DB      3       ; PEEDRIP
        DB      3       ; SELECT
        DB      9       ; START
        DB      9       ; EXTEND
        DB      9       ; ACHIEVE
        DB      9       ; NAMEOK

SFXTBL:
        DW      SFX_D_STEP, SFX_D_MARK, SFX_D_INVALID, SFX_D_OVERWRITE
        DW      SFX_D_TERRITORY, SFX_D_ENEMYTERR, SFX_D_ENEMYOUT, SFX_D_MISS
        DW      SFX_D_CARHIT, SFX_D_ITEM, SFX_D_RAIN, SFX_D_THUNDER
        DW      SFX_D_KICKED, SFX_D_BARK, SFX_D_PEEDRIP, SFX_D_SELECT
        DW      SFX_D_START, SFX_D_EXTEND, SFX_D_ACHIEVE, SFX_D_NAMEOK

; 周期上位, 周期下位 (ノイズのときはノイズ周期), 音量 (bit7 でノイズ), 長さ (ティック)
SFX_D_STEP:
        DB      0x00,0x71,0x08,1    ; 552Hz
        DB      0xFF
SFX_D_MARK:
        DB      0x00,0x2F,0x0C,2    ; e6 1328Hz
        DB      0x00,0x23,0x0C,4    ; a6 1783Hz
        DB      0xFF
SFX_D_INVALID:
        DB      0x02,0x08,0x0C,3    ; 120Hz
        DB      0x02,0x58,0x0B,3    ; 104Hz
        DB      0xFF
SFX_D_OVERWRITE:
        DB      0x00,0x47,0x0C,2    ; a5 879Hz
        DB      0x00,0x5F,0x0C,2    ; e5 657Hz
        DB      0x00,0x47,0x0C,2    ; a5 879Hz
        DB      0x00,0x2F,0x0C,2    ; e6 1328Hz
        DB      0xFF
SFX_D_TERRITORY:
        DB      0x00,0x77,0x0D,2    ; c5 524Hz
        DB      0x00,0x5F,0x0D,2    ; e5 657Hz
        DB      0x00,0x50,0x0D,2    ; g5 780Hz
        DB      0x00,0x3C,0x0D,2    ; c6 1040Hz
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x28,0x0D,2    ; g6 1560Hz
        DB      0x00,0x1E,0x0D,6    ; c7 2080Hz
        DB      0xFF
SFX_D_ENEMYTERR:
        DB      0x01,0x3E,0x09,2    ; g3 196Hz
        DB      0x01,0x0C,0x09,2    ; a#3 233Hz
        DB      0x00,0xD4,0x09,2    ; d4 294Hz
        DB      0x00,0x9F,0x09,6    ; g4 392Hz
        DB      0xFF
SFX_D_ENEMYOUT:
        DB      0x00,0x59,0x0C,1    ; 701Hz
        DB      0x00,0x34,0x0C,1    ; 1200Hz
        DB      0x00,0x25,0x0C,1    ; 1686Hz
        DB      0x00,0x50,0x0C,2    ; g5 780Hz
        DB      0x00,0x3C,0x0C,2    ; c6 1040Hz
        DB      0x00,0x2F,0x0C,2    ; e6 1328Hz
        DB      0x00,0x28,0x0C,6    ; g6 1560Hz
        DB      0xFF
SFX_D_MISS:
        DB      0x00,0x45,0x0D,3    ; 904Hz
        DB      0x00,0x60,0x0C,3    ; 650Hz
        DB      0x00,0x8B,0x0B,3    ; 449Hz
        DB      0x00,0xC3,0x0A,3    ; 320Hz
        DB      0x01,0x0F,0x09,3    ; 230Hz
        DB      0x01,0x86,0x08,3    ; 160Hz
        DB      0x02,0x37,0x07,4    ; 110Hz
        DB      0xFF
SFX_D_CARHIT:
        DB      0x00,0x03,0x8F,2    ; ノイズ周期 3
        DB      0x00,0x08,0x8E,2    ; ノイズ周期 8
        DB      0x00,0x0E,0x8C,2    ; ノイズ周期 14
        DB      0x00,0x16,0x8A,2    ; ノイズ周期 22
        DB      0x00,0x1F,0x88,3    ; ノイズ周期 31
        DB      0xFF
SFX_D_ITEM:
        DB      0x00,0x2F,0x0C,2    ; e6 1328Hz
        DB      0x00,0x28,0x0C,2    ; g6 1560Hz
        DB      0x00,0x2F,0x0C,2    ; e6 1328Hz
        DB      0x00,0x1E,0x0C,6    ; c7 2080Hz
        DB      0xFF
SFX_D_RAIN:
        DB      0x00,0x01,0x89,6    ; ノイズ周期 1
        DB      0x00,0x02,0x87,6    ; ノイズ周期 2
        DB      0x00,0x03,0x85,8    ; ノイズ周期 3
        DB      0xFF
SFX_D_THUNDER:
        DB      0x00,0x06,0x8F,3    ; ノイズ周期 6
        DB      0x00,0x0C,0x8E,4    ; ノイズ周期 12
        DB      0x00,0x12,0x8C,5    ; ノイズ周期 18
        DB      0x00,0x18,0x8A,6    ; ノイズ周期 24
        DB      0x00,0x1F,0x88,8    ; ノイズ周期 31
        DB      0xFF
SFX_D_KICKED:
        DB      0x00,0x3C,0x0C,2    ; c6 1040Hz
        DB      0x00,0x50,0x0C,2    ; g5 780Hz
        DB      0x00,0x5F,0x0C,2    ; e5 657Hz
        DB      0x00,0x77,0x0C,2    ; c5 524Hz
        DB      0xFF
SFX_D_BARK:
        DB      0x00,0x78,0x0D,1    ; 520Hz
        DB      0x00,0x45,0x0D,2    ; 904Hz
        DB      0x00,0x00,0x00,2    ; 休み
        DB      0x00,0x74,0x0D,1    ; 538Hz
        DB      0x00,0x42,0x0D,2    ; 945Hz
        DB      0xFF
SFX_D_PEEDRIP:
        DB      0x00,0x21,0x0B,1    ; 1891Hz
        DB      0x00,0x32,0x09,1    ; 1248Hz
        DB      0xFF
SFX_D_SELECT:
        DB      0x00,0x47,0x0B,2    ; 879Hz
        DB      0xFF
SFX_D_START:
        DB      0x00,0x77,0x0D,2    ; c5 524Hz
        DB      0x00,0x5F,0x0D,2    ; e5 657Hz
        DB      0x00,0x50,0x0D,2    ; g5 780Hz
        DB      0x00,0x3C,0x0D,6    ; c6 1040Hz
        DB      0xFF
SFX_D_EXTEND:
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x28,0x0D,2    ; g6 1560Hz
        DB      0x00,0x18,0x0D,2    ; e7 2600Hz
        DB      0x00,0x1E,0x0D,2    ; c7 2080Hz
        DB      0x00,0x1B,0x0D,2    ; d7 2311Hz
        DB      0x00,0x14,0x0D,8    ; g7 3120Hz
        DB      0xFF
SFX_D_ACHIEVE:
        DB      0x00,0x50,0x0D,2    ; g5 780Hz
        DB      0x00,0x3C,0x0D,2    ; c6 1040Hz
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x28,0x0D,2    ; g6 1560Hz
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x28,0x0D,2    ; g6 1560Hz
        DB      0x00,0x1E,0x0D,8    ; c7 2080Hz
        DB      0xFF
SFX_D_NAMEOK:
        DB      0x00,0x50,0x0D,2    ; g5 780Hz
        DB      0x00,0x3C,0x0D,2    ; c6 1040Hz
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x3C,0x0D,2    ; c6 1040Hz
        DB      0x00,0x2F,0x0D,2    ; e6 1328Hz
        DB      0x00,0x28,0x0D,8    ; g6 1560Hz
        DB      0xFF
; ==== sfxgen.py ここまで (効果音) ====
