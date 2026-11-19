; =====================================================================
; render.asm - フィールドと HUD の描画
; =====================================================================
; 背景は「汚れたマス」だけ描き直す。汚れたマスは待ち行列で持つので、
; 毎フレーム 800 マスを走査しなくてよい。
; スプライト (犬・車・アイテム) は毎フレーム重ねて描き、
; 次のフレームでその下のマスを汚れた扱いにして消す。
; =====================================================================

; ---------------------------------------------------------------------
; CELLIDX - マス (x,y) の配列添字   HL = y*32 + x
;   入力: B = x, C = y / 出力: HL / 壊す: A, DE
; ---------------------------------------------------------------------
CELLIDX:
        LD      H,0
        LD      L,C
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; y*32
        LD      D,0
        LD      E,B
        ADD     HL,DE
        RET

; ---------------------------------------------------------------------
; IDXTOXY - 添字 DE から x,y を求める
;   入力: DE = 添字 / 出力: B = x, C = y / 壊す: A
; ---------------------------------------------------------------------
IDXTOXY:
        LD      A,E
        AND     31
        LD      B,A
        LD      A,E
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x07
        LD      C,A
        LD      A,D
        ADD     A,A
        ADD     A,A
        ADD     A,A
        OR      C
        LD      C,A
        RET

; ---------------------------------------------------------------------
; CELLPTR - 配列 DE のマス (x,y) のアドレス
;   入力: B = x, C = y, DE = 配列の先頭 / 出力: HL
; ---------------------------------------------------------------------
CELLPTR:
        PUSH    DE
        CALL    CELLIDX
        POP     DE
        ADD     HL,DE
        RET

; =====================================================================
; 描き直す場所の管理
; =====================================================================

; ---------------------------------------------------------------------
; MARKDIRTY - マス (x,y) を描き直す対象にする
;   入力: B = x, C = y   (壊す: A, DE, HL)
; ---------------------------------------------------------------------
MARKDIRTY:
        LD      A,B
        CP      FW
        RET     NC
        LD      A,C
        CP      FH
        RET     NC
        PUSH    BC
        CALL    CELLIDX                 ; HL = 添字
        LD      D,H
        LD      E,L                     ; DE = 添字
        LD      BC,ARR_DIRTY
        ADD     HL,BC
        LD      A,(HL)
        OR      A
        JR      NZ,.already
        LD      (HL),1
        ; 待ち行列に積む
        LD      HL,(DIRTYTAIL)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (DIRTYTAIL),HL
.already:
        POP     BC
        RET

; MARKDIRTYI - 添字 DE のマスを描き直す対象にする
MARKDIRTYI:
        LD      HL,ARR_DIRTY
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET     NZ
        LD      (HL),1
        LD      HL,(DIRTYTAIL)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (DIRTYTAIL),HL
        RET

; ---------------------------------------------------------------------
; DIRTYRESET - 待ち行列を空にする
; ---------------------------------------------------------------------
DIRTYRESET:
        LD      HL,ARR_DIRTYQ
        LD      (DIRTYTAIL),HL
        LD      HL,ARR_DIRTY
        LD      BC,NCELL
        XOR     A
        CALL    MEMFILL
        XOR     A
        LD      (DIRTYALLF),A
        RET

; ---------------------------------------------------------------------
; DIRTYALL - 画面全部を描き直す
; ---------------------------------------------------------------------
DIRTYALL:
        LD      A,1
        LD      (DIRTYALLF),A
        RET

; ---------------------------------------------------------------------
; FLUSHDIRTY - 汚れたマスを描き直す
; ---------------------------------------------------------------------
FLUSHDIRTY:
        LD      A,(DIRTYALLF)
        OR      A
        JR      NZ,.all
        ; --- 待ち行列の分だけ ---
        ; 大きななわばりを取った瞬間に 700 マス描き直すと 10 フレーム以上
        ; 固まるので、1 ティックに FLUSHBUDGET マスまでにして残りは次に回す。
        LD      A,FLUSHBUDGET
        LD      (FLUSHLEFT),A
        LD      HL,ARR_DIRTYQ
.lp:
        LD      DE,(DIRTYTAIL)
        LD      A,L
        CP      E
        JR      NZ,.go
        LD      A,H
        CP      D
        JR      Z,.done
.go:
        LD      A,(FLUSHLEFT)
        OR      A
        JR      Z,.partial
        DEC     A
        LD      (FLUSHLEFT),A
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        PUSH    DE
        LD      HL,ARR_DIRTY
        ADD     HL,DE
        LD      (HL),0
        POP     DE
        CALL    IDXTOXY
        LD      A,B
        CP      FW
        JR      NC,.skip
        CALL    DRAWCELL
        CALL    VBPOLL
.skip:
        POP     HL
        JR      .lp
.done:
        LD      HL,ARR_DIRTYQ
        LD      (DIRTYTAIL),HL
        RET
.partial:
        ; HL から先がまだ残っている。待ち行列の先頭に詰め直す。
        LD      DE,(DIRTYTAIL)
        EX      DE,HL                   ; HL = 終わり, DE = 残りの先頭
        XOR     A
        SBC     HL,DE
        LD      B,H
        LD      C,L                     ; BC = 残りのバイト数
        EX      DE,HL                   ; HL = 残りの先頭
        LD      DE,ARR_DIRTYQ
        LDIR
        LD      (DIRTYTAIL),DE
        RET
.all:
        XOR     A
        LD      (DIRTYALLF),A
        LD      C,0
.ay:
        LD      B,0
.ax:
        PUSH    BC
        CALL    DRAWCELL
        CALL    VBPOLL
        POP     BC
        INC     B
        LD      A,B
        CP      FW
        JR      C,.ax
        INC     C
        LD      A,C
        CP      FH
        JR      C,.ay
        JP      DIRTYRESET

; =====================================================================
; マスの描画
; =====================================================================

; ---------------------------------------------------------------------
; DRAWCELL - マス 1 個の背景を描く
;   道路 / なわばり (縁取りつき) / 草 のどれか + 電柱 + アイテム
;   入力: B = x, C = y
;   壊す: すべて
; ---------------------------------------------------------------------
DRAWCELL:
        LD      A,B
        LD      (RND_CX),A
        LD      A,C
        LD      (RND_CY),A
        ; --- 道路か? ---
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JP      NZ,.road
        ; --- なわばりか? ---
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.grass
        ; なわばり: 持ち主の模様で塗って、隣と違うところに縁をつける
        LD      (TERROWNER),A
        CALL    DOGSTYLE                ; DE = 模様
        PUSH    DE
        CALL    CELLVA                  ; HL = VRAM アドレス
        POP     DE
        CALL    FILLCELL
        CALL    TERREDGE                ; A = 縁のビット
        OR      A
        JR      Z,.overlay
        PUSH    AF
        CALL    CELLVA
        POP     AF
        CALL    EDGECELL
        JR      .overlay
