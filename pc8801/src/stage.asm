; =====================================================================
; stage.asm - ステージの生成と 1 フレーム分の更新
; =====================================================================

; ---------------------------------------------------------------------
; STAGEINIT - 1 ステージ分の状態を作る
;   入力: STAGE, BONUSMODE, SHIBACOLOR, DEMOMODE
; ---------------------------------------------------------------------
STAGEINIT:
        ; 配列の初期化
        LD      HL,ARR_TERR
        LD      BC,NCELL
        LD      A,0xFF
        CALL    MEMFILL
        LD      HL,ARR_POLEAT
        LD      BC,NCELL
        LD      A,0xFF
        CALL    MEMFILL
        CALL    DIRTYRESET
        LD      HL,LANEOF
        LD      BC,FH
        XOR     A
        CALL    MEMFILL
        LD      HL,CARS
        LD      BC,NCAR*CR_SIZE
        XOR     A
        CALL    MEMFILL
        CALL    CARSINIT
        CALL    FLOODRESET
        LD      HL,ITEMS
        LD      BC,NITEM*IT_SIZE
        XOR     A
        CALL    MEMFILL
        LD      HL,DOGS
        LD      BC,NDOG*D_SIZE
        XOR     A
        CALL    MEMFILL

        LD      HL,0
        LD      (CLAIMED),HL
        LD      (RAINWARN),HL
        LD      (RAINT),HL
        XOR     A
        LD      (FINISHED),A
        LD      (CLEARED),A
        LD      (PERFECT),A
        LD      (BONUSCAUGHT),A
        LD      (PAUSED),A
        LD      (GIVEUP),A
        LD      (SPRCOUNT),A
        LD      (CURDOG),A
        LD      (MSGTIMER),A

        ; 制限時間 (秒 + フレーム)
        LD      A,STAGETIME
        LD      HL,BONUSMODE
        LD      B,(HL)
        INC     B
        DEC     B
        JR      Z,.t1
        LD      A,BONUSTIME
.t1:
        LD      (SECLEFT),A
        LD      A,TICKHZ
        LD      (SECTICK),A

        ; 雨の予告までの時間
        LD      HL,0x7FFF
        LD      (RAINNEXT),HL
        LD      A,(BONUSMODE)
        OR      A
        JR      NZ,.norain
        LD      A,(STAGE)
        CP      RAINFROMSTAGE
        JR      C,.norain
        CALL    RANDB
        LD      L,A
        LD      H,0
        ADD     HL,HL                   ; 0..510
        LD      DE,22*TICKHZ
        ADD     HL,DE
        LD      (RAINNEXT),HL
.norain:
        ; アイテムの出る間隔
        LD      HL,6*TICKHZ
        LD      (ITEMSPAWN),HL

        CALL    GENROADS
        CALL    GENPOLES
        CALL    GENDOGS
        RET

; ---------------------------------------------------------------------
; MEMFILL - HL から BC バイトを A で埋める
; ---------------------------------------------------------------------
MEMFILL:
        LD      (HL),A
        LD      D,H
        LD      E,L
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        RET     Z
        LDIR
        RET

; ---------------------------------------------------------------------
; GENROADS - 道路を作る
; ---------------------------------------------------------------------
GENROADS:
        LD      A,(BONUSMODE)
        OR      A
        RET     NZ                      ; ボーナス面は道路なし
        LD      B,1
        LD      A,(STAGE)
        CP      4
        JR      C,.one
        LD      B,2
.one:
        LD      A,B
        LD      (TMPB3),A               ; 作る本数
        XOR     A
        LD      (TMPB2),A               ; 作った本数
        LD      B,100
.tries:
        PUSH    BC
        LD      A,(TMPB2)
        LD      HL,TMPB3
        CP      (HL)
        JR      NC,.done
        LD      A,FH-10
        CALL    RANDMOD
        ADD     A,4                     ; 4 .. FH-7
        LD      C,A
        ; ほかの車線から 6 マス以上離れているか
        LD      HL,LANEOF
        LD      B,FH
        LD      D,0
