; =====================================================================
; path.asm - 敵の犬の道さがし
; =====================================================================
; 元の版は毎歩、電柱までの幅優先探索をしている。4MHz の Z80 では 1 回で
; 数ティックかかるので、次のようにしてある。
;   ・探索は 1 度に 1 匹ぶんだけ。犬は DF_WANTPATH を立てて順番を待つ。
;   ・探索はメインループの最後、帰線を待っているはずの時間に少しずつ進める
;     (FLOODSTEP)。だから探索のせいでゲームが遅くなることはない。
;   ・犬の位置から全部のマスへの歩数を求める (元の版の Flood と同じ)。
;     どの電柱に何歩で行けるかがわかるので、行けない電柱は狙わない。
;   ・選んだ電柱から歩数をたどって道順を作り、ROUTES に覚えて歩く。
;     道がふさがったら (なわばりができたなど) 探しなおす。
;
; DIST の中身 (CSTRIDE = 32 の並び。上下に 1 行ずつ番兵の壁):
;   FL_DBASE + d  犬から d 歩 (16..253)
;   0xFF          まだ届いていない
;   0xFE          壁 (電柱 / 右端の 2 列 / 番兵)
;   0..8          ほかの犬のなわばり (壁として扱う)
; =====================================================================

; ---------------------------------------------------------------------
; FLOODRESET - ステージの最初に呼ぶ
; ---------------------------------------------------------------------
FLOODRESET:
        XOR     A
        LD      (FL_STATE),A
        LD      (FL_NEXT),A
        LD      (VBFRESH),A
        LD      HL,DISTB
        LD      BC,CSTRIDE
        LD      A,FL_WALL
        CALL    MEMFILL
        LD      HL,DIST0+NCELL
        LD      BC,CSTRIDE
        LD      A,FL_WALL
        JP      MEMFILL

; ---------------------------------------------------------------------
; FLOODSTEP - 道さがしを少し進める (メインループの最後、WAITVSYNC の前)
;   WAITVSYNC が待つはずの帰線が来るまで続ける。帰線をここで見つけたら
;   VBFRESH を立てて、WAITVSYNC がもう 1 回待たないようにする。
; ---------------------------------------------------------------------
FLOODSTEP:
        LD      A,(FL_STATE)
        OR      A
        JR      NZ,.busy
        CALL    FLPICK
        RET     NC                      ; 頼んでいる犬がいない
        LD      A,(FL_STATE)
.busy:
        CP      3
        JP      Z,FLDONECHK
        ; WAITVSYNC が待つはずの帰線 (= max(2, いまの数 + 1)) が来るまで使う。
        ; 重くて 2 フレームを超えたティックは、もともと次の帰線まで丸ごと待つので
        ; そのぶんがまるまる道さがしに使える。
        LD      A,(VBCOUNT)
        INC     A
        CP      VSYNCPERTICK
        JR      NC,.tgt
        LD      A,VSYNCPERTICK
.tgt:
        LD      (FL_EARLY),A            ; この数の帰線が来たら終わり
.lp:
        CALL    VBPOLL
        LD      A,(FL_EARLY)
        LD      B,A
        LD      A,(VBCOUNT)
        CP      B
        JR      C,.work
        LD      A,1
        LD      (VBFRESH),A             ; 帰線の始まりをここで見つけた
        RET
.work:
        LD      A,(FL_STATE)
        CP      1
        JR      NZ,.bfs
        CALL    FLINITCHUNK
        JR      .lp
.bfs:
        CALL    FLBFS8
        LD      A,(FL_STATE)
        CP      3
        JR      NZ,.lp
        RET

; ---------------------------------------------------------------------
; FLDONECHK - 結果を持ち主が取りに来るのを待つ。来なければ捨てる
; ---------------------------------------------------------------------
FLDONECHK:
        LD      A,(FL_AGE)
        INC     A
        LD      (FL_AGE),A
        CP      45                      ; 1.5 秒
        JR      NC,.drop
        LD      A,(FL_DOG)
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE | DF_WANTPATH
        CP      DF_ALIVE | DF_WANTPATH
        RET     Z
.drop:
        XOR     A
        LD      (FL_STATE),A
        RET

; ---------------------------------------------------------------------
; FLPICK - 道さがしを頼んでいる犬を順番に探し、見つかれば始める
;   出力: CY = 始めた
; ---------------------------------------------------------------------
FLPICK:
        LD      A,(NDOGS)
        OR      A
        RET     Z
        LD      B,A
        LD      A,(FL_NEXT)
        LD      C,A
