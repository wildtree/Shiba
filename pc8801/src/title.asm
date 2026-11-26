; =====================================================================
; title.asm - タイトル画面 (元の版の App.DrawTitle に寄せたもの)
; =====================================================================
; 元の版 (640x400) の並びを 640x200 に縦半分で写している:
;   ハイスコア / 肉球の飾り / 大きな "SHIBA JINTORI" (影つき) / 副題
;   柴犬えらび (選ぶと黄色い枠で跳ねる) / 点滅する開始の案内
;   遊び方 / 行進する犬たち / 下の帯に著作権表示
; 背景は草を暗くしたもの (PALTITLE が色 0 と 5 を暗い緑にする)。
; =====================================================================

T_HI_Y          EQU 2
T_LOGO_Y        EQU 16
T_TAG_Y         EQU 42
T_SEL_Y         EQU 55
PICK_TOP        EQU 66              ; 枠の上の行
PICK_BOT        EQU 110             ; 枠の下の行
PICK_CY0        EQU 8               ; 枠をふくむマス行 (64..111)
PICK_CY1        EQU 14
PICK_CYDOG      EQU 12              ; 犬だけのマス行 (64..95)
PICK_DOGY       EQU 71
PICK_NAMEY      EQU 100
T_PRESS_Y       EQU 117
T_PRESS_X       EQU 10
T_PRESS_W       EQU 61              ; 横 2 倍 30 文字 + 影
T_PRESS_H       EQU 9
T_PRESS_CX0     EQU 5               ; そのマスの範囲 (点滅で消すとき)
T_PRESS_CX1     EQU 36
T_PRESS_CY0     EQU 14
T_PRESS_CY1     EQU 16
T_I1_Y          EQU 132
T_I2_Y          EQU 141
T_I3_Y          EQU 150
T_I4_Y          EQU 159
T_PARADE_Y      EQU 168
T_PARADE_CY     EQU 21
T_BAR_Y         EQU 184
T_COPY_Y        EQU 188
TSNAP           EQU ARR_DIRTYQ      ; 点滅用の保存場所 (タイトルでは空いている)

; ---------------------------------------------------------------------
; TITLESCREEN - タイトル画面。しばらく放置するとデモに進む
; ---------------------------------------------------------------------
TITLESCREEN:
        CALL    CLS
        CALL    PALTITLE
        CALL    TITLEDRAW
        LD      A,BGM_TITLE
        CALL    BGMSTART
        LD      HL,0
        LD      (IDLETIMER),HL
        CALL    READKEYS                ; 描いているあいだに離したキーを読み直す
.loop:
        CALL    WAITVSYNC
        LD      HL,(FRAMECNT)
        INC     HL
        LD      (FRAMECNT),HL
        CALL    READKEYS
        ; --- 左右で柴犬の色を選ぶ ---
        CALL    KEYLEFT
        JR      Z,.nl
        LD      A,(SHIBACOLOR)
        OR      A
        JR      Z,.nl
        DEC     A
        CALL    TPICKMOVE
.nl:
        CALL    KEYRIGHT
        JR      Z,.nr
        LD      A,(SHIBACOLOR)
        CP      SHIBACOUNT-1
        JR      NC,.nr
        INC     A
        CALL    TPICKMOVE
.nr:
        ; --- 上: ハイスコア / 下: 実績 ---
        CALL    KEYUP
        JR      Z,.nup
        LD      A,SFX_SELECT
        CALL    SFXPLAY
        LD      A,0xFF
        LD      (NEWRANK),A
        LD      HL,30*TICKHZ
        LD      (HSVIEW),HL
        CALL    HSSCREEN
        JP      TITLESCREEN
.nup:
        CALL    KEYDOWN
        JR      Z,.ndn
        LD      A,SFX_SELECT
        CALL    SFXPLAY
        CALL    ACHSCREEN
        JP      TITLESCREEN
.ndn:
        ; --- 動くもの。重い処理が同じティックに重ならないようにずらしてある ---
        LD      A,(FRAMECNT)
        AND     3
        CALL    Z,PARADE                ; 4 ティックごとに行進
        LD      A,(FRAMECNT)
        AND     7
        CP      2
        CALL    Z,TBOUNCESTEP           ; 8 ティックごとに跳ねる
        LD      A,(FRAMECNT)
        AND     15
        CP      5
        CALL    Z,TBLINKSTEP            ; 16 ティックごとに点滅
        ; --- 開始 ---
        CALL    ANYKEY
        JR      Z,.nostart
        LD      A,SFX_START
        CALL    SFXPLAY
        OR      1                       ; NZ で返す
        RET