.grass:
        ; 草: マスの位置で 4 種類の模様を使い分ける
        LD      A,(RND_CY)
        AND     1
        ADD     A,A
        LD      E,A
        LD      A,(RND_CX)
        AND     1
        ADD     A,E                     ; 0..3
        LD      E,A
        ADD     A,A                     ; *2
        ADD     A,E                     ; *3
        ADD     A,A                     ; *6
        LD      E,A
        LD      D,0
        LD      HL,GRASSSTYLE
        ADD     HL,DE
        EX      DE,HL
        PUSH    DE
        CALL    CELLVA
        POP     DE
        CALL    FILLCELL
        JR      .overlay

.road:
        ; A = 1 (上の車線) / 2 (下の車線)
        DEC     A
        ADD     A,A                     ; 車線*2
        LD      E,A
        LD      A,(RND_CX)
        AND     1
        ADD     A,E
        ADD     A,A                     ; ワード添字
        LD      E,A
        LD      D,0
        LD      HL,SPRROAD
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        PUSH    HL                      ; 道路の絵
        CALL    CELLVA                  ; HL = VRAM
        EX      DE,HL                   ; DE = VRAM
        POP     HL                      ; HL = 道路の絵
        JP      BLITOPQ2                ; 道路のマスには電柱もアイテムも置かれない

.overlay:
        ; --- 電柱 ---
        LD      A,(RND_CX)
        LD      B,A
        LD      A,(RND_CY)
        LD      C,A
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.noitem0
        CALL    DRAWPOLE
.noitem0:
        ; --- アイテム ---
        LD      IY,ITEMS
        LD      B,NITEM
.itemlp:
        LD      A,(IY+IT_ACTIVE)
        OR      A
        JR      Z,.itemnext
        LD      A,(RND_CX)
        CP      (IY+IT_X)
        JR      NZ,.itemnext
        LD      A,(RND_CY)
        CP      (IY+IT_Y)
        JR      NZ,.itemnext
        ; 消える前 (残り 2 秒) は点滅させる
        LD      A,(IY+IT_T+1)
        OR      A
        JR      NZ,.show
        LD      A,(IY+IT_T)
        CP      2*TICKHZ
        JR      NC,.show
        LD      A,(FRAMECNT)
        AND     0x04
        JR      NZ,.itemnext
.show:
        PUSH    BC
        LD      A,(IY+IT_KIND)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,SPRITEM
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        PUSH    HL
        POP     IX
        CALL    CELLPX
        LD      A,C_WHITE
        CALL    DRAWSPR
        POP     BC
.itemnext:
        LD      DE,IT_SIZE
        ADD     IY,DE
        DJNZ    .itemlp
        RET

; ---------------------------------------------------------------------
; CELLVA - RND_CX/RND_CY のマスの VRAM アドレス -> HL
; ---------------------------------------------------------------------
CELLVA:
        LD      A,(RND_CX)
        LD      B,A
        LD      A,(RND_CY)
        LD      C,A
        JP      VADDR_CELL

; ---------------------------------------------------------------------
; CELLPX - RND_CX/RND_CY のマスのドット位置 -> D = 行, E = バイト列
; ---------------------------------------------------------------------
CELLPX:
        LD      A,(RND_CY)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        LD      A,(RND_CX)
        ADD     A,A
        LD      E,A
        RET

; ---------------------------------------------------------------------
; TERREDGE - 隣のマスと持ち主が違うところを調べる
;   入力: RND_CX/RND_CY, TERROWNER
;   出力: A = bit0 上 / bit1 下 / bit2 左 / bit3 右
; ---------------------------------------------------------------------
TERREDGE:
        XOR     A
        LD      (GFX_TMP),A
        ; 上
        LD      A,(RND_CY)
        OR      A
        JR      Z,.topedge
        DEC     A
        LD      C,A
        LD      A,(RND_CX)
        LD      B,A
        CALL    .same
        JR      Z,.noup
.topedge:
        LD      A,(GFX_TMP)
        OR      1
        LD      (GFX_TMP),A
.noup:
        ; 下
        LD      A,(RND_CY)
        INC     A
        CP      FH
        JR      NC,.botedge
        LD      C,A
        LD      A,(RND_CX)
        LD      B,A
        CALL    .same
        JR      Z,.nodown
.botedge:
        LD      A,(GFX_TMP)
        OR      2
        LD      (GFX_TMP),A
.nodown:
        ; 左
        LD      A,(RND_CX)
        OR      A
        JR      Z,.leftedge
        DEC     A
        LD      B,A
        LD      A,(RND_CY)
        LD      C,A
        CALL    .same
        JR      Z,.noleft
.leftedge:
        LD      A,(GFX_TMP)
        OR      4
        LD      (GFX_TMP),A
.noleft:
        ; 右
        LD      A,(RND_CX)
        INC     A
        CP      FW
        JR      NC,.rightedge
        LD      B,A
        LD      A,(RND_CY)
        LD      C,A
        CALL    .same
        JR      Z,.noright
.rightedge:
        LD      A,(GFX_TMP)
        OR      8
        LD      (GFX_TMP),A
.noright:
        LD      A,(GFX_TMP)
        RET
.same:
        ; (B,C) の持ち主が TERROWNER と同じなら Z
        PUSH    BC
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        POP     BC
        LD      HL,TERROWNER
        CP      (HL)
        RET

; ---------------------------------------------------------------------
; DOGSTYLE - 犬 ID からなわばりの模様を求める
;   入力: A = 犬 ID / 出力: DE = 模様のアドレス
; ---------------------------------------------------------------------
DOGSTYLE:
        CALL    DOGBREED
        CALL    BREEDPTR
        LD      A,(HL)                  ; B_STYLE
        LD      L,A
        LD      H,0
        ADD     HL,HL
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,DE                   ; *6
        LD      DE,TERRSTYLE
        ADD     HL,DE
        LD      D,H
        LD      E,L
        RET

; ---------------------------------------------------------------------
; DOGBREED - 犬 ID から犬種
; ---------------------------------------------------------------------
DOGBREED:
        PUSH    DE
        CALL    DOGADDR
        LD      DE,D_BREED
        ADD     HL,DE
        LD      A,(HL)
        POP     DE
        RET

