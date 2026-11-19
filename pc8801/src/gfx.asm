; =====================================================================
; gfx.asm - 画面まわり
; =====================================================================
; GVRAM は独立アクセスモードで使う。ポート 5Ch/5Dh/5Eh でプレーンを
; C000h-FFFFh に出し、5Fh でメイン RAM に戻す。
;   GVRAM0 = 青, GVRAM1 = 赤, GVRAM2 = 緑
;   色番号のビット 0/1/2 がそれぞれプレーン 0/1/2 に対応する。
; 色 0 は書き込みゼロのまま = 地面の色にしてあるので、地面は描かなくてよい。
;
; スプライトの形式 (16x8 ドット、48 バイト):
;   16 組 x 3 バイト = (マスク, 体, 白)
;   並びは 行0の左, 行0の右, 行1の左, ... 行7の右
;   マスク = 不透明なドット / 体 = 体の色のドット / 白 = 白のドット
;   マスクのうち体でも白でもないドットは輪郭 (黒) になる
; =====================================================================

; ---------------------------------------------------------------------
; GFX_INIT - 画面モードとパレットの設定、GVRAM の消去
; ---------------------------------------------------------------------
GFX_INIT:
        LD      A,MISC_GAME
        OUT     (P_MISC),A              ; アナログパレット / F000h 以降はメイン RAM
        LD      A,SYS2_GAME
        OUT     (P_SYS2),A              ; 200 行 / カラー / グラフィック表示 / 64K RAM
        LD      A,LAYER_GAME
        OUT     (P_LAYER),A             ; テキスト面を隠す
        XOR     A
        OUT     (P_BGCOL),A             ; 背景・ボーダーは黒
        CALL    SETPAL
        CALL    CLS
        RET

; ---------------------------------------------------------------------
; SETPAL - アナログパレット (512 色中 8 色)
;   ポート 54h+n に 2 回書く:
;     bit7=0 bit6=0 のとき  00 RRR BBB   (赤と青)
;     bit7=0 bit6=1 のとき  01 - - GGG   (緑)
; ---------------------------------------------------------------------
SETPAL:
        LD      HL,PALDATA
        LD      B,8
        LD      C,P_PAL0
.lp:
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        INC     C
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; CLS - GVRAM の 3 プレーンすべてを 0 にする
; ---------------------------------------------------------------------
CLS:
        XOR     A
        LD      (HUDBG),A               ; HUD の背景は HUDALL が設定しなおす
        LD      C,P_GV0
.plane:
        XOR     A
        OUT     (C),A
        PUSH    BC
        LD      HL,VRAM
        LD      (HL),A
        LD      DE,VRAM+1
        LD      BC,320-1
        LDIR
        ; 残りは 4 行 (320 バイト) ずつ。あいだで帰線を数える (音も止めない)
        LD      A,16000/320-1
.chunk:
        CALL    VBPOLL
        LD      BC,320
        LDIR
        DEC     A
        JR      NZ,.chunk
        POP     BC
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; VADDR_CELL - マス (x,y) の VRAM アドレス
;   入力: B = セル x (0..29), C = セル y (0..24)
;   出力: HL = VRAM アドレス
;   壊す: A, DE
; ---------------------------------------------------------------------
VADDR_CELL:
        LD      H,0
        LD      L,C
        ADD     HL,HL
        LD      DE,ROWADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)                  ; DE = そのマス行の先頭
        LD      H,0
        LD      L,B
        ADD     HL,HL                   ; x * 2 バイト
        ADD     HL,DE
        RET

; ---------------------------------------------------------------------
; VADDR_PX - ドット位置の VRAM アドレス
;   入力: D = ドット行 (0..199), E = バイト列 (0..79)
;   出力: HL = VRAM アドレス
;   壊す: A, BC
; ---------------------------------------------------------------------
VADDR_PX:
        LD      H,0
        LD      L,D
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; y*16
        LD      B,H
        LD      C,L
        ADD     HL,HL
        ADD     HL,HL                   ; y*64
        ADD     HL,BC                   ; y*80
        LD      B,0
        LD      C,E
        ADD     HL,BC
        LD      BC,VRAM
        ADD     HL,BC
        RET