.nostart:
        LD      HL,(IDLETIMER)
        INC     HL
        LD      (IDLETIMER),HL
        LD      DE,450
        PUSH    HL
        XOR     A
        SBC     HL,DE
        POP     HL
        JP      C,.loop
        ; しばらく放っておくと、ハイスコア表 (8 秒) -> デモ (元の版と同じ)
        LD      A,0xFF
        LD      (NEWRANK),A
        LD      HL,8*TICKHZ
        LD      (HSVIEW),HL
        CALL    HSSCREEN
        JP      NZ,TITLESCREEN          ; キーで抜けたらタイトルへ
        CALL    DEMOPLAY
        JP      TITLESCREEN

; ---------------------------------------------------------------------
; TITLEDRAW - タイトルの止まっている部分を全部描く
; ---------------------------------------------------------------------
TITLEDRAW:
        LD      A,1
        LD      (PK_FULL),A
        XOR     A
        LD      (TBOUNCE),A
        LD      (TBLINK),A
        LD      (TPSTEP),A
        ; 背景の草
        LD      B,0
        LD      C,0
        LD      D,40
        LD      E,25
        CALL    TPAINT
        ; 肉球の飾り (元の版は白を薄く重ねている -> 少し明るい緑)
        LD      HL,PAWPOS
        LD      B,8
.paw:
        PUSH    BC
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        LD      IX,SPR_PAW
        LD      A,C_GRASS2
        CALL    DRAWSPR
        POP     HL
        POP     BC
        DJNZ    .paw
        ; 大きな題字: 影 -> 字
        LD      A,C_DARK
        LD      (TXTCOL),A
        LD      HL,LOGO_SH
        LD      D,T_LOGO_Y
        LD      E,LOGO_X
        LD      B,LOGO_W
        LD      C,LOGO_H
        CALL    BLIT1
        LD      A,C_ORANGE
        LD      (TXTCOL),A
        LD      HL,LOGO_FG
        LD      D,T_LOGO_Y
        LD      E,LOGO_X
        LD      B,LOGO_W
        LD      C,LOGO_H
        CALL    BLIT1
        ; ここからの文字は 1 ドットの影つき (元の版の Gfx.Text と同じ)
        LD      A,2
        LD      (TXTFLG),A
        LD      A,C_DARK
        LD      (TXSHCOL),A
        CALL    THISCORE
        LD      A,C_WHITE
        LD      HL,S_T_TAG
        LD      C,T_TAG_Y
        CALL    TXTCOLC
        LD      A,C_YELLOW
        LD      HL,S_T_SEL
        LD      C,T_SEL_Y
        CALL    TXTCOLC
        ; 柴犬えらび
        XOR     A
        CALL    DRAWPICK
        LD      A,1
        CALL    DRAWPICK
        LD      A,2
        CALL    DRAWPICK
        ; 開始の案内 (横 2 倍)。点滅のために描いた絵を取っておく
        LD      A,3
        LD      (TXTFLG),A
        LD      A,C_WHITE
        LD      (TXTCOL),A
        LD      HL,S_T_PRESS
        LD      B,T_PRESS_X
        LD      C,T_PRESS_Y
        CALL    TXT
        LD      HL,TSNAP
        LD      D,T_PRESS_Y
        LD      E,T_PRESS_X
        LD      B,T_PRESS_W
        LD      C,T_PRESS_H
        CALL    SNAPSAVE
        ; 遊び方
        LD      A,2
        LD      (TXTFLG),A
        LD      A,C_WHITE
        LD      HL,S_T_I1
        LD      C,T_I1_Y
        CALL    TXTCOLC
        LD      A,C_WHITE
        LD      HL,S_T_I2
        LD      C,T_I2_Y
        CALL    TXTCOLC
        LD      A,C_WHITE
        LD      HL,S_T_I3
        LD      C,T_I3_Y
        CALL    TXTCOLC
        LD      A,C_YELLOW
        LD      HL,S_T_I4
        LD      C,T_I4_Y
        CALL    TXTCOLC
        ; 行進
        CALL    PARADE
        ; 下の帯と著作権表示 (元の版は半透明の黒い帯)
        LD      D,T_BAR_Y
        LD      E,0
        LD      B,80
        LD      C,200-T_BAR_Y
        LD      A,C_DARK
        CALL    FILLRECT
        XOR     A
        LD      (TXTFLG),A
        LD      A,C_GRASS2
        LD      HL,S_T_COPY
        LD      C,T_COPY_Y
        CALL    TXTCOLC
        LD      A,C_GRASS2
        LD      (TXTCOL),A
        LD      HL,S_T_VER
        LD      B,80-1-14               ; 右端にそろえる ("PC-8801 v1.0.6" は 14 文字)
        LD      C,T_COPY_Y
        JP      TXT

