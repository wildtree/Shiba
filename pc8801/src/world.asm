; =====================================================================
; world.asm - 乱数・算術・マスの判定・三角形の判定
; =====================================================================

; ---------------------------------------------------------------------
; 乱数 (16bit の xorshift 風。1 回の呼び出しで 1 バイト取れる)
; ---------------------------------------------------------------------
RANDB:
        PUSH    HL
        PUSH    DE
        LD      HL,(RNGSEED)
        LD      A,H
        RRA
        LD      A,L
        RRA
        XOR     H
        LD      H,A
        LD      A,L
        RRA
        LD      A,H
        RRA
        XOR     L
        LD      L,A
        XOR     H
        LD      H,A
        LD      (RNGSEED),HL
        LD      A,L
        POP     DE
        POP     HL
        RET

; RANDMOD - 0..A-1 の乱数 -> A
RANDMOD:
        ; 引き算をくり返すと法が小さいとき 80 回以上まわってしまうので、
        ; 8 回の「寄せて引く」割り算で余りを出す。
        OR      A
        RET     Z
        PUSH    BC
        PUSH    DE
        LD      C,A                     ; C = 法
        CALL    RANDB                   ; A = 乱数 0..255
        LD      E,A
        LD      A,C
        CP      0x81
        JR      C,.div
        ; 法が 129 以上なら引き算 1 回で足りる
        LD      A,E
        CP      C
        JR      C,.fin
        SUB     C
        JR      .fin
.div:
        LD      A,E
        LD      B,8
        LD      D,0                     ; D = 余り
.lp:
        ADD     A,A                     ; 上の桁を carry へ
        LD      E,A
        LD      A,D
        ADC     A,A                     ; 余り = 余り*2 + carry
        CP      C
        JR      C,.nosub
        SUB     C
.nosub:
        LD      D,A
        LD      A,E
        DJNZ    .lp
        LD      A,D
.fin:
        POP     DE
        POP     BC
        RET

; ---------------------------------------------------------------------
; MULS88 - 符号付き 8bit x 8bit -> 16bit
;   入力: B, C / 出力: HL / 壊す: A, BC, DE
; ---------------------------------------------------------------------
MULS88:
        XOR     A
        LD      (MUL_SGN),A
        LD      A,B
        OR      A
        JP      P,.bpos
        NEG
        LD      B,A
        LD      A,1
        LD      (MUL_SGN),A
.bpos:
        LD      A,C
        OR      A
        JP      P,.cpos
        NEG
        LD      C,A
        LD      A,(MUL_SGN)
        XOR     1
        LD      (MUL_SGN),A
.cpos:
        LD      HL,0
        LD      D,0
        LD      E,C
        LD      A,B
        OR      A
        JR      Z,.zero
        LD      B,8
.lp:
        ADD     HL,HL
        RLCA
        JR      NC,.skip
        ADD     HL,DE
.skip:
        DJNZ    .lp
.zero:
        LD      A,(MUL_SGN)
        OR      A
        RET     Z
        XOR     A
        SUB     L
        LD      L,A
        SBC     A,A
        SUB     H
        LD      H,A
        RET

; ---------------------------------------------------------------------
; MULU88 - 符号なし 8bit x 8bit -> 16bit
;   入力: B, C / 出力: HL / 壊す: A, BC, DE
; ---------------------------------------------------------------------
MULU88:
        LD      HL,0
        LD      D,0
        LD      E,C
        LD      A,B
        OR      A
        RET     Z
        LD      B,8
.lp:
        ADD     HL,HL
        RLCA
        JR      NC,.skip
        ADD     HL,DE
.skip:
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; SEXT - A を符号付きで 16bit に伸ばす -> HL
; ---------------------------------------------------------------------
SEXT:
        LD      L,A
        ADD     A,A
        SBC     A,A
        LD      H,A
        RET

; ---------------------------------------------------------------------
; ABS16 - HL の絶対値
; ---------------------------------------------------------------------
ABS16:
        BIT     7,H
        RET     Z
        XOR     A
        SUB     L
        LD      L,A
        SBC     A,A
        SUB     H
        LD      H,A
        RET

