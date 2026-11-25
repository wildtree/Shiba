; =====================================================================
; events.asm - 車・雨・アイテム
; =====================================================================

; ---------------------------------------------------------------------
; UPDATECARS
; ---------------------------------------------------------------------
UPDATECARS:
        ; --- 車を出す ---
        LD      C,0
.spawnlp:
        LD      HL,LANEOF
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.spawnnext
        LD      HL,LANESPAWN
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        JR      Z,.spawnnext
        DEC     A
        LD      (HL),A
        OR      A
        JR      NZ,.spawnnext
        PUSH    BC
        CALL    SPAWNCAR
        POP     BC
        ; 次の車までの時間
        LD      A,(STAGE)
        LD      B,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,B                     ; stage*9
        LD      B,A
        LD      A,100
        CP      B
        JR      NC,.ok
        LD      B,70
.ok:
        LD      A,100
        SUB     B
        CP      30
        JR      NC,.base
        LD      A,30
.base:
        LD      B,A
        CALL    RANDMOD                 ; 0..base-1
        LD      E,A
        LD      A,B
        SRL     A
        ADD     A,E                     ; base/2 + rand(base)
        LD      HL,LANESPAWN
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      (HL),A
.spawnnext:
        INC     C
        LD      A,C
        CP      FH
        JR      C,.spawnlp

        ; --- 車を動かす ---
        LD      IX,CARS
        LD      B,NCAR
.movelp:
        LD      A,(IX+CR_ACTIVE)
        OR      A
        JR      Z,.movenext
        PUSH    BC
        CALL    MOVECAR
        CALL    VBPOLL
        POP     BC
.movenext:
        PUSH    BC
        LD      BC,CR_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .movelp
        RET

; ---------------------------------------------------------------------
; SPAWNCAR - 行 C に車を 1 台出す
; ---------------------------------------------------------------------
SPAWNCAR:
        LD      A,C
        LD      (TMPB0),A
        ; 空いている枠を探す
        LD      IX,CARS
        LD      B,NCAR
.find:
        LD      A,(IX+CR_ACTIVE)
        OR      A
        JR      Z,.got
        PUSH    BC
        LD      BC,CR_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .find
        RET                             ; 空きがない
.got:
        LD      A,(TMPB0)
        LD      (IX+CR_ROW),A
        LD      (IX+CR_ACTIVE),1
        LD      (IX+CR_FRAC),0
        ; 車線の向き (1 = 左へ, 2 = 右へ)
        LD      HL,LANEOF
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      A,(HL)
        CP      1
        JR      NZ,.toright
        LD      (IX+CR_SIGN),1
        LD      (IX+CR_XLO),FW*16 & 0xFF
        LD      (IX+CR_XHI),FW*16 >> 8
        JR      .spd
.toright:
        LD      (IX+CR_SIGN),0
        LD      (IX+CR_XLO),0xE0        ; -32
        LD      (IX+CR_XHI),0xFF
.spd:
        LD      A,(TMPB0)
        LD      HL,LANESPEED
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      A,(HL)
        LD      (IX+CR_SPEED),A
        LD      A,4
        CALL    RANDMOD
        LD      (IX+CR_COLOR),A
        RET

; ---------------------------------------------------------------------
; MOVECAR - 車 1 台を動かし、当たりを見る
;   入力: IX = 車
; ---------------------------------------------------------------------
MOVECAR:
        ; 進む量 = (frac + speed) / 16
        LD      A,(IX+CR_FRAC)
        ADD     A,(IX+CR_SPEED)
        LD      B,A
        AND     0x0F
        LD      (IX+CR_FRAC),A
        LD      A,B
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        LD      E,A
        LD      D,0
        LD      L,(IX+CR_XLO)
        LD      H,(IX+CR_XHI)
        LD      A,(IX+CR_SIGN)
        OR      A
        JR      Z,.right
        XOR     A
        SBC     HL,DE
        JR      .store
.right:
        ADD     HL,DE
.store:
        LD      (IX+CR_XLO),L
        LD      (IX+CR_XHI),H
        ; 画面外に出たか
        LD      A,(IX+CR_SIGN)
        OR      A
        JR      Z,.chkright
        ; 左へ: x < -40 で消す
        BIT     7,H
        JR      Z,.alive
        LD      DE,-40
        XOR     A
        SBC     HL,DE
        JR      NC,.alive
        LD      (IX+CR_ACTIVE),0
        RET
.chkright:
        BIT     7,H
        JR      NZ,.alive               ; 左の画面外から入ってくるところ (x < 0)
        LD      DE,FW*16+8
        XOR     A
        SBC     HL,DE
        JR      C,.alive
        LD      (IX+CR_ACTIVE),0
        RET