; 肉球の位置 (バイト列, 行)。元の版の 40 + i*78, 22 + (i&1)*26 を写したもの
PAWPOS:
        DB      5,12, 15,25, 24,12, 34,25, 44,12, 54,25, 64,12, 73,25

; ---------------------------------------------------------------------
; THISCORE - 上に "HI-SCORE 0001234" を出す
; ---------------------------------------------------------------------
THISCORE:
        LD      HL,S_T_HI
        LD      DE,STRBUF
        LD      BC,9
        LDIR
        LD      HL,HISCORE
        LD      DE,STRBUF+9
        LD      B,7
        CALL    NUMSTR24
        LD      HL,STRBUF+9
        LD      B,7
.z:
        LD      A,(HL)
        CP      ' '
        JR      NZ,.nz
        LD      (HL),'0'
.nz:
        INC     HL
        DJNZ    .z
        LD      A,C_WHITE
        LD      HL,STRBUF
        LD      C,T_HI_Y
        JP      TXTCOLC

; ---------------------------------------------------------------------
; 柴犬えらび
; ---------------------------------------------------------------------
PICKX:          DB      25, 37, 49      ; 元の版の CX + (i-1)*96 - 24
PICKNAME:       DW      S_T_RED, S_T_BLACK, S_T_WHITE

; TPICKMOVE - 選んでいる柴犬を A に変える
TPICKMOVE:
        LD      B,A
        LD      A,(SHIBACOLOR)
        LD      C,A
        LD      A,B
        LD      (SHIBACOLOR),A
        PUSH    BC
        LD      A,SFX_SELECT
        CALL    SFXPLAY
        POP     BC
        PUSH    BC
        LD      A,C
        CALL    DRAWPICK                ; 前の (枠を外す)
        POP     BC
        LD      A,B
        JP      DRAWPICK                ; 新しいの (枠をつける)

; TBOUNCESTEP - 選んでいる柴犬を跳ねさせる (名前のマスは触らない)
TBOUNCESTEP:
        LD      A,(TBOUNCE)
        XOR     1
        LD      (TBOUNCE),A
        XOR     A
        LD      (PK_FULL),A
        LD      A,(SHIBACOLOR)
        CALL    DRAWPICK
        LD      A,1
        LD      (PK_FULL),A
        RET

; DRAWPICK - A 番目の柴犬 (枠・犬・名前) を描きなおす
DRAWPICK:
        LD      (PK_I),A
        LD      E,A
        LD      D,0
        LD      HL,PICKX
        ADD     HL,DE
        LD      A,(HL)
        LD      (PK_X),A
        ; 枠の範囲 (バイト x-1 .. x+6) のマスを草で塗りなおす
        DEC     A
        SRL     A
        LD      B,A
        LD      A,(PK_X)
        ADD     A,6
        SRL     A
        INC     A
        LD      D,A
        LD      C,PICK_CY0
        LD      E,PICK_CY1
        LD      A,(PK_FULL)
        OR      A
        JR      NZ,.full
        LD      E,PICK_CYDOG            ; 跳ねるだけ: 犬のマスだけ
.full:
        CALL    TPAINT
        ; 選んでいれば黄色い枠
        LD      A,(PK_I)
        LD      HL,SHIBACOLOR
        CP      (HL)
        JR      NZ,.nofr
        LD      A,C_YELLOW
        LD      (TXTCOL),A
        LD      A,(PK_X)
        DEC     A
        LD      E,A
        LD      D,PICK_TOP
        LD      B,8
        LD      C,PICK_BOT-PICK_TOP+1
        CALL    FRAME