; ---------------------------------------------------------------------
; FILLCELL - マス 1 個を模様で塗る
;   入力: HL = VRAM アドレス
;         DE = 模様 (6 バイト: 偶数行 p0,p1,p2 / 奇数行 p0,p1,p2)
;   8 行をアンロールして書くので 1 プレーンあたり 250 サイクルほど。
;   壊す: すべて
; ---------------------------------------------------------------------
FILLCELL:
        LD      (GFX_VA),HL
        LD      (GFX_ST),DE
        LD      C,P_GV0
.plane:
        LD      A,0
        OUT     (C),A                   ; このプレーンを窓に出す
        ; このプレーンの偶数行・奇数行の値を取り出す
        LD      HL,(GFX_ST)
        LD      A,C
        SUB     P_GV0
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      D,(HL)                  ; 偶数行
        INC     HL
        INC     HL
        INC     HL
        LD      E,(HL)                  ; 奇数行
        LD      HL,(GFX_VA)
        PUSH    BC
        LD      BC,VSTRIDE-1
        ; 8 行をそのまま並べる
        LD      (HL),D
        INC     HL
        LD      (HL),D
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),E
        ADD     HL,BC
        LD      (HL),D
        INC     HL
        LD      (HL),D
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),E
        ADD     HL,BC
        LD      (HL),D
        INC     HL
        LD      (HL),D
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),E
        ADD     HL,BC
        LD      (HL),D
        INC     HL
        LD      (HL),D
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),E
        POP     BC
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; EDGECELL - なわばりの縁取りを描く (色は 1 番 = プレーン 0 だけ)
;   入力: HL = VRAM アドレス, A = 縁のビット
;         bit0 上 / bit1 下 / bit2 左 / bit3 右
; ---------------------------------------------------------------------
EDGECELL:
        OR      A
        RET     Z
        LD      (GFX_EDGE),A
        LD      (GFX_VA),HL
        LD      C,P_GV0
.plane:
        LD      A,0
        OUT     (C),A
        ; このプレーンでの縁の色のビット (色 1 = プレーン 0 だけ 1)
        LD      A,C
        CP      P_GV0
        LD      A,0xFF
        JR      Z,.full
        XOR     A
.full:
        LD      (GFX_EV),A              ; 行全体の値
        ; --- 上の辺 ---
        LD      A,(GFX_EDGE)
        BIT     0,A
        JR      Z,.nodown0
        LD      HL,(GFX_VA)
        LD      A,(GFX_EV)
        LD      (HL),A
        INC     HL
        LD      (HL),A
.nodown0:
        ; --- 下の辺 ---
        LD      A,(GFX_EDGE)
        BIT     1,A
        JR      Z,.noup
        LD      HL,(GFX_VA)
        LD      DE,VSTRIDE*7
        ADD     HL,DE
        LD      A,(GFX_EV)
        LD      (HL),A
        INC     HL
        LD      (HL),A
.noup:
        ; --- 左の辺 (各行の bit7) ---
        LD      A,(GFX_EDGE)
        BIT     2,A
        JR      Z,.noleft
        LD      HL,(GFX_VA)
        LD      DE,VSTRIDE
        LD      B,8
.lf:
        LD      A,(GFX_EV)
        OR      A
        LD      A,(HL)
        JR      Z,.lclr
        OR      0x80
        JR      .lput
.lclr:
        AND     0x7F
.lput:
        LD      (HL),A
        ADD     HL,DE
        DJNZ    .lf
.noleft:
        ; --- 右の辺 (各行の bit0) ---
        LD      A,(GFX_EDGE)
        BIT     3,A
        JR      Z,.noright
        LD      HL,(GFX_VA)
        INC     HL
        LD      DE,VSTRIDE
        LD      B,8
.rt:
        LD      A,(GFX_EV)
        OR      A
        LD      A,(HL)
        JR      Z,.rclr
        OR      0x01
        JR      .rput