; ---------------------------------------------------------------------
; DOGADDR - 犬 ID から構造体のアドレス   HL = DOGS + id*32
; ---------------------------------------------------------------------
DOGADDR:
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        PUSH    DE
        LD      DE,DOGS
        ADD     HL,DE
        POP     DE
        RET

; ---------------------------------------------------------------------
; BREEDPTR - 犬種テーブルのアドレス   HL = BREEDTBL + breed*6
; ---------------------------------------------------------------------
BREEDPTR:
        LD      L,A
        LD      H,0
        ADD     HL,HL
        PUSH    DE
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,DE                   ; *6
        LD      DE,BREEDTBL
        ADD     HL,DE
        POP     DE
        RET

; ---------------------------------------------------------------------
; TEMPERPTR - 性格テーブルのアドレス   HL = TEMPERTBL + breed*11
; ---------------------------------------------------------------------
TEMPERPTR:
        LD      L,A
        LD      H,0
        PUSH    DE
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; *8
        ADD     HL,DE
        ADD     HL,DE
        ADD     HL,DE                   ; *11
        LD      DE,TEMPERTBL
        ADD     HL,DE
        POP     DE
        RET

; ---------------------------------------------------------------------
; DRAWPOLE - 電柱とその印を描く
;   入力: A = 電柱番号, RND_CX / RND_CY = マス
; ---------------------------------------------------------------------
DRAWPOLE:
        LD      (TMPB0),A
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        ; 印 (おしっこ済み) は電柱の下に敷く
        LD      A,(IX+PL_OWNER)
        CP      0xFF
        JR      Z,.nomark
        LD      (TMPB1),A
        LD      IX,SPR_PEEMARK
        CALL    CELLPX
        LD      A,(TMPB1)
        PUSH    DE
        CALL    DOGTCOL
        POP     DE
        CALL    DRAWSPR
.nomark:
        ; 電柱そのもの
        LD      IX,SPR_POLE
        CALL    CELLPX
        LD      A,C_WHITE
        CALL    DRAWSPR
        ; なわばりに取り込まれた電柱は色帯をつける
        LD      A,(TMPB0)
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      Z,.nolock
        LD      A,(IX+PL_OWNER)
        CP      0xFF
        JR      Z,.nolock
        LD      (TMPB1),A
        LD      IX,SPR_POLEBAND
        CALL    CELLPX
        LD      A,(TMPB1)
        PUSH    DE
        CALL    DOGTCOL
        POP     DE
        CALL    DRAWSPR
.nolock:
        ; 柴犬が印をつけた電柱は点滅する枠で知らせる
        LD      A,(FRAMECNT)
        AND     0x08
        RET     Z
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(TMPB0)
        CALL    CHAINHAS
        POP     IY
        OR      A
        RET     Z
        LD      IX,SPR_SELFRAME
        CALL    CELLPX
        LD      A,C_WHITE
        JP      DRAWSPR

; ---------------------------------------------------------------------
; DOGTCOL / DOGBODYCOL - 犬 ID から色
; ---------------------------------------------------------------------
DOGTCOL:
        CALL    DOGBREED
        CALL    BREEDPTR
        INC     HL
        LD      A,(HL)                  ; B_TCOL
        RET

DOGBODYCOL:
        CALL    DOGBREED
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      A,(HL)                  ; B_BODY
        RET

; ---------------------------------------------------------------------
; POLEPTR - 電柱番号からアドレス   HL = POLES + n*4
; ---------------------------------------------------------------------
POLEPTR:
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        PUSH    DE
        LD      DE,POLES
        ADD     HL,DE
        POP     DE
        RET

; =====================================================================
; スプライト
; =====================================================================

; ---------------------------------------------------------------------
; SPRCLEAR - 前のフレームでスプライトを描いたマスを汚れた扱いにする
; ---------------------------------------------------------------------
SPRCLEAR:
        LD      A,(SPRCOUNT)
        OR      A
        RET     Z
        LD      B,A
        LD      HL,ARR_SPRCELL
.lp:
        PUSH    BC
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        CALL    MARKDIRTYI
        POP     HL
        POP     BC
        DJNZ    .lp
        XOR     A
        LD      (SPRCOUNT),A
        RET

; ---------------------------------------------------------------------
; SPRPUSH - マス (x,y) を「スプライトを描いた」一覧に加える
; ---------------------------------------------------------------------
SPRPUSH:
        LD      A,B
        CP      FW
        RET     NC
        LD      A,C
        CP      FH
        RET     NC
        LD      A,(SPRCOUNT)
        CP      250
        RET     NC
        PUSH    BC
        CALL    CELLIDX                 ; HL = 添字
        LD      A,(SPRCOUNT)
        LD      E,A
        LD      D,0
        EX      DE,HL                   ; HL = 個数, DE = 添字
        ADD     HL,HL
        LD      BC,ARR_SPRCELL
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),D
        LD      A,(SPRCOUNT)
        INC     A
        LD      (SPRCOUNT),A
        POP     BC
        RET

; ---------------------------------------------------------------------
; SPRCOVER - バイト列 E / ドット行 D から 16x8 が覆うマスを一覧に加える
; ---------------------------------------------------------------------
SPRCOVER:
        LD      A,D
        LD      (SPC_D),A
        LD      A,E
        LD      (SPC_E),A
        SRL     A
        LD      B,A                     ; 左のマス x
        LD      A,(SPC_D)
        SRL     A
        SRL     A
        SRL     A
        LD      C,A                     ; 上のマス y
        PUSH    BC
        CALL    SPRPUSH
        POP     BC
        ; 右のマスはバイト列が奇数のときだけ
        LD      A,(SPC_E)
        AND     1
        JR      Z,.nox
        INC     B
        PUSH    BC
        CALL    SPRPUSH
        POP     BC
        DEC     B
.nox:
        ; 下のマスはマス行の途中にいるときだけ
        LD      A,(SPC_D)
        AND     7
        JR      Z,.fin
        INC     C
        PUSH    BC
        CALL    SPRPUSH
        POP     BC
        LD      A,(SPC_E)
        AND     1
        JR      Z,.fin
        INC     B
        CALL    SPRPUSH
.fin:
        LD      A,(SPC_D)
        LD      D,A
        LD      A,(SPC_E)
        LD      E,A
        RET

; ---------------------------------------------------------------------
; DRAWSPR_C - 覆うマスを記録してからスプライトを描く
; ---------------------------------------------------------------------
DRAWSPR_C:
        LD      (GFX_COL),A
        PUSH    IX
        CALL    SPRCOVER
        POP     IX
        LD      A,(GFX_COL)
        JP      DRAWSPR