.nofr:
        ; 犬 (選んでいるものは跳ねる)
        LD      A,(PK_I)
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      A,(HL)
        LD      (BIG_COL),A
        LD      D,PICK_DOGY
        LD      A,(PK_I)
        LD      HL,SHIBACOLOR
        CP      (HL)
        JR      NZ,.nob
        LD      A,(TBOUNCE)
        OR      A
        JR      Z,.nob
        LD      D,PICK_DOGY-2
.nob:
        LD      A,(PK_X)
        LD      E,A
        LD      A,(BIG_COL)
        CALL    DRAWBIG
        LD      A,(PK_FULL)
        OR      A
        RET     Z
        ; 名前 (選んでいれば白、ほかは灰緑)
        LD      A,(PK_I)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,PICKNAME
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        CALL    STRLEN
        SRL     B
        LD      A,(PK_X)
        ADD     A,3
        SUB     B
        LD      B,A
        PUSH    HL
        LD      A,(PK_I)
        LD      HL,SHIBACOLOR
        CP      (HL)
        LD      A,C_WHITE
        JR      Z,.ncol
        LD      A,C_GRASS2
.ncol:
        LD      (TXTCOL),A
        LD      A,2
        LD      (TXTFLG),A
        POP     HL
        LD      C,PICK_NAMEY
        JP      TXT

; ---------------------------------------------------------------------
; DRAWBIG - 大きな柴犬 (48x24、16x8 を 3x3) を描く
;   入力: D = 上の行, E = 左のバイト列, A = 体の色
; ---------------------------------------------------------------------
DRAWBIG:
        LD      (BIG_COL),A
        LD      A,D
        LD      (BIG_Y),A
        LD      A,E
        LD      (BIG_X),A
        LD      HL,SPRBIG               ; 体の色 + 白 + 輪郭
        LD      A,(BIG_COL)
        CALL    BIG9
        LD      HL,SPRBIGM              ; 舌
        LD      A,C_RED
        CALL    BIG9
        LD      A,(BIG_COL)
        CP      C_DARK
        RET     NZ
        LD      HL,SPRBIGT              ; 黒柴のまゆと足先 (元の版は茶色)
        LD      A,C_ORANGE
        ; そのまま BIG9 へ

; BIG9 - 9 枚の表 HL を色 A で描く (0 の枚は飛ばす)
BIG9:
        LD      (BIG_PC),A
        LD      C,0
.r:
        LD      B,0
.c:
        PUSH    BC
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      A,D
        OR      E
        JR      Z,.skip
        PUSH    DE
        POP     IX
        LD      A,C
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        LD      A,(BIG_Y)
        ADD     A,D
        LD      D,A
        LD      A,B
        ADD     A,A
        LD      E,A
        LD      A,(BIG_X)
        ADD     A,E
        LD      E,A
        LD      A,(BIG_PC)
        CALL    DRAWSPR
.skip:
        POP     HL
        INC     HL
        INC     HL
        POP     BC
        INC     B
        LD      A,B
        CP      3
        JR      C,.c
        INC     C
        LD      A,C
        CP      3
        JR      C,.r
        RET

; ---------------------------------------------------------------------
; TBLINKSTEP - 開始の案内を点滅させる
;   消すときは草で塗りなおし、出すときは取っておいた絵を戻す (どちらも 1 フレーム未満)
; ---------------------------------------------------------------------
TBLINKSTEP:
        LD      A,(TBLINK)
        XOR     1
        LD      (TBLINK),A
        JR      Z,.show
        LD      B,T_PRESS_CX0
        LD      C,T_PRESS_CY0
        LD      D,T_PRESS_CX1
        LD      E,T_PRESS_CY1
        JP      TPAINT
.show:
        LD      HL,TSNAP
        LD      D,T_PRESS_Y
        LD      E,T_PRESS_X
        LD      B,T_PRESS_W
        LD      C,T_PRESS_H
        JP      SNAPLOAD

; ---------------------------------------------------------------------
; PARADE - 行進する犬たちを 1 歩すすめる (元の版と同じく選んだ柴犬が先頭)
; ---------------------------------------------------------------------
PARADE:
        LD      HL,TPSTEP
        INC     (HL)
        LD      B,0
        LD      C,T_PARADE_CY
        LD      D,40
        LD      E,T_PARADE_CY+1
        CALL    TPAINT
        XOR     A