.alive:
        ; --- 犬との当たり ---
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
        LD      IY,DOGS                 ; 犬は 32 バイトずつ並んでいる
.dlp:
        PUSH    BC
        LD      A,C
        LD      (CDID),A
        LD      A,(IY+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.dnext
        LD      A,(IY+D_INVULN)
        OR      A
        JR      NZ,.dnext
        LD      A,(IY+D_Y)
        CP      (IX+CR_ROW)
        JR      NZ,.dnext
        ; 横の重なり: car.x+30 > dog.x*16+2 かつ car.x+2 < dog.x*16+14
        ;   つまり -28 < car.x - dog.x*16 < 12。x は 29 まであるので 16 ビットで
        LD      L,(IY+D_X)
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        EX      DE,HL                   ; DE = dog.x*16
        LD      L,(IX+CR_XLO)
        LD      H,(IX+CR_XHI)
        XOR     A
        SBC     HL,DE
        LD      DE,28
        ADD     HL,DE                   ; 当たり: 0 < HL < 40
        LD      A,H
        OR      A
        JR      NZ,.dnext               ; 負 か 256 以上
        LD      A,L
        OR      A
        JR      Z,.dnext
        CP      40
        JR      NC,.dnext
        ; --- ひかれた ---
        LD      A,SFX_CARHIT
        CALL    SFXPLAY
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.enemyhit
        CALL    ACH
        DB      ACH_CAR_HIT
        LD      HL,S_OUCH
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,25
        LD      (MSGTIMER),A
        CALL    LOSELIFE
        POP     BC
        RET
.enemyhit:
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        CALL    MARKDIRTY
        CALL    RESPAWN
        LD      A,2*TICKHZ
        LD      (IY+D_INVULN),A
        LD      A,30
        LD      (IY+D_THINK),A
.dnext:
        POP     BC
        LD      DE,D_SIZE
        ADD     IY,DE
        INC     C
        DJNZ    .dlp
        RET

; ---------------------------------------------------------------------
; UPDATERAIN - 雨
;   5 秒の予告のあと降りだし、降りだした瞬間になわばりになっていない印が流れる
; ---------------------------------------------------------------------
UPDATERAIN:
        LD      HL,(RAINT)
        LD      A,H
        OR      L
        JR      Z,.nofall
        DEC     HL
        LD      (RAINT),HL
        LD      A,H
        OR      L
        RET     NZ
        CALL    PALNORMAL
        LD      HL,S_EMPTY
        LD      A,C_WHITE
        CALL    HUDMSG
        RET
.nofall:
        LD      HL,(RAINWARN)
        LD      A,H
        OR      L
        JR      Z,.nowarn
        DEC     HL
        LD      (RAINWARN),HL
        LD      A,H
        OR      L
        RET     NZ
        ; --- 降りだす ---
        LD      HL,4*TICKHZ
        LD      (RAINT),HL
        CALL    RANDB
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL                   ; 0..1020
        LD      DE,35*TICKHZ
        ADD     HL,DE
        LD      (RAINNEXT),HL
        CALL    WASHMARKS
        CALL    PALRAIN
        LD      HL,S_RAIN
        LD      A,C_BLUE
        CALL    HUDMSG
        LD      A,SFX_RAIN
        JP      SFXPLAY
.nowarn:
        LD      HL,(RAINNEXT)
        LD      A,H
        OR      L
        RET     Z
        DEC     HL
        LD      (RAINNEXT),HL
        LD      A,H
        OR      L
        RET     NZ
        LD      HL,5*TICKHZ
        LD      (RAINWARN),HL
        LD      HL,S_RAINCOME
        LD      A,C_YELLOW
        CALL    HUDMSG
        LD      A,SFX_THUNDER
        JP      SFXPLAY

; ---------------------------------------------------------------------
; WASHMARKS - なわばりになっていない印を全部流す
; ---------------------------------------------------------------------
WASHMARKS:
        LD      A,(NPOLES)
        OR      A
        JR      Z,.dogs
        XOR     A
        LD      (POLEI),A
.lp:
        LD      A,(POLEI)
        CALL    POLEPTR
        PUSH    HL
        POP     IX
        LD      A,(IX+PL_LOCKED)
        OR      A
        JR      NZ,.next
        LD      A,(IX+PL_OWNER)
        CP      0xFF
        JR      Z,.next
        LD      (IX+PL_OWNER),0xFF
        LD      B,(IX+PL_X)
        LD      C,(IX+PL_Y)
        CALL    MARKDIRTY
.next:
        LD      A,(POLEI)
        INC     A
        LD      (POLEI),A
        LD      HL,NPOLES
        CP      (HL)
        JR      C,.lp
.dogs:
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.dlp:
        PUSH    BC
        LD      A,C
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_CHAINN)
        OR      A
        JR      Z,.dn
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.dn2
        CALL    ACH
        DB      ACH_WASHED
        LD      HL,S_WASHED
        LD      A,C_BLUE
        CALL    HUDMSG
        LD      A,30
        LD      (MSGTIMER),A
