; =====================================================================
; ai.asm - 敵の犬の動き
; =====================================================================
; 4MHz の Z80 で 1 ティック (1/30 秒) に収めるため、元の版から次のように
; 作り変えてある。見た目の動きはほぼ同じになる。
;   ・幅優先探索は path.asm で、帰線を待つあいだに少しずつ進める。
;     目標を選ぶときに 1 回だけ探して道順を覚え、ふさがったら探しなおす。
;   ・3 本目の電柱は、外接箱の大きさで面積を見積もって候補を選び、
;     いちばん良いものだけ本物の三角形判定で確かめる。
;   ・評価式の掛け算はほとんど 8bit の足し引きに置き換えた。
; =====================================================================

; ---------------------------------------------------------------------
; AICTL - 敵 1 匹の思考
;   入力: IY = 犬, CURDOG = 犬 ID
; ---------------------------------------------------------------------
AICTL:
        CALL    AITAKE                  ; 道さがしの結果が届いていれば受け取る
        JR      C,.taken
        LD      A,(IY+D_THINK)
        OR      A
        JR      Z,.maythink
        DEC     A
        LD      (IY+D_THINK),A
        ; もうすぐ考える番で目標がないなら、いまのうちに道さがしを頼んでおく
        CP      6
        RET     NC
        LD      A,(IY+D_TARGET)
        CP      0xFF
        RET     NZ
        SET     7,(IY+D_FLAGS)          ; DF_WANTPATH
        RET
.taken:
        LD      A,(IY+D_THINK)
        OR      A
        RET     NZ                      ; まだ考える番ではない (道順は覚えておく)
        JR      .havetarget
.maythink:
        BIT     7,(IY+D_FLAGS)
        RET     NZ                      ; 道さがしの順番待ち (その場で待つ)
        LD      A,(IY+D_TARGET)
        CP      0xFF
        JR      Z,.ask
        CALL    CHAINHAS
        OR      A
        JR      Z,.havetarget
        LD      (IY+D_TARGET),0xFF
.ask:
        SET     7,(IY+D_FLAGS)
        RET
.havetarget:
        LD      A,(IY+D_TARGET)
        LD      (TMPB0),A
        CALL    POLEPTR
        LD      A,(HL)
        LD      (AI_PX),A
        INC     HL
        LD      A,(HL)
        LD      (AI_PY),A
        ; 電柱の隣にいるか
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        LD      A,(AI_PX)
        LD      D,A
        LD      A,(AI_PY)
        LD      E,A
        CALL    MANHATTAN
        CP      1
        JP      NZ,AIWALK

        ; --- 電柱の隣: 向きを合わせておしっこ ---
        LD      C,0
.dirlp:
        LD      A,C
        PUSH    BC
        CALL    DIRCELL                 ; B,C = 行き先
        LD      A,(AI_PX)
        CP      B
        JR      NZ,.dirnext
        LD      A,(AI_PY)
        CP      C
        JR      NZ,.dirnext
        POP     BC
        LD      A,C
        LD      (IY+D_DIR),A
        JR      .dirdone
.dirnext:
        POP     BC
        INC     C
        LD      A,C
        CP      4
        JR      C,.dirlp
.dirdone:
        ; 3 本目なら、まだ三角形が作れるか確かめる
        LD      A,(IY+D_CHAINN)
        CP      2
        JR      C,.pee
        CALL    SETTRI_FROMCHAIN
        XOR     A
        LD      (EVAL_COLLECT),A
        LD      A,(IY+D_TERRID)
        LD      (EVAL_ID),A
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        LD      (EVAL_STEAL),A
        CALL    EVALUATE
        LD      HL,(EV_N)
        LD      A,H
        OR      L
        JR      NZ,.pee
        LD      (IY+D_TARGET),0xFF
        LD      A,6
        LD      (IY+D_THINK),A
        RET
.pee:
        LD      A,(TMPB0)
        CALL    STARTPEE
        LD      (IY+D_TARGET),0xFF
        ; 次に考えるまでの間
        LD      A,(STAGE)
        CP      6
        LD      A,18
        JR      C,.dth
        LD      A,6
