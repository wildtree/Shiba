; =====================================================================
; tick.asm - 1 フレーム分のルールの進行
; =====================================================================

; ---------------------------------------------------------------------
; WORLDTICK
; ---------------------------------------------------------------------
WORLDTICK:
        ; おしっこの先行入力を覚えておく (元の版の _actionBuffer)
        LD      A,(ACTPRESS)
        OR      A
        JR      Z,.nobuf
        LD      A,8
        LD      (ACTBUF),A
        JR      .dirbuf
.nobuf:
        LD      A,(ACTBUF)
        OR      A
        JR      Z,.dirbuf
        DEC     A
        LD      (ACTBUF),A
.dirbuf:
        ; 方向の先行入力
        LD      A,(HELDDIR)
        CP      0xFF
        JR      Z,.nodir
        LD      (DIRBUF),A
        LD      A,9
        LD      (DIRBUFT),A
        JR      .time
.nodir:
        LD      A,(DIRBUFT)
        OR      A
        JR      Z,.time
        DEC     A
        LD      (DIRBUFT),A
.time:
        CALL    TICKTIME
        OR      A
        JP      NZ,FINISHSTAGE

        XOR     A
        LD      (AITHINKS),A            ; AI の思考はティックごとに数えなおす
        CALL    UPDATECARS
        LD      A,(GAMEOVER)
        OR      A
        RET     NZ
        CALL    UPDATERAIN
        CALL    UPDATEITEMS
        CALL    UPDATEDOGS
        LD      A,(FINISHED)
        OR      A
        RET     NZ
        LD      A,(GAMEOVER)
        OR      A
        RET     NZ
        CALL    CHECKTRAPPED
        RET

; ---------------------------------------------------------------------
; UPDATEDOGS - すべての犬を 1 フレーム進める
; ---------------------------------------------------------------------
UPDATEDOGS:
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0                     ; 犬 ID
.lp:
        PUSH    BC
        LD      A,C
        CALL    UPDATEONEDOG
        CALL    VBPOLL
        POP     BC
        LD      A,(FINISHED)
        OR      A
        RET     NZ
        LD      A,(GAMEOVER)
        OR      A
        RET     NZ
        INC     C
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; UPDATEONEDOG - 犬 1 匹
;   入力: A = 犬 ID
; ---------------------------------------------------------------------
UPDATEONEDOG:
        LD      (CURDOG),A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_FLAGS)
        AND     DF_ALIVE
        RET     Z
        ; 無敵時間
        LD      A,(IY+D_INVULN)
        OR      A
        JR      Z,.noinv
        DEC     A
        LD      (IY+D_INVULN),A
.noinv:
        ; 移動中か
        LD      A,(IY+D_FLAGS)
        AND     DF_MOVING
        JR      Z,.notmoving
        LD      A,(IY+D_MOVET)
        INC     A
        LD      (IY+D_MOVET),A
        CP      (IY+D_STEPTIME)
        RET     C
        LD      A,(IY+D_FLAGS)
        AND     0xFF - DF_MOVING
        LD      (IY+D_FLAGS),A
        ; ここで RET していたので 1 マスにつき 1 ティック無駄にしていた。
        ; そのまま下の「次の行動を決める」に落として、元の版と同じ速さにする。
.notmoving:
        ; おしっこ中か
        LD      L,(IY+D_PEET)
        LD      H,(IY+D_PEET+1)
        LD      A,H
        OR      L
        JR      Z,.notpeeing
        DEC     HL
        LD      (IY+D_PEET),L
        LD      (IY+D_PEET+1),H
        ; AI の犬は、おしっこが終わる少し前に次の道さがしを頼んでおく
        ; (道さがしはふつう 10 ティックほど。終わるころに結果がそろう)
        LD      A,H
        OR      A
        JR      NZ,.noask
        LD      A,L
        CP      12
        JR      NZ,.noask
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.ask
        LD      A,(DEMOMODE)
        OR      A
        JR      Z,.noask
.ask:
        SET     7,(IY+D_FLAGS)          ; DF_WANTPATH
.noask:
        ; 柴犬なら 0.13 秒 (4 ティック) ごとにしずくの音 (元の版の PeeDrip)
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.nodrip
        PUSH    HL
        LD      A,(DRIPT)
        OR      A
        JR      Z,.drip
        DEC     A
        LD      (DRIPT),A
        JR      .dripdone