.dn2:
        LD      (IY+D_CHAINN),0
.dn:
        LD      (IY+D_TARGET),0xFF
        LD      (IY+D_STUCK),0
        POP     BC
        INC     C
        DJNZ    .dlp
        RET

; ---------------------------------------------------------------------
; PALRAIN / PALNORMAL - 雨のあいだ地面の色を暗く青くする
; ---------------------------------------------------------------------
PALRAIN:
        LD      A,0x0B                  ; R=1 B=3
        OUT     (P_PAL0),A
        LD      A,0x41                  ; G=1
        OUT     (P_PAL0),A
        RET

PALNORMAL:
        LD      A,(PALDATA)
        OUT     (P_PAL0),A
        LD      A,(PALDATA+1)
        OUT     (P_PAL0),A
        LD      A,(PALDATA+10)          ; 濃い草 (色 5)
        OUT     (P_PAL0+5),A
        LD      A,(PALDATA+11)
        OUT     (P_PAL0+5),A
        RET

; タイトル: 草を暗くした背景 (元の版は草の上に 0x102018 を半分重ねている)
;   色 0 = 暗い草 / 色 5 = 少し明るい緑 (草の点・肉球・控えめな文字)
PALTITLE:
        LD      A,0x09                  ; R=1 B=1
        OUT     (P_PAL0),A
        LD      A,0x43                  ; G=3
        OUT     (P_PAL0),A
        LD      A,0x1B                  ; R=3 B=3
        OUT     (P_PAL0+5),A
        LD      A,0x45                  ; G=5
        OUT     (P_PAL0+5),A
        RET

; ---------------------------------------------------------------------
; UPDATEITEMS - アイテム
; ---------------------------------------------------------------------
UPDATEITEMS:
        ; --- 消える ---
        LD      IX,ITEMS
        LD      B,NITEM
.lp:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.next
        LD      L,(IX+IT_T)
        LD      H,(IX+IT_T+1)
        DEC     HL
        LD      (IX+IT_T),L
        LD      (IX+IT_T+1),H
        LD      A,H
        OR      L
        JR      NZ,.blink
        LD      (IX+IT_ACTIVE),0
        PUSH    BC
        LD      B,(IX+IT_X)
        LD      C,(IX+IT_Y)
        CALL    MARKDIRTY
        POP     BC
        JR      .next
.blink:
        ; 消える前は点滅させるのでマスを描き直し続ける
        LD      A,H
        OR      A
        JR      NZ,.next
        PUSH    BC
        LD      B,(IX+IT_X)
        LD      C,(IX+IT_Y)
        CALL    MARKDIRTY
        POP     BC
.next:
        PUSH    BC
        LD      BC,IT_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .lp

        ; --- 新しく出す ---
        LD      A,(BONUSMODE)
        OR      A
        JR      NZ,.pickup
        LD      A,(STAGE)
        CP      ITEMFROMSTAGE
        JR      C,.pickup
        LD      HL,(ITEMSPAWN)
        LD      A,H
        OR      L
        JR      Z,.pickup
        DEC     HL
        LD      (ITEMSPAWN),HL
        LD      A,H
        OR      L
        JR      NZ,.pickup
        CALL    RANDB
        LD      L,A
        LD      H,0
        ADD     HL,HL                   ; 0..510
        LD      DE,9*TICKHZ
        ADD     HL,DE
        LD      (ITEMSPAWN),HL
        CALL    SPAWNITEM

.pickup:
        ; --- 効果の時間と拾い上げ ---
        LD      A,(NDOGS)
        LD      B,A
        LD      C,0
.plp:
        PUSH    BC
        LD      A,C
        CALL    DOGADDR
        PUSH    HL
        POP     IY
        LD      A,(IY+D_FLAGS)
        AND     DF_ALIVE
        JR      Z,.pn
        ; 骨
        LD      L,(IY+D_BONET)
        LD      H,(IY+D_BONET+1)
        LD      A,H
        OR      L
        JR      Z,.nobone
        DEC     HL
        LD      (IY+D_BONET),L
        LD      (IY+D_BONET+1),H