.dth:
        CALL    RANDMOD
        ADD     A,5
        LD      B,A
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,T_DITHER
        ADD     HL,DE
        LD      C,(HL)
        CALL    MULU88
        LD      B,4
.sh:
        SRL     H
        RR      L
        DJNZ    .sh
        LD      A,L
        OR      A
        JR      NZ,.st
        LD      A,1
.st:
        LD      (IY+D_THINK),A
        RET

; ---------------------------------------------------------------------
; AITAKE - 道さがしの結果が自分のものなら受け取り、目標と道順を決める
;   出力: CY = 目標と道順ができた
; ---------------------------------------------------------------------
AITAKE:
        LD      A,(FL_STATE)
        CP      3
        JR      NZ,.no
        LD      A,(FL_DOG)
        LD      HL,CURDOG
        CP      (HL)
        JR      NZ,.no
        ; 同じティックに何匹も考えると 1 フレームに収まらなくなるので、
        ; 1 ティックあたり AIBUDGET 匹まで。結果は次のティックまで取っておかれる。
        LD      A,(AITHINKS)
        CP      AIBUDGET
        JR      NC,.no
        INC     A
        LD      (AITHINKS),A
        ; 探しはじめた場所から動いていなければ使える
        LD      A,(FL_OX)
        CP      (IY+D_X)
        JR      NZ,.stale
        LD      A,(FL_OY)
        CP      (IY+D_Y)
        JR      NZ,.stale
        RES     7,(IY+D_FLAGS)
        LD      A,(IY+D_TARGET)
        CP      0xFF
        JR      Z,.choose
        CALL    CHAINHAS
        OR      A
        JR      NZ,.choose0
        ; いまの目標へ行く道を作りなおす
        LD      A,(IY+D_TARGET)
        CALL    POLETRAVEL
        CP      0xFF
        JR      NZ,.route
.choose0:
        LD      (IY+D_TARGET),0xFF
.choose:
        CALL    CHOOSETARGET
        LD      A,(IY+D_TARGET)
        CP      0xFF
        JR      Z,.none
        CALL    POLETRAVEL
        CP      0xFF
        JR      Z,.none
.route:
        CALL    BUILDROUTE
        XOR     A
        LD      (FL_STATE),A            ; 結果を手放す (次の犬の番)
        SCF
        RET
.none:
        ; 行ける電柱がない: ぶらぶらして、しばらくしてから探しなおす
        XOR     A
        LD      (FL_STATE),A
        LD      (IY+D_TARGET),0xFF
        CALL    WANDER
        LD      (IY+D_THINK),8
        OR      A
        RET
.stale:
        XOR     A
        LD      (FL_STATE),A            ; 動いてしまった: 捨てて頼みなおす
        RET
.no:
        OR      A
        RET

; ---------------------------------------------------------------------
; AIWALK - 目標へ 1 歩進む
; ---------------------------------------------------------------------
AIWALK:
        ; 覚えている道の次の一歩
        CALL    ROUTEPTR
        LD      A,(IX+1)
        CP      (IX+0)
        JR      NC,.replan              ; 使い切った (遠くて途中までしか覚えていない)
        ADD     A,2
        LD      E,A
        LD      D,0
        ADD     IX,DE
        LD      A,(IX+0)
        LD      (AI_DIR),A
        CALL    DIRCELL
        CALL    CANENTER
        OR      A
        JR      NZ,.gotdir
.replan:
        SET     7,(IY+D_FLAGS)          ; 道がふさがった: 探しなおす
        RET
.gotdir:
        LD      A,(AI_DIR)
        ; --- 道路を渡るときの用心 ---
        LD      E,A
        LD      D,0
        LD      HL,DIRDY
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,(IY+D_Y)
        CP      FH
        JR      NC,.nocheck
        LD      C,A
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.nocheck
        ; いま自分が道路の上なら急いで抜ける
        LD      HL,LANEOF
        LD      D,0
        LD      E,(IY+D_Y)
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      NZ,.nocheck
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,T_CAUTION
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.nocheck
        LD      (AI_CAUT),A
        ; 見る時間 = 1 歩の時間 * 2 * caution/16
        LD      A,(IY+D_STEPTIME)
        ADD     A,A
        LD      B,A
        LD      A,(AI_CAUT)
        LD      C,A
        CALL    MULU88
        LD      B,4