.chk:
        LD      A,(HL)
        OR      A
        JR      Z,.chknext
        LD      A,D
        SUB     C
        JP      P,.abs
        NEG
.abs:
        CP      6
        JR      C,.bad
.chknext:
        INC     HL
        INC     D
        DJNZ    .chk
        ; 置く
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      (HL),1
        INC     HL
        LD      (HL),2
        ; 速さと次の車までの時間
        LD      B,2
        LD      HL,LANESPEED
        LD      D,0
        LD      E,C
        ADD     HL,DE
.spd:
        PUSH    BC
        PUSH    HL
        LD      A,60
        CALL    RANDMOD
        LD      B,A
        LD      A,(STAGE)
        ADD     A,A
        ADD     A,A
        ADD     A,A                     ; stage*8 (元は stage*5 相当)
        ADD     A,B
        ADD     A,95
        JR      NC,.nocap
        LD      A,210
.nocap:
        CP      210
        JR      C,.ok2
        LD      A,210
.ok2:
        SRL     A                       ; 1/16 ドット毎ティックの速さ
        POP     HL
        LD      (HL),A
        INC     HL
        POP     BC
        DJNZ    .spd
        ; 次の車まで
        LD      HL,LANESPAWN
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      B,2
.spw:
        PUSH    BC
        LD      A,60
        CALL    RANDMOD
        ADD     A,30
        LD      (HL),A
        INC     HL
        POP     BC
        DJNZ    .spw
        LD      A,(TMPB2)
        INC     A
        LD      (TMPB2),A
.bad:
        POP     BC
        DJNZ    .tries
        RET
.done:
        POP     BC
        RET

; ---------------------------------------------------------------------
; GENPOLES - 電柱を 5x6 のブロックごとに 1 本ずつ置く
; ---------------------------------------------------------------------
GENPOLES:
        XOR     A
        LD      (NPOLES),A
        LD      (GP_BY),A
.byl:
        XOR     A
        LD      (GP_BX),A
.bxl:
        LD      B,60
.tries:
        PUSH    BC
        LD      A,(GP_BX)
        LD      B,A
        LD      A,(GP_BY)
        LD      C,A
        CALL    GENPOLE1
        POP     BC
        OR      A
        JR      NZ,.placed
        DJNZ    .tries
.placed:
        LD      A,(GP_BX)
        INC     A
        LD      (GP_BX),A
        CP      6
        JR      C,.bxl
        LD      A,(GP_BY)
        INC     A
        LD      (GP_BY),A
        CP      5
        JR      C,.byl
        RET

; GENPOLE1 - ブロック (B=bx, C=by) に 1 本試す / 出力: A != 0 なら置けた
GENPOLE1:
        LD      A,B
        LD      (TMPB0),A
        LD      A,C
        LD      (TMPB1),A
        ; x = bx*5 + rand(5)
        LD      A,5
        CALL    RANDMOD
        LD      E,A
        LD      A,(TMPB0)
        LD      B,A
        ADD     A,A
        ADD     A,A
        ADD     A,B                     ; bx*5
        ADD     A,E
        LD      B,A
        ; 外周のブロックは端に寄せる
        LD      A,(TMPB0)
        OR      A
        JR      NZ,.nx0
        LD      A,2
        CALL    RANDMOD
        LD      B,A
.nx0:
        LD      A,(TMPB0)
        CP      5
        JR      NZ,.nx5
        LD      A,2
        CALL    RANDMOD
        LD      B,A
        LD      A,FW-1
        SUB     B
        LD      B,A
.nx5:
        ; y = by*5 + rand(5)
        LD      A,5
        CALL    RANDMOD
        LD      E,A
        LD      A,(TMPB1)
        LD      C,A
        ADD     A,A
        ADD     A,A
        ADD     A,C                     ; by*5
        ADD     A,E
        LD      C,A
        LD      A,(TMPB1)
        OR      A
        JR      NZ,.ny0
        LD      A,2
        CALL    RANDMOD
        LD      C,A
.ny0:
        LD      A,(TMPB1)
        CP      4
        JR      NZ,.ny4
        LD      A,2
        CALL    RANDMOD
        LD      C,A
        LD      A,FH-1
        SUB     C
        LD      C,A