; ---------------------------------------------------------------------
; DRAWDOGS - 生きている犬をすべて描く
; ---------------------------------------------------------------------
DRAWDOGS:
        LD      A,(NDOGS)
        LD      B,A
        XOR     A
.lp:
        PUSH    BC
        PUSH    AF
        CALL    DRAWONEDOG
        CALL    VBPOLL
        POP     AF
        INC     A
        POP     BC
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; DRAWONEDOG - 犬 1 匹を描く
;   入力: A = 犬 ID
; ---------------------------------------------------------------------
DRAWONEDOG:
        LD      (TMPB2),A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_FLAGS)
        AND     DF_ALIVE
        RET     Z
        ; 無敵中は点滅させる
        LD      A,(IY+D_INVULN)
        OR      A
        JR      Z,.visible
        LD      A,(FRAMECNT)
        AND     0x02
        RET     NZ
.visible:
        ; --- 描く位置 ---
        LD      A,(IY+D_X)
        ADD     A,A
        LD      E,A
        LD      A,(IY+D_Y)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        LD      A,(IY+D_FLAGS)
        AND     DF_MOVING
        JR      Z,.nohalf
        LD      A,(IY+D_MOVET)
        ADD     A,A
        CP      (IY+D_STEPTIME)
        JR      NC,.nohalf
        ; 移動の前半は移動元から半分だけ進んだ位置
        LD      A,(IY+D_FROMX)
        ADD     A,A
        LD      E,A
        LD      A,(IY+D_X)
        SUB     (IY+D_FROMX)
        ADD     A,E
        LD      E,A
        LD      A,(IY+D_FROMY)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        LD      A,(IY+D_Y)
        SUB     (IY+D_FROMY)
        ADD     A,A
        ADD     A,A
        ADD     A,D
        LD      D,A
.nohalf:
        LD      A,D
        LD      (TMPB0),A
        LD      A,E
        LD      (TMPB1),A
        ; --- ボスは 2 倍の大きさ ---
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        JP      NZ,DRAWBOSS
        ; --- スプライトを選ぶ ---
        LD      A,(TMPB2)
        CALL    DOGBREED
        CALL    BREEDPTR
        INC     HL
        INC     HL
        INC     HL
        LD      A,(HL)                  ; B_EAR (0..2)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A                     ; 耳*16
        LD      C,A
        ; おしっこ中は専用の絵
        LD      A,(IY+D_PEET)
        OR      (IY+D_PEET+1)
        JR      Z,.walk
        SRL     C                       ; 耳*16 -> 耳*8
        LD      A,(IY+D_DIR)
        ADD     A,A
        ADD     A,C
        LD      E,A
        LD      D,0
        LD      HL,SPRPEE
        ADD     HL,DE
        JR      .gotspr
.walk:
        LD      A,(IY+D_FLAGS)
        AND     DF_STEPFLIP
        JR      Z,.f0
        LD      A,8
        ADD     A,C
        LD      C,A
.f0:
        LD      A,(IY+D_DIR)
        ADD     A,A
        ADD     A,C
        LD      E,A
        LD      D,0
        LD      HL,SPRDOG
        ADD     HL,DE
.gotspr:
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        PUSH    HL
        POP     IX
        LD      A,(TMPB2)
        CALL    DOGBODYCOL
        LD      C,A
        ; 巻物の効果中は点滅で半透明っぽく見せる
        LD      A,(IY+D_PASST)
        OR      (IY+D_PASST+1)
        JR      Z,.solid
        LD      A,(FRAMECNT)
        AND     0x01
        JR      Z,.solid
        LD      C,C_WHITE
.solid:
        LD      A,(TMPB0)
        LD      D,A
        LD      A,(TMPB1)
        LD      E,A
        LD      A,C
        CALL    DRAWSPR_C
        ; --- ボーナス面: 眠っている / 起きている印 ---
        LD      A,(BONUSMODE)
        OR      A
        RET     Z
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        RET     NZ
        LD      A,(IY+D_FLAGS)
        AND     DF_ASLEEP
        LD      IX,SPR_AWAKE
        JR      Z,.aw
        LD      IX,SPR_ZZZ
.aw:
        LD      A,(TMPB0)
        SUB     8
        RET     C
        LD      D,A
        LD      A,(TMPB1)
        LD      E,A
        LD      A,C_WHITE
        JP      DRAWSPR_C

; ---------------------------------------------------------------------
; DRAWBOSS - ボス犬 (32x16) を描く
; ---------------------------------------------------------------------
DRAWBOSS:
        LD      A,(TMPB2)
        CALL    DOGBODYCOL
        LD      (TMPB3),A
        LD      IX,SPR_BOSS_TL
        LD      A,(TMPB0)
        LD      D,A
        LD      A,(TMPB1)
        LD      E,A
        LD      A,(TMPB3)
        CALL    DRAWSPR_C
        LD      A,(TMPB1)
        ADD     A,2
        CP      HUD_X
        JR      NC,.skip1
        LD      E,A
        LD      A,(TMPB0)
        LD      D,A
        LD      IX,SPR_BOSS_TR
        LD      A,(TMPB3)
        CALL    DRAWSPR_C
.skip1:
        LD      A,(TMPB0)
        ADD     A,8
        CP      193
        RET     NC
        LD      D,A
        LD      IX,SPR_BOSS_BL
        LD      A,(TMPB1)
        LD      E,A
        LD      A,(TMPB3)
        CALL    DRAWSPR_C
        LD      A,(TMPB1)
        ADD     A,2
        CP      HUD_X
        RET     NC
        LD      E,A
        LD      A,(TMPB0)
        ADD     A,8
        LD      D,A
        LD      IX,SPR_BOSS_BR
        LD      A,(TMPB3)
        JP      DRAWSPR_C

; ---------------------------------------------------------------------
; DRAWCARS - 走っている車を描く
; ---------------------------------------------------------------------
; ---------------------------------------------------------------------
; CARSMARK - 車が動いた/消えたマスだけを汚す (FLUSHDIRTY の前に呼ぶ)
;   車は不透明で自分のマスを塗りつぶすので、止まっているあいだは
;   下の道路を描き直す必要がない。動いた瞬間だけ前の場所を汚す。
;   CARPBX/CARPROW に「いま描くべき場所」を残すので DRAWCARS はそれを使う。
; ---------------------------------------------------------------------
CARSMARK:
        LD      IY,CARS
        LD      IX,CARPBX
        LD      B,NCAR