.sh2:
        SRL     H
        RR      L
        DJNZ    .sh2
        LD      A,L
        OR      A
        JR      NZ,.t2
        LD      A,1
.t2:
        LD      (AI_LOOK),A
        LD      A,(AI_DIR)
        CALL    DIRCELL
        LD      A,(AI_LOOK)
        CALL    CARDANGER
        OR      A
        JR      Z,.nocheck
        LD      A,(AI_DIR)
        LD      (IY+D_DIR),A
        LD      A,3
        LD      (IY+D_THINK),A
        RET
.nocheck:
        LD      A,(AI_DIR)
        CALL    TRYMOVE
        OR      A
        JR      NZ,.moved
        SET     7,(IY+D_FLAGS)          ; 入れなかった: 探しなおす
        RET
.moved:
        CALL    ROUTEPTR
        INC     (IX+1)
        ; --- スタミナ ---
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,T_STAMINA
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET     Z
        LD      (AI_STAM),A
        LD      A,(IY+D_STEPS)
        OR      A
        JR      Z,.rest
        DEC     A
        LD      (IY+D_STEPS),A
        RET     NZ
.rest:
        LD      HL,LANEOF
        LD      D,0
        LD      E,(IY+D_Y)
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.dorest
        LD      A,1
        LD      (IY+D_STEPS),A
        RET
.dorest:
        LD      A,(AI_STAM)
        CALL    RANDMOD
        LD      B,A
        LD      A,(AI_STAM)
        SRL     A
        ADD     A,B
        LD      (IY+D_STEPS),A
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,T_REST
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET     Z
        SRL     A                       ; 30Hz なので半分
        LD      (AI_REST),A
        SRL     A
        CALL    RANDMOD
        LD      B,A
        LD      A,(AI_REST)
        ADD     A,B
        LD      (IY+D_THINK),A
        ; 休むときのせりふ
        LD      A,(IY+D_BREED)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,RESTTBL
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      A,(HL)
        OR      A
        RET     Z
        LD      A,C_WHITE
        CALL    HUDMSG
        LD      A,20
        LD      (MSGTIMER),A
        RET

; ---------------------------------------------------------------------
; DIRCELL - 方向 A の隣のマス -> B, C
;   入力: IY = 犬, A = 方向
; ---------------------------------------------------------------------
DIRCELL:
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
        RET

; ---------------------------------------------------------------------
; OPPD - 方向 A の逆向き
; ---------------------------------------------------------------------
OPPD:
        PUSH    DE
        LD      E,A
        LD      D,0
        LD      HL,OPPDIR
        ADD     HL,DE
        LD      A,(HL)
        POP     DE
        RET

OPPDIR: DB      3, 2, 1, 0

; ---------------------------------------------------------------------
; WANDER - でたらめに 1 歩 (道路には不用意に入らない)
; ---------------------------------------------------------------------
WANDER:
        LD      A,4
        CALL    RANDMOD
        LD      (AI_DIR),A
        LD      E,A
        LD      D,0
        LD      HL,DIRDY
        ADD     HL,DE
        LD      A,(HL)
        ADD     A,(IY+D_Y)
        CP      FH
        RET     NC
        LD      C,A
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.ok
        LD      HL,LANEOF
        LD      D,0
        LD      E,(IY+D_Y)
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET     Z
.ok:
        LD      A,(AI_DIR)
        JP      TRYMOVE

; ---------------------------------------------------------------------
; SCOREADD - AI_SCORE に符号付き 8bit の A を足す
; ---------------------------------------------------------------------
SCOREADD:
        PUSH    HL
        PUSH    DE
        LD      E,A
        ADD     A,A
        SBC     A,A
        LD      D,A
        LD      HL,(AI_SCORE)
        ADD     HL,DE
        LD      (AI_SCORE),HL
        POP     DE
        POP     HL
        RET

