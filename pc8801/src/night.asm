; =====================================================================
; night.asm - 夜のボーナス面の暗がり (テキスト面でマスクする)
; =====================================================================
; ここは GVRAM の裏のメイン RAM (C000h-) で動く。起動時に GAME_ENTRY が
; 本体のうしろから写してくる。GVRAM のプレーンを C000h に出しているあいだは
; ここが見えなくなるので、ここから GVRAM に触る処理を呼ばないこと。
;
; テキスト面は 40 桁 x 25 行で、1 文字 = 16x8 ドット = フィールドの 1 マス。
; 文字はすべてセミグラフィック、色は 1 番 (パレット 1 = 輪郭の暗い紺) で、
;   00h = 何もない (グラフィックが見える)
;   A5h = 市松模様 (半分暗い)
;   FFh = 全部埋まる (暗がり)
; の 3 段階を使う。値の大小がそのまま暗さの順なので、明かりは「小さい方を
; 残す」だけで重ねられる。
;
; 明るいところ (元の版の DrawNight と同じ考え方):
;   柴犬のまわり、柴犬が印をつけた電柱のまわり、柴犬のなわばり。
; 眠っている犬の zZ と起きている犬の目 (render.asm が NIGHTPOS に位置を残す)
; のマスは抜いておき、暗がりの中でも見えるようにする。
; =====================================================================

TC_HALF         EQU 0xA5        ; セミグラフィックの市松模様
TC_DARK         EQU 0xFF
TATTR           EQU 0x38        ; 色属性: 青ビット (= 色 1) / セミグラフィック
TXTROW          EQU 120         ; 1 行 = 文字 80 バイト + 属性 20 組

; ---------------------------------------------------------------------
; TEXTINIT - テキスト面を 40 桁・カラー属性にして、マスク用の面を用意する
;   CRTC と DMAC の設定は N88-BASIC ROM と同じ手順で、行数を 25 行、
;   属性をカラーにしたもの。文字の高さはモニタ (15k / 24k) に合わせて選ぶ。
;   画面は TXTBUF (メイン RAM) から DMA で読ませる。
; ---------------------------------------------------------------------
TEXTINIT:
        LD      HL,TXTBUF
        LD      C,FH
.row:
        LD      B,80
.ch:
        LD      (HL),0
        INC     HL
        DJNZ    .ch
        LD      (HL),0                  ; 0 桁目から色 1 のセミグラフィック
        INC     HL
        LD      (HL),TATTR
        INC     HL
        LD      B,19                    ; のこりの属性は画面の外 (80 桁目)
.at:
        LD      (HL),80
        INC     HL
        LD      (HL),TATTR
        INC     HL
        DJNZ    .at
        DEC     C
        JR      NZ,.row
        LD      A,0x20
        OUT     (P_SYS1),A              ; 40 桁 / カラー
        XOR     A
        OUT     (P_CRTC1),A             ; CRTC リセット (表示を止める)
        LD      A,0xA0
        OUT     (0x68),A                ; DMAC モード (止める)
        LD      A,TXTBUF & 0xFF
        OUT     (0x64),A                ; チャネル 2 のアドレス
        LD      A,TXTBUF >> 8
        OUT     (0x64),A
        LD      A,(TXTROW * FH - 1) & 0xFF
        OUT     (0x65),A                ; 転送数 - 1 (上位 2 ビット = 読み出し)
        LD      A,0x80 | ((TXTROW * FH - 1) >> 8)
        OUT     (0x65),A
        LD      HL,CRTC15
        IN      A,(P_STROBE)
        AND     0x02                    ; 1 = 15kHz (標準) / 0 = 24kHz
        JR      NZ,.k15
        LD      HL,CRTC24
.k15:
        LD      BC,5 * 256 + P_CRTC0
        OTIR
        LD      A,0x43
        OUT     (P_CRTC1),A             ; 割り込みを止める
        LD      A,0xE4
        OUT     (0x68),A                ; DMAC: チャネル 2 / オートロード
        LD      A,0x20
        OUT     (P_CRTC1),A             ; 表示開始
        LD      A,0x80
        OUT     (P_CRTC1),A             ; カーソルを消す
        XOR     A
        OUT     (P_CRTC0),A
        OUT     (P_CRTC0),A
        RET

; 80 字 / 25 行 / 文字の高さ / 帰線 / カラー属性 20 組
CRTC15: DB      0xCE,0x98,0x67,0xDE,0x53        ; 8 ラスタ
CRTC24: DB      0xCE,0x98,0x6F,0x58,0x53        ; 16 ラスタ

; ---------------------------------------------------------------------
; NIGHTOFF - テキスト面を隠す
; ---------------------------------------------------------------------
NIGHTOFF:
        LD      A,LAYER_GAME
        OUT     (P_LAYER),A
        RET