; ---------------------------------------------------------------------
; MANHATTAN - |x1-x2| + |y1-y2| -> A
;   入力: B,C = 1 点目  D,E = 2 点目
; ---------------------------------------------------------------------
MANHATTAN:
        LD      A,B
        SUB     D
        JP      P,.p1
        NEG
.p1:
        LD      (MAN_T),A
        LD      A,C
        SUB     E
        JP      P,.p2
        NEG
.p2:
        PUSH    HL
        LD      HL,MAN_T
        ADD     A,(HL)
        POP     HL
        RET

; ---------------------------------------------------------------------
; CELLFREE - マス (x,y) が空いているか (範囲内 / 電柱なし / 道路でない /
;            なわばりでない)
;   入力: B = x, C = y / 出力: A != 0 なら空いている
; ---------------------------------------------------------------------
CELLFREE:
        LD      A,B
        CP      FW
        JR      NC,.no
        LD      A,C
        CP      FH
        JR      NC,.no
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      NZ,.no
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(HL)
        INC     A
        JR      NZ,.no
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        INC     A
        JR      NZ,.no
        LD      A,1
        RET
.no:
        XOR     A
        RET

; ---------------------------------------------------------------------
; CANENTER - 犬が (x,y) に入れるか
;   入力: IY = 犬, B = x, C = y / 出力: A != 0 なら入れる
; ---------------------------------------------------------------------
CANENTER:
        LD      A,B
        CP      FW
        JR      NC,.no
        LD      A,C
        CP      FH
        JR      NC,.no
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(HL)
        INC     A
        JR      NZ,.no                  ; 電柱には入れない
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        INC     A
        JR      Z,.yes                  ; なわばりでない
        DEC     A
        LD      E,A
        LD      A,(IY+D_TERRID)
        CP      E
        JR      Z,.yes                  ; 自分のなわばり
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        JR      NZ,.yes                 ; ボスは踏み越える
        LD      A,(IY+D_PASST)
        OR      (IY+D_PASST+1)
        JR      NZ,.yes                 ; 巻物の効果中
.no:
        XOR     A
        RET
.yes:
        LD      A,1
        RET

; ---------------------------------------------------------------------
; TRYMOVE - 犬を方向 A へ 1 歩動かす
;   入力: IY = 犬, A = 方向 / 出力: A != 0 なら動けた
; ---------------------------------------------------------------------
TRYMOVE:
        LD      (IY+D_DIR),A
        LD      E,A
        LD      D,0
        LD      HL,DIRDX
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,(IY+D_X)
        LD      B,A
        LD      HL,DIRDY
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,(IY+D_Y)
        LD      C,A
        PUSH    BC
        CALL    CANENTER
        POP     BC
        OR      A
        JR      NZ,.ok
        XOR     A
        RET
.ok:
        LD      A,(IY+D_X)
        LD      (IY+D_FROMX),A
        LD      A,(IY+D_Y)
        LD      (IY+D_FROMY),A
        LD      (IY+D_X),B
        LD      (IY+D_Y),C
        LD      A,(IY+D_FLAGS)
        OR      DF_MOVING
        XOR     DF_STEPFLIP
        LD      (IY+D_FLAGS),A
        LD      (IY+D_MOVET),0
        LD      A,1
        RET

; ---------------------------------------------------------------------
; STARTPEE - 電柱 A におしっこを始める
; ---------------------------------------------------------------------
STARTPEE:
        LD      (IY+D_PEEPOLE),A
        LD      HL,PEEFRAMES
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        JR      Z,.normal
        LD      HL,BOSSPEEFRAMES
.normal:
        LD      A,(IY+D_BONET)
        OR      (IY+D_BONET+1)
        JR      Z,.full
        SRL     H
        RR      L
.full:
        LD      (IY+D_PEET),L
        LD      (IY+D_PEET+1),H
        LD      (IY+D_PEETOTAL),L
        LD      (IY+D_PEETOTAL+1),H
        ; 柴犬なら最初のしずくをすぐ鳴らす (元の版は _dripT = 0)
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        RET     Z
        XOR     A
        LD      (DRIPT),A
        RET

; =====================================================================
; chain (おしっこ済みでまだなわばりになっていない電柱) の操作
; =====================================================================

; CHAINGET - A 番目 (0..2) の電柱 -> A
CHAINGET:
        OR      A
        JR      NZ,.g1
        LD      A,(IY+D_CHAIN)
        RET