.rclr:
        AND     0xFE
.rput:
        LD      (HL),A
        ADD     HL,DE
        DJNZ    .rt
.noright:
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; DRAWSPR - 16x8 のスプライトを重ねて描く
;   入力: IX = 絵 (64 バイト: 16 バイト列 x マスク/p0下地/p1,2下地/体)
;         A  = 体の色 (0..7)
;         D  = ドット行, E = バイト列
;   プレーンごとの合成は絵の中にあらかじめ入れてあるので、
;   ここは「読んで AND して OR して書く」だけ。16 バイト列ぶん展開済み。
;   壊す: すべて
; ---------------------------------------------------------------------
DRAWSPR:
        CALL    VBPOLL
        LD      (GFX_COL),A
        CALL    VADDR_PX
        LD      (GFX_VA),HL
        LD      DE,VSTRIDE-1

        ; --- プレーン 0 (青): 下地 = 輪郭|白 ---
        XOR     A
        OUT     (P_GV0),A
        LD      A,(GFX_COL)
        BIT     0,A
        JR      Z,.p0n
        CALL    SPRB0
        JR      .pl1
.p0n:   CALL    SPRN0
.pl1:
        ; --- プレーン 1 (赤): 下地 = 白 ---
        XOR     A
        OUT     (P_GV0+1),A
        LD      HL,(GFX_VA)
        LD      DE,VSTRIDE-1
        LD      A,(GFX_COL)
        BIT     1,A
        JR      Z,.p1n
        CALL    SPRB1
        JR      .pl2
.p1n:   CALL    SPRN1
.pl2:
        ; --- プレーン 2 (緑): 下地 = 白 ---
        XOR     A
        OUT     (P_GV0+2),A
        LD      HL,(GFX_VA)
        LD      DE,VSTRIDE-1
        LD      A,(GFX_COL)
        BIT     2,A
        JR      Z,.p2n
        CALL    SPRB1
        JR      .done
.p2n:   CALL    SPRN1
.done:
        XOR     A
        OUT     (P_GVOFF),A
        RET

; SPRB0/SPRN0 = プレーン 0 用 (下地 +1) / SPRB1/SPRN1 = プレーン 1,2 用 (下地 +2)
; B の付くほうは体の色も OR する。
;   入力: HL = VRAM, DE = VSTRIDE-1, IX = 絵
SPRB0:
        LD      A,(IX+0)
        OR      A
        JR      Z,.s00
        CPL
        AND     (HL)
        OR      (IX+1)
        OR      (IX+3)
        LD      (HL),A
.s00:
        INC     HL
        LD      A,(IX+4)
        OR      A
        JR      Z,.s01
        CPL
        AND     (HL)
        OR      (IX+5)
        OR      (IX+7)
        LD      (HL),A
.s01:
        ADD     HL,DE
        LD      A,(IX+8)
        OR      A
        JR      Z,.s10
        CPL
        AND     (HL)
        OR      (IX+9)
        OR      (IX+11)
        LD      (HL),A
.s10:
        INC     HL
        LD      A,(IX+12)
        OR      A
        JR      Z,.s11
        CPL
        AND     (HL)
        OR      (IX+13)
        OR      (IX+15)
        LD      (HL),A
.s11:
        ADD     HL,DE
        LD      A,(IX+16)
        OR      A
        JR      Z,.s20
        CPL
        AND     (HL)
        OR      (IX+17)
        OR      (IX+19)
        LD      (HL),A
.s20:
        INC     HL
        LD      A,(IX+20)
        OR      A
        JR      Z,.s21
        CPL
        AND     (HL)
        OR      (IX+21)
        OR      (IX+23)
        LD      (HL),A
.s21:
        ADD     HL,DE
        LD      A,(IX+24)
        OR      A
        JR      Z,.s30
        CPL
        AND     (HL)
        OR      (IX+25)
        OR      (IX+27)
        LD      (HL),A