.lp:
        LD      A,C
        LD      HL,NDOGS
        CP      (HL)
        JR      C,.ok
        XOR     A
.ok:
        LD      C,A
        INC     C                       ; 次に見る番号
        PUSH    BC
        LD      (FL_DOG),A
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        POP     BC
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE | DF_WANTPATH
        CP      DF_ALIVE | DF_WANTPATH
        JR      Z,.start
        DJNZ    .lp
        OR      A                       ; CY = 0
        RET
.start:
        LD      A,C
        LD      (FL_NEXT),A
        LD      A,(IX+D_X)
        LD      (FL_OX),A
        LD      A,(IX+D_Y)
        LD      (FL_OY),A
        LD      A,(IX+D_TERRID)
        LD      (FL_ID),A
        ; ボスと巻物の効果中の犬は、なわばりを気にしない
        LD      B,0
        LD      A,(IX+D_FLAGS)
        AND     DF_BOSS
        JR      NZ,.all
        LD      A,(IX+D_PASST)
        OR      (IX+D_PASST+1)
        JR      Z,.notall
.all:
        INC     B
.notall:
        LD      A,B
        LD      (FL_ALL),A
        XOR     A
        LD      (FL_CHUNK),A
        LD      A,1
        LD      (FL_STATE),A
        SCF
        RET

; ---------------------------------------------------------------------
; FLINITCHUNK - なわばりの地図を 5 行 (160 バイト) ぶん DIST に写す
;   ほかの犬のなわばりは犬の番号 (0..8) のまま残るので壁になる。
;   自分のなわばりは 0xFF (通れる) に直す。5 かたまりで終わり。
; ---------------------------------------------------------------------
FLINITCHUNK:
        LD      A,(FL_CHUNK)
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL                   ; *4
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL                   ; *16
        ADD     HL,DE                   ; *20
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; *160
        PUSH    HL
        LD      DE,DIST0
        ADD     HL,DE
        EX      DE,HL                   ; DE = DIST0 + off
        POP     HL
        PUSH    DE
        LD      BC,ARR_TERR
        ADD     HL,BC                   ; HL = ARR_TERR + off
        LD      BC,5*CSTRIDE
        LD      A,(FL_ALL)
        OR      A
        JR      NZ,.fill
        LDIR
        POP     HL
        PUSH    HL
        LD      BC,5*CSTRIDE
        LD      A,(FL_ID)
.own:
        CPIR
        JR      NZ,.done                ; もうない
        DEC     HL
        LD      (HL),0xFF
        INC     HL
        LD      E,A
        LD      A,B
        OR      C
        LD      A,E
        JR      NZ,.own
        JR      .done
.fill:
        EX      DE,HL                   ; HL = DIST0 + off
        LD      (HL),0xFF
        LD      D,H
        LD      E,L
        INC     DE
        LD      BC,5*CSTRIDE-1
        LDIR
.done:
        POP     HL                      ; DIST0 + off
        ; 右の 2 列 (x = 30, 31) は壁
        LD      DE,FW
        ADD     HL,DE
        LD      DE,CSTRIDE-1
        LD      B,5
.pad:
        LD      (HL),FL_WALL
        INC     HL
        LD      (HL),FL_WALL
        ADD     HL,DE
        DJNZ    .pad
        LD      A,(FL_CHUNK)
        INC     A
        LD      (FL_CHUNK),A
        CP      FH/5
        RET     C
        ; ---- 地図ができた: 電柱を壁にして、犬のいるマスから始める ----
        LD      A,(NPOLES)
        OR      A
        JR      Z,.np
        LD      B,A
        LD      HL,POLES
.pl:
        PUSH    BC
        PUSH    HL
        LD      B,(HL)
        INC     HL
        LD      C,(HL)
        CALL    DISTPTR
        LD      (HL),FL_WALL
        POP     HL
        LD      DE,PL_SIZE
        ADD     HL,DE
        POP     BC
        DJNZ    .pl
.np:
        LD      A,(FL_OX)
        LD      B,A
        LD      A,(FL_OY)
        LD      C,A
        CALL    DISTPTR
        LD      (HL),FL_DBASE
        LD      A,L
        LD      (QLOP*256),A
        LD      A,H
        LD      (QHIP*256),A
        XOR     A
        LD      (FL_HEAD),A
        INC     A
        LD      (FL_TAIL),A
        LD      A,2
        LD      (FL_STATE),A
        RET