.drip:
        LD      A,3                     ; このティックを入れて 4 ティックごと
        LD      (DRIPT),A
        LD      A,SFX_PEEDRIP
        CALL    SFXPLAY
.dripdone:
        POP     HL
.nodrip:
        LD      A,H
        OR      L
        RET     NZ
        ; 柴犬ならしずくの音
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.cp
        LD      A,SFX_MARK
        CALL    SFXPLAY
.cp:
        CALL    COMPLETEPEE
        RET
.notpeeing:
        ; 行動を決める
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.enemy
        LD      A,(DEMOMODE)
        OR      A
        JP      Z,PLAYERCTL
        JP      AICTL                   ; デモでは柴犬も AI が動かす
.enemy:
        LD      A,(BONUSMODE)
        OR      A
        JP      NZ,BONUSAI
        JP      AICTL

; ---------------------------------------------------------------------
; PLAYERCTL - 柴犬の操作
;   入力: IY = 柴犬
; ---------------------------------------------------------------------
PLAYERCTL:
        LD      A,(ACTBUF)
        OR      A
        JR      Z,.move
        ; 向いている方向の電柱
        CALL    POLEINFRONT
        CP      0xFF
        JR      NZ,.gotpole
        ; 周りの 4 方向を見る
        LD      C,0
.look:
        LD      A,C
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
        PUSH    BC
        LD      C,A
        LD      A,B
        CP      FW
        JR      NC,.looknext
        LD      A,C
        CP      FH
        JR      NC,.looknext
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.looknext
        POP     BC
        LD      (IY+D_DIR),C
        JR      .gotpole
.looknext:
        POP     BC
        INC     C
        LD      A,C
        CP      4
        JR      C,.look
        JR      .move
.gotpole:
        LD      (TMPB0),A
        XOR     A
        LD      (ACTBUF),A
        LD      A,(TMPB0)
        CALL    CHAINHAS
        OR      A
        JR      Z,.startpee
        ; すでに印をつけた電柱
        LD      HL,S_MARKED
        LD      A,C_WHITE
        CALL    HUDMSG
        LD      A,20
        LD      (MSGTIMER),A
        LD      A,SFX_INVALID
        CALL    SFXPLAY
        JR      .move
.startpee:
        LD      A,(TMPB0)
        CALL    STARTPEE
        RET
.move:
        LD      A,(HELDDIR)
        CP      0xFF
        JR      NZ,.go
        LD      A,(DIRBUFT)
        OR      A
        RET     Z
        LD      A,(DIRBUF)
.go:
        CP      0xFF
        RET     Z
        XOR     A
        LD      (DIRBUFT),A
        LD      A,(HELDDIR)
        CP      0xFF
        JR      NZ,.use
        LD      A,(DIRBUF)
.use:
        CALL    TRYMOVE
        OR      A
        RET     Z
        ; 巻物の力でほかの犬のなわばりに入った
        LD      A,(IY+D_PASST)
        OR      (IY+D_PASST+1)
        JR      Z,.step
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.step
        CP      (IY+D_TERRID)
        JR      Z,.step
        CALL    ACH
        DB      ACH_NINJA
.step:
        LD      A,SFX_STEP
        JP      SFXPLAY

; ---------------------------------------------------------------------
; POLEINFRONT - 向いている方向の電柱番号 (なければ 0xFF)
;   入力: IY = 犬
; ---------------------------------------------------------------------
POLEINFRONT:
        LD      A,(IY+D_DIR)
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
        LD      A,B
        CP      FW
        JR      NC,.no
        LD      A,C
        CP      FH
        JR      NC,.no
        LD      DE,ARR_POLEAT
        CALL    CELLPTR
        LD      A,(HL)
        RET
.no:
        LD      A,0xFF
        RET