.s30:
        INC     HL
        LD      A,(IX+28)
        OR      A
        JR      Z,.s31
        CPL
        AND     (HL)
        OR      (IX+29)
        OR      (IX+31)
        LD      (HL),A
.s31:
        ADD     HL,DE
        LD      A,(IX+32)
        OR      A
        JR      Z,.s40
        CPL
        AND     (HL)
        OR      (IX+33)
        OR      (IX+35)
        LD      (HL),A
.s40:
        INC     HL
        LD      A,(IX+36)
        OR      A
        JR      Z,.s41
        CPL
        AND     (HL)
        OR      (IX+37)
        OR      (IX+39)
        LD      (HL),A
.s41:
        ADD     HL,DE
        LD      A,(IX+40)
        OR      A
        JR      Z,.s50
        CPL
        AND     (HL)
        OR      (IX+41)
        OR      (IX+43)
        LD      (HL),A
.s50:
        INC     HL
        LD      A,(IX+44)
        OR      A
        JR      Z,.s51
        CPL
        AND     (HL)
        OR      (IX+45)
        OR      (IX+47)
        LD      (HL),A
.s51:
        ADD     HL,DE
        LD      A,(IX+48)
        OR      A
        JR      Z,.s60
        CPL
        AND     (HL)
        OR      (IX+49)
        OR      (IX+51)
        LD      (HL),A
.s60:
        INC     HL
        LD      A,(IX+52)
        OR      A
        JR      Z,.s61
        CPL
        AND     (HL)
        OR      (IX+53)
        OR      (IX+55)
        LD      (HL),A
.s61:
        ADD     HL,DE
        LD      A,(IX+56)
        OR      A
        JR      Z,.s70
        CPL
        AND     (HL)
        OR      (IX+57)
        OR      (IX+59)
        LD      (HL),A
.s70:
        INC     HL
        LD      A,(IX+60)
        OR      A
        JR      Z,.s71
        CPL
        AND     (HL)
        OR      (IX+61)
        OR      (IX+63)
        LD      (HL),A
.s71:
        RET

SPRN0:
        LD      A,(IX+0)
        OR      A
        JR      Z,.s00
        CPL
        AND     (HL)
        OR      (IX+1)
        LD      (HL),A
.s00:
        INC     HL
        LD      A,(IX+4)
        OR      A
        JR      Z,.s01
        CPL
        AND     (HL)
        OR      (IX+5)
        LD      (HL),A
.s01:
        ADD     HL,DE
        LD      A,(IX+8)
        OR      A
        JR      Z,.s10
        CPL
        AND     (HL)
        OR      (IX+9)
        LD      (HL),A
.s10:
        INC     HL
        LD      A,(IX+12)
        OR      A
        JR      Z,.s11
        CPL
        AND     (HL)
        OR      (IX+13)
        LD      (HL),A
.s11:
        ADD     HL,DE
        LD      A,(IX+16)
        OR      A
        JR      Z,.s20
        CPL
        AND     (HL)
        OR      (IX+17)
        LD      (HL),A
.s20:
        INC     HL
        LD      A,(IX+20)
        OR      A
        JR      Z,.s21
        CPL
        AND     (HL)
        OR      (IX+21)
        LD      (HL),A
.s21:
        ADD     HL,DE
        LD      A,(IX+24)
        OR      A
        JR      Z,.s30
        CPL
        AND     (HL)
        OR      (IX+25)
        LD      (HL),A
.s30:
        INC     HL
        LD      A,(IX+28)
        OR      A
        JR      Z,.s31
        CPL
        AND     (HL)
        OR      (IX+29)
        LD      (HL),A
.s31:
        ADD     HL,DE
        LD      A,(IX+32)
        OR      A
        JR      Z,.s40
        CPL
        AND     (HL)
        OR      (IX+33)
        LD      (HL),A
.s40:
        INC     HL
        LD      A,(IX+36)
        OR      A
        JR      Z,.s41
        CPL
        AND     (HL)
        OR      (IX+37)
        LD      (HL),A