; ---------------------------------------------------------------------
; NIGHTSTART - ステージの始まり。夜なら暗がりを全部計算して出す
; ---------------------------------------------------------------------
NIGHTSTART:
        CALL    NIGHTOFF
        LD      A,(BONUSMODE)
        OR      A
        RET     Z
        LD      HL,NM_IND
        LD      DE,NM_IND+1
        LD      BC,NCELL-1
        LD      (HL),0
        LDIR
        LD      HL,NIGHTPOS
        LD      B,NDOG
.np:
        LD      (HL),0xFF
        INC     HL
        INC     HL
        DJNZ    .np
        XOR     A
        LD      (NM_OLDN),A
        LD      (NM_BAND),A
        INC     A
        LD      (NM_GEN),A
        LD      IX,DOGS
        LD      A,(IX+D_X)
        LD      (NM_LPX),A
        LD      A,(IX+D_Y)
        LD      (NM_LPY),A
        CALL    NMLIGHTS
        LD      DE,FH-1                 ; 0 行目から 24 行目まで
        CALL    NMROWS
        XOR     A
        OUT     (P_LAYER),A             ; テキスト面も出す
        RET

; ---------------------------------------------------------------------
; NIGHTTICK - 1 ティックごと (犬を描いたあと)
;   柴犬のマスが変わったらそのまわりの行、それとは別に毎回 3 行ずつ
;   (9 ティックで 1 周) 計算しなおす。電柱やなわばりの変化は後者で拾う。
; ---------------------------------------------------------------------
NIGHTTICK:
        LD      A,(BONUSMODE)
        OR      A
        RET     Z
        CALL    NMLIGHTS
        LD      IX,DOGS
        LD      A,(NM_LPX)
        CP      (IX+D_X)
        JR      NZ,.moved
        LD      A,(NM_LPY)
        CP      (IX+D_Y)
        JR      Z,.band
.moved:
        LD      A,(NM_LPY)
        LD      C,A                     ; C = 前の行
        LD      A,(IX+D_X)
        LD      (NM_LPX),A
        LD      A,(IX+D_Y)
        LD      (NM_LPY),A
        LD      B,A                     ; B = 今の行
        CP      C
        JR      NC,.ge
        LD      D,B
        LD      E,C
        JR      .mm
.ge:
        LD      D,C
        LD      E,B
.mm:
        LD      A,D                     ; 上の行 - 3 .. 下の行 + 3
        SUB     3
        JR      NC,.lo
        XOR     A
.lo:
        LD      D,A
        LD      A,E
        ADD     A,3
        CP      FH
        JR      C,.hi
        LD      A,FH-1
.hi:
        LD      E,A
        CALL    NMROWS
.band:
        LD      A,(NM_BAND)
        LD      D,A
        ADD     A,2
        CP      FH
        JR      C,.b1
        LD      A,FH-1
.b1:
        LD      E,A
        INC     A
        CP      FH
        JR      C,.b2
        XOR     A
.b2:
        LD      (NM_BAND),A
        CALL    NMROWS
        JP      NMMARKS

; ---------------------------------------------------------------------
; NMROWS - D 行目から E 行目までを計算する
; ---------------------------------------------------------------------
NMROWS:
        PUSH    DE
        LD      A,D
        CALL    NMROW
        CALL    VBPOLL                  ; 1 行 5000 サイクルほど。帰線を逃さない
        POP     DE
        LD      A,D
        INC     D
        CP      E
        JR      C,NMROWS
        RET

; ---------------------------------------------------------------------
; NMLIGHTS - 明かりの一覧 NM_LT を作る
;   1 件 4 バイト (x, y, 明かりの形 2 バイト)。x = FFh で終わり。
;   柴犬が持っている電柱と、柴犬。
; ---------------------------------------------------------------------
NMLIGHTS:
        LD      IX,POLES
        LD      HL,NM_LT
        LD      A,(NPOLES)
        OR      A
        JR      Z,.pl
        LD      B,A
.lp:
        LD      A,(IX+PL_OWNER)
        OR      A
        JR      NZ,.no
        LD      A,(IX+PL_X)
        LD      (HL),A
        INC     HL
        LD      A,(IX+PL_Y)
        LD      (HL),A
        INC     HL
        LD      DE,ST_POLE
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      Z,.st
        LD      DE,ST_LOCK
.st:
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
.no:
        LD      DE,PL_SIZE
        ADD     IX,DE
        DJNZ    .lp
.pl:
        LD      IX,DOGS
        LD      A,(IX+D_X)
        LD      (HL),A
        INC     HL
        LD      A,(IX+D_Y)
        LD      (HL),A
        INC     HL
        LD      (HL),ST_PLAYER & 0xFF
        INC     HL
        LD      (HL),ST_PLAYER >> 8
        INC     HL
        LD      (HL),0xFF
        RET