.lp:
        PUSH    BC
        ; --- いまのバイト列 (0xFF = 画面の外) ---
        LD      A,0xFF
        LD      (CARNBX),A
        LD      A,(IY+CR_ACTIVE)
        OR      A
        JR      Z,.got
        LD      L,(IY+CR_XLO)
        LD      H,(IY+CR_XHI)
        BIT     7,H
        JR      NZ,.got                 ; まだ画面の左の外
        SRL     H
        RR      L
        SRL     H
        RR      L
        SRL     H
        RR      L                       ; x/8
        LD      A,H
        OR      A
        JR      NZ,.got
        LD      A,L
        CP      HUD_X
        JR      NC,.got
        LD      (CARNBX),A
.got:
        ; --- 前に描いた場所と比べる ---
        LD      A,(CARNBX)
        CP      (IX+0)
        JR      NZ,.moved
        LD      A,(IY+CR_ROW)
        CP      (IX+NCAR)
        JR      Z,.store                ; 動いていない: 何もしない
.moved:
        LD      A,(IX+0)
        CP      0xFF
        JR      Z,.store                ; 前は描いていない
        ; 前の 4 バイト列が重なっていたマスを汚す
        SRL     A
        LD      B,A                     ; 左のマス x
        LD      A,(IX+0)
        ADD     A,3
        SRL     A                       ; 右のマス x
        SUB     B
        INC     A
        LD      (CARN),A
        LD      C,(IX+NCAR)
.mklp:
        PUSH    BC
        CALL    MARKDIRTY
        POP     BC
        INC     B
        LD      A,(CARN)
        DEC     A
        LD      (CARN),A
        JR      NZ,.mklp
.store:
        LD      A,(CARNBX)
        LD      (IX+0),A
        LD      A,(IY+CR_ROW)
        LD      (IX+NCAR),A
        INC     IX
        LD      DE,CR_SIZE
        ADD     IY,DE
        POP     BC
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; CARSINIT - 「前に描いた場所」をなしにする (ステージの最初に呼ぶ)
; ---------------------------------------------------------------------
CARSINIT:
        LD      HL,CARPBX
        LD      BC,NCAR*2
        LD      A,0xFF
        JP      MEMFILL

; ---------------------------------------------------------------------
; DRAWCARS - 車を 32x8 の不透明スプライトで描く
;   CARSMARK が決めた位置 (CARPBX/CARPROW) に描くだけ。
; ---------------------------------------------------------------------
DRAWCARS:
        LD      IY,CARS
        LD      IX,CARPBX
        LD      B,NCAR
.lp:
        PUSH    BC
        LD      A,(IX+0)
        CP      0xFF
        JP      Z,.off
        LD      (CARBX),A
        ; --- HUD にはみ出さない幅 (1..4) ---
        LD      C,A
        LD      A,HUD_X
        SUB     C
        CP      4
        JR      C,.clip
        LD      A,4
.clip:
        LD      (CARW),A
        ; --- 絵を選ぶ: 色*2 + 向き ---
        LD      A,(IY+CR_COLOR)
        AND     3
        ADD     A,A
        ADD     A,(IY+CR_SIGN)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,SPRCAR
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        PUSH    HL
        ; --- VRAM アドレス ---
        LD      A,(IX+NCAR)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        LD      A,(CARBX)
        LD      E,A
        CALL    VADDR_PX
        EX      DE,HL                   ; DE = VRAM
        POP     HL                      ; HL = 絵
        LD      A,(CARW)
        CP      4
        JP      NZ,.wclip
        CALL    BLITOPQ4
        JR      .off
.wclip:
        CALL    BLITOPQW
.off:
        POP     BC
        INC     IX
        LD      DE,CR_SIZE
        ADD     IY,DE
        DJNZ    .lp
        RET

; =====================================================================
; HUD
; =====================================================================

; ---------------------------------------------------------------------
; HUD の並び (元の版の DrawPanel を 640x400 -> 640x200 に)。
;   元の版の文字は 400 ドットの画面で 8 ドット = こちらの 4 行ぶんなので、
;   8 行の文字が重ならないよう行の間だけ少し詰めてある。並びと横の位置は同じ。
; ---------------------------------------------------------------------
HX              EQU HUD_X+1     ; 左端 (元の版の X = FieldW + 8)
HXV             EQU HUD_X+12    ; SCORE / HI の値 (X + 88)
HY_LOGO         EQU 2
HY_STAGE        EQU 14
HY_SCORE        EQU 25
HY_HI           EQU 34
HY_LIVES        EQU 45
HY_TIME         EQU 56
HY_AREA         EQU 67
HY_BAR          EQU 77              ; 5 行
HY_LIST         EQU 87              ; 犬ごとの面積 (9 行おき)
HY_FPS          EQU 192
BAR_W           EQU 144             ; ドット (18 バイト)

; ---------------------------------------------------------------------
; HUDFPS - 1 秒あたりのティック数を HUD のいちばん下に出す (T キーで切り替え)
;   30 と出れば設計どおりの速さ。小さいほど重い。
; ---------------------------------------------------------------------
HUDFPS:
        LD      A,(FPSVAL)
        LD      L,A
        LD      H,0
        LD      DE,STRBUF
        LD      B,2
        CALL    NUMSTR
        LD      A,C_YELLOW
        LD      (GFX_COL),A
        LD      HL,S_TPS
        LD      B,HX
        LD      C,HY_FPS
        CALL    DRAWSTR
        LD      A,C_YELLOW
        LD      (GFX_COL),A
        LD      HL,STRBUF
        LD      B,HX+4
        LD      C,HY_FPS
        JP      DRAWSTR

HUDFPSCLR:
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,S_TPSCLR
        LD      B,HX
        LD      C,HY_FPS
        JP      DRAWSTR

; ---------------------------------------------------------------------
; HUDALL - HUD を全部描く
; ---------------------------------------------------------------------
HUDALL:
        LD      A,C_DARK
        LD      (HUDBG),A               ; これ以降 HUD の文字は暗い背景で描く
        ; 右側を暗い色 (色 1 = プレーン 0 だけ) で塗る (元の版の PanelBg)
        LD      C,P_GV0
.clr:
        LD      A,0
        OUT     (C),A
        LD      HL,VRAM+HUD_X
        LD      B,200
.clrow:
        PUSH    BC
        PUSH    HL
        LD      A,C
        CP      P_GV0
        LD      A,0
        JR      NZ,.clv
        LD      A,0xFF
.clv:
        LD      B,80-HUD_X
.clb:
        LD      (HL),A
        INC     HL
        DJNZ    .clb
        POP     HL
        LD      DE,VSTRIDE
        ADD     HL,DE
        POP     BC
        DJNZ    .clrow
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.clr
        XOR     A
        OUT     (P_GVOFF),A

        ; 左に 1 ドットの仕切り線 (色 4 = プレーン 2 だけ)
        LD      C,P_GV0