.s41:
        ADD     HL,DE
        LD      A,(IX+40)
        OR      A
        JR      Z,.s50
        CPL
        AND     (HL)
        OR      (IX+41)
        LD      (HL),A
.s50:
        INC     HL
        LD      A,(IX+44)
        OR      A
        JR      Z,.s51
        CPL
        AND     (HL)
        OR      (IX+45)
        LD      (HL),A
.s51:
        ADD     HL,DE
        LD      A,(IX+48)
        OR      A
        JR      Z,.s60
        CPL
        AND     (HL)
        OR      (IX+49)
        LD      (HL),A
.s60:
        INC     HL
        LD      A,(IX+52)
        OR      A
        JR      Z,.s61
        CPL
        AND     (HL)
        OR      (IX+53)
        LD      (HL),A
.s61:
        ADD     HL,DE
        LD      A,(IX+56)
        OR      A
        JR      Z,.s70
        CPL
        AND     (HL)
        OR      (IX+57)
        LD      (HL),A
.s70:
        INC     HL
        LD      A,(IX+60)
        OR      A
        JR      Z,.s71
        CPL
        AND     (HL)
        OR      (IX+61)
        LD      (HL),A
.s71:
        RET

SPRB1:
        LD      A,(IX+0)
        OR      A
        JR      Z,.s00
        CPL
        AND     (HL)
        OR      (IX+2)
        OR      (IX+3)
        LD      (HL),A
.s00:
        INC     HL
        LD      A,(IX+4)
        OR      A
        JR      Z,.s01
        CPL
        AND     (HL)
        OR      (IX+6)
        OR      (IX+7)
        LD      (HL),A
.s01:
        ADD     HL,DE
        LD      A,(IX+8)
        OR      A
        JR      Z,.s10
        CPL
        AND     (HL)
        OR      (IX+10)
        OR      (IX+11)
        LD      (HL),A
.s10:
        INC     HL
        LD      A,(IX+12)
        OR      A
        JR      Z,.s11
        CPL
        AND     (HL)
        OR      (IX+14)
        OR      (IX+15)
        LD      (HL),A
.s11:
        ADD     HL,DE
        LD      A,(IX+16)
        OR      A
        JR      Z,.s20
        CPL
        AND     (HL)
        OR      (IX+18)
        OR      (IX+19)
        LD      (HL),A
.s20:
        INC     HL
        LD      A,(IX+20)
        OR      A
        JR      Z,.s21
        CPL
        AND     (HL)
        OR      (IX+22)
        OR      (IX+23)
        LD      (HL),A
.s21:
        ADD     HL,DE
        LD      A,(IX+24)
        OR      A
        JR      Z,.s30
        CPL
        AND     (HL)
        OR      (IX+26)
        OR      (IX+27)
        LD      (HL),A
.s30:
        INC     HL
        LD      A,(IX+28)
        OR      A
        JR      Z,.s31
        CPL
        AND     (HL)
        OR      (IX+30)
        OR      (IX+31)
        LD      (HL),A
.s31:
        ADD     HL,DE
        LD      A,(IX+32)
        OR      A
        JR      Z,.s40
        CPL
        AND     (HL)
        OR      (IX+34)
        OR      (IX+35)
        LD      (HL),A
.s40:
        INC     HL
        LD      A,(IX+36)
        OR      A
        JR      Z,.s41
        CPL
        AND     (HL)
        OR      (IX+38)
        OR      (IX+39)
        LD      (HL),A
.s41:
        ADD     HL,DE
        LD      A,(IX+40)
        OR      A
        JR      Z,.s50
        CPL
        AND     (HL)
        OR      (IX+42)
        OR      (IX+43)
        LD      (HL),A
.s50:
        INC     HL
        LD      A,(IX+44)
        OR      A
        JR      Z,.s51
        CPL
        AND     (HL)
        OR      (IX+46)
        OR      (IX+47)
        LD      (HL),A