; ---------------------------------------------------------------------
; COMPLETEPEE - おしっこが終わった
;   入力: IY = 犬
; ---------------------------------------------------------------------
COMPLETEPEE:
        LD      A,(IY+D_PEEPOLE)
        CP      0xFF
        RET     Z
        LD      (TMPB0),A
        LD      (IY+D_PEEPOLE),0xFF
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      NZ,.locked
        ; なわばりに入っていない電柱は上書きできる
        LD      A,(IX+PL_OWNER)
        CP      0xFF
        JR      Z,.setowner
        CP      (IY+D_TERRID)
        JR      Z,.setowner
        ; 前の持ち主の chain から外す
        LD      (TMPB1),A
        PUSH    IY
        LD      A,(TMPB1)
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(TMPB0)
        LD      C,A
        CALL    CHAINREM
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        POP     IY
        CALL    ACHPL                   ; 柴犬がほかの犬の印を上書きした (フラグは残る)
        DB      ACH_OVERWRITE
        JR      Z,.setowner
        ; 柴犬の印が取られた
        LD      HL,S_LOST
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,20
        LD      (MSGTIMER),A
        LD      A,SFX_OVERWRITE
        CALL    SFXPLAY
.setowner:
        LD      A,(IY+D_TERRID)
        LD      (IX+PL_OWNER),A
        JR      .mark
.locked:
        ; なわばりの頂点になった電柱は共有できるが、印は 1 匹分だけ
        CALL    STEALSHARED
.mark:
        LD      A,(TMPB0)
        CALL    CHAINADD
        ; 電柱のマスを描き直す
        LD      B,(IX+PL_X)
        LD      C,(IX+PL_Y)
        CALL    MARKDIRTY
        LD      A,(IY+D_CHAINN)
        CP      3
        RET     C
        JP      TRYTERRITORY

; ---------------------------------------------------------------------
; STEALSHARED - なわばりに取り込まれた電柱 (TMPB0) に印をつけたとき、
;   ほかの犬の chain からその電柱を外す (上書き)。IX は残す
;   入力: IY = 印をつけた犬
; ---------------------------------------------------------------------
STEALSHARED:
        PUSH    IX
        LD      A,(IY+D_TERRID)
        LD      (SSID),A
        XOR     A
        LD      (SSHIT),A
        PUSH    IY
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.lp:
        PUSH    BC
        LD      A,C
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_TERRID)
        LD      HL,SSID
        CP      (HL)
        JR      Z,.next
        LD      A,(TMPB0)
        LD      C,A
        CALL    CHAINHAS
        OR      A
        JR      Z,.next
        LD      A,(TMPB0)
        LD      C,A
        CALL    CHAINREM
        LD      A,1
        LD      (SSHIT),A
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.next
        ; 柴犬の印が取られた
        LD      HL,S_LOST
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,20
        LD      (MSGTIMER),A
        LD      A,SFX_OVERWRITE
        CALL    SFXPLAY
.next:
        POP     BC
        INC     C
        DJNZ    .lp
        POP     IY
        POP     IX
        LD      A,(SSHIT)
        OR      A
        RET     Z
        CALL    ACHPL                   ; 柴犬がほかの犬の印を上書きした
        DB      ACH_OVERWRITE
        RET

; ---------------------------------------------------------------------
; TRYTERRITORY - chain の 3 本でなわばりができるか試す
;   入力: IY = 犬
; ---------------------------------------------------------------------
TRYTERRITORY:
        ; 3 本の電柱の座標を TRI_* に入れる
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
        LD      A,2
        CALL    CHAINGET
        CALL    POLEPTR
        LD      A,(HL)
        LD      (TRI_CX),A
        INC     HL
        LD      A,(HL)
        LD      (TRI_CY),A

        LD      A,(IY+D_TERRID)
        LD      (EVAL_ID),A
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        LD      (EVAL_STEAL),A
        LD      A,1
        LD      (EVAL_COLLECT),A
        LD      HL,ARR_FILLQ
        LD      (FILLHEAD),HL
        LD      (FILLTAIL),HL
        ; 前回の「新しく取ったマス」の印が残らないよう全部消しておく
        LD      HL,ARR_INTRI
        LD      BC,NCELL
        XOR     A
        CALL    MEMFILL
        CALL    EVALUATE
        LD      HL,(EV_N)
        LD      A,H
        OR      L
        JR      NZ,.ok

        ; --- 作れない三角形: 印を全部取り消す ---
        CALL    CHAINDROP
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        RET     Z
        LD      HL,S_NOGOOD
        LD      A,C_WHITE
        CALL    HUDMSG
        LD      A,30
        LD      (MSGTIMER),A
        LD      A,SFX_INVALID
        JP      SFXPLAY

.ok:
        LD      (TERRCNT),HL
        ; --- 取ったマスを塗る ---
        LD      HL,(FILLHEAD)