.div:
        LD      A,0
        OUT     (C),A
        LD      HL,VRAM+HUD_X
        LD      DE,VSTRIDE
        LD      B,200
.divrow:
        LD      A,C
        CP      P_GV0+2
        LD      A,(HL)
        JR      Z,.divset
        AND     0x7F
        JR      .divput
.divset:
        OR      0x80
.divput:
        LD      (HL),A
        ADD     HL,DE
        DJNZ    .divrow
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.div
        XOR     A
        OUT     (P_GVOFF),A

        ; 肉球と "SHIBA JINTORI" (元の版と同じ橙)
        LD      IX,SPR_PAW
        LD      A,C_ORANGE
        LD      D,HY_LOGO
        LD      E,HX
        CALL    DRAWSPR
        LD      A,C_ORANGE
        LD      (GFX_COL),A
        LD      HL,S_LOGO
        LD      B,HX+2                  ; X + 20
        LD      C,HY_LOGO
        CALL    DRAWSTR
        ; 見出し (元の版の 0x9AA4C8 = 水色)
        LD      HL,HUDLABELS
.lab:
        LD      A,(HL)
        OR      A
        JR      Z,.labd
        LD      C,A
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        EX      DE,HL
        LD      A,C_BLUE
        LD      (GFX_COL),A
        LD      B,HX
        CALL    DRAWSTR
        POP     HL
        JR      .lab
.labd:
        LD      A,0xFF
        LD      (LIVESSHOWN),A          ; 残機も描かせる
        LD      A,1
        LD      (AREADIRTY),A
        LD      (LISTDIRTY),A
        JP      HUDVALUES

HUDLABELS:
        DB      HY_SCORE
        DW      S_SCORE
        DB      HY_HI
        DW      S_HI
        DB      HY_LIVES
        DW      S_LIVES
        DB      HY_TIME
        DW      S_TIME
        DB      HY_AREA
        DW      S_AREA
        DB      0

; ---------------------------------------------------------------------
; HUDVALUES - 数字の部分を描き直す
;   犬ごとの一覧と面積の帯は、変わったとき (LISTDIRTY / AREADIRTY) だけ
; ---------------------------------------------------------------------
HUDVALUES:
        ; --- STAGE 01 / BONUS STAGE ---
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.stage
        LD      A,C_YELLOW
        LD      (GFX_COL),A
        LD      HL,S_BONUSST
        JR      .stput
.stage:
        LD      A,(STAGE)
        LD      L,A
        LD      H,0
        LD      DE,STRBUF+6
        LD      B,2
        CALL    NUMSTR
        LD      HL,STRBUF+6
        CALL    ZEROPAD
        LD      HL,S_STAGE6
        LD      DE,STRBUF
        LD      BC,6
        LDIR
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,STRBUF
.stput:
        LD      B,HX
        LD      C,HY_STAGE
        CALL    DRAWSTR
        ; --- SCORE / HI (7 桁、0 で埋める) ---
        LD      HL,SCORE
        LD      C,HY_SCORE
        CALL    .num7
        CALL    HIDISPPTR               ; 1 位と今の点の大きいほう (元の版と同じ)
        LD      C,HY_HI
        CALL    .num7
        ; --- TIME (3 桁。残り 20 秒からは赤) ---
        LD      A,(SECLEFT)
        LD      L,A
        LD      H,0
        LD      DE,STRBUF
        LD      B,3
        CALL    NUMSTR
        LD      A,(SECLEFT)
        CP      21
        LD      A,C_WHITE
        JR      NC,.tcol
        LD      A,C_RED
.tcol:
        LD      (GFX_COL),A
        LD      HL,STRBUF
        LD      B,HUD_X+16              ; X + 120
        LD      C,HY_TIME
        CALL    DRAWSTR
        ; --- AREA nn%/75% (全体のなわばり率) ---
        LD      HL,(CLAIMED)
        ADD     HL,HL                   ; *100/750 = *2/15
        LD      C,15
        CALL    DIVHLC
        LD      DE,STRBUF
        LD      B,3
        CALL    NUMSTR
        LD      HL,S_PCT75
        LD      DE,STRBUF+3
        LD      BC,6
        LDIR
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,STRBUF
        LD      B,HUD_X+11              ; X + 80
        LD      C,HY_AREA
        CALL    DRAWSTR
        ; --- LIVES ---
        CALL    HUDLIVES
        ; --- 帯と一覧 ---
        LD      A,(LISTDIRTY)
        OR      A
        JR      Z,.nolist
        XOR     A
        LD      (LISTDIRTY),A
        CALL    HUDLIST
.nolist:
        LD      A,(AREADIRTY)
        OR      A
        RET     Z
        XOR     A
        LD      (AREADIRTY),A
        CALL    HUDBAR
        JP      HUDAREAS

; .num7 - 3 バイトの値 HL を 7 桁 (0 埋め) で、HXV 列・行 C に白で
.num7:
        PUSH    BC
        LD      DE,STRBUF
        LD      B,7
        CALL    NUMSTR24
        LD      HL,STRBUF
        CALL    ZEROPAD
        POP     BC
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,STRBUF
        LD      B,HXV
        JP      DRAWSTR

; ZEROPAD - 文字列 HL の頭の空白を 0 に
ZEROPAD:
        LD      A,(HL)
        CP      ' '
        RET     NZ
        LD      (HL),'0'
        INC     HL
        JR      ZEROPAD

; DIVHLC - HL = HL / C (A = 余り)。C は 128 未満
DIVHLC:
        XOR     A
        LD      B,16
.l:
        ADD     HL,HL
        RLA
        CP      C
        JR      C,.n
        SUB     C
        INC     L
.n:
        DJNZ    .l
        RET

; ---------------------------------------------------------------------
; HUDLIVES - 残機 (元の版と同じく 5 匹までは顔を並べ、6 以上は「顔 x 数」)
; ---------------------------------------------------------------------
LIVES_X         EQU HUD_X+7             ; X + 48

HUDLIVES:
        LD      A,(LIVES)
        LD      HL,LIVESSHOWN
        CP      (HL)
        RET     Z                       ; 変わっていなければ描かない
        LD      (HL),A
        CP      6
        JR      C,.few
        ; 6 以上: 顔 + "x 7"
        LD      E,LIVES_X
        LD      D,HY_LIVES
        CALL    HUDBLANK16
        LD      E,LIVES_X
        LD      D,HY_LIVES
        CALL    LIFEFACE
        LD      A,(LIVES)
        ADD     A,'0'
        LD      (S_XN+2),A
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,S_XN
        LD      B,LIVES_X+2
        LD      C,HY_LIVES
        JP      DRAWSTR