.s51:
        ADD     HL,DE
        LD      A,(IX+48)
        OR      A
        JR      Z,.s60
        CPL
        AND     (HL)
        OR      (IX+50)
        OR      (IX+51)
        LD      (HL),A
.s60:
        INC     HL
        LD      A,(IX+52)
        OR      A
        JR      Z,.s61
        CPL
        AND     (HL)
        OR      (IX+54)
        OR      (IX+55)
        LD      (HL),A
.s61:
        ADD     HL,DE
        LD      A,(IX+56)
        OR      A
        JR      Z,.s70
        CPL
        AND     (HL)
        OR      (IX+58)
        OR      (IX+59)
        LD      (HL),A
.s70:
        INC     HL
        LD      A,(IX+60)
        OR      A
        JR      Z,.s71
        CPL
        AND     (HL)
        OR      (IX+62)
        OR      (IX+63)
        LD      (HL),A
.s71:
        RET

SPRN1:
        LD      A,(IX+0)
        OR      A
        JR      Z,.s00
        CPL
        AND     (HL)
        OR      (IX+2)
        LD      (HL),A
.s00:
        INC     HL
        LD      A,(IX+4)
        OR      A
        JR      Z,.s01
        CPL
        AND     (HL)
        OR      (IX+6)
        LD      (HL),A
.s01:
        ADD     HL,DE
        LD      A,(IX+8)
        OR      A
        JR      Z,.s10
        CPL
        AND     (HL)
        OR      (IX+10)
        LD      (HL),A
.s10:
        INC     HL
        LD      A,(IX+12)
        OR      A
        JR      Z,.s11
        CPL
        AND     (HL)
        OR      (IX+14)
        LD      (HL),A
.s11:
        ADD     HL,DE
        LD      A,(IX+16)
        OR      A
        JR      Z,.s20
        CPL
        AND     (HL)
        OR      (IX+18)
        LD      (HL),A
.s20:
        INC     HL
        LD      A,(IX+20)
        OR      A
        JR      Z,.s21
        CPL
        AND     (HL)
        OR      (IX+22)
        LD      (HL),A
.s21:
        ADD     HL,DE
        LD      A,(IX+24)
        OR      A
        JR      Z,.s30
        CPL
        AND     (HL)
        OR      (IX+26)
        LD      (HL),A
.s30:
        INC     HL
        LD      A,(IX+28)
        OR      A
        JR      Z,.s31
        CPL
        AND     (HL)
        OR      (IX+30)
        LD      (HL),A
.s31:
        ADD     HL,DE
        LD      A,(IX+32)
        OR      A
        JR      Z,.s40
        CPL
        AND     (HL)
        OR      (IX+34)
        LD      (HL),A
.s40:
        INC     HL
        LD      A,(IX+36)
        OR      A
        JR      Z,.s41
        CPL
        AND     (HL)
        OR      (IX+38)
        LD      (HL),A
.s41:
        ADD     HL,DE
        LD      A,(IX+40)
        OR      A
        JR      Z,.s50
        CPL
        AND     (HL)
        OR      (IX+42)
        LD      (HL),A
.s50:
        INC     HL
        LD      A,(IX+44)
        OR      A
        JR      Z,.s51
        CPL
        AND     (HL)
        OR      (IX+46)
        LD      (HL),A
.s51:
        ADD     HL,DE
        LD      A,(IX+48)
        OR      A
        JR      Z,.s60
        CPL
        AND     (HL)
        OR      (IX+50)
        LD      (HL),A
.s60:
        INC     HL
        LD      A,(IX+52)
        OR      A
        JR      Z,.s61
        CPL
        AND     (HL)
        OR      (IX+54)
        LD      (HL),A
.s61:
        ADD     HL,DE
        LD      A,(IX+56)
        OR      A
        JR      Z,.s70
        CPL
        AND     (HL)
        OR      (IX+58)
        LD      (HL),A
.s70:
        INC     HL
        LD      A,(IX+60)
        OR      A
        JR      Z,.s71
        CPL
        AND     (HL)
        OR      (IX+62)
        LD      (HL),A
.s71:
        RET