.filllp:
        LD      DE,(FILLTAIL)
        LD      A,L
        CP      E
        JR      NZ,.go
        LD      A,H
        CP      D
        JR      Z,.filldone
.go:
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        ; DE = セルの添字
        LD      HL,ARR_TERR
        ADD     HL,DE
        LD      A,(HL)
        CP      0xFF
        JR      Z,.wasfree
        ; ほかの犬のなわばりを奪った
        PUSH    HL
        PUSH    DE
        CALL    DOGADDR
        LD      DE,D_AREA
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        DEC     DE
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        POP     DE
        POP     HL
        JR      .setterr
.wasfree:
        LD      BC,(CLAIMED)
        INC     BC
        LD      (CLAIMED),BC
.setterr:
        LD      A,(IY+D_TERRID)
        LD      (HL),A
        ; 描き直す対象にする (まわりも縁が変わるので一緒に)
        PUSH    DE
        CALL    MARKDIRTYI
        POP     DE
        CALL    MARKNEIGH
        POP     HL
        JR      .filllp
.filldone:
        ; 自分の面積を増やす
        PUSH    IY
        POP     HL
        LD      DE,D_AREA
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      BC,(TERRCNT)
        EX      DE,HL
        ADD     HL,BC
        EX      DE,HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        LD      (IY+D_CHAINN),0

        ; --- なわばりの中の電柱をロックする ---
        CALL    LOCKPOLES
        ; --- なわばりの中のアイテムを消す ---
        CALL    CLEARITEMSINTERR
        ; --- 点数 ---
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.enemysound
        ; 1 マス 10 点 (ボーナス面は 30 点)
        LD      HL,(TERRCNT)
        ADD     HL,HL                   ; 2n
        LD      B,H
        LD      C,L
        LD      A,(BONUSMODE)
        OR      A
        JR      NZ,.b30
        ADD     HL,HL                   ; 4n
        ADD     HL,HL                   ; 8n
        ADD     HL,BC                   ; 10n
        JR      .sc
.b30:
        ADD     HL,HL                   ; 4n
        ADD     HL,HL                   ; 8n
        ADD     HL,HL                   ; 16n
        ADD     HL,HL                   ; 32n
        XOR     A
        SBC     HL,BC                   ; 30n
.sc:
        CALL    ADDSCORE
        CALL    ACH
        DB      ACH_FIRST_TURF
        LD      HL,(TERRCNT)
        LD      DE,100
        OR      A
        SBC     HL,DE
        JR      C,.nobig
        CALL    ACH
        DB      ACH_BIG_TURF
.nobig:
        LD      L,(IY+D_AREA)
        LD      H,(IY+D_AREA+1)
        LD      DE,(FW*FH+1)/2          ; 半分以上
        OR      A
        SBC     HL,DE
        JR      C,.nohalf
        CALL    ACH
        DB      ACH_HALF
.nohalf:
        LD      A,SFX_TERRITORY
        CALL    SFXPLAY
        JR      .caught
.enemysound:
        LD      A,SFX_ENEMYTERR
        CALL    SFXPLAY
.caught:
        ; HUD の面積の帯と数字を描きなおす
        LD      A,1
        LD      (NEEDHUD),A
        LD      (AREADIRTY),A
        CALL    CATCHDOGS
        LD      A,(GAMEOVER)
        OR      A
        RET     NZ
        ; --- 終了の判定 ---
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.normal
        ; ボーナス面: 全員囲んだらパーフェクト
        CALL    COUNTALIVEENEMY
        OR      A
        RET     NZ
        LD      A,1
        LD      (PERFECT),A
        LD      HL,5000
        CALL    ADDSCORE
        JP      FINISHSTAGE
.normal:
        LD      HL,(CLAIMED)
        LD      DE,GOALCELL
        XOR     A
        SBC     HL,DE
        RET     C
        JP      FINISHSTAGE

; ---------------------------------------------------------------------
; MARKNEIGH - 添字 DE のマスの上下左右も描き直す対象にする
;   (なわばりの縁取りは隣のマスの持ち主で変わるため)
; ---------------------------------------------------------------------
MARKNEIGH:
        PUSH    DE
        CALL    IDXTOXY
        LD      A,B
        LD      (TMPB2),A
        LD      A,C
        LD      (TMPB3),A
        ; 上
        LD      A,(TMPB3)
        OR      A
        JR      Z,.nodown
        DEC     A
        LD      C,A
        LD      A,(TMPB2)
        LD      B,A
        CALL    MARKDIRTY