.nobone:
        ; 巻物
        LD      L,(IY+D_PASST)
        LD      H,(IY+D_PASST+1)
        LD      A,H
        OR      L
        JR      Z,.nopass
        DEC     HL
        LD      (IY+D_PASST),L
        LD      (IY+D_PASST+1),H
        LD      A,H
        OR      L
        JR      NZ,.nopass
        ; 効果が切れた。他のなわばりの中にいたら放り出される
        LD      A,(IY+D_FLAGS)
        AND     DF_BOSS
        JR      NZ,.nopass
        LD      B,(IY+D_X)
        LD      C,(IY+D_Y)
        LD      DE,ARR_TERR
        CALL    CELLPTR
        LD      A,(HL)
        CP      0xFF
        JR      Z,.nopass
        CP      (IY+D_TERRID)
        JR      Z,.nopass
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.kick
        LD      HL,S_KICKED
        LD      A,C_BLUE
        CALL    HUDMSG
        LD      A,30
        LD      (MSGTIMER),A
        LD      A,SFX_KICKED
        CALL    SFXPLAY
.kick:
        CALL    RESPAWN
        LD      A,45
        LD      (IY+D_INVULN),A
.nopass:
        ; アイテムを踏んだか
        CALL    PICKITEM
.pn:
        POP     BC
        INC     C
        DJNZ    .plp
        RET

; ---------------------------------------------------------------------
; SPAWNITEM - アイテムを 1 つ出す
; ---------------------------------------------------------------------
SPAWNITEM:
        ; 2 つ以上あるなら出さない
        LD      IX,ITEMS
        LD      B,NITEM
        LD      C,0
.cnt:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.c2
        INC     C
.c2:
        PUSH    BC
        LD      BC,IT_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .cnt
        LD      A,C
        CP      NITEM
        RET     NC
        ; 空き枠
        LD      IX,ITEMS
        LD      B,NITEM
.find:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.got
        PUSH    BC
        LD      BC,IT_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .find
        RET
.got:
        LD      A,4
        CALL    FINDCELL
        LD      A,(FOUNDX)
        LD      B,A
        LD      A,(FOUNDY)
        LD      C,A
        PUSH    BC
        CALL    CELLFREE
        POP     BC
        OR      A
        RET     Z
        LD      (IX+IT_X),B
        LD      (IX+IT_Y),C
        LD      (IX+IT_ACTIVE),1
        LD      HL,ITEMLIFE
        LD      (IX+IT_T),L
        LD      (IX+IT_T+1),H
        PUSH    BC                      ; RANDMOD は BC を壊す
        LD      A,3
        CALL    RANDMOD
        OR      A
        LD      A,0
        JR      NZ,.kind
        LD      A,1
.kind:
        LD      (IX+IT_KIND),A
        POP     BC
        CALL    MARKDIRTY
        RET

; ---------------------------------------------------------------------
; PICKITEM - IY の犬がアイテムを踏んでいたら拾う
; ---------------------------------------------------------------------
PICKITEM:
        LD      IX,ITEMS
        LD      B,NITEM
.lp:
        LD      A,(IX+IT_ACTIVE)
        OR      A
        JR      Z,.next
        LD      A,(IX+IT_X)
        CP      (IY+D_X)
        JR      NZ,.next
        LD      A,(IX+IT_Y)
        CP      (IY+D_Y)
        JR      NZ,.next
        ; 拾った
        LD      (IX+IT_ACTIVE),0
        PUSH    BC
        LD      B,(IX+IT_X)
        LD      C,(IX+IT_Y)
        CALL    MARKDIRTY
        POP     BC
        LD      A,(IX+IT_KIND)
        OR      A
        JR      NZ,.scroll
        LD      HL,BONETIME
        LD      (IY+D_BONET),L
        LD      (IY+D_BONET+1),H
        CALL    ACHPL
        DB      ACH_BONE
        LD      DE,S_BONE
        JR      .msg
.scroll:
        LD      HL,PASSTIME
        LD      (IY+D_PASST),L
        LD      (IY+D_PASST+1),H
        LD      DE,S_NINJA
.msg:
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        JR      Z,.next
        EX      DE,HL
        LD      A,C_YELLOW
        CALL    HUDMSG
        LD      A,25
        LD      (MSGTIMER),A
        LD      HL,100
        CALL    ADDSCORE
        LD      A,SFX_ITEM
        CALL    SFXPLAY
.next:
        PUSH    BC
        LD      BC,IT_SIZE
        ADD     IX,BC
        POP     BC
        DJNZ    .lp
        RET