; ---------------------------------------------------------------------
; BLITOPQ2 / BLITOPQ4 - 透明なしの絵をそのまま流し込む
;   入力: HL = 絵 (プレーン 0,1,2 の順に 8 行 x 2 or 4 バイト)
;         DE = 書き込み先 VRAM (左上)
;   マスクも VRAM 読みもないので 1 プレーン 500 サイクルほど。
;   壊す: すべて
; ---------------------------------------------------------------------
BLITOPQ2:
        CALL    VBPOLL
        LD      (OPQ_VA),DE
        LD      A,P_GV0
.plane:
        LD      (OPQ_PL),A
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      DE,(OPQ_VA)
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-2
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LD      A,(OPQ_PL)
        INC     A
        CP      P_GV0+3
        JP      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

BLITOPQ4:
        CALL    VBPOLL
        LD      (OPQ_VA),DE
        LD      A,P_GV0
.plane:
        LD      (OPQ_PL),A
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      DE,(OPQ_VA)
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        EX      DE,HL
        LD      BC,VSTRIDE-4
        ADD     HL,BC
        EX      DE,HL
        LDI
        LDI
        LDI
        LDI
        LD      A,(OPQ_PL)
        INC     A
        CP      P_GV0+3
        JP      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; BLITOPQW - 不透明な 32x8 の絵を左から A バイトだけ描く (画面端のクリップ用)
;   入力: HL = 絵 (1 行 4 バイト), DE = VRAM, A = 1..4
; ---------------------------------------------------------------------
BLITOPQW:
        CALL    VBPOLL
        LD      (OPQ_W),A
        LD      C,A
        LD      A,VSTRIDE
        SUB     C
        LD      (OPQ_STEP),A
        XOR     A
        LD      (OPQ_STEP+1),A
        LD      (OPQ_VA),DE
        LD      (OPQ_SRC),HL
        LD      A,P_GV0
.plane:
        LD      (OPQ_PL),A
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      DE,(OPQ_VA)
        LD      HL,(OPQ_SRC)
        LD      B,8
.row:
        PUSH    BC
        LD      A,(OPQ_W)
        LD      B,A
.byte:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .byte
        ; 絵は 1 行 4 バイトなので余りを飛ばす
        LD      A,4
        LD      C,A
        LD      A,(OPQ_W)
        NEG
        ADD     A,C
        LD      C,A
        LD      B,0
        ADD     HL,BC
        EX      DE,HL
        LD      BC,(OPQ_STEP)
        ADD     HL,BC
        EX      DE,HL
        POP     BC
        DJNZ    .row
        LD      (OPQ_SRC),HL
        LD      A,(OPQ_PL)
        INC     A
        CP      P_GV0+3
        JP      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; DRAWCHAR - 8x8 の文字を描く (背景は塗りつぶす)
;   入力: A = 文字 (ASCII), B = バイト列 (0..79), C = ドット行 (0..192)
;         GFX_COL = 色
;   壊す: すべて
; ---------------------------------------------------------------------
DRAWCHAR:
        CALL    VBPOLL
        PUSH    BC
        CALL    FONTADDR
        LD      (GFX_SRC),HL
        POP     BC
        LD      D,C
        LD      E,B
        ; 背景色: HUD (右側) なら HUDBG、それ以外は 0
        LD      A,(HUDBG)
        OR      A
        JR      Z,.bgset
        LD      A,E
        CP      HUD_X
        LD      A,0
        JR      C,.bgset
        LD      A,(HUDBG)
.bgset:
        LD      (GFX_BGT),A
        CALL    VADDR_PX
        LD      (GFX_VA),HL
        LD      A,(GFX_COL)
        LD      (GFX_TMP),A
        LD      C,P_GV0
.plane:
        LD      A,0
        OUT     (C),A
        LD      HL,(GFX_VA)
        LD      DE,(GFX_SRC)
        LD      B,8
        ; 文字色と背景色のこのプレーンのビットで 4 通り
        LD      A,(GFX_BGT)
        AND     1
        JR      NZ,.bg1
        LD      A,(GFX_TMP)
        AND     1
        JR      Z,.zero
        JR      .ink