; ---------------------------------------------------------------------
; FLBFS8 - 待ち行列から 8 マス取り出して、まわりのマスに歩数を入れる
;   待ち行列は 256 個の輪。下位バイトと上位バイトを別のページに置く。
; ---------------------------------------------------------------------
FLBFS8:
        LD      A,(FL_TAIL)
        LD      B,A                     ; B = 末尾 (この中ではレジスタに置く)
        LD      A,8
        LD      (FL_CNT),A
.cell:
        LD      A,(FL_HEAD)
        CP      B
        JR      Z,.empty
        LD      L,A
        INC     A
        LD      (FL_HEAD),A
        LD      H,QLOP
        LD      E,(HL)
        INC     H
        LD      D,(HL)
        EX      DE,HL                   ; HL = マス
        LD      A,(HL)
        INC     A
        CP      FL_WALL
        JR      C,.dok
        LD      A,FL_WALL-1             ; これ以上は数えない
.dok:
        LD      C,A                     ; C = となりの歩数
        LD      DE,-CSTRIDE
        ADD     HL,DE                   ; 上
        LD      A,(HL)
        INC     A
        JR      NZ,.n1
        LD      (HL),C
        LD      E,B
        LD      D,QLOP
        LD      A,L
        LD      (DE),A
        INC     D
        LD      A,H
        LD      (DE),A
        INC     B
.n1:
        LD      DE,CSTRIDE-1
        ADD     HL,DE                   ; 左
        LD      A,(HL)
        INC     A
        JR      NZ,.n2
        LD      (HL),C
        LD      E,B
        LD      D,QLOP
        LD      A,L
        LD      (DE),A
        INC     D
        LD      A,H
        LD      (DE),A
        INC     B
.n2:
        INC     HL
        INC     HL                      ; 右
        LD      A,(HL)
        INC     A
        JR      NZ,.n3
        LD      (HL),C
        LD      E,B
        LD      D,QLOP
        LD      A,L
        LD      (DE),A
        INC     D
        LD      A,H
        LD      (DE),A
        INC     B
.n3:
        LD      DE,CSTRIDE-1
        ADD     HL,DE                   ; 下
        LD      A,(HL)
        INC     A
        JR      NZ,.n4
        LD      (HL),C
        LD      E,B
        LD      D,QLOP
        LD      A,L
        LD      (DE),A
        INC     D
        LD      A,H
        LD      (DE),A
        INC     B
.n4:
        LD      HL,FL_CNT
        DEC     (HL)
        JR      NZ,.cell
        LD      A,B
        LD      (FL_TAIL),A
        RET
.empty:
        LD      A,B
        LD      (FL_TAIL),A
        LD      A,3
        LD      (FL_STATE),A            ; できあがり
        XOR     A
        LD      (FL_AGE),A
        RET

; 待ち行列は 256 個の輪。幅優先探索の「これから広げるマス」は、30x25 の
; 盤では多くても 120 個ほどなのであふれない。

; ---------------------------------------------------------------------
; DISTPTR - HL = DIST0 + y*32 + x   (B = x, C = y)。DE, A を壊す
; ---------------------------------------------------------------------
DISTPTR:
        LD      L,C
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,L
        ADD     A,B
        LD      L,A
        LD      DE,DIST0
        ADD     HL,DE
        RET

; ---------------------------------------------------------------------
; POLETRAVEL - 電柱 A の隣のマスまでの歩数 (探索の結果から)
;   出力: A = 歩数 (0xFF = 行けない), HL = いちばん近い隣のマス
;   IX, IY は壊さない
; ---------------------------------------------------------------------
POLETRAVEL:
        CALL    POLEPTR
        LD      B,(HL)
        INC     HL
        LD      C,(HL)
        CALL    DISTPTR
        LD      A,0xFF
        LD      (PT_MIN),A
        LD      DE,-CSTRIDE
        ADD     HL,DE
        CALL    .try                    ; 上
        LD      DE,CSTRIDE-1
        ADD     HL,DE
        CALL    .try                    ; 左
        INC     HL
        INC     HL
        CALL    .try                    ; 右
        LD      DE,CSTRIDE-1
        ADD     HL,DE
        CALL    .try                    ; 下
        LD      A,(PT_MIN)
        CP      0xFF
        RET     Z
        SUB     FL_DBASE
        LD      HL,(PT_ADDR)
        RET