; ---------------------------------------------------------------------
; CHOOSETARGET - 次に向かう電柱を選ぶ
; ---------------------------------------------------------------------
CHOOSETARGET:
        LD      A,(IY+D_BREED)
        CALL    TEMPERPTR
        LD      DE,AITMP
        LD      BC,T_SIZE
        LDIR
        ; 柴犬の位置を覚えておく
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        LD      DE,D_X
        ADD     HL,DE
        LD      A,(HL)
        LD      (AI_PLX),A
        INC     HL
        LD      A,(HL)
        LD      (AI_PLY),A
        POP     IY
        LD      A,2
        LD      (AI_ATTEMPT),A
CT_ATTEMPT:
        ; いちばん低い値。0x8000 にすると引き算があふれて符号判定が狂うので
        ; 少し余裕をもたせてある
        LD      HL,0xC000
        LD      (BESTSCORE),HL
        LD      A,0xFF
        LD      (BESTIDX),A
        XOR     A
        LD      (POLEI),A
CT_LOOP:
        LD      A,(POLEI)
        LD      HL,NPOLES
        CP      (HL)
        JP      NC,CT_ENDLOOP
        LD      A,(POLEI)
        CALL    CHAINHAS
        OR      A
        JP      NZ,CT_NEXT
        LD      A,(POLEI)
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      A,(IX+PL_X)
        LD      (AI_PX),A
        LD      A,(IX+PL_Y)
        LD      (AI_PY),A
        ; 歩数は道さがしの結果から。行けない電柱は選ばない
        LD      A,(POLEI)
        CALL    POLETRAVEL
        CP      0xFF
        JP      Z,CT_NEXT
        CP      100
        JR      C,.tv
        LD      A,100
.tv:
        LD      (AI_TRAVEL),A
        LD      HL,100
        LD      (AI_SCORE),HL
        LD      A,(AI_TRAVEL)
        NEG
        CALL    SCOREADD
        ; 気まぐれ
        LD      A,(AITMP+T_NOISE)
        SRL     A
        SRL     A
        OR      A
        JR      Z,.nonoise
        CALL    RANDMOD
        CALL    SCOREADD
.nonoise:
        LD      A,(IY+D_CHAINN)
        OR      A
        JP      Z,CT_FIRST
        CP      1
        JP      Z,CT_SECOND
        JP      CT_THIRD

CT_BACK:
        LD      HL,(AI_SCORE)
        LD      DE,(BESTSCORE)
        PUSH    HL
        XOR     A
        SBC     HL,DE
        POP     HL
        JP      M,CT_NEXT
        JR      Z,CT_NEXT
        LD      (BESTSCORE),HL
        LD      A,(POLEI)
        LD      (BESTIDX),A
CT_NEXT:
        LD      A,(POLEI)
        INC     A
        LD      (POLEI),A
        JP      CT_LOOP

CT_ENDLOOP:
        LD      A,(BESTIDX)
        CP      0xFF
        JR      Z,CT_FAILED
        LD      A,(IY+D_CHAINN)
        CP      2
        JR      C,CT_ACCEPT
        ; 3 本目は本物の判定で確かめる
        LD      A,(BESTIDX)
        LD      (TMPB0),A
        CALL    SETTRI_FROMCHAIN
        XOR     A
        LD      (EVAL_COLLECT),A
        LD      A,(IY+D_TERRID)
        LD      (EVAL_ID),A
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        LD      (EVAL_STEAL),A
        CALL    EVALUATE
        LD      HL,(EV_N)
        LD      A,H
        OR      L
        JR      Z,CT_FAILED
CT_ACCEPT:
        LD      A,(BESTIDX)
        LD      (IY+D_TARGET),A
        LD      (IY+D_STUCK),0
        RET
CT_FAILED:
        LD      A,(IY+D_CHAINN)
        CP      2
        JR      C,CT_GIVEUP
        ; 組み直す: いちばん古い印を捨てる
        LD      A,(IY+D_CHAIN+1)
        LD      (IY+D_CHAIN),A
        LD      A,(IY+D_CHAIN+2)
        LD      (IY+D_CHAIN+1),A
        LD      A,(IY+D_CHAINN)
        DEC     A
        LD      (IY+D_CHAINN),A
        LD      A,(AI_ATTEMPT)
        DEC     A
        LD      (AI_ATTEMPT),A
        JP      NZ,CT_ATTEMPT