.lp:
        LD      (PR_I),A
        ; うしろにずらす量 = i*4 (+5 は先頭と 2 匹目のあいだ)
        LD      B,A
        ADD     A,A
        ADD     A,A
        LD      C,A
        LD      A,B
        OR      A
        JR      Z,.g
        LD      A,5
.g:
        ADD     A,C
        LD      C,A
        LD      A,(TPSTEP)
        SUB     C
        AND     127
        SUB     8                       ; -8 .. 119
        JP      M,.next                 ; まだ左の外
        CP      79
        JR      NC,.next                ; もう右の外
        LD      (PR_X),A
        ; 犬種: 0 = 選んだ柴犬, 1..8 = 敵の犬種 3..10
        LD      A,(PR_I)
        OR      A
        LD      A,(SHIBACOLOR)
        JR      Z,.b
        LD      A,(PR_I)
        ADD     A,2
.b:
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      A,(HL)
        LD      (PR_COL),A
        INC     HL
        LD      A,(HL)                  ; 耳
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      C,A                     ; 耳 * 16
        ; 歩くコマ = (歩数 + i) & 1
        LD      A,(TPSTEP)
        LD      B,A
        LD      A,(PR_I)
        ADD     A,B
        AND     1
        JR      Z,.f0
        LD      A,8
.f0:
        ADD     A,C
        ADD     A,4                     ; 右向き
        LD      E,A
        LD      D,0
        LD      HL,SPRDOG
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        PUSH    DE
        POP     IX
        LD      D,T_PARADE_Y
        LD      A,(PR_X)
        LD      E,A
        LD      A,(PR_COL)
        CALL    DRAWSPR
.next:
        LD      A,(PR_I)
        INC     A
        CP      9
        JR      C,.lp
        RET

; =====================================================================
; 描画の道具 (タイトル用)
; =====================================================================

; ---------------------------------------------------------------------
; TPAINT - マスの範囲を草の模様で塗る
;   入力: B = x0, C = y0, D = x1, E = y1  (マス単位、x1 / y1 は含まない)
; ---------------------------------------------------------------------
TPAINT:
        LD      A,B
        LD      (TP_X0),A
        LD      A,D
        LD      (TP_X1),A
        LD      A,E
        LD      (TP_Y1),A
.y:
        LD      A,(TP_X0)
        LD      B,A
.x:
        PUSH    BC
        LD      A,C
        AND     1
        ADD     A,A
        LD      E,A
        LD      A,B
        AND     1
        ADD     A,E                     ; 0..3
        LD      E,A
        ADD     A,A
        ADD     A,E
        ADD     A,A                     ; *6
        LD      E,A
        LD      D,0
        LD      HL,GRASSSTYLE
        ADD     HL,DE
        PUSH    HL
        CALL    VADDR_CELL
        POP     DE
        CALL    FILLCELL
        CALL    VBPOLL                  ; 帰線を数えておく (WAITVSYNC が取りこぼさないように)
        POP     BC
        INC     B
        LD      A,B
        LD      HL,TP_X1
        CP      (HL)
        JR      C,.x
        INC     C
        LD      A,C
        LD      HL,TP_Y1
        CP      (HL)
        JR      C,.y
        RET

; ---------------------------------------------------------------------
; 1 バイトの重ね書き。プレーンごとに「立てる / 消す」が決まっているので、
; そのプレーンの処理を IX (影) / IY (字・絵) に入れておいて JP (IX) で呼ぶ。
;   入力: A = 書くビット, HL = 場所。HL は進めない (呼んだ側で INC HL)
; ---------------------------------------------------------------------
OPSET:
        OR      (HL)
        LD      (HL),A
        RET
OPCLR:
        CPL
        AND     (HL)
        LD      (HL),A
        RET
JPIX:
        JP      (IX)
JPIY:
        JP      (IY)

; PLANEOPS - 色 A の最下位ビットで IY を OPSET / OPCLR にする。A は右に送って返す
PLANEOPS:
        LD      IY,OPCLR
        RRA
        RET     NC
        LD      IY,OPSET
        RET