.try:
        LD      A,(HL)
        CP      FL_DBASE
        RET     C                       ; なわばり
        CP      FL_WALL
        RET     NC                      ; 壁 / 届いていない
        PUSH    HL
        LD      HL,PT_MIN
        CP      (HL)
        POP     HL
        RET     NC
        LD      (PT_MIN),A
        LD      (PT_ADDR),HL
        RET

; ---------------------------------------------------------------------
; ROUTEPTR - IX = この犬の道順 (ROUTES + id*48)
;   +0 長さ / +1 いま何歩目 / +2.. 向き (RT_MAX 歩まで)
; ---------------------------------------------------------------------
ROUTEPTR:
        LD      A,(IY+D_TERRID)
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; *16
        LD      D,H
        LD      E,L
        ADD     HL,HL                   ; *32
        ADD     HL,DE                   ; *48
        LD      DE,ROUTES
        ADD     HL,DE
        PUSH    HL
        POP     IX
        RET

; ---------------------------------------------------------------------
; BUILDROUTE - 目的のマスから歩数を 1 ずつ減らしてたどり、道順を作る
;   入力: IY = 犬, HL = 目的のマス (POLETRAVEL の出力), A = 歩数
; ---------------------------------------------------------------------
BUILDROUTE:
        LD      (RT_GOAL),HL
        LD      (RT_D),A
        CALL    ROUTEPTR
        LD      A,(RT_D)
        CP      RT_MAX+1
        JR      C,.len
        LD      A,RT_MAX                ; 遠いときは途中まで覚えて、着いたら探しなおす
.len:
        LD      (IX+0),A
        LD      (IX+1),0
        ; たどる向きを毎回少し変えて、いつも同じ曲がり方にならないようにする
        CALL    RANDB
        AND     1
        LD      (RT_FLIP),A
        LD      HL,(RT_GOAL)
        LD      A,(RT_D)
        LD      C,A                     ; C = いまのマスの歩数
.back:
        LD      A,C
        OR      A
        RET     Z
        LD      A,(HL)
        DEC     A
        LD      B,A                     ; ひとつ手前のマスの値
        LD      A,(RT_FLIP)
        OR      A
        JR      NZ,.vfirst
        ; 横を先に見る
        DEC     HL
        LD      A,(HL)
        CP      B
        LD      A,2                     ; 左から来た = 右へ歩いた
        JR      Z,.got
        INC     HL
        INC     HL
        LD      A,(HL)
        CP      B
        LD      A,1                     ; 右から来た = 左へ
        JR      Z,.got
        LD      DE,-CSTRIDE-1
        ADD     HL,DE
        LD      A,(HL)
        CP      B
        LD      A,0                     ; 上から来た = 下へ
        JR      Z,.got
        LD      DE,2*CSTRIDE
        ADD     HL,DE
        LD      A,(HL)
        CP      B
        LD      A,3                     ; 下から来た = 上へ
        JR      Z,.got
        JR      .lost
.vfirst:
        ; 縦を先に見る
        LD      DE,-CSTRIDE
        ADD     HL,DE
        LD      A,(HL)
        CP      B
        LD      A,0
        JR      Z,.got
        LD      DE,2*CSTRIDE
        ADD     HL,DE
        LD      A,(HL)
        CP      B
        LD      A,3
        JR      Z,.got
        LD      DE,-CSTRIDE-1
        ADD     HL,DE
        LD      A,(HL)
        CP      B
        LD      A,2
        JR      Z,.got
        INC     HL
        INC     HL
        LD      A,(HL)
        CP      B
        LD      A,1
        JR      Z,.got
.lost:
        LD      (IX+0),0                ; たどれない (起きないはず)
        RET
.got:
        ; HL = ひとつ手前のマス、A = そこからの向き。これが C-1 歩目
        DEC     C
        LD      E,A
        LD      A,C
        CP      RT_MAX
        JR      NC,.back
        PUSH    HL
        PUSH    IX
        POP     HL
        ADD     A,2
        ADD     A,L
        LD      L,A
        JR      NC,.nc
        INC     H
.nc:
        LD      (HL),E
        POP     HL
        JR      .back