CT_GIVEUP:
        LD      (IY+D_TARGET),0xFF
        RET

; --- 1 本目: 近くて、ほかの犬の印があればうれしい -------------------
CT_FIRST:
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      NZ,.locked
        LD      A,(IX+PL_OWNER)
        CP      0xFF
        JR      Z,.aggro
        CP      (IY+D_TERRID)
        JR      Z,.aggro
        LD      A,(AITMP+T_STEAL)
        SRL     A
        CALL    SCOREADD
        JR      .aggro
.locked:
        LD      A,(IX+PL_OWNER)
        CP      (IY+D_TERRID)
        JR      Z,.aggro
        LD      A,-20
        CALL    SCOREADD
.aggro:
        ; 攻撃的な犬は柴犬の近くから始める
        LD      A,(AITMP+T_AGGRO)
        CP      17
        JP      C,CT_BACK
        LD      A,(AI_PX)
        LD      B,A
        LD      A,(AI_PY)
        LD      C,A
        LD      A,(AI_PLX)
        LD      D,A
        LD      A,(AI_PLY)
        LD      E,A
        CALL    MANHATTAN
        SRL     A
        NEG
        CALL    SCOREADD
        JP      CT_BACK

; --- 2 本目: 1 本目から好みの距離だけ離れたところ -------------------
CT_SECOND:
        XOR     A
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      B,A
        INC     HL
        LD      A,(HL)
        LD      C,A
        LD      A,(AI_PX)
        LD      D,A
        LD      A,(AI_PY)
        LD      E,A
        CALL    MANHATTAN
        LD      (AI_TMP1),A
        ; 好みの距離 = min(15, reach + stage/3)
        LD      A,(STAGE)
        LD      C,3
        CALL    DIV8A
        LD      C,A
        LD      A,(AITMP+T_REACH)
        ADD     A,C
        CP      16
        JR      C,.id
        LD      A,15
.id:
        LD      C,A
        LD      A,(AI_TMP1)
        SUB     C
        JP      P,.p
        NEG
.p:
        LD      B,A
        ADD     A,A
        ADD     A,B                     ; |dd-ideal| * 3
        NEG
        CALL    SCOREADD
        JP      CT_BACK

; --- 3 本目: 外接箱が大きく、犬を囲めるところ -----------------------
CT_THIRD:
        ; 3 点の外接箱
        XOR     A
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_AX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_AY),A
        LD      A,1
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_BX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_BY),A
        LD      A,(AI_PX)
        LD      (TRI_CX),A
        LD      A,(AI_PY)
        LD      (TRI_CY),A
        CALL    TRIBOX
        LD      A,(EV_X1)
        LD      HL,EV_X0
        SUB     (HL)
        LD      (AI_BW),A
        LD      A,(EV_Y1)
        LD      HL,EV_Y0
        SUB     (HL)
        LD      (AI_BH),A
        ; つぶれた三角形は選ばない
        LD      A,(AI_BW)
        CP      2
        JP      C,.bad
        LD      A,(AI_BH)
        CP      2
        JP      C,.bad
        ; (幅 + 高さ) * sizew / 16
        LD      A,(AI_BW)
        LD      HL,AI_BH
        ADD     A,(HL)
        LD      B,A
        LD      A,(AITMP+T_SIZEW)
        LD      C,A
        CALL    MULU88
        LD      B,4
.sh:
        SRL     H
        RR      L
        DJNZ    .sh
        LD      A,L
        CALL    SCOREADD
        ; 柴犬が外接箱の中なら狙う
        LD      A,(AITMP+T_AGGRO)
        OR      A
        JR      Z,.noaggro
        LD      A,(AI_PLX)
        LD      B,A
        LD      A,(AI_PLY)
        LD      C,A
        CALL    INBOX
        OR      A
        JR      Z,.noaggro
        LD      A,(AITMP+T_AGGRO)
        CALL    SCOREADD