.few:
        LD      B,0
.lp:
        LD      A,B
        CP      5
        RET     NC
        PUSH    BC
        ADD     A,A
        ADD     A,LIVES_X
        LD      E,A
        LD      D,HY_LIVES
        PUSH    DE
        CALL    HUDBLANK16
        POP     DE
        POP     BC
        PUSH    BC
        LD      A,(LIVES)
        CP      B
        JR      Z,.skip
        JR      C,.skip
        CALL    LIFEFACE
.skip:
        POP     BC
        INC     B
        JR      .lp
; HUDBLANK16 - 16x8 を HUD の地の色で塗る (D = 行, E = バイト列)
HUDBLANK16:
        CALL    VADDR_PX
        EX      DE,HL
        LD      HL,OPQ_HUDBG
        JP      BLITOPQ2

; LIFEFACE - 柴犬の顔を (D, E) に (黒柴は紺に溶けるので水色の輪郭の絵)
LIFEFACE:
        LD      A,(SHIBACOLOR)
        CP      1
        JR      NZ,.col
        LD      IX,SPR_LIFEK
        LD      A,C_BLUE
        JP      DRAWSPR
.col:
        LD      IX,SPR_LIFE
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      A,(HL)
        JP      DRAWSPR

; ---------------------------------------------------------------------
; HUDBAR - 全体のなわばりの帯 (犬ごとの色を並べる。75% に白い目印)
;   色ごとのプレーンを TMPBUF (18 バイト x 3) に作ってから流しこむ。
;   まだ誰のものでもないところは濃い草の色。
; ---------------------------------------------------------------------
HUDBAR:
        ; 地 = 色 5 (プレーン 0 と 2)
        LD      HL,TMPBUF
        LD      B,18
.f0:
        LD      (HL),0xFF
        INC     HL
        DJNZ    .f0
        LD      B,18
.f1:
        LD      (HL),0
        INC     HL
        DJNZ    .f1
        LD      B,18
.f2:
        LD      (HL),0xFF
        INC     HL
        DJNZ    .f2
        XOR     A
        LD      (BAR_X0),A
        LD      (BAR_I),A
        LD      HL,0
        LD      (BAR_CUM),HL
.dog:
        LD      A,(BAR_I)
        LD      HL,NDOGS
        CP      (HL)
        JR      NC,.blit
        CALL    DOGADDR
        LD      DE,D_AREA
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      HL,(BAR_CUM)
        ADD     HL,DE
        LD      (BAR_CUM),HL
        ; 右端 = 累計 * 144 / 750 = 累計 * 24 / 125
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,DE                   ; *3
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; *24
        LD      C,125
        CALL    DIVHLC
        LD      A,L
        LD      (BAR_X1),A
        LD      A,(BAR_I)
        CALL    DOGTCOL
        LD      (BAR_COL),A
        CALL    BARFILL
        LD      A,(BAR_X1)
        LD      (BAR_X0),A
        LD      HL,BAR_I
        INC     (HL)
        JR      .dog
.blit:
        ; 5 行に流しこむ
        LD      C,P_GV0
        LD      HL,TMPBUF
.pl:
        XOR     A
        OUT     (C),A
        PUSH    BC
        LD      B,5
        LD      D,HY_BAR
.row:
        PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      E,HX
        PUSH    HL
        CALL    VADDR_PX
        EX      DE,HL                   ; DE = VRAM
        POP     HL
        LD      BC,18
        LDIR
        POP     DE
        INC     D
        POP     HL
        POP     BC
        DJNZ    .row
        LD      DE,18
        ADD     HL,DE
        POP     BC
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.pl
        ; 75% の白い目印 (ドット 108 = バイト HX+13 の bit3)。帯の上下に 1 行はみ出す
        LD      C,P_GV0
.mk:
        XOR     A
        OUT     (C),A
        PUSH    BC
        LD      D,HY_BAR-1
        LD      E,HX+13
        CALL    VADDR_PX
        LD      DE,VSTRIDE
        LD      B,7
.mr:
        LD      A,(HL)
        OR      0x08
        LD      (HL),A
        ADD     HL,DE
        DJNZ    .mr
        POP     BC
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.mk
        XOR     A
        OUT     (P_GVOFF),A
        RET

; BARFILL - TMPBUF の帯の BAR_X0 .. BAR_X1-1 ドットを色 BAR_COL に
BARFILL:
        LD      A,(BAR_X0)
        LD      C,A
.lp:
        LD      A,(BAR_X1)
        CP      C
        RET     Z
        RET     C
        ; マスク B, バイト位置 HL
        LD      A,C
        AND     7
        LD      B,0x80
        JR      Z,.m
.s:
        SRL     B
        DEC     A
        JR      NZ,.s
.m:
        LD      A,C
        RRCA
        RRCA
        RRCA
        AND     0x1F
        LD      E,A
        LD      D,0
        LD      HL,TMPBUF
        ADD     HL,DE
        LD      A,(BAR_COL)
        LD      D,A
        LD      E,3
.p:
        RR      D
        LD      A,(HL)
        JR      NC,.clr
        OR      B
        JR      .put
.clr:
        PUSH    BC
        LD      C,A
        LD      A,B
        CPL
        AND     C
        POP     BC
.put:
        LD      (HL),A
        PUSH    DE
        LD      DE,18
        ADD     HL,DE
        POP     DE
        DEC     E
        JR      NZ,.p
        INC     C
        JR      .lp

; ---------------------------------------------------------------------
; HUDLIST - 犬ごとの行 (色の印・顔・名前)。退場した犬は "OUT"
; HUDAREAS - その右の面積 (3 桁、なわばりの色)
; ---------------------------------------------------------------------
HUDLIST:
        XOR     A
.lp:
        LD      HL,NDOGS
        CP      (HL)
        RET     NC
        LD      (BAR_I),A
        CALL    LISTROW                 ; D = 行
        LD      (BAR_Y),A
        ; 左の色の印 (元の版の 3 ドットの帯): バイト HUD_X の bit3..1
        LD      A,(BAR_I)
        CALL    DOGTCOL
        LD      (BAR_COL),A
        LD      C,P_GV0
.sp:
        XOR     A
        OUT     (C),A
        PUSH    BC
        ; このプレーンのビット = (色 >> プレーン番号) & 1
        LD      A,C
        SUB     P_GV0
        LD      B,A
        LD      A,(BAR_COL)
        JR      Z,.s1
.sh:
        RRCA
        DJNZ    .sh