.g1:
        DEC     A
        JR      NZ,.g2
        LD      A,(IY+D_CHAIN+1)
        RET
.g2:
        LD      A,(IY+D_CHAIN+2)
        RET

; CHAINSET - A 番目 (0..2) に E を入れる
CHAINSET:
        OR      A
        JR      NZ,.s1
        LD      (IY+D_CHAIN),E
        RET
.s1:
        DEC     A
        JR      NZ,.s2
        LD      (IY+D_CHAIN+1),E
        RET
.s2:
        LD      (IY+D_CHAIN+2),E
        RET

; CHAINHAS - 電柱 A が chain にあるか / 出力: A != 0 なら「ある」
CHAINHAS:
        LD      C,A
        LD      B,0
.lp:
        LD      A,B
        CP      (IY+D_CHAINN)
        JR      NC,.no
        LD      A,B
        CALL    CHAINGET
        CP      C
        JR      Z,.yes
        INC     B
        JR      .lp
.no:
        XOR     A
        RET
.yes:
        LD      A,1
        RET

; CHAINREM - 電柱 C を chain から取り除く
CHAINREM:
        LD      B,0                     ; 読み位置
        LD      D,0                     ; 書き位置
.lp:
        LD      A,B
        CP      (IY+D_CHAINN)
        JR      NC,.fin
        LD      A,B
        CALL    CHAINGET
        CP      C
        JR      Z,.skip
        LD      E,A
        LD      A,D
        CALL    CHAINSET
        INC     D
.skip:
        INC     B
        JR      .lp
.fin:
        LD      A,D
        LD      (IY+D_CHAINN),A
        RET

; CHAINADD - chain の末尾に電柱 A を足す (同じものは入れ直す)
CHAINADD:
        LD      C,A
        CALL    CHAINREM
        LD      A,(IY+D_CHAINN)
        CP      3
        JR      C,.ok
        ; いっぱいなら先頭を捨てる
        LD      A,(IY+D_CHAIN+1)
        LD      (IY+D_CHAIN),A
        LD      A,(IY+D_CHAIN+2)
        LD      (IY+D_CHAIN+1),A
        LD      A,2
        LD      (IY+D_CHAINN),A
.ok:
        LD      E,C
        LD      A,(IY+D_CHAINN)
        CALL    CHAINSET
        LD      A,(IY+D_CHAINN)
        INC     A
        LD      (IY+D_CHAINN),A
        RET

; CHAINDROP - chain を空にして、自分が付けた未ロックの印を消す
CHAINDROP:
        LD      A,(IY+D_CHAINN)
        OR      A
        JR      Z,.done
        LD      C,0
.lp:
        LD      A,C
        CP      (IY+D_CHAINN)
        JR      NC,.done
        PUSH    BC
        LD      A,C
        CALL    CHAINGET
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      NZ,.keep
        LD      A,(IX+PL_OWNER)
        CP      (IY+D_TERRID)
        JR      NZ,.keep
        LD      (IX+PL_OWNER),0xFF
        LD      B,(IX+PL_X)
        LD      C,(IX+PL_Y)
        CALL    MARKDIRTY
.keep:
        POP     BC
        INC     C
        JR      .lp
.done:
        LD      (IY+D_CHAINN),0
        RET