; ---------------------------------------------------------------------
; TXTCOLC - 色 A で文字列 HL を行 C の真ん中に描く
; TXTC    - 文字列 HL を行 C の真ん中に描く (色は TXTCOL)
; TXT     - 文字列 HL を (バイト列 B, 行 C) から描く
;   背景はそのまま残す。TXTFLG: bit0 = 横 2 倍, bit1 = 影 (TXSHCOL)
; ---------------------------------------------------------------------
TXTCOLC:
        LD      (TXTCOL),A
TXTC:
        CALL    STRLEN
        LD      A,(TXTFLG)
        AND     1
        JR      Z,.w
        SLA     B
.w:
        LD      A,80
        SUB     B
        SRL     A
        LD      B,A
TXT:
        LD      A,(HL)
        OR      A
        RET     Z
        CP      ' '
        JR      Z,.sp                   ; 空白は背景のままなので描かない
        PUSH    HL
        PUSH    BC
        CALL    TXTCHAR
        CALL    VBPOLL
        POP     BC
        POP     HL
.sp:
        INC     HL
        INC     B
        LD      A,(TXTFLG)
        AND     1
        JR      Z,TXT
        INC     B
        JR      TXT

; STRLEN - 文字列 HL の長さを B に (HL はそのまま)
STRLEN:
        PUSH    HL
        LD      B,0
.lp:
        LD      A,(HL)
        OR      A
        JR      Z,.d
        INC     HL
        INC     B
        JR      .lp
.d:
        POP     HL
        RET

; TXTCHAR - 文字 A を (バイト列 B, 行 C) に描く
TXTCHAR:
        CALL    VBPOLL
        PUSH    BC
        CALL    FONTADDR
        LD      (TX_SRC),HL
        POP     BC
        LD      D,C
        LD      E,B
        CALL    VADDR_PX
        LD      (TX_VA),HL
        LD      A,(TXTCOL)
        LD      (TX_TC),A
        LD      A,(TXSHCOL)
        LD      (TX_SC),A
        LD      A,P_GV0
        LD      (TX_PL),A
.plane:
        CALL    VBPOLL
        LD      A,(TX_PL)
        LD      C,A
        XOR     A
        OUT     (C),A
        ; このプレーンで字 (IY) と影 (IX) を立てるか消すか
        LD      A,(TX_SC)
        CALL    PLANEOPS
        LD      (TX_SC),A
        PUSH    IY
        POP     IX
        LD      A,(TX_TC)
        CALL    PLANEOPS
        LD      (TX_TC),A
        LD      HL,(TX_VA)
        LD      DE,(TX_SRC)
        LD      B,8
.row:
        LD      A,(DE)
        OR      A
        JR      NZ,.draw
        INC     DE                      ; 点のない行: 字も影もない
        LD      A,L
        ADD     A,VSTRIDE
        LD      L,A
        JR      NC,.e1
        INC     H
.e1:
        DJNZ    .row
        JR      .pnext
.draw:
        PUSH    BC
        INC     DE
        PUSH    DE
        LD      D,A                     ; DE = この行の点 (16 ビット、左詰め)
        LD      E,0
        LD      A,(TXTFLG)
        RRA
        JR      NC,.nowide
        LD      A,D                     ; 横 2 倍: 1 ビットを 2 ビットに
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        CALL    DBLNIB
        PUSH    AF
        LD      A,D
        AND     0x0F
        CALL    DBLNIB
        LD      E,A
        POP     AF
        LD      D,A
.nowide:
        LD      A,(TXTFLG)
        AND     2
        JR      Z,.noshadow
        ; 影: 1 ドット右・1 行下 (右にずらすと 1 バイトはみ出す)
        PUSH    DE
        PUSH    HL
        LD      C,0
        SRL     D
        RR      E
        RR      C
        LD      A,L
        ADD     A,VSTRIDE
        LD      L,A
        JR      NC,.nc
        INC     H
.nc:
        LD      A,D
        OR      A
        CALL    NZ,JPIX
        INC     HL
        LD      A,E
        OR      A
        CALL    NZ,JPIX
        LD      A,C
        OR      A
        JR      Z,.sh2
        INC     HL
        CALL    JPIX
.sh2:
        POP     HL
        POP     DE
.noshadow:
        LD      A,D
        OR      A
        CALL    NZ,JPIY
        LD      A,E
        OR      A
        JR      Z,.t1
        INC     HL
        CALL    JPIY
        DEC     HL
.t1:
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        POP     BC
        DJNZ    .row