; 明かりの形: 縦の距離 |dy| = 0..3 ごとに (市松の半幅, 明るい半幅)。FFh = なし
;   元の版の半径 (柴犬 64 / 電柱 36 / 印を固めた電柱 44 ドット) から、
;   暗さ 0.25 以下を明るい、0.75 以下を市松にしたもの。
ST_PLAYER:      DB      3,2, 3,2, 3,1, 2,0xFF
ST_POLE:        DB      2,1, 1,1, 0,0xFF, 0xFF,0xFF
ST_LOCK:        DB      2,1, 2,1, 1,0xFF, 0xFF,0xFF

; ---------------------------------------------------------------------
; NMROW - A 行目の暗さを計算して NM_MASK とテキスト面に書く
; ---------------------------------------------------------------------
NMROW:
        LD      (NM_Y),A
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      (NM_RO),HL              ; 配列の行の先頭 (y * 32)
        ; --- なわばり: 柴犬のマスは明るい、ほかは暗い ---
        LD      DE,NM_MASK
        ADD     HL,DE
        EX      DE,HL
        LD      HL,(NM_RO)
        LD      BC,ARR_TERR
        ADD     HL,BC
        LD      B,FW
.base:
        LD      A,(HL)
        SUB     1                       ; 柴犬 (0) だけ桁あふれする
        SBC     A,A
        CPL                             ; 柴犬 00h / ほか FFh
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .base
        ; --- 明かり ---
        LD      IX,NM_LT
.lt:
        LD      A,(IX+0)
        CP      0xFF
        JR      Z,.out
        LD      A,(NM_Y)
        SUB     (IX+1)
        JR      NC,.pos
        NEG
.pos:
        CP      4
        JR      NC,.next
        ADD     A,A
        ADD     A,(IX+2)
        LD      L,A
        LD      A,(IX+3)
        ADC     A,0
        LD      H,A
        LD      A,(HL)
        LD      C,TC_HALF
        CALL    NMSPAN
        INC     HL
        LD      A,(HL)
        LD      C,0
        CALL    NMSPAN
.next:
        LD      DE,4
        ADD     IX,DE
        JR      .lt
        ; --- テキスト面へ (印のマスは抜く) ---
.out:
        LD      A,(NM_Y)
        LD      L,A
        LD      H,0
        CALL    NMTROW                  ; HL = テキストの行
        EX      DE,HL
        LD      HL,(NM_RO)
        LD      BC,NM_MASK
        ADD     HL,BC
        LD      B,FW
.o:
        LD      A,H
        XOR     NM_PGX
        LD      H,A
        LD      C,(HL)                  ; 印
        XOR     NM_PGX
        LD      H,A
        XOR     A
        CP      C
        JR      NZ,.put
        LD      A,(HL)
.put:
        LD      (DE),A
        INC     DE
        INC     DE
        INC     HL
        DJNZ    .o
        RET

; ---------------------------------------------------------------------
; NMSPAN - 今の行の (IX+0) - A .. (IX+0) + A 桁を C 以下の暗さにする
;   A = FFh なら何もしない。HL / IX はそのまま。
; ---------------------------------------------------------------------
NMSPAN:
        CP      0xFF
        RET     Z
        PUSH    HL
        LD      B,A
        LD      A,(IX+0)
        SUB     B
        JR      NC,.x0
        XOR     A
.x0:
        LD      E,A                     ; 左端
        LD      A,(IX+0)
        ADD     A,B
        CP      FW
        JR      C,.x1
        LD      A,FW-1
.x1:
        SUB     E
        INC     A
        LD      B,A                     ; 桁数
        LD      HL,(NM_RO)
        LD      D,0
        ADD     HL,DE
        LD      DE,NM_MASK
        ADD     HL,DE
.lp:
        LD      A,(HL)
        CP      C
        JR      C,.keep
        LD      (HL),C
.keep:
        INC     HL
        DJNZ    .lp
        POP     HL
        RET

; ---------------------------------------------------------------------
; NMTROW - HL = 行 (0..24) -> HL = テキスト面の行の先頭。BC を壊す
; NMTADDR - HL = マスの番号 (y * 32 + x) -> DE = テキスト面のアドレス
;   HL はそのまま。A / BC を壊す
; ---------------------------------------------------------------------
NMTROW:
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      B,H
        LD      C,L                     ; y * 8
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; y * 128
        OR      A
        SBC     HL,BC                   ; y * 120
        LD      BC,TXTBUF
        ADD     HL,BC
        RET

NMTADDR:
        PUSH    HL
        LD      A,L
        AND     CSTRIDE-1
        ADD     A,A
        PUSH    AF                      ; x * 2
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      L,H
        LD      H,0                     ; y
        CALL    NMTROW
        POP     AF
        LD      E,A
        LD      D,0
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        RET