; =====================================================================
; 三角形の判定 (元の C# 版の Evaluate)
; =====================================================================
; 入力: TRI_AX..TRI_CY, EVAL_ID, EVAL_STEAL, EVAL_COLLECT
; 出力: EV_N = 新しく取れるマス数 (0 なら作れない)
;       ARR_INTRI: bit0 = 三角形の内側, bit2 = 辺または頂点の上, bit3 = 今回取るマス
;                  bit4..6 = 辺 0..2 の外側か辺の上 (EVALCROSS が使う)
;       EVAL_COLLECT != 0 なら ARR_FILLQ に取れるマスの添字を積む
; =====================================================================

EVALUATE:
        ; 面積の 2 倍 = (Bx-Ax)*(Cy-Ay) - (By-Ay)*(Cx-Ax)
        CALL    TRIAREA
        LD      A,H
        OR      L
        JR      NZ,.notline
        LD      HL,0
        LD      (EV_N),HL
        RET
.notline:
        BIT     7,H
        JR      Z,.pos
        ; 負なら B と C を入れ替えて正にする
        LD      A,(TRI_BX)
        LD      B,A
        LD      A,(TRI_CX)
        LD      (TRI_BX),A
        LD      A,B
        LD      (TRI_CX),A
        LD      A,(TRI_BY)
        LD      B,A
        LD      A,(TRI_CY)
        LD      (TRI_BY),A
        LD      A,B
        LD      (TRI_CY),A
        CALL    TRIAREA
.pos:
        LD      (EV_AREA),HL
        CALL    TRIBOX
        ; --- AI の下見 (EVAL_COLLECT = 0) で箱が大きいときは概算で済ませる ---
        ; 本番 (なわばりを取るとき) は必ず正確に数える。
        LD      A,(EVAL_COLLECT)
        OR      A
        JR      NZ,.exact
        LD      A,(EV_X1)
        LD      B,A
        LD      A,(EV_X0)
        NEG
        ADD     A,B
        INC     A                       ; 横のマス数
        LD      B,A
        LD      A,(EV_Y1)
        LD      C,A
        LD      A,(EV_Y0)
        NEG
        ADD     A,C
        INC     A                       ; 縦のマス数
        LD      C,A
        CALL    MULU88                  ; HL = 箱のマス数
        LD      DE,EVALQUICK
        XOR     A
        SBC     HL,DE
        JR      C,.exact                ; 小さいので正確に
        ; 大きい三角形は「面積の半分くらい取れる」とみなす
        LD      HL,(EV_AREA)
        SRL     H
        RR      L
        LD      (EV_N),HL
        XOR     A
        LD      (EVAL_OTHER),A
        RET
.exact:
        ; 3 つの辺について外積の符号を調べる。3 回目で数える
        XOR     A
        CALL    EVALPASS
        LD      A,1
        CALL    EVALPASS
        LD      A,2
        CALL    EVALPASS
        ; 作れそうなら、細い三角形がほかのなわばりをすり抜けていないかも見る
        LD      HL,(EV_N)
        LD      A,H
        OR      L
        RET     Z
        LD      A,(EVAL_STEAL)
        OR      A
        RET     NZ                      ; ボス犬はなわばりごと奪うので見ない
        JP      EVALCROSS

; ---------------------------------------------------------------------
; TRIAREA - TRI_* から辺のベクトルと面積の 2 倍 (HL) を求める
; ---------------------------------------------------------------------
TRIAREA:
        LD      A,(TRI_BX)
        LD      HL,TRI_AX
        SUB     (HL)
        LD      (EV_UX),A
        LD      A,(TRI_BY)
        LD      HL,TRI_AY
        SUB     (HL)
        LD      (EV_UY),A
        LD      A,(TRI_CX)
        LD      HL,TRI_BX
        SUB     (HL)
        LD      (EV_VX),A
        LD      A,(TRI_CY)
        LD      HL,TRI_BY
        SUB     (HL)
        LD      (EV_VY),A
        LD      A,(TRI_AX)
        LD      HL,TRI_CX
        SUB     (HL)
        LD      (EV_WX),A
        LD      A,(TRI_AY)
        LD      HL,TRI_CY
        SUB     (HL)
        LD      (EV_WY),A
        LD      A,(TRI_CY)
        LD      HL,TRI_AY
        SUB     (HL)
        LD      C,A
        LD      A,(EV_UX)
        LD      B,A
        CALL    MULS88
        LD      (EV_T1),HL
        LD      A,(TRI_CX)
        LD      HL,TRI_AX
        SUB     (HL)
        LD      C,A
        LD      A,(EV_UY)
        LD      B,A
        CALL    MULS88
        LD      DE,(EV_T1)
        EX      DE,HL
        XOR     A
        SBC     HL,DE
        RET

; ---------------------------------------------------------------------
; TRIBOX - 3 点のバウンディングボックス -> EV_X0/X1/Y0/Y1
; ---------------------------------------------------------------------
TRIBOX:
        LD      A,(TRI_AX)
        LD      B,A
        LD      C,A
        LD      A,(TRI_BX)
        CP      B
        JR      NC,.b1
        LD      B,A
.b1:
        LD      A,(TRI_BX)
        CP      C
        JR      C,.b2
        LD      C,A
.b2:
        LD      A,(TRI_CX)
        CP      B
        JR      NC,.b3
        LD      B,A
.b3:
        LD      A,(TRI_CX)
        CP      C
        JR      C,.b4
        LD      C,A
.b4:
        LD      A,B
        LD      (EV_X0),A
        LD      A,C
        LD      (EV_X1),A
        LD      A,(TRI_AY)
        LD      B,A
        LD      C,A
        LD      A,(TRI_BY)
        CP      B
        JR      NC,.c1
        LD      B,A
.c1:
        LD      A,(TRI_BY)
        CP      C
        JR      C,.c2
        LD      C,A
.c2:
        LD      A,(TRI_CY)
        CP      B
        JR      NC,.c3
        LD      B,A
.c3:
        LD      A,(TRI_CY)
        CP      C
        JR      C,.c4
        LD      C,A
.c4:
        LD      A,B
        LD      (EV_Y0),A
        LD      A,C
        LD      (EV_Y1),A
        RET

; ---------------------------------------------------------------------
; EVALPASS - 辺 A (0,1,2) の外積の符号をボックス内のマスに記録する
;   0 回目は書き込み、1 回目は OR、2 回目は符号を合わせて数える。
;   外積は x,y の 1 次式なので、足し算だけで隣のマスへ進める。
;   ARR_INTRI: bit0 = 負があった / bit2 = 0 があった / bit3 = 今回取るマス
; ---------------------------------------------------------------------
EVALPASS:
        LD      (EV_PASS),A
        OR      A
        JR      NZ,.e1
        LD      A,(EV_UX)
        LD      (EV_SY),A
        LD      A,(EV_UY)
        NEG
        LD      (EV_SX),A
        LD      A,(TRI_AX)
        LD      (EV_PX),A
        LD      A,(TRI_AY)
        LD      (EV_PY),A
        JR      .go
.e1:
        DEC     A
        JR      NZ,.e2
        LD      A,(EV_VX)
        LD      (EV_SY),A
        LD      A,(EV_VY)
        NEG
        LD      (EV_SX),A
        LD      A,(TRI_BX)
        LD      (EV_PX),A
        LD      A,(TRI_BY)
        LD      (EV_PY),A
        JR      .go
.e2:
        LD      A,(EV_WX)
        LD      (EV_SY),A
        LD      A,(EV_WY)
        NEG
        LD      (EV_SX),A
        LD      A,(TRI_CX)
        LD      (EV_PX),A
        LD      A,(TRI_CY)
        LD      (EV_PY),A
.go:
        ; 行頭の値 = sy*(y0-py) + sx*(x0-px)
        LD      A,(EV_Y0)
        LD      HL,EV_PY
        SUB     (HL)
        LD      C,A
        LD      A,(EV_SY)
        LD      B,A
        CALL    MULS88
        LD      (EV_ROW),HL
        LD      A,(EV_X0)
        LD      HL,EV_PX
        SUB     (HL)
        LD      C,A
        LD      A,(EV_SX)
        LD      B,A
        CALL    MULS88
        LD      DE,(EV_ROW)
        ADD     HL,DE
        LD      (EV_ROW),HL
        LD      A,(EV_SX)
        CALL    SEXT
        LD      (EV_SX16),HL
        LD      A,(EV_SY)
        CALL    SEXT
        LD      (EV_SY16),HL
        LD      A,(EV_PASS)
        CP      2
        JR      NZ,.nz0
        LD      HL,0
        LD      (EV_N),HL
        XOR     A
        LD      (EVAL_OTHER),A
.nz0:
        LD      A,(EV_X1)
        LD      B,A
        LD      A,(EV_X0)
        NEG
        ADD     A,B
        INC     A
        LD      (EV_W),A
        LD      A,(EV_Y0)
        LD      (EV_CY),A
.rowlp:
        CALL    VBPOLL
        LD      A,(EV_X0)
        LD      B,A
        LD      A,(EV_CY)
        LD      C,A
        LD      DE,ARR_INTRI
        CALL    CELLPTR
        PUSH    HL
        POP     IX
        LD      HL,(EV_ROW)
        LD      DE,(EV_SX16)
        LD      A,(EV_X0)
        LD      (EV_CX),A
        LD      A,(EV_W)
        LD      B,A
        LD      A,(EV_PASS)
        OR      A
        JP      Z,.p0
        DEC     A
        JP      Z,.p1
        JP      .p2

        ; --- 0 回目: 書き込み ---
.p0:
        BIT     7,H
        JR      NZ,.p0neg
        LD      A,H
        OR      L
        JR      Z,.p0zero
        LD      (IX+0),0
        JR      .p0adv
.p0neg:
        LD      (IX+0),0x11             ; 負 + 辺 0 の外側
        JR      .p0adv
.p0zero:
        LD      (IX+0),0x14             ; 0 + 辺 0 の上
.p0adv:
        ADD     HL,DE
        INC     IX
        DJNZ    .p0
        JP      .rownext

        ; --- 1 回目: OR ---
.p1:
        BIT     7,H
        JR      NZ,.p1neg
        LD      A,H
        OR      L
        JR      Z,.p1zero
        JR      .p1adv
.p1neg:
        LD      A,(IX+0)
        OR      0x21                    ; 負 + 辺 1 の外側
        LD      (IX+0),A
        JR      .p1adv
.p1zero:
        LD      A,(IX+0)
        OR      0x24                    ; 0 + 辺 1 の上
        LD      (IX+0),A
.p1adv:
        ADD     HL,DE
        INC     IX
        DJNZ    .p1
        JP      .rownext

        ; --- 2 回目: 符号を合わせて数える ---
.p2:
        ; 辺 0,1 のビットを残し、辺 2 (いまの辺) が外側か辺の上なら bit6
        LD      A,(IX+0)
        AND     0x30
        BIT     7,H
        JR      NZ,.p2le
        LD      C,A
        LD      A,H
        OR      L
        LD      A,C
        JR      NZ,.p2gt
.p2le:
        OR      0x40
.p2gt:
        LD      (EV_EB),A
        BIT     7,H
        JP      NZ,.p2out
        LD      A,(IX+0)
        AND     1
        JP      NZ,.p2out               ; どれかが負 = 外側
        LD      A,H
        OR      L
        LD      C,0
        JR      NZ,.p2nz
        LD      C,4
.p2nz:
        LD      A,(IX+0)
        OR      C
        AND     4
        LD      C,A                     ; C != 0 なら辺や頂点の上
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      A,(EV_CX)
        LD      B,A
        LD      A,(EV_CY)
        LD      C,A
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        POP     BC
        INC     A
        JR      Z,.p2take
        DEC     A
        LD      HL,EVAL_ID
        CP      (HL)
        JR      Z,.p2skip
        LD      A,(EVAL_STEAL)
        OR      A
        JR      NZ,.p2take
        LD      A,C
        OR      A
        JR      NZ,.p2skip
        LD      A,1
        LD      (EVAL_OTHER),A
.p2skip:
        LD      A,(EV_EB)
        OR      1
        LD      (IX+0),A
        POP     DE
        POP     HL
        JR      .p2adv
.p2take:
        LD      HL,(EV_N)
        INC     HL
        LD      (EV_N),HL
        LD      A,(EV_EB)
        OR      9
        LD      (IX+0),A
        LD      A,(EVAL_COLLECT)
        OR      A
        JR      Z,.p2done
        ; 添字 = EV_CY*32 + EV_CX  (B は x のループ回数なので触らない)
        LD      A,(EV_CY)
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,(EV_CX)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,(FILLTAIL)
        EX      DE,HL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (FILLTAIL),HL
.p2done:
        POP     DE
        POP     HL
        JR      .p2adv
.p2out:
        LD      A,(EV_EB)
        LD      (IX+0),A
.p2adv:
        LD      A,(EV_CX)
        INC     A
        LD      (EV_CX),A
        ADD     HL,DE
        INC     IX
        DEC     B
        JP      NZ,.p2

.rownext:
        LD      HL,(EV_ROW)
        LD      DE,(EV_SY16)
        ADD     HL,DE
        LD      (EV_ROW),HL
        LD      A,(EV_CY)
        INC     A
        LD      (EV_CY),A
        LD      HL,EV_Y1
        CP      (HL)
        JP      C,.rowlp
        JP      Z,.rowlp
        LD      A,(EV_PASS)
        CP      2
        RET     NZ
        LD      A,(EVAL_OTHER)
        OR      A
        RET     Z
        LD      HL,0
        LD      (EV_N),HL
        RET

; ---------------------------------------------------------------------
; EVALCROSS - 細い三角形が、ほかの犬のなわばりのマスのあいだを
;   すり抜けていないか (C# 版の CrossesOther)。
;   マスの中心だけで見ると、高さが 1 マスもない三角形はなわばりを素通り
;   できてしまう。そこで、同じ犬のなわばりで隣り合う 2 マス (横・縦・斜め)
;   の中心を結ぶ線分が、三角形の内側 (辺は含まない) を通っていたら
;   作れない三角形にする。辺や頂点で接しているだけ (共有) なら引っかからない。
;   線分と三角形が分かれているかは分離軸で調べる:
;     - 三角形の辺: 2 マスとも同じ辺の外側か辺の上 (ARR_INTRI の bit4..6)
;     - 線分の向き: 3 つの頂点がすべて線分の片側 (線上を含む)
;   EVALPASS の 3 回のあとに呼ぶ。
;   出力: 横切っていたら EV_N = 0, EVAL_OTHER = 1
; ---------------------------------------------------------------------
EVALCROSS:
        ; 斜めの線分に使う、頂点の y-x+32 と x+y の最小・最大
        LD      A,(TRI_AY)
        LD      HL,TRI_AX
        SUB     (HL)
        ADD     A,32
        LD      B,A
        LD      C,A
        LD      A,(TRI_BY)
        LD      HL,TRI_BX
        SUB     (HL)
        ADD     A,32
        CALL    MINMAXBC
        LD      A,(TRI_CY)
        LD      HL,TRI_CX
        SUB     (HL)
        ADD     A,32
        CALL    MINMAXBC
        LD      A,B
        LD      (EC_DMIN),A
        LD      A,C
        LD      (EC_DMAX),A
        LD      A,(TRI_AY)
        LD      HL,TRI_AX
        ADD     A,(HL)
        LD      B,A
        LD      C,A
        LD      A,(TRI_BY)
        LD      HL,TRI_BX
        ADD     A,(HL)
        CALL    MINMAXBC
        LD      A,(TRI_CY)
        LD      HL,TRI_CX
        ADD     A,(HL)
        CALL    MINMAXBC
        LD      A,B
        LD      (EC_SMIN),A
        LD      A,C
        LD      (EC_SMAX),A

        LD      A,(EV_Y0)
        LD      (EV_CY),A
.rowlp:
        CALL    VBPOLL
        LD      A,(EV_X0)
        LD      (EV_CX),A
        LD      B,A
        LD      A,(EV_CY)
        LD      C,A
        CALL    CELLIDX
        LD      (EC_IDX),HL
.scan:
        ; 空きマスは短いループで読み飛ばす (ほとんどのマスはここで終わる)
        LD      HL,(EC_IDX)
        LD      DE,ARR_TERR
        ADD     HL,DE
        LD      A,(EV_X1)
        LD      C,A
        LD      A,(EV_CX)
        LD      B,A
.skip:
        LD      A,(HL)
        CP      0xFF
        JR      NZ,.found
        LD      A,B
        CP      C
        JP      Z,.rowend               ; 行の右端まで空きマス
        INC     B
        INC     HL
        JR      .skip
.found:
        LD      (EC_T),A
        LD      A,B
        LD      (EV_CX),A
        LD      DE,ARR_TERR
        OR      A
        SBC     HL,DE
        LD      (EC_IDX),HL
        LD      A,(EC_T)
        LD      HL,EVAL_ID
        CP      (HL)
        JP      Z,.cellnext             ; 自分のなわばり

        ; --- 右 (+1,0): 線分の向きで分かれるのは y が箱の上端か下端のとき
        LD      A,(EV_CX)
        LD      HL,EV_X1
        CP      (HL)
        JR      NC,.down                ; 右は箱の外
        LD      A,(EV_CY)
        LD      HL,EV_Y0
        CP      (HL)
        JR      Z,.down
        LD      HL,EV_Y1
        CP      (HL)
        JR      Z,.down
        LD      DE,1
        CALL    ECPAIR
        JP      NZ,.hit
.down:
        ; --- 下 (0,+1): 分かれるのは x が箱の左端か右端のとき
        LD      A,(EV_CY)
        LD      HL,EV_Y1
        CP      (HL)
        JP      NC,.cellnext            ; 下の 3 方向はどれも箱の外
        LD      A,(EV_CX)
        LD      HL,EV_X0
        CP      (HL)
        JR      Z,.dr
        LD      HL,EV_X1
        CP      (HL)
        JR      Z,.dr
        LD      DE,32
        CALL    ECPAIR
        JP      NZ,.hit
.dr:
        ; --- 右下 (+1,+1): 分かれるのは y-x が頂点の y-x の範囲の端か外のとき
        LD      A,(EV_CX)
        LD      HL,EV_X1
        CP      (HL)
        JR      NC,.dl                  ; 右下は箱の外
        LD      B,A
        LD      A,(EV_CY)
        SUB     B
        ADD     A,32
        LD      HL,EC_DMIN
        CP      (HL)
        JR      C,.dl
        JR      Z,.dl
        LD      HL,EC_DMAX
        CP      (HL)
        JR      NC,.dl
        LD      DE,33
        CALL    ECPAIR
        JP      NZ,.hit
.dl:
        ; --- 左下 (-1,+1): 分かれるのは x+y が頂点の x+y の範囲の端か外のとき
        LD      A,(EV_CX)
        LD      HL,EV_X0
        CP      (HL)
        JP      Z,.cellnext             ; 左下は箱の外
        LD      B,A
        LD      A,(EV_CY)
        ADD     A,B
        LD      HL,EC_SMIN
        CP      (HL)
        JP      C,.cellnext
        JP      Z,.cellnext
        LD      HL,EC_SMAX
        CP      (HL)
        JP      NC,.cellnext
        LD      DE,31
        CALL    ECPAIR
        JP      NZ,.hit
.cellnext:
        LD      A,(EV_CX)
        LD      HL,EV_X1
        CP      (HL)
        JR      NC,.rowend              ; 行の右端
        INC     A
        LD      (EV_CX),A
        LD      HL,(EC_IDX)
        INC     HL
        LD      (EC_IDX),HL
        JP      .scan
.rowend:
        LD      A,(EV_CY)
        INC     A
        LD      (EV_CY),A
        LD      HL,EV_Y1
        CP      (HL)
        JP      C,.rowlp
        JP      Z,.rowlp
        RET
.hit:
        LD      HL,0
        LD      (EV_N),HL
        LD      A,1
        LD      (EVAL_OTHER),A
        RET

; ---------------------------------------------------------------------
; ECPAIR - マス EC_IDX と EC_IDX+DE が同じ犬のなわばりで、
;   どの辺についても「2 マスとも外側か辺の上」になっていないか
;   出力: NZ なら線分が三角形の内側を通る / 壊す: A, DE, HL
; ---------------------------------------------------------------------
ECPAIR:
        LD      HL,(EC_IDX)
        ADD     HL,DE
        PUSH    HL
        LD      DE,ARR_TERR
        ADD     HL,DE
        LD      A,(EC_T)
        CP      (HL)
        POP     HL
        JR      NZ,.no                  ; 同じ犬のなわばりではない
        LD      DE,ARR_INTRI
        ADD     HL,DE
        LD      A,(HL)
        LD      HL,(EC_IDX)
        ADD     HL,DE
        AND     (HL)
        AND     0x70
        JR      NZ,.no                  ; どこかの辺で 2 つとも外側か辺の上
        OR      1
        RET
.no:
        XOR     A
        RET

; ---------------------------------------------------------------------
; MINMAXBC - A で B (最小) と C (最大) を更新する (符号なし)
; ---------------------------------------------------------------------
MINMAXBC:
        CP      B
        JR      NC,.nomin
        LD      B,A
.nomin:
        CP      C
        RET     C
        RET     Z
        LD      C,A
        RET

; ---------------------------------------------------------------------
; INTRI - 点 (B,C) が直前の EVALUATE の三角形の内側か
;   出力: A != 0 なら内側
; ---------------------------------------------------------------------
INTRI:
        LD      A,B
        CP      FW
        JR      NC,.no
        LD      A,C
        CP      FH
        JR      NC,.no
        LD      DE,ARR_INTRI
        CALL    CELLPTR
        LD      A,(HL)
        AND     1
        RET
.no:
        XOR     A
        RET