.pnext:
        LD      A,(TX_PL)
        INC     A
        LD      (TX_PL),A
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; DBLNIB - 4 ビット A を横 2 倍の 8 ビットに (A 以外は壊さない)
DBLNIB:
        PUSH    HL
        LD      HL,DBLTBL
        ADD     A,L
        LD      L,A
        JR      NC,.nc
        INC     H
.nc:
        LD      A,(HL)
        POP     HL
        RET

DBLTBL:
        DB      0x00,0x03,0x0C,0x0F,0x30,0x33,0x3C,0x3F
        DB      0xC0,0xC3,0xCC,0xCF,0xF0,0xF3,0xFC,0xFF

; ---------------------------------------------------------------------
; BLIT1 - 1 ビットの絵を色 TXTCOL で重ねる (0 のところは背景のまま)
;   入力: HL = 絵 (幅 B バイト x 高さ C 行), D = 行, E = バイト列
; ---------------------------------------------------------------------
BLIT1:
        LD      (BL_SRC),HL
        LD      A,B
        LD      (BL_W),A
        LD      A,C
        LD      (BL_H),A
        CALL    VADDR_PX
        LD      (BL_VA),HL
        LD      A,(TXTCOL)
        LD      (TX_TC),A
        LD      A,P_GV0
        LD      (TX_PL),A
.plane:
        LD      A,(TX_PL)
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      A,(TX_TC)
        CALL    PLANEOPS
        LD      (TX_TC),A
        LD      HL,(BL_VA)
        LD      DE,(BL_SRC)
        LD      A,(BL_H)
        LD      C,A
.row:
        PUSH    HL
        LD      A,(BL_W)
        LD      B,A
.byte:
        LD      A,(DE)
        INC     DE
        OR      A
        CALL    NZ,JPIY
        INC     HL
        DJNZ    .byte
        CALL    VBPOLL
        POP     HL
        PUSH    DE
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     DE
        DEC     C
        JR      NZ,.row
        LD      A,(TX_PL)
        INC     A
        LD      (TX_PL),A
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; FILLRECT - 長方形を 1 色で塗る (不透明)
;   入力: D = 行, E = バイト列, B = 幅 (バイト), C = 高さ (行), A = 色
; ---------------------------------------------------------------------
FILLRECT:
        LD      (FR_TMP),A
        LD      A,B
        LD      (FR_W),A
        LD      A,C
        LD      (FR_H),A
        CALL    VADDR_PX
        LD      (FR_VA),HL
        LD      A,P_GV0
        LD      (TX_PL),A
.plane:
        LD      A,(TX_PL)
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      A,(FR_TMP)
        AND     1
        LD      A,0
        JR      Z,.v
        LD      A,0xFF
.v:
        LD      (FR_V),A
        LD      HL,(FR_VA)
        LD      A,(FR_H)
        LD      C,A
.row:
        PUSH    HL
        LD      A,(FR_W)
        LD      B,A
        LD      A,(FR_V)
.b:
        LD      (HL),A
        INC     HL
        DJNZ    .b
        POP     HL
        CALL    VBPOLL                  ; 帰線を数えておく (大きな箱は数フレームかかる)
        LD      DE,VSTRIDE
        ADD     HL,DE
        DEC     C
        JR      NZ,.row
        LD      A,(FR_TMP)
        SRL     A
        LD      (FR_TMP),A
        LD      A,(TX_PL)
        INC     A
        LD      (TX_PL),A
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; FRAME - 1 ドットの枠を色 TXTCOL で描く
;   入力: D = 上の行, E = 左のバイト列, B = 幅 (バイト), C = 高さ (行, 3 以上)
; ---------------------------------------------------------------------
FRAME:
        LD      A,B
        LD      (FR_W),A
        LD      A,C
        LD      (FR_H),A
        CALL    VADDR_PX
        LD      (FR_VA),HL
        LD      A,(TXTCOL)
        LD      (TX_TC),A
        LD      A,P_GV0
        LD      (TX_PL),A
.plane:
        CALL    VBPOLL
        LD      A,(TX_PL)
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      A,(TX_TC)
        CALL    PLANEOPS
        LD      (TX_TC),A
        ; 上の辺
        LD      HL,(FR_VA)
        CALL    FRAMEH
        ; 下の辺
        LD      HL,(FR_VA)
        LD      A,(FR_H)
        DEC     A
        LD      DE,VSTRIDE