.noaggro:
        ; 牧羊犬はほかの敵を囲みに行く
        LD      A,(AITMP+T_HERD)
        OR      A
        JP      Z,CT_BACK
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.hlp:
        PUSH    BC
        LD      A,C
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.hn
        LD      A,(IX+D_FLAGS)
        AND     DF_PLAYER
        JR      NZ,.hn
        LD      A,(IX+D_TERRID)
        CP      (IY+D_TERRID)
        JR      Z,.hn
        LD      B,(IX+D_X)
        LD      C,(IX+D_Y)
        CALL    INBOX
        OR      A
        JR      Z,.hn
        LD      A,(AITMP+T_HERD)
        CALL    SCOREADD
.hn:
        POP     BC
        INC     C
        DJNZ    .hlp
        ; IX を候補の電柱に戻す
        LD      A,(POLEI)
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        JP      CT_BACK
.bad:
        LD      HL,0xC000
        LD      (AI_SCORE),HL
        JP      CT_BACK

; ---------------------------------------------------------------------
; INBOX - 点 (B,C) が EV_X0..EV_Y1 の箱の中か
;   出力: A != 0 なら中
; ---------------------------------------------------------------------
INBOX:
        LD      A,B
        LD      HL,EV_X0
        CP      (HL)
        JR      C,.no
        LD      HL,EV_X1
        CP      (HL)
        JR      Z,.x
        JR      NC,.no
.x:
        LD      A,C
        LD      HL,EV_Y0
        CP      (HL)
        JR      C,.no
        LD      HL,EV_Y1
        CP      (HL)
        JR      Z,.yes
        JR      NC,.no
.yes:
        LD      A,1
        RET
.no:
        XOR     A
        RET

; ---------------------------------------------------------------------
; SETTRI_FROMCHAIN - chain の最後の 2 本 + 目標の電柱で TRI_* を作る
;   入力: IY = 犬, TMPB0 = 目標の電柱
; ---------------------------------------------------------------------
SETTRI_FROMCHAIN:
        LD      A,(IY+D_CHAINN)
        SUB     2
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_AX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_AY),A
        LD      A,(IY+D_CHAINN)
        DEC     A
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_BX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_BY),A
        LD      A,(TMPB0)
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_CX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_CY),A
        RET

; ---------------------------------------------------------------------
; DIV8A - A / C -> A
; ---------------------------------------------------------------------
DIV8A:
        LD      B,0
.lp:
        CP      C
        JR      C,.done
        SUB     C
        INC     B
        JR      .lp
.done:
        LD      A,B
        RET

; ---------------------------------------------------------------------
; CARDANGER - マス (B,C) に A ティック以内に車が来るか
;   出力: A != 0 なら危ない
; ---------------------------------------------------------------------
CARDANGER:
        LD      (AI_LOOK),A
        LD      L,B
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                   ; x*16 (x は 29 まであるので 16 ビット)
        EX      DE,HL
        LD      HL,-8
        ADD     HL,DE
        LD      (AI_CX0),HL
        LD      HL,24
        ADD     HL,DE
        LD      (AI_CX1),HL
        LD      A,C
        LD      (AI_CROW),A
        ; もうすぐ画面外から入ってくる車
        LD      HL,LANESPAWN
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        LD      HL,AI_LOOK
        CP      (HL)
        JR      NC,.cars
        LD      A,1
        RET
.cars:
        LD      IX,CARS
        LD      B,NCAR
.lp:
        LD      A,(IX+CR_ACTIVE)
        OR      A
        JR      Z,.next
        LD      A,(IX+CR_ROW)
        LD      HL,AI_CROW
        CP      (HL)
        JR      NZ,.next
        PUSH    BC
        LD      A,(IX+CR_SPEED)
        LD      B,A
        LD      A,(AI_LOOK)
        LD      C,A
        CALL    MULU88
        LD      B,4