.ny4:
        ; 範囲の外はだめ
        LD      A,B
        CP      FW
        JP      NC,.no
        LD      A,C
        CP      FH
        JP      NC,.no
        ; 道路の上はだめ
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      NZ,.no
        ; ほかの電柱と隣り合ってはだめ
        LD      A,(NPOLES)
        OR      A
        JR      Z,.place
        LD      (TMPB2),A
        LD      IX,POLES
.near:
        LD      A,(IX+PL_X)
        SUB     B
        JP      P,.a1
        NEG
.a1:
        CP      2
        JR      NC,.farx
        LD      A,(IX+PL_Y)
        SUB     C
        JP      P,.a2
        NEG
.a2:
        CP      2
        JP      C,.no
.farx:
        PUSH    BC
        LD      BC,PL_SIZE
        ADD     IX,BC
        POP     BC
        LD      A,(TMPB2)
        DEC     A
        LD      (TMPB2),A
        JR      NZ,.near
.place:
        LD      A,(NPOLES)
        PUSH    BC
        CALL    POLEPTR
        POP     BC
        LD      (HL),B                  ; PL_X
        INC     HL
        LD      (HL),C                  ; PL_Y
        INC     HL
        LD      (HL),0xFF               ; PL_OWNER
        INC     HL
        LD      (HL),0                  ; PL_LOCKED
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(NPOLES)
        LD      (HL),A
        INC     A
        LD      (NPOLES),A
        LD      A,1
        RET
.no:
        XOR     A
        RET

; ---------------------------------------------------------------------
; GENDOGS - 柴犬と敵の犬を置く
; ---------------------------------------------------------------------
GENDOGS:
        ; --- 柴犬 ---
        XOR     A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(SHIBACOLOR)
        LD      (IY+D_BREED),A
        LD      A,DF_ALIVE | DF_PLAYER
        LD      (IY+D_FLAGS),A
        LD      (IY+D_TERRID),0
        LD      (IY+D_STEPTIME),4
        LD      (IY+D_PEEPOLE),0xFF
        LD      (IY+D_TARGET),0xFF
        LD      (IY+D_DIR),0
        LD      A,1                     ; 真ん中あたり
        CALL    FINDCELL
        LD      A,(FOUNDX)
        LD      (IY+D_X),A
        LD      (IY+D_FROMX),A
        LD      A,(FOUNDY)
        LD      (IY+D_Y),A
        LD      (IY+D_FROMY),A

        ; --- 敵の数 ---
        LD      A,(STAGE)
        OR      A
        JR      NZ,.ns
        LD      A,1
.ns:
        CP      9
        JR      C,.ne
        LD      A,8
.ne:
        LD      (NENEMY),A
        INC     A
        LD      (NDOGS),A
        ; ボスの出るステージか
        XOR     A
        LD      (HASBOSS),A
        LD      A,(BONUSMODE)
        OR      A
        JR      NZ,.noboss
        LD      A,(STAGE)
        CP      BOSSEVERY
        JR      C,.noboss
        LD      C,BOSSEVERY
        CALL    MOD8A
        OR      A
        JR      NZ,.noboss
        LD      A,1
        LD      (HASBOSS),A
.noboss:
        LD      A,(NENEMY)
        OR      A
        RET     Z
        LD      B,A
        LD      C,1                     ; 犬 ID
.dogl:
        PUSH    BC
        LD      A,C
        CALL    GENONEDOG
        POP     BC
        INC     C
        DJNZ    .dogl
        RET

; MOD8A - A mod C -> A
MOD8A:
        CP      C
        RET     C
        SUB     C
        JR      MOD8A

; GENONEDOG - 犬 ID A の敵を作る
GENONEDOG:
        LD      (TMPB2),A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        ; 犬種を決める
        LD      A,(TMPB2)
        LD      B,A                     ; B = id (1..8)
        LD      A,DF_ALIVE
        LD      (IY+D_FLAGS),A
        ; ボスは最後の 1 匹
        LD      A,(HASBOSS)
        OR      A
        JR      Z,.normal
        LD      A,(NENEMY)
        CP      B
        JR      NZ,.normal
        LD      A,BOSSBREED
        LD      (IY+D_BREED),A
        LD      A,(IY+D_FLAGS)
        OR      DF_BOSS
        LD      (IY+D_FLAGS),A
        JR      .breeddone