.nodown:
        LD      A,(TMPB3)
        INC     A
        CP      FH
        JR      NC,.noup
        LD      C,A
        LD      A,(TMPB2)
        LD      B,A
        CALL    MARKDIRTY
.noup:
        LD      A,(TMPB2)
        OR      A
        JR      Z,.noleft
        DEC     A
        LD      B,A
        LD      A,(TMPB3)
        LD      C,A
        CALL    MARKDIRTY
.noleft:
        LD      A,(TMPB2)
        INC     A
        CP      FW
        JR      NC,.noright
        LD      B,A
        LD      A,(TMPB3)
        LD      C,A
        CALL    MARKDIRTY
.noright:
        POP     DE
        RET

; ---------------------------------------------------------------------
; LOCKPOLES - 自分のなわばりに入った電柱をロックする
;   入力: IY = 犬
; ---------------------------------------------------------------------
LOCKPOLES:
        LD      A,(NPOLES)
        OR      A
        RET     Z
        XOR     A
        LD      (POLEI),A
.lp:
        LD      A,(POLEI)
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      B,(IX+PL_X)
        LD      C,(IX+PL_Y)
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        CP      (IY+D_TERRID)
        JR      NZ,.next
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      Z,.dolock
        LD      A,(IX+PL_OWNER)
        CP      (IY+D_TERRID)
        JR      Z,.next
.dolock:
        LD      (IX+PL_LOCKED),1
        LD      A,(IY+D_TERRID)
        LD      (IX+PL_OWNER),A
        LD      B,(IX+PL_X)
        LD      C,(IX+PL_Y)
        CALL    MARKDIRTY
        LD      A,(POLEI)
        LD      C,A
        CALL    REMOVEFROMOTHERS
.next:
        LD      A,(POLEI)
        INC     A
        LD      (POLEI),A
        LD      HL,NPOLES
        CP      (HL)
        JR      C,.lp
        RET

; ---------------------------------------------------------------------
; REMOVEFROMOTHERS - 電柱 C を、IY 以外の犬の chain から外す。
;   その電柱におしっこ中の犬がいれば、おしっこも取り消す (終わったら印が
;   つく、ではおかしい)。すでに取り込まれた電柱へのおしっこ(共有)はよい
; ---------------------------------------------------------------------
REMOVEFROMOTHERS:
        LD      A,C
        LD      (RFOPOLE),A
        PUSH    IY
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.lp:
        PUSH    BC
        LD      A,C
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_TERRID)
        LD      HL,EVAL_ID
        CP      (HL)
        JR      Z,.next
        ; おしっこ中の電柱だった (chain にはまだ入っていない)
        LD      A,(IY+D_PEEPOLE)
        LD      HL,RFOPOLE
        CP      (HL)
        JR      NZ,.chain
        XOR     A
        LD      (IY+D_PEET),A
        LD      (IY+D_PEET+1),A
        LD      (IY+D_PEEPOLE),0xFF
        JR      .lost
.chain:
        LD      A,(RFOPOLE)
        LD      C,A
        CALL    CHAINHAS
        OR      A
        JR      Z,.next
        LD      A,(RFOPOLE)
        LD      C,A
        CALL    CHAINREM
.lost:
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.next
        LD      HL,S_LOST
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,20
        LD      (MSGTIMER),A
.next:
        POP     BC
        INC     C
        DJNZ    .lp
        POP     IY
        RET

; ---------------------------------------------------------------------
; CLEARITEMSINTERR - なわばりになったマスのアイテムを消す
; ---------------------------------------------------------------------
CLEARITEMSINTERR:
        LD      IX,ITEMS
        LD      B,NITEM
.lp:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.next
        PUSH    BC
        LD      B,(IX+IT_X)
        LD      C,(IX+IT_Y)
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.keep
        LD      (IX+IT_ACTIVE),0
.keep:
        POP     BC
.next:
        PUSH    BC
        LD      BC,IT_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; CATCHDOGS - 今回取ったマスの上にいた犬を退場させる