.dn:
        OR      A
        JR      Z,.dnd
        ADD     HL,DE
        DEC     A
        JR      .dn
.dnd:
        CALL    FRAMEH
        ; 左右の辺
        LD      HL,(FR_VA)
        LD      DE,VSTRIDE
        ADD     HL,DE
        LD      A,(FR_H)
        SUB     2
        LD      C,A
        LD      A,(FR_W)
        DEC     A
        LD      B,A                     ; 右端までのバイト数
.vl:
        PUSH    HL
        LD      A,0x80
        CALL    JPIY
        LD      A,L
        ADD     A,B
        LD      L,A
        JR      NC,.nc
        INC     H
.nc:
        LD      A,0x01
        CALL    JPIY
        POP     HL
        ADD     HL,DE
        DEC     C
        JR      NZ,.vl
        LD      A,(TX_PL)
        INC     A
        LD      (TX_PL),A
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; FRAMEH - HL から FR_W バイトの横線
FRAMEH:
        LD      A,(FR_W)
        LD      C,A
.hl:
        LD      A,0xFF
        CALL    JPIY
        INC     HL
        DEC     C
        JR      NZ,.hl
        RET

; ---------------------------------------------------------------------
; SNAPSAVE / SNAPLOAD - 画面の長方形をバッファに取っておく / 戻す
;   入力: HL = バッファ, D = 行, E = バイト列, B = 幅, C = 高さ
; ---------------------------------------------------------------------
SNAPSAVE:
        XOR     A
        JR      SNAPGO
SNAPLOAD:
        LD      A,1
SNAPGO:
        LD      (SN_DIR),A
        LD      (SN_BUF),HL
        LD      A,B
        LD      (SN_W),A
        LD      A,C
        LD      (SN_H),A
        CALL    VADDR_PX
        LD      (SN_VA),HL
        LD      A,P_GV0
        LD      (TX_PL),A
.plane:
        LD      A,(TX_PL)
        LD      C,A
        XOR     A
        OUT     (C),A
        LD      HL,(SN_VA)
        LD      A,(SN_H)
.row:
        PUSH    AF
        PUSH    HL
        LD      A,(SN_DIR)
        OR      A
        LD      DE,(SN_BUF)
        LD      A,(SN_W)
        LD      C,A
        LD      B,0
        JR      NZ,.load
        LDIR                            ; VRAM -> バッファ
        LD      (SN_BUF),DE
        JR      .rn
.load:
        EX      DE,HL
        LDIR                            ; バッファ -> VRAM
        LD      (SN_BUF),HL
.rn:
        CALL    VBPOLL
        POP     HL
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     AF
        DEC     A
        JR      NZ,.row
        LD      A,(TX_PL)
        INC     A
        LD      (TX_PL),A
        CP      P_GV0+3
        JR      C,.plane
        XOR     A
        OUT     (P_GVOFF),A
        RET

; ---------------------------------------------------------------------
; 文字列
; ---------------------------------------------------------------------
S_T_HI:         DB      "HI-SCORE "             ; 9 文字 (0 終わりなし)
S_T_TAG:        DB      "- DEFEND YOUR TERRITORY! -",0
S_T_SEL:        DB      "< SELECT YOUR SHIBA >",0
S_T_PRESS:      DB      "PRESS SPACE OR RETURN TO START",0
S_T_I1:         DB      "PEE ON 3 POLES TO CLAIM THE TRIANGLE AS YOUR TERRITORY.",0
S_T_I2:         DB      "DON",0x27,"T GET SURROUNDED BY OTHER DOGS. WATCH OUT FOR CARS!",0
S_T_I3:         DB      "ARROWS/2468/WASD:MOVE  SPACE/Z:PEE  P:PAUSE  M:MUSIC",0
S_T_I4:         DB      "UP: HIGH SCORES     DOWN: ACHIEVEMENTS",0
S_T_COPY:       DB      "Copyright ",0x7F," 2026 wildtree with Claude AI",0
S_T_VER:        DB      "PC-8801 v1.0.6",0       ; 版番号は PC版・Android版とそろえる (変えたら上の桁位置も)
S_T_RED:        DB      "RED",0
S_T_BLACK:      DB      "BLACK",0
S_T_WHITE:      DB      "WHITE",0