.normal:
        LD      A,B
        DEC     A
        LD      C,ENEMYBREEDS
        CALL    MOD8A
        ADD     A,SHIBACOUNT
        LD      (IY+D_BREED),A
.breeddone:
        LD      A,(TMPB2)
        LD      (IY+D_TERRID),A
        LD      (IY+D_PEEPOLE),0xFF
        LD      (IY+D_TARGET),0xFF
        LD      (IY+D_DIR),0
        ; 1 歩の時間 = 基本 * 性格の倍率 / 16
        LD      A,(STAGE)
        DEC     A
        SRL     A
        LD      B,A
        LD      A,9
        SUB     B
        CP      5
        JR      NC,.base
        LD      A,5
.base:
        LD      B,A                     ; B = 基本フレーム
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      A,(HL)                  ; T_SPEED
        LD      C,A
        CALL    MULS88                  ; HL = base * speed
        ; /16
        LD      B,4
.sh:
        SRL     H
        RR      L
        DJNZ    .sh
        LD      A,L
        CP      4
        JR      NC,.spdok
        LD      A,4
.spdok:
        LD      (IY+D_STEPTIME),A
        ; ボーナス面では一定
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.nb
        LD      (IY+D_STEPTIME),6
        LD      A,(IY+D_FLAGS)
        OR      DF_ASLEEP
        LD      (IY+D_FLAGS),A
.nb:
        ; スタミナ
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,T_STAMINA
        ADD     HL,DE
        LD      A,(HL)
        LD      (IY+D_STEPS),A
        ; 考えるまでの時間
        LD      A,30
        CALL    RANDMOD
        ADD     A,15
        LD      (IY+D_THINK),A
        ; 置き場所
        LD      A,2
        CALL    FINDCELL
        LD      A,(FOUNDX)
        LD      (IY+D_X),A
        LD      (IY+D_FROMX),A
        LD      A,(FOUNDY)
        LD      (IY+D_Y),A
        LD      (IY+D_FROMY),A
        RET

; ---------------------------------------------------------------------
; FINDCELL - 条件に合う空きマスを探す
;   入力: A = モード
;         0 = 空いているだけ
;         1 = 画面の真ん中あたり (±4)
;         2 = ほかの犬から離れている
;         3 = 復活用 (隣に空きがある)
;         4 = アイテム用 (犬から 3 マス以上、アイテムが重ならない)
;   出力: FOUNDX, FOUNDY
; ---------------------------------------------------------------------
FINDCELL:
        ; 中で FINDCHECK などが IX/IY を使うので、呼び出し側のために残す
        PUSH    IX
        PUSH    IY
        CALL    FINDCELL0
        POP     IY
        POP     IX
        RET

FINDCELL0:
        LD      (FINDMODE),A
        LD      HL,600
.lp:
        PUSH    HL                      ; 残り試行回数
        LD      A,FW
        CALL    RANDMOD
        LD      B,A
        LD      A,FH
        CALL    RANDMOD
        LD      C,A
        PUSH    BC
        CALL    CELLFREE
        POP     BC
        OR      A
        JR      Z,.next
        ; 試行回数が残り少なくなったら追加条件は見ない
        POP     HL
        PUSH    HL
        LD      A,H
        OR      A
        JR      Z,.accept
        CALL    FINDCHECK
        OR      A
        JR      NZ,.accept
.next:
        POP     HL
        DEC     HL
        LD      A,H
        OR      L
        JR      NZ,.lp
        JR      .scan
.accept:
        POP     HL
        LD      A,B
        LD      (FOUNDX),A
        LD      A,C
        LD      (FOUNDY),A
        RET
.scan:
        ; 見つからなければ順番に探す
        LD      C,0
.sy:
        LD      B,0