;   入力: IY = 取った犬
; ---------------------------------------------------------------------
CATCHDOGS:
        XOR     A
        LD      (CDCOUNT),A
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.lp:
        PUSH    BC
        LD      A,C
        LD      (CDID),A
        CALL    DOGADDR
        PUSH    HL
        POP     IX
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.next
        LD      A,(IX+D_TERRID)
        CP      (IY+D_TERRID)
        JR      Z,.next
        ; 今回新しく取ったマスにいるか (ARR_INTRI の bit3)
        PUSH    BC
        LD      B,(IX+D_X)
        LD      C,(IX+D_Y)
        LD      DE,ARR_INTRI
        CALL    CELLPTR
        POP     BC
        LD      A,(HL)
        AND     8
        JR      Z,.next
        ; 柴犬か?
        LD      A,(IX+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.enemyout
        ; 囲まれた
        CALL    ACH
        DB      ACH_GOT_CAUGHT
        LD      HL,S_CAUGHT
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,30
        LD      (MSGTIMER),A
        CALL    LOSELIFE
        LD      A,(GAMEOVER)
        OR      A
        JR      NZ,.fin
        JR      .next
.enemyout:
        LD      A,1
        LD      (LISTDIRTY),A           ; HUD の一覧を "OUT" に
        LD      A,(IX+D_FLAGS)
        LD      (CDFLAGS),A
        LD      (IX+D_FLAGS),0          ; 退場
        LD      B,(IX+D_X)
        LD      C,(IX+D_Y)
        PUSH    BC
        ; 点数 (囲んだのが柴犬のときだけ)
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.nopts
        LD      HL,500
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.chkboss
        LD      HL,2000
        LD      A,(CDFLAGS)
        AND     DF_ASLEEP
        JR      NZ,.pts
        LD      HL,1000
        JR      .pts
.chkboss:
        LD      A,(CDFLAGS)
        AND     DF_BOSS
        JR      Z,.pts
        LD      HL,3000
.pts:
        CALL    ADDSCORE
        CALL    ACH
        DB      ACH_CATCH_DOG
        LD      A,(CDFLAGS)
        AND     DF_BOSS
        JR      Z,.nboss
        CALL    ACH
        DB      ACH_BOSS_DOWN
.nboss:
        LD      HL,CDCOUNT
        INC     (HL)
        LD      HL,S_OUT
        LD      A,C_YELLOW
        CALL    HUDMSG
        LD      A,25
        LD      (MSGTIMER),A
.nopts:
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.snd
        LD      A,(BONUSCAUGHT)
        INC     A
        LD      (BONUSCAUGHT),A
.snd:
        LD      A,SFX_ENEMYOUT
        CALL    SFXPLAY
        ; 退場した犬の chain を落とす
        PUSH    IY
        LD      A,(CDID)
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        CALL    CHAINDROP
        POP     IY
        POP     BC
        CALL    MARKDIRTY
        JR      .next
.next:
        POP     BC
        INC     C
        DJNZ    .lp
        LD      A,(CDCOUNT)
        CP      2
        RET     C
        CALL    ACH
        DB      ACH_DOUBLE_CATCH
        RET
.fin:
        POP     BC
        RET

; ---------------------------------------------------------------------
; COUNTALIVEENEMY - 生きている敵の数 -> A
; ---------------------------------------------------------------------
COUNTALIVEENEMY:
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
        LD      E,0
        LD      IX,DOGS
.lp:
        LD      A,(IX+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.next
        LD      A,(IX+D_FLAGS)
        AND     DF_PLAYER
        JR      NZ,.next
        INC     E
.next:
        PUSH    DE
        LD      DE,D_SIZE
        ADD     IX,DE
        POP     DE
        DJNZ    .lp
        LD      A,E
        RET

; ---------------------------------------------------------------------
; ADDSCORE - スコアに HL を足す
; ---------------------------------------------------------------------
ADDSCORE:
        LD      A,(DEMOMODE)
        OR      A
        RET     NZ
        PUSH    DE
        LD      DE,(SCORE)
        ADD     HL,DE
        LD      (SCORE),HL
        JR      NC,.nc
        LD      A,(SCORE+2)
        INC     A
        LD      (SCORE+2),A
.nc:
        POP     DE
        LD      A,1
        LD      (NEEDHUD),A
        RET

; ---------------------------------------------------------------------
; LOSELIFE - 柴犬が 1 機失う
; ---------------------------------------------------------------------
LOSELIFE:
        LD      A,SFX_MISS
        CALL    SFXPLAY
        LD      A,(DEMOMODE)
        OR      A
        JR      NZ,.resp
        LD      A,(BONUSMODE)
        OR      A
        JR      NZ,.resp                ; ボーナス面では減らない
        LD      HL,MISSES
        INC     (HL)
        LD      A,(LIVES)
        OR      A
        JR      Z,.over
        DEC     A
        LD      (LIVES),A
        LD      A,1
        LD      (NEEDHUD),A
        LD      A,(LIVES)
        OR      A
        JR      Z,.over
.resp:
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        CALL    RESPAWN
        LD      A,3*TICKHZ
        LD      (IY+D_INVULN),A
        POP     IY
        RET
.over:
        LD      A,1
        LD      (GAMEOVER),A
        RET

; ---------------------------------------------------------------------
; RESPAWN - 犬をなわばりの外に出し直す
;   入力: IY = 犬
; ---------------------------------------------------------------------
RESPAWN:
        LD      HL,0
        LD      (IY+D_PEET),L
        LD      (IY+D_PEET+1),H
        LD      (IY+D_PEEPOLE),0xFF
        LD      (IY+D_TARGET),0xFF
        LD      (IY+D_STUCK),0
        LD      A,(IY+D_FLAGS)
        AND     0xFF - DF_MOVING
        LD      (IY+D_FLAGS),A
        ; 元の位置を描き直す
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        CALL    MARKDIRTY
        LD      A,3
        CALL    FINDCELL
        LD      A,(FOUNDX)
        LD      (IY+D_X),A
        LD      (IY+D_FROMX),A
        LD      A,(FOUNDY)
        LD      (IY+D_Y),A
        LD      (IY+D_FROMY),A
        RET

; ---------------------------------------------------------------------
; CHECKTRAPPED - 柴犬が身動きできなくなったら囲まれた扱い
; ---------------------------------------------------------------------
CHECKTRAPPED:
        LD      A,(BONUSMODE)
        OR      A
        RET     NZ
        PUSH    IY
        XOR     A
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_FLAGS)
        AND     DF_MOVING
        JR      NZ,.out
        LD      A,(IY+D_PEET)
        OR      (IY+D_PEET+1)
        JR      NZ,.out
        LD      A,(IY+D_INVULN)
        OR      A
        JR      NZ,.out
        LD      C,0
.lp:
        LD      A,C
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
        PUSH    BC
        LD      C,A
        CALL    CANENTER
        POP     BC
        OR      A
        JR      NZ,.out                 ; 動けるところがある
        INC     C
        LD      A,C
        CP      4
        JR      C,.lp
        ; どこにも動けない
        LD      HL,S_TRAPPED
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,30
        LD      (MSGTIMER),A
        CALL    LOSELIFE
.out:
        POP     IY
        RET

; ---------------------------------------------------------------------
; FINISHSTAGE - ステージの終わり
; ---------------------------------------------------------------------
FINISHSTAGE:
        LD      A,(FINISHED)
        OR      A
        RET     NZ
        LD      A,1
        LD      (FINISHED),A
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.normal
        LD      A,1
        LD      (CLEARED),A
        RET
.normal:
        ; 自分の面積が敵のどれよりも小さくなければクリア
        XOR     A
        CALL    DOGADDR
        LD      DE,D_AREA
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      (TMPW0),DE              ; 自分の面積
        LD      HL,0
        LD      (TMPW1),HL              ; 敵の最大
        LD      A,(NDOGS)
        LD      B,A
        LD      IX,DOGS
.lp:
        PUSH    BC
        LD      A,(IX+D_FLAGS)
        AND     DF_PLAYER
        JR      NZ,.next
        LD      L,(IX+D_AREA)
        LD      H,(IX+D_AREA+1)
        LD      DE,(TMPW1)
        XOR     A
        SBC     HL,DE
        JR      C,.next
        LD      L,(IX+D_AREA)
        LD      H,(IX+D_AREA+1)
        LD      (TMPW1),HL
.next:
        PUSH    DE
        LD      DE,D_SIZE
        ADD     IX,DE
        POP     DE
        POP     BC
        DJNZ    .lp
        ; 自分 >= 敵の最大 かつ 自分 > 0 ならクリア
        LD      HL,(TMPW0)
        LD      A,H
        OR      L
        RET     Z
        LD      DE,(TMPW1)
        XOR     A
        SBC     HL,DE
        RET     C
        LD      A,1
        LD      (CLEARED),A
        RET