.bg1:
        LD      A,(GFX_TMP)
        AND     1
        JR      NZ,.full
.inv:                                   ; 背景だけ: 字の形を抜く
        LD      A,(DE)
        CPL
        LD      (HL),A
        INC     DE
        PUSH    DE
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        DJNZ    .inv
        JR      .next
.full:                                  ; 文字も背景も: 全部 1
        LD      (HL),0xFF
        PUSH    DE
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        DJNZ    .full
        JR      .next
.ink:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        PUSH    DE
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        DJNZ    .ink
        JR      .next
.zero:
        LD      (HL),0
        PUSH    DE
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        DJNZ    .zero
.next:
        LD      A,(GFX_TMP)
        SRL     A
        LD      (GFX_TMP),A
        LD      A,(GFX_BGT)
        SRL     A
        LD      (GFX_BGT),A
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; FONTADDR - 文字コードからグリフ (8 バイト) のアドレス
;   入力: A = 文字 (ASCII)
;   出力: HL
; ---------------------------------------------------------------------
FONTADDR:
        SUB     32
        JR      NC,.ge
        XOR     A
.ge:
        CP      FONT_COUNT
        JR      C,.lt
        XOR     A
.lt:
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,FONTDATA
        ADD     HL,DE
        RET

; ---------------------------------------------------------------------
; DRAWSTR - 0 終端の文字列を描く
;   入力: HL = 文字列, B = バイト列, C = ドット行, GFX_COL = 色
; ---------------------------------------------------------------------
DRAWSTR:
        LD      A,(HL)
        OR      A
        RET     Z
        PUSH    HL
        PUSH    BC
        CALL    DRAWCHAR
        POP     BC
        POP     HL
        INC     HL
        INC     B
        LD      A,B
        CP      80
        RET     NC
        JR      DRAWSTR

; ---------------------------------------------------------------------
; NUMSTR - 16bit の値を 10 進文字列にする (右詰め、上位はスペース)
;   入力: HL = 値, DE = 書き込み先, B = 桁数
;   出力: DE の先に 0 終端の文字列
; ---------------------------------------------------------------------
NUMSTR:
        PUSH    DE
        LD      C,B
        LD      A,E
        ADD     A,C
        LD      E,A
        JR      NC,.n1
        INC     D
.n1:
        XOR     A
        LD      (DE),A                  ; 終端
.loop:
        DEC     DE
        CALL    DIV10                   ; HL /= 10, A = 余り  (DE は保たれる)
        ADD     A,'0'
        LD      (DE),A
        DEC     C
        JR      Z,.done
        LD      A,H
        OR      L
        JR      NZ,.loop
.pad:
        DEC     DE
        LD      A,' '
        LD      (DE),A
        DEC     C
        JR      NZ,.pad
.done:
        POP     DE
        RET

; ---------------------------------------------------------------------
; DIV10 - HL / 10 -> HL, 余り -> A   (DE は保つ)
; ---------------------------------------------------------------------
DIV10:
        PUSH    BC                      ; 呼び出し側は C を桁数に使っている
        LD      B,16
        LD      C,0
.lp:
        ADD     HL,HL                   ; 上位ビットを CY に押し出す
        RL      C                       ; 余り = 余り*2 + CY
        LD      A,C
        SUB     10
        JR      C,.skip
        LD      C,A
        INC     L                       ; 商のビットを立てる
.skip:
        DJNZ    .lp
        LD      A,C
        POP     BC
        RET

; ---------------------------------------------------------------------
; HEXB - A を 16 進 2 桁にして (DE) に書く (デバッグ用)
; ---------------------------------------------------------------------
HEXB:
        LD      C,A
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .nib
        LD      A,C
.nib:
        AND     0x0F
        ADD     A,'0'
        CP      '9'+1
        JR      C,.put
        ADD     A,7
.put:
        LD      (DE),A
        INC     DE
        RET