.s1:
        AND     1
        LD      (BAR_BIT),A
        LD      A,(BAR_Y)
        LD      D,A
        LD      E,HUD_X
        CALL    VADDR_PX
        LD      DE,VSTRIDE
        LD      B,8
.sr:
        LD      A,(HL)
        AND     0xF1
        LD      C,A
        LD      A,(BAR_BIT)
        OR      A
        LD      A,C
        JR      Z,.s0
        OR      0x0E
.s0:
        LD      (HL),A
        ADD     HL,DE
        DJNZ    .sr
        POP     BC
        INC     C
        LD      A,C
        CP      P_GV0+3
        JR      C,.sp
        XOR     A
        OUT     (P_GVOFF),A
        ; 顔: 地を塗ってから
        LD      A,(BAR_Y)
        LD      D,A
        LD      E,HX
        CALL    HUDBLANK16
        LD      A,(BAR_I)
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        LD      A,(IX+D_FLAGS)
        LD      (BAR_FL),A
        LD      A,(BAR_Y)
        LD      D,A
        LD      E,HX
        LD      A,(BAR_FL)
        AND     DF_PLAYER
        JR      Z,.enemy
        CALL    LIFEFACE
        JR      .name
.enemy:
        PUSH    DE
        LD      A,(BAR_I)
        CALL    DOGBREED
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      C,(HL)                  ; 体の色
        INC     HL
        LD      A,(HL)                  ; 耳
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A                     ; 耳 * 32 (SPRDOG の正面の絵)
        LD      E,A
        LD      D,0
        LD      HL,SPRDOG
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        PUSH    HL
        POP     IX
        LD      A,(BAR_FL)
        AND     DF_ALIVE
        LD      A,C
        JR      NZ,.alive
        LD      A,C_GRASS2              ; 退場した犬はくすんだ色
.alive:
        POP     DE
        CALL    DRAWSPR
.name:
        ; 名前 (10 文字に空白で埋める)。自分は黄、退場は "OUT"
        LD      HL,STRBUF
        LD      B,10
.bl:
        LD      (HL),' '
        INC     HL
        DJNZ    .bl
        LD      (HL),0
        LD      A,(BAR_FL)
        AND     DF_ALIVE
        LD      HL,S_OUT3
        LD      C,C_GRASS2
        JR      Z,.cp
        LD      A,(BAR_I)
        CALL    DOGBREED
        CALL    BREEDPTR
        LD      DE,4
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      C,C_WHITE
        LD      A,(BAR_FL)
        AND     DF_PLAYER
        JR      Z,.cp
        LD      C,C_YELLOW
.cp:
        LD      A,C
        LD      (GFX_COL),A
        LD      DE,STRBUF
.cl:
        LD      A,(HL)
        OR      A
        JR      Z,.cd
        LD      (DE),A
        INC     HL
        INC     DE
        JR      .cl
.cd:
        LD      HL,STRBUF
        LD      B,HUD_X+4               ; X + 22
        LD      A,(BAR_Y)
        LD      C,A
        CALL    DRAWSTR
        LD      A,(BAR_I)
        INC     A
        JP      .lp

HUDAREAS:
        XOR     A
.lp:
        LD      HL,NDOGS
        CP      (HL)
        RET     NC
        LD      (BAR_I),A
        CALL    DOGADDR
        LD      DE,D_AREA
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        LD      DE,STRBUF
        LD      B,3
        CALL    NUMSTR
        LD      A,(BAR_I)
        CALL    DOGTCOL
        LD      (GFX_COL),A
        LD      A,(BAR_I)
        CALL    LISTROW
        LD      C,A
        LD      HL,STRBUF
        LD      B,HUD_X+16              ; X + 120
        CALL    DRAWSTR
        LD      A,(BAR_I)
        INC     A
        JR      .lp

; LISTROW - 犬 A の行 -> A
LISTROW:
        LD      B,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,B                     ; *9
        ADD     A,HY_LIST
        RET

S_LOGO:         DB      "SHIBA JINTORI",0
S_STAGE6:       DB      "STAGE "
S_BONUSST:      DB      "BONUS STAGE",0
S_PCT75:        DB      "%/75%",0
S_OUT3:         DB      "OUT",0
S_XN:           DB      "x 6       ",0      ; うしろの空白で 2 匹目以降の顔を消す

; ---------------------------------------------------------------------
; HUDMSG - HUD の下にメッセージを出す (HL = 文字列, A = 色)
; ---------------------------------------------------------------------
HUDMSG:
        LD      (TMPB3),A
        PUSH    HL
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      HL,S_BLANK20
        LD      B,HUD_X+1               ; HUD_X には仕切り線があるので 1 つ右から
        LD      C,184
        CALL    DRAWSTR
        POP     HL
        LD      A,(TMPB3)
        LD      (GFX_COL),A
        LD      B,HUD_X+1
        LD      C,184
        JP      DRAWSTR

S_BLANK20:      DB      "                   ",0   ; 19 文字 (HUD_X+1 から右端まで)

; ---------------------------------------------------------------------
; NUMSTR24 - 24bit の値 (HL が指す 3 バイト) を 10 進にする
; ---------------------------------------------------------------------
NUMSTR24:
        LD      A,(HL)
        LD      (TMPW0),A
        INC     HL
        LD      A,(HL)
        LD      (TMPW0+1),A
        INC     HL
        LD      A,(HL)
        LD      (TMPW1),A
        PUSH    DE
        LD      C,B
        LD      A,E
        ADD     A,C
        LD      E,A
        JR      NC,.n1
        INC     D
.n1:
        XOR     A
        LD      (DE),A
.loop:
        DEC     DE
        CALL    DIV10_24
        ADD     A,'0'
        LD      (DE),A
        DEC     C
        JR      Z,.done
        LD      A,(TMPW0)
        OR      A
        JR      NZ,.loop
        LD      A,(TMPW0+1)
        OR      A
        JR      NZ,.loop
        LD      A,(TMPW1)
        OR      A
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
; DIV10_24 - TMPW0..TMPW1 (24bit) を 10 で割る。余りを A に返す
; ---------------------------------------------------------------------
DIV10_24:
        PUSH    BC                      ; 呼び出し側は C を桁数に使っている
        LD      B,24
        LD      C,0
.lp:
        LD      HL,TMPW0
        SLA     (HL)
        INC     HL
        RL      (HL)
        INC     HL
        RL      (HL)
        LD      A,C
        ADC     A,A
        LD      C,A
        SUB     10
        JR      C,.skip
        LD      C,A
        LD      HL,TMPW0
        INC     (HL)
.skip:
        DJNZ    .lp
        LD      A,C
        POP     BC
        RET