.sx:
        PUSH    BC
        CALL    CELLFREE
        POP     BC
        OR      A
        JR      NZ,.take
        INC     B
        LD      A,B
        CP      FW
        JR      C,.sx
        INC     C
        LD      A,C
        CP      FH
        JR      C,.sy
        LD      B,0
        LD      C,0
.take:
        LD      A,B
        LD      (FOUNDX),A
        LD      A,C
        LD      (FOUNDY),A
        RET

; FINDCHECK - モードごとの追加条件 / 出力: A != 0 なら合格
FINDCHECK:
        LD      A,(FINDMODE)
        OR      A
        JR      NZ,.m1
        LD      A,1
        RET
.m1:
        DEC     A
        JR      NZ,.m2
        ; 真ん中あたり
        LD      A,B
        SUB     FW/2
        JP      P,.p1
        NEG
.p1:
        JP      NC,.no
        LD      A,C
        SUB     FH/2
        JP      P,.p2
        NEG
.p2:
        JP      NC,.no
        LD      A,1
        RET
.m2:
        DEC     A
        JR      NZ,.m3
        ; ほかの犬から離れている
        LD      A,(NDOGS)
        OR      A
        JR      Z,.yes
        LD      D,A
        LD      IX,DOGS
        LD      E,0                     ; 犬 ID
.dlp:
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.dnext
        PUSH    DE
        PUSH    BC
        LD      D,(IX+D_X)
        LD      E,(IX+D_Y)
        CALL    MANHATTAN
        POP     BC
        POP     DE
        LD      H,4
        LD      A,(IX+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.lim
        LD      H,9
.lim:
        CP      H
        JP      C,.no
.dnext:
        PUSH    DE
        LD      DE,D_SIZE
        ADD     IX,DE
        POP     DE
        INC     E
        DEC     D
        JR      NZ,.dlp
        JP      .yes
.m3:
        DEC     A
        JR      NZ,.m4
        ; 復活用: 隣に空きがあるか
        LD      D,0
.nlp:
        PUSH    DE
        PUSH    BC
        LD      A,D
        LD      E,A
        LD      D,0
        LD      HL,DIRDX
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,B
        LD      B,A
        LD      HL,DIRDY
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,C
        LD      C,A
        CALL    CELLFREE
        POP     BC
        POP     DE
        OR      A
        JP      NZ,.yes
        INC     D
        LD      A,D
        CP      4
        JR      C,.nlp
        JP      .no
.m4:
        ; アイテム用
        LD      A,(NDOGS)
        LD      D,A
        LD      IX,DOGS
.ilp:
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.inext
        PUSH    DE
        PUSH    BC
        LD      D,(IX+D_X)
        LD      E,(IX+D_Y)
        CALL    MANHATTAN
        POP     BC
        POP     DE
        CP      3
        JP      C,.no
.inext:
        PUSH    DE
        LD      DE,D_SIZE
        ADD     IX,DE
        POP     DE
        DEC     D
        JR      NZ,.ilp
        ; アイテムが重ならないか
        LD      IX,ITEMS
        LD      D,NITEM
.jlp:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.jnext
        LD      A,(IX+IT_X)
        CP      B
        JR      NZ,.jnext
        LD      A,(IX+IT_Y)
        CP      C
        JP      Z,.no
.jnext:
        PUSH    DE
        LD      DE,IT_SIZE
        ADD     IX,DE
        POP     DE
        DEC     D
        JR      NZ,.jlp
.yes:
        LD      A,1
        RET
.no:
        XOR     A
        RET

; ---------------------------------------------------------------------
; TICKTIME - 残り時間を 1 フレーム分進める
;   出力: A != 0 なら時間切れ
; ---------------------------------------------------------------------
TICKTIME:
        LD      A,(SECTICK)
        DEC     A
        LD      (SECTICK),A
        OR      A
        JR      Z,.sec
        XOR     A
        RET
.sec:
        LD      A,TICKHZ
        LD      (SECTICK),A
        LD      A,1
        LD      (NEEDHUD),A
        LD      A,(SECLEFT)
        OR      A
        JR      Z,.over
        DEC     A
        LD      (SECLEFT),A
        OR      A
        JR      Z,.over
        XOR     A
        RET
.over:
        LD      A,1
        RET