; ---------------------------------------------------------------------
; NMMARKS - zZ と目の印のマスを抜く / 印がいなくなったマスを戻す
;   NIGHTPOS には render.asm が犬ごとに印を描いた位置 (ドット行, バイト列)
;   を残している。読んだら FFh にしておく。
; ---------------------------------------------------------------------
NMMARKS:
        LD      A,(NM_GEN)
        INC     A
        JR      NZ,.g
        INC     A
.g:
        LD      (NM_GEN),A
        XOR     A
        LD      (NM_NEWN),A
        LD      HL,NM_NEW
        LD      (NM_NEWP),HL
        LD      HL,NIGHTPOS
        LD      B,NDOG
.dog:
        LD      A,(HL)
        CP      0xFF
        JR      Z,.nodog
        LD      (HL),0xFF
        PUSH    BC
        PUSH    HL
        LD      D,A                     ; ドット行
        INC     HL
        LD      E,(HL)                  ; バイト列
        ; 行: y/8 .. (y+7)/8   桁: x/2 .. (x+1)/2
        LD      A,D
        RRCA
        RRCA
        RRCA
        AND     0x1F
        LD      (NM_R0),A
        LD      A,D
        ADD     A,7
        RRCA
        RRCA
        RRCA
        AND     0x1F
        CP      FH
        JR      C,.r1
        LD      A,FH-1
.r1:
        LD      (NM_R1),A
        LD      A,E
        SRL     A
        LD      (NM_C0),A
        LD      A,E
        INC     A
        SRL     A
        CP      FW
        JR      C,.c1
        LD      A,FW-1
.c1:
        LD      (NM_C1),A
        LD      A,(NM_R0)
.rl:
        LD      (NM_RC),A
        LD      A,(NM_C0)
.cl:
        LD      (NM_CC),A
        LD      L,A
        LD      A,(NM_RC)
        LD      H,0
        ; HL = 行 * 32 + 桁
        PUSH    HL
        LD      L,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        POP     DE
        LD      D,0
        ADD     HL,DE
        CALL    NMMARK
        LD      A,(NM_C1)
        LD      C,A
        LD      A,(NM_CC)
        CP      C
        INC     A
        JR      C,.cl
        LD      A,(NM_R1)
        LD      C,A
        LD      A,(NM_RC)
        CP      C
        INC     A
        JR      C,.rl
        POP     HL
        POP     BC
.nodog:
        INC     HL
        INC     HL
        DJNZ    .dog
        ; --- 前の印のうち、今回の印でないマスを戻す ---
        LD      A,(NM_OLDN)
        OR      A
        JR      Z,.swap
        LD      B,A
        LD      HL,NM_OLD
.old:
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        PUSH    BC
        EX      DE,HL                   ; HL = マスの番号
        LD      DE,NM_IND
        ADD     HL,DE
        LD      A,(NM_GEN)
        CP      (HL)
        JR      Z,.still
        LD      (HL),0
        LD      DE,NM_MASK-NM_IND
        ADD     HL,DE
        LD      A,(HL)                  ; そのマスの暗さ
        LD      DE,-NM_MASK
        ADD     HL,DE
        PUSH    AF
        CALL    NMTADDR
        POP     AF
        LD      (DE),A
.still:
        POP     BC
        POP     HL
        DJNZ    .old
.swap:
        LD      A,(NM_NEWN)
        LD      (NM_OLDN),A
        LD      HL,NM_NEW
        LD      DE,NM_OLD
        LD      BC,NDOG*4*2
        LDIR
        RET

; NMMARK - HL = マスの番号 を印のマスにする (テキストを抜いて一覧に足す)
NMMARK:
        PUSH    HL
        LD      DE,NM_IND
        ADD     HL,DE
        LD      A,(NM_GEN)
        LD      (HL),A
        POP     HL
        CALL    NMTADDR
        XOR     A
        LD      (DE),A
        EX      DE,HL
        LD      HL,(NM_NEWP)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (NM_NEWP),HL
        LD      HL,NM_NEWN
        INC     (HL)
        RET

; ---------------------------------------------------------------------
; 変数 (ここもメイン RAM の裏側)
; ---------------------------------------------------------------------
NM_Y:   DB      0
NM_RO:  DW      0
NM_LPX: DB      0
NM_LPY: DB      0
NM_BAND: DB     0
NM_GEN: DB      0
NM_R0:  DB      0
NM_R1:  DB      0
NM_C0:  DB      0
NM_C1:  DB      0
NM_RC:  DB      0
NM_CC:  DB      0
NM_NEWN: DB     0
NM_NEWP: DW     0
NM_OLDN: DB     0
NM_NEW: DS      NDOG*4*2
NM_OLD: DS      NDOG*4*2
NM_LT:  DS      (NPOLE+2)*4