.sh:
        SRL     H
        RR      L
        DJNZ    .sh
        LD      (AI_REACH),HL
        POP     BC
        LD      L,(IX+CR_XLO)
        LD      H,(IX+CR_XHI)
        LD      A,(IX+CR_SIGN)
        OR      A
        JR      Z,.toright
        PUSH    HL
        LD      DE,(AI_REACH)
        XOR     A
        SBC     HL,DE
        LD      (AI_LO),HL
        POP     HL
        LD      DE,32
        ADD     HL,DE
        LD      (AI_HI),HL
        JR      .test
.toright:
        LD      (AI_LO),HL
        LD      DE,32
        ADD     HL,DE
        LD      DE,(AI_REACH)
        ADD     HL,DE
        LD      (AI_HI),HL
.test:
        LD      HL,(AI_HI)
        LD      DE,(AI_CX0)
        XOR     A
        SBC     HL,DE
        JP      M,.next
        JR      Z,.next
        LD      HL,(AI_LO)
        LD      DE,(AI_CX1)
        XOR     A
        SBC     HL,DE
        JP      P,.next
        LD      A,1
        RET
.next:
        PUSH    BC
        LD      BC,CR_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .lp
        XOR     A
        RET

; ---------------------------------------------------------------------
; BONUSAI - ボーナス面の犬 (眠っている / 起きて逃げる)
; ---------------------------------------------------------------------
BONUSAI:
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        LD      DE,D_X
        ADD     HL,DE
        LD      A,(HL)
        LD      (AI_PLX),A
        INC     HL
        LD      A,(HL)
        LD      (AI_PLY),A
        POP     IY
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        LD      A,(AI_PLX)
        LD      D,A
        LD      A,(AI_PLY)
        LD      E,A
        CALL    MANHATTAN
        LD      (AI_DIST),A

        LD      A,(IY+D_FLAGS)
        AND     DF_ASLEEP
        JR      Z,.awake
        ; --- 眠っている ---
        LD      A,(AI_DIST)
        CP      WAKEWALK+1
        JR      C,.wake
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        LD      A,(IX+D_PEET)
        OR      (IX+D_PEET+1)
        POP     IY
        RET     Z
        LD      A,(AI_DIST)
        CP      WAKEPEE+1
        RET     NC
.wake:
        LD      A,(IY+D_FLAGS)
        AND     0xFF - DF_ASLEEP
        LD      (IY+D_FLAGS),A
        LD      A,25
        LD      (IY+D_AWAKE),A
        LD      A,SFX_BARK
        CALL    SFXPLAY
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        JP      MARKDIRTY
.awake:
        LD      A,(IY+D_AWAKE)
        OR      A
        JR      Z,.maysleep
        DEC     A
        LD      (IY+D_AWAKE),A
        JR      .flee
.maysleep:
        LD      A,(AI_DIST)
        CP      6
        JR      C,.flee
        LD      A,(IY+D_FLAGS)
        OR      DF_ASLEEP
        LD      (IY+D_FLAGS),A
        LD      (IY+D_DIR),0
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        JP      MARKDIRTY
.flee:
        ; 柴犬からいちばん遠ざかる向きへ
        LD      A,0xFF
        LD      (AI_BESTD),A
        LD      (AI_DIR),A
        LD      C,0
.lp:
        PUSH    BC
        LD      A,C
        CALL    DIRCELL
        PUSH    BC
        CALL    CANENTER
        POP     BC
        OR      A
        JR      Z,.next
        LD      A,(AI_PLX)
        LD      D,A
        LD      A,(AI_PLY)
        LD      E,A
        CALL    MANHATTAN
        LD      B,A
        CALL    RANDB
        AND     1
        ADD     A,B
        LD      B,A
        LD      A,(AI_BESTD)
        CP      0xFF
        JR      Z,.better
        CP      B
        JR      NC,.next
.better:
        LD      A,B
        LD      (AI_BESTD),A
        POP     BC
        PUSH    BC
        LD      A,C
        LD      (AI_DIR),A
.next:
        POP     BC
        INC     C
        LD      A,C
        CP      4
        JR      C,.lp
        LD      A,(AI_DIR)
        CP      0xFF
        RET     Z
        JP      TRYMOVE
