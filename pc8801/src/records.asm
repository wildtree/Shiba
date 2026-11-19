; =====================================================================
; records.asm - ハイスコア表と実績
; =====================================================================
; 元の版の HiScores.cs / Achievements.cs と同じ内容を、ディスクの
; 1 セクタ (disk.asm) に保存する。
;   ・ハイスコアは上位 10 件 (名前 3 文字・点・ステージ)
;   ・実績は 24 個。取ったかどうかを 1 ビットずつ (日時は持たない)
;   ・「3 色の柴犬でクリア」の途中経過も 1 バイト
; 実績を取るとすぐに HUD に通知を出し、ディスクへはステージの切れ目で書く
; (ゲーム中にディスクを回すと止まって見えるため)。
; =====================================================================

ACH_N           EQU 24
ACH_FIRST_TURF     EQU 0
ACH_BIG_TURF       EQU 1
ACH_HALF           EQU 2
ACH_CATCH_DOG      EQU 3
ACH_DOUBLE_CATCH   EQU 4
ACH_BOSS_DOWN      EQU 5
ACH_GOT_CAUGHT     EQU 6
ACH_CAR_HIT        EQU 7
ACH_OVERWRITE      EQU 8
ACH_WASHED         EQU 9
ACH_BONE           EQU 10
ACH_NINJA          EQU 11
ACH_GIVE_UP        EQU 12
ACH_ONE_UP         EQU 13
ACH_NO_MISS        EQU 14
ACH_SPEEDY         EQU 15
ACH_STAGE4         EQU 16
ACH_STAGE8         EQU 17
ACH_STAGE16        EQU 18
ACH_BONUS_CLEAR    EQU 19
ACH_BONUS_PERFECT  EQU 20
ACH_SCORE_100K     EQU 21
ACH_ALL_SHIBA      EQU 22
ACH_HIGH_SCORE     EQU 23

; ---------------------------------------------------------------------
; HSRESET - ハイスコア表を最初の状態に、実績を全部なしに
; ---------------------------------------------------------------------
HSRESET:
        LD      HL,HSDEFAULT
        LD      DE,HISCORES
        LD      BC,10*8
        LDIR
        LD      HL,ACHBITS
        LD      BC,4
        XOR     A
        CALL    MEMFILL
        JP      HSSETTOP

; HSSETTOP - HISCORE (HUD とタイトルに出す値) = 1 位の点
HSSETTOP:
        LD      HL,(HISCORES)
        LD      (HISCORE),HL
        LD      A,(HISCORES+2)
        LD      (HISCORE+2),A
        RET

; 元の版と同じ最初の 10 件 (犬種の略称、10000 点から 1000 点ずつ)
HSDEFAULT:
        DB      0x10,0x27,0x00, "SHB", 1, 0
        DB      0x28,0x23,0x00, "KRO", 1, 0
        DB      0x40,0x1F,0x00, "SRO", 1, 0
        DB      0x58,0x1B,0x00, "CRG", 1, 0
        DB      0x70,0x17,0x00, "CHW", 1, 0
        DB      0x88,0x13,0x00, "SLT", 1, 0
        DB      0xA0,0x0F,0x00, "HSK", 1, 0
        DB      0xB8,0x0B,0x00, "PUG", 1, 0
        DB      0xD0,0x07,0x00, "DAL", 1, 0
        DB      0xE8,0x03,0x00, "BGL", 1, 0

; ---------------------------------------------------------------------
; CMP24 - 3 バイトの値 (HL) と (DE) を比べる
;   出力: CY = (HL) < (DE)。HL, DE は壊す
; ---------------------------------------------------------------------
CMP24:
        INC     HL
        INC     HL
        INC     DE
        INC     DE
        LD      A,(DE)
        CP      (HL)
        JR      NZ,.d
        DEC     HL
        DEC     DE
        LD      A,(DE)
        CP      (HL)
        JR      NZ,.d
        DEC     HL
        DEC     DE
        LD      A,(DE)
        CP      (HL)
        JR      NZ,.d
        OR      A                       ; 同じ: CY = 0
        RET
.d:
        CCF                             ; (DE) > (HL) なら CY
        RET

; ---------------------------------------------------------------------
; HIDISPPTR - HUD に出す HI の値 (1 位と今の点の大きいほう) -> HL
; ---------------------------------------------------------------------
HIDISPPTR:
        LD      HL,HISCORE
        LD      DE,SCORE
        CALL    CMP24
        LD      HL,HISCORE
        RET     NC
        LD      HL,SCORE
        RET

; ---------------------------------------------------------------------
; HSQUALIFY - いまの点 (SCORE) がハイスコア表に入るか。CY = 入る
;   HSNEW / HSSTAGE も用意する
; ---------------------------------------------------------------------
HSQUALIFY:
        LD      HL,SCORE
        LD      DE,HSNEW
        LD      BC,3
        LDIR
        LD      A,(STAGE)
        LD      (HSSTAGE),A
        LD      HL,(HSNEW)
        LD      A,(HSNEW+2)
        OR      H
        OR      L
        RET     Z                       ; 0 点は載せない (CY = 0)
        LD      HL,HISCORES+9*8
        LD      DE,HSNEW
        JP      CMP24

; ---------------------------------------------------------------------
; HSINSERT - HSNEW / HSNAME / HSSTAGE を表に入れる。A = 順位 (0..9)
;   同じ点なら前からいる人が上 (元の版と同じ)
; ---------------------------------------------------------------------
HSINSERT:
        LD      B,0
        LD      HL,HISCORES
.find:
        PUSH    HL
        LD      DE,HSNEW
        CALL    CMP24
        POP     HL
        JR      C,.found
        LD      DE,8
        ADD     HL,DE
        INC     B
        LD      A,B
        CP      10
        JR      C,.find
        LD      A,0xFF
        RET
.found:
        PUSH    BC
        PUSH    HL
        LD      A,9
        SUB     B
        JR      Z,.nomove
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      C,A
        LD      B,0
        LD      HL,HISCORES+9*8-1
        LD      DE,HISCORES+10*8-1
        LDDR
.nomove:
        POP     DE
        LD      HL,HSNEW
        LD      BC,7                    ; 点 3 + 名前 3 + ステージ 1
        LDIR
        XOR     A
        LD      (DE),A
        CALL    HSSETTOP
        POP     BC
        LD      A,B
        RET

; =====================================================================
; 実績
; =====================================================================

; ---------------------------------------------------------------------
; ACH - 実績を解除する。   CALL ACH / DB 番号
; ACHPL - IY の犬が柴犬のときだけ解除する。   CALL ACHPL / DB 番号
;   どちらもレジスタとフラグはすべて残す
; ---------------------------------------------------------------------
ACH:
        EX      (SP),HL
        PUSH    AF
        LD      A,(HL)
        INC     HL
        CALL    ACHUNLOCK
        POP     AF
        EX      (SP),HL
        RET

ACHPL:
        EX      (SP),HL
        PUSH    AF
        LD      A,(IY+D_FLAGS)
        AND     DF_PLAYER
        LD      A,(HL)
        INC     HL
        CALL    NZ,ACHUNLOCK
        POP     AF
        EX      (SP),HL
        RET

; ACHUNLOCK - 実績 A を解除する (デモでは何もしない)。BC, DE, HL は残す
ACHUNLOCK:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      C,A
        LD      A,(DEMOMODE)
        OR      A
        JR      NZ,.out
        LD      A,C
        LD      HL,ACHBITS
        CALL    BITPTR
        LD      A,(HL)
        AND     B
        JR      NZ,.out                 ; もう持っている
        LD      A,(HL)
        OR      B
        LD      (HL),A
        LD      A,1
        LD      (ACHDIRTY),A
        ; 通知の順番待ちにも入れる
        LD      DE,ACHQ-ACHBITS
        ADD     HL,DE
        LD      A,(HL)
        OR      B
        LD      (HL),A
        LD      A,SFX_ACHIEVE
        CALL    SFXPLAY
.out:
        POP     BC
        POP     DE
        POP     HL
        RET

; BITPTR - ビット列 HL の A 番目 -> HL = そのバイト, B = マスク (A, C を壊す)
BITPTR:
        LD      C,A
        AND     7
        LD      B,1
        JR      Z,.m
.s:
        SLA     B
        DEC     A
        JR      NZ,.s
.m:
        LD      A,C
        RRCA
        RRCA
        RRCA
        AND     0x1F
        ADD     A,L
        LD      L,A
        RET     NC
        INC     H
        RET

; ACHHAS - 実績 A を持っているか。NZ = 持っている
ACHHAS:
        PUSH    HL
        PUSH    BC
        LD      HL,ACHBITS
        CALL    BITPTR
        LD      A,(HL)
        AND     B
        POP     BC
        POP     HL
        RET

; ACHCOUNT - 解除した数 -> A
ACHCOUNT:
        LD      C,0
        LD      B,ACH_N
.lp:
        LD      A,B
        DEC     A
        PUSH    BC
        CALL    ACHHAS
        POP     BC
        JR      Z,.n
        INC     C
.n:
        DJNZ    .lp
        LD      A,C
        RET

; ACHSAVEIF - 変わっていればディスクに書く (ステージの切れ目で呼ぶ)
ACHSAVEIF:
        LD      A,(ACHDIRTY)
        OR      A
        RET     Z
        XOR     A
        LD      (ACHDIRTY),A
        JP      SAVEHISCORE

; ---------------------------------------------------------------------
; STAGECLEARACH - ステージを終えたときの実績 (元の版の StageClearAchievements)
; ---------------------------------------------------------------------
STAGECLEARACH:
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.normal
        CALL    ACH
        DB      ACH_BONUS_CLEAR
        LD      A,(PERFECT)
        OR      A
        RET     Z
        CALL    ACH
        DB      ACH_BONUS_PERFECT
        RET
.normal:
        LD      A,(STAGE)
        CP      4
        JR      NZ,.s8
        CALL    ACH
        DB      ACH_STAGE4
.s8:
        CP      8
        JR      NZ,.s16
        CALL    ACH
        DB      ACH_STAGE8
.s16:
        CP      16
        JR      NZ,.miss
        CALL    ACH
        DB      ACH_STAGE16
.miss:
        LD      A,(MISSES)
        OR      A
        JR      NZ,.speed
        CALL    ACH
        DB      ACH_NO_MISS
.speed:
        LD      A,(SECLEFT)
        CP      STAGETIME-120
        JR      C,.trio
        CALL    ACH
        DB      ACH_SPEEDY
.trio:
        ; 柴犬の 3 色それぞれでクリアしたか (途中経過は画面に出さない)
        LD      A,(DEMOMODE)
        OR      A
        RET     NZ
        LD      A,(SHIBACOLOR)
        LD      HL,ACHPROG
        CALL    BITPTR
        LD      A,(HL)
        OR      B
        CP      (HL)
        JR      Z,.had
        LD      (HL),A
        LD      A,1
        LD      (ACHDIRTY),A
.had:
        LD      A,(ACHPROG)
        AND     7
        CP      7
        RET     NZ
        CALL    ACH
        DB      ACH_ALL_SHIBA
        RET

; ---------------------------------------------------------------------
; ACHTOAST - 実績の通知を HUD に出す (ゲーム中に毎ティック呼ぶ)
;   アイコン + "UNLOCKED!" + 名前を 4 秒。たまっていれば順に出す
; ---------------------------------------------------------------------
TOAST_Y         EQU 168

ACHTOAST:
        LD      A,(ACHTT)
        OR      A
        JR      Z,.idle
        DEC     A
        LD      (ACHTT),A
        RET     NZ
        JP      TOASTCLR
.idle:
        LD      HL,ACHQ
        LD      A,(HL)
        INC     HL
        OR      (HL)
        INC     HL
        OR      (HL)
        RET     Z
        ; いちばん番号の小さいものを出す
        LD      E,0
.f:
        LD      A,E
        LD      HL,ACHQ
        CALL    BITPTR
        LD      A,(HL)
        AND     B
        JR      NZ,.got
        INC     E
        JR      .f
.got:
        LD      A,(HL)
        XOR     B
        LD      (HL),A
        LD      A,E
        LD      (ACHSHOW),A
        CALL    TOASTCLR
        LD      A,(ACHSHOW)
        LD      D,TOAST_Y
        LD      E,HUD_X+1
        CALL    ICONDRAW
        LD      A,C_YELLOW
        LD      (GFX_COL),A
        LD      HL,S_UNLOCKED
        LD      B,HUD_X+6
        LD      C,TOAST_Y
        CALL    DRAWSTR
        LD      A,C_WHITE
        LD      (GFX_COL),A
        LD      A,(ACHSHOW)
        LD      HL,ACHNAME
        CALL    PTRIDX
        LD      B,HUD_X+6
        LD      C,TOAST_Y+8
        CALL    DRAWSTR
        LD      A,4*TICKHZ
        LD      (ACHTT),A
        RET

TOASTCLR:
        LD      D,TOAST_Y
        LD      E,HUD_X+1
        LD      B,80-HUD_X-1
        LD      C,16
        LD      A,C_DARK
        JP      FILLRECT

; PTRIDX - HL = 表 HL の A 番目のポインタ
PTRIDX:
        ADD     A,A
        ADD     A,L
        LD      L,A
        JR      NC,.nc
        INC     H
.nc:
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        RET

; ---------------------------------------------------------------------
; ICONDRAW - 実績アイコン A (32x16) を (行 D, バイト列 E) に描く
;   色ごとの 1 ビットの絵を順に重ねる (tools/icons.py)
; ---------------------------------------------------------------------
ICONDRAW:
        LD      (IC_POS),DE
        LD      HL,ICONTBL
        CALL    PTRIDX
.layer:
        LD      A,(HL)
        CP      0xFF
        RET     Z
        INC     HL
        LD      C,A
        AND     7
        LD      (TXTCOL),A
        BIT     4,C
        JR      NZ,.native
        ; 16 ドット幅を横 2 倍にして TMPBUF へ
        LD      DE,TMPBUF
        LD      B,32
.d:
        LD      A,(HL)
        INC     HL
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        CALL    DBLNIB
        LD      (DE),A
        INC     DE
        POP     AF
        AND     0x0F
        CALL    DBLNIB
        LD      (DE),A
        INC     DE
        DJNZ    .d
        PUSH    HL
        LD      HL,TMPBUF
        JR      .blit
.native:
        LD      DE,64
        PUSH    HL
        ADD     HL,DE
        EX      (SP),HL                 ; (SP) = 次の色, HL = この色の絵
.blit:
        LD      DE,(IC_POS)
        LD      B,4
        LD      C,16
        CALL    BLIT1
        POP     HL
        JR      .layer

; =====================================================================
; メニュー画面の共通部品
; =====================================================================

; MENUBACK - 暗い草の背景 (タイトルと同じ)
MENUBACK:
        CALL    CLS
        CALL    PALTITLE
        LD      B,0
        LD      C,0
        LD      D,40
        LD      E,25
        JP      TPAINT

; MBOX - 紺の箱 + 白い枠。D = 行, E = バイト列, B = 幅, C = 高さ
MBOX:
        PUSH    DE
        PUSH    BC
        LD      A,C_DARK
        CALL    FILLRECT
        POP     BC
        POP     DE
        LD      A,C_WHITE
        LD      (TXTCOL),A
        JP      FRAME

; MTEXT - 色 A で HL を (バイト列 B, 行 C) に。影なし
MTEXT:
        LD      (TXTCOL),A
        XOR     A
        LD      (TXTFLG),A
        JP      TXT

; MCENTER - 色 A で HL を行 C の真ん中に。E = TXTFLG (bit0 = 横 2 倍)
MCENTER:
        PUSH    AF
        LD      A,E
        LD      (TXTFLG),A
        POP     AF
        JP      TXTCOLC

; MENUWAIT - 1 ティック待って入力と音を進める
MENUWAIT:
        CALL    WAITVSYNC
        LD      HL,(FRAMECNT)
        INC     HL
        LD      (FRAMECNT),HL
        CALL    READKEYS
        JP      SNDTICK

; ANYPRESS - 何かのキーが新しく押されたか (NZ = 押された)
ANYPRESS:
        LD      HL,KEYNOW
        LD      DE,KEYPREV
        LD      B,15
.lp:
        LD      A,(DE)
        CPL
        AND     (HL)
        RET     NZ
        INC     HL
        INC     DE
        DJNZ    .lp
        XOR     A
        RET

; ---------------------------------------------------------------------
; HSSCREEN - ハイスコア表 (元の版の DrawHiScores)
;   入力: NEWRANK (0xFF = なし), HSVIEW = 出しておくティック数
;   出力: NZ = キーで抜けた / Z = 時間切れ
; ---------------------------------------------------------------------
HS_ROW0         EQU 53
HS_X            EQU 27

HSSCREEN:
        CALL    MENUBACK
        LD      D,15
        LD      E,17
        LD      B,46
        LD      C,166
        CALL    MBOX
        LD      A,C_YELLOW
        LD      HL,S_HS_TITLE
        LD      C,22
        LD      E,1
        CALL    MCENTER
        LD      A,C_BLUE
        LD      HL,S_HS_HEAD
        LD      B,HS_X
        LD      C,43
        CALL    MTEXT
        XOR     A
.rows:
        PUSH    AF
        CALL    HSROW
        POP     AF
        INC     A
        CP      10
        JR      C,.rows
        LD      A,C_BLUE
        LD      HL,S_ANYKEY
        LD      C,169
        LD      E,0
        CALL    MCENTER
        CALL    READKEYS
.loop:
        CALL    MENUWAIT
        ; 新しく入った順位を点滅させる
        LD      A,(NEWRANK)
        CP      10
        JR      NC,.noblink
        LD      A,(FRAMECNT)
        AND     7
        JR      NZ,.noblink
        LD      A,(NEWRANK)
        CALL    HSROW
.noblink:
        CALL    ANYPRESS
        RET     NZ
        LD      HL,(HSVIEW)
        DEC     HL
        LD      (HSVIEW),HL
        LD      A,H
        OR      L
        JR      NZ,.loop
        RET

; HSROW - A 位の行を描く ("  1.   SHB     10000     1")
HSROW:
        LD      (HS_I),A
        ; 色: 新しく入った行は黄と白の点滅 / 1 位は橙 / ほかは白
        LD      C,C_WHITE
        OR      A
        JR      NZ,.c1
        LD      C,C_ORANGE
.c1:
        LD      HL,NEWRANK
        CP      (HL)
        JR      NZ,.c2
        LD      C,C_YELLOW
        LD      A,(FRAMECNT)
        AND     8
        JR      Z,.c2
        LD      C,C_WHITE
.c2:
        LD      A,C
        LD      (HS_COL),A
        ; 行を消す
        LD      A,(HS_I)
        LD      B,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,B
        ADD     A,B
        ADD     A,B                     ; *11
        ADD     A,HS_ROW0
        LD      (HS_Y),A
        LD      D,A
        LD      E,HS_X
        LD      B,26
        LD      C,8
        LD      A,C_DARK
        CALL    FILLRECT
        ; 文字列を作る
        LD      HL,STRBUF
        LD      B,26
.sp:
        LD      (HL),' '
        INC     HL
        DJNZ    .sp
        LD      (HL),0
        LD      A,(HS_I)
        INC     A
        LD      L,A
        LD      H,0
        LD      DE,TMPBUF
        LD      B,3
        CALL    NUMSTR
        LD      HL,TMPBUF
        LD      DE,STRBUF
        LD      BC,3
        LDIR
        LD      A,'.'
        LD      (STRBUF+3),A
        ; 名前と点とステージ
        LD      A,(HS_I)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      L,A
        LD      H,0
        LD      DE,HISCORES
        ADD     HL,DE
        LD      (HS_P),HL
        INC     HL
        INC     HL
        INC     HL
        LD      DE,STRBUF+7
        LD      BC,3
        LDIR
        LD      HL,(HS_P)
        LD      DE,TMPBUF
        LD      B,7
        CALL    NUMSTR24
        LD      HL,TMPBUF
        LD      DE,STRBUF+13
        LD      BC,7
        LDIR
        LD      HL,(HS_P)
        LD      DE,6
        ADD     HL,DE
        LD      L,(HL)
        LD      H,0
        LD      DE,TMPBUF
        LD      B,2
        CALL    NUMSTR
        LD      HL,TMPBUF
        LD      DE,STRBUF+24
        LD      BC,2
        LDIR
        LD      A,(HS_COL)
        LD      HL,STRBUF
        LD      B,HS_X
        LD      A,(HS_Y)
        LD      C,A
        LD      A,(HS_COL)
        JP      MTEXT

; ---------------------------------------------------------------------
; NAMEENTRY - 名前 (イニシャル 3 文字) を入れて表に載せる (元の版の NameEntry)
;   HSQUALIFY のあとに呼ぶ。出力: NEWRANK
; ---------------------------------------------------------------------
NE_SLOTX        EQU 29          ; 1 文字目の箱 (バイト列)。8 バイトおき
NE_SLOTY        EQU 89
NE_SLOTH        EQU 28

NAMEENTRY:
        LD      HL,HSNAME
        LD      (HL),'A'
        INC     HL
        LD      (HL),'A'
        INC     HL
        LD      (HL),'A'
        XOR     A
        LD      (NAMEPOS),A
        CALL    MENUBACK
        LD      D,40
        LD      E,15
        LD      B,50
        LD      C,120
        CALL    MBOX
        LD      A,C_YELLOW
        LD      HL,S_NE_TITLE
        LD      C,47
        LD      E,1
        CALL    MCENTER
        ; "SCORE 0012345   STAGE  3"
        LD      HL,S_NE_SCORE
        LD      DE,STRBUF
        LD      BC,S_NE_SCORE_END-S_NE_SCORE
        LDIR
        LD      HL,HSNEW
        LD      DE,TMPBUF
        LD      B,7
        CALL    NUMSTR24
        LD      HL,TMPBUF
        LD      DE,STRBUF+6
        LD      BC,7
        LDIR
        LD      A,(HSSTAGE)
        LD      L,A
        LD      H,0
        LD      DE,TMPBUF
        LD      B,2
        CALL    NUMSTR
        LD      HL,TMPBUF
        LD      DE,STRBUF+22
        LD      BC,2
        LDIR
        LD      A,C_WHITE
        LD      HL,STRBUF
        LD      C,59
        LD      E,0
        CALL    MCENTER
        LD      A,C_BLUE
        LD      HL,S_NE_ENTER
        LD      C,71
        LD      E,0
        CALL    MCENTER
        LD      A,C_BLUE
        LD      HL,S_NE_HELP1
        LD      C,130
        LD      E,0
        CALL    MCENTER
        LD      A,C_BLUE
        LD      HL,S_NE_HELP2
        LD      C,141
        LD      E,0
        CALL    MCENTER
        ; 選んだ柴犬 (元の版と同じく右に大きく)
        LD      A,(SHIBACOLOR)
        CALL    BREEDPTR
        INC     HL
        INC     HL
        LD      A,(HL)
        LD      D,90
        LD      E,54
        CALL    DRAWBIG
        XOR     A
        CALL    NESLOT
        LD      A,1
        CALL    NESLOT
        LD      A,2
        CALL    NESLOT
        CALL    READKEYS
.loop:
        CALL    MENUWAIT
        LD      A,(FRAMECNT)
        AND     7
        JR      NZ,.keys
        CALL    NEARROWS                ; 矢印の点滅
.keys:
        ; 上下: 文字を変える
        CALL    KEYUP
        JR      Z,.nu
        LD      C,1
        JR      .change
.nu:
        CALL    KEYDOWN
        JR      Z,.nd
        LD      C,NAMECHARS_N-1
.change:
        CALL    NECURCHAR               ; HL = いまの文字の場所, A = 文字
        PUSH    HL
        LD      HL,NAMECHARS
        LD      B,0
.fi:
        CP      (HL)
        JR      Z,.fo
        INC     HL
        INC     B
        LD      E,A
        LD      A,B
        CP      NAMECHARS_N
        LD      A,E
        JR      C,.fi
        LD      B,0
.fo:
        LD      A,B
        ADD     A,C
.md:
        CP      NAMECHARS_N
        JR      C,.mk
        SUB     NAMECHARS_N
        JR      .md
.mk:
        LD      E,A
        LD      D,0
        LD      HL,NAMECHARS
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        LD      (HL),A
        CALL    NESELECT
        LD      A,(NAMEPOS)
        CALL    NESLOT
        JR      .loop
.nd:
        ; 左右: 動く
        CALL    KEYLEFT
        JR      Z,.nl
        LD      A,(NAMEPOS)
        OR      A
        JR      Z,.loop
        DEC     A
        CALL    NEMOVE
        JR      .loop
.nl:
        CALL    KEYRIGHT
        JR      Z,.nr
        LD      A,(NAMEPOS)
        CP      2
        JR      NC,.loop
        INC     A
        CALL    NEMOVE
        JR      .loop
.nr:
        ; 決定: RETURN / SPACE
        LD      B,K_RET_P
        LD      C,K_RET_B
        CALL    KEYHIT
        JR      NZ,.ok
        LD      B,K_SPACE_P
        LD      C,K_SPACE_B
        CALL    KEYHIT
        JR      NZ,.ok
        ; 文字を打った
        CALL    TYPEDKEY
        OR      A
        JP      Z,.loop
        PUSH    AF
        CALL    NECURCHAR
        POP     AF
        LD      (HL),A
        CALL    NESELECT
        LD      A,(NAMEPOS)
        CALL    NESLOT
        LD      A,(NAMEPOS)
        CP      2
        JP      NC,.loop
        INC     A
        CALL    NEMOVE
        JP      .loop
.ok:
        LD      A,(NAMEPOS)
        CP      2
        JR      NC,.done
        INC     A
        CALL    NEMOVE
        JP      .loop
.done:
        CALL    HSINSERT
        LD      (NEWRANK),A
        CALL    ACH
        DB      ACH_HIGH_SCORE
        LD      A,SFX_NAMEOK
        CALL    SFXPLAY
        LD      A,1
        LD      (ACHDIRTY),A
        RET

NESELECT:
        LD      A,SFX_SELECT
        JP      SFXPLAY

; NECURCHAR - HL = いま選んでいる文字の場所, A = その文字
NECURCHAR:
        LD      A,(NAMEPOS)
        LD      E,A
        LD      D,0
        LD      HL,HSNAME
        ADD     HL,DE
        LD      A,(HL)
        RET

; NEMOVE - 選んでいる箱を A に (前の箱は枠の色を戻す)
NEMOVE:
        PUSH    AF
        LD      A,(NAMEPOS)
        LD      B,A
        POP     AF
        LD      (NAMEPOS),A
        PUSH    AF
        LD      A,B
        CALL    NESLOT
        POP     AF
        CALL    NESLOT
        JP      NESELECT

; NESLOT - A 番目の箱 (枠・文字・矢印) を描く
NESLOT:
        LD      (NE_I),A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,NE_SLOTX
        LD      (NE_X),A
        ; 箱と矢印のあたりを消す
        LD      D,NE_SLOTY-9
        LD      E,A
        LD      B,6
        LD      C,NE_SLOTH+18
        LD      A,C_DARK
        CALL    FILLRECT
        ; 枠 (選んでいれば黄色)
        LD      A,(NE_I)
        LD      HL,NAMEPOS
        CP      (HL)
        LD      A,C_BLUE
        JR      NZ,.fc
        LD      A,C_YELLOW
.fc:
        LD      (TXTCOL),A
        LD      D,NE_SLOTY
        LD      A,(NE_X)
        LD      E,A
        LD      B,6
        LD      C,NE_SLOTH
        CALL    FRAME
        ; 大きな文字 (横 4 倍・縦 2 倍)
        LD      A,(NE_I)
        LD      E,A
        LD      D,0
        LD      HL,HSNAME
        ADD     HL,DE
        LD      A,(HL)
        LD      D,NE_SLOTY+6
        LD      HL,NE_X
        LD      E,(HL)
        INC     E
        CALL    BIGCHAR
        LD      A,(NE_I)
        LD      HL,NAMEPOS
        CP      (HL)
        RET     NZ
        LD      A,1
        LD      (NE_ARROW),A
        JR      NEARROW1

; NEARROWS - 選んでいる箱の上下の矢印を点滅させる
NEARROWS:
        LD      A,(NE_ARROW)
        XOR     1
        LD      (NE_ARROW),A
        LD      A,(NAMEPOS)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,NE_SLOTX
        LD      (NE_X),A
NEARROW1:
        LD      A,(NE_X)
        LD      E,A
        LD      D,NE_SLOTY-9
        LD      B,6
        LD      C,8
        LD      A,C_DARK
        CALL    FILLRECT
        LD      A,(NE_X)
        LD      E,A
        LD      D,NE_SLOTY+NE_SLOTH+1
        LD      B,6
        LD      C,8
        LD      A,C_DARK
        CALL    FILLRECT
        LD      A,(NE_ARROW)
        OR      A
        RET     Z
        LD      A,1
        LD      (TXTFLG),A
        LD      A,C_YELLOW
        LD      (TXTCOL),A
        LD      HL,S_NE_UP
        LD      A,(NE_X)
        ADD     A,2
        LD      B,A
        LD      C,NE_SLOTY-9
        CALL    TXT
        LD      HL,S_NE_DN
        LD      A,(NE_X)
        ADD     A,2
        LD      B,A
        LD      C,NE_SLOTY+NE_SLOTH+1
        JP      TXT

; ---------------------------------------------------------------------
; BIGCHAR - 文字 A を横 4 倍・縦 2 倍 (32x16) の白で (行 D, バイト列 E) に
; ---------------------------------------------------------------------
BIGCHAR:
        PUSH    DE
        CALL    FONTADDR                ; HL = 8 行の点
        LD      DE,TMPBUF
        LD      B,8
.row:
        PUSH    BC
        LD      A,(HL)
        INC     HL
        PUSH    HL
        LD      C,A
        ; 上の 4 ドット -> 16 ドット
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        CALL    DBLNIB
        CALL    .x2
        ; 下の 4 ドット
        LD      A,C
        AND     0x0F
        CALL    DBLNIB
        CALL    .x2
        ; 同じ行をもう 1 行
        LD      H,D
        LD      L,E
        LD      BC,-4
        ADD     HL,BC
        LD      BC,4
        LDIR
        POP     HL
        POP     BC
        DJNZ    .row
        POP     DE
        LD      A,C_WHITE
        LD      (TXTCOL),A
        LD      HL,TMPBUF
        LD      B,4
        LD      C,16
        JP      BLIT1
; .x2 - 8 ビット A をさらに横 2 倍して (DE) に 2 バイト
.x2:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        CALL    DBLNIB
        LD      (DE),A
        INC     DE
        POP     AF
        AND     0x0F
        CALL    DBLNIB
        LD      (DE),A
        INC     DE
        RET

; ---------------------------------------------------------------------
; TYPEDKEY - 英字・数字のキーが新しく押されたら A = その文字 (なければ 0)
; ---------------------------------------------------------------------
TYPEDKEY:
        LD      C,2                     ; ポート 2..7
        LD      HL,KEYCHARS
.p:
        PUSH    HL
        LD      HL,KEYNOW
        LD      B,0
        ADD     HL,BC
        LD      A,(HL)
        LD      HL,KEYPREV
        ADD     HL,BC
        LD      B,A
        LD      A,(HL)
        CPL
        AND     B                       ; 新しく押されたビット
        POP     HL
        JR      NZ,.hit
        LD      DE,8
        ADD     HL,DE
        INC     C
        LD      A,C
        CP      8
        JR      C,.p
        XOR     A
        RET
.hit:
        RRA
        JR      C,.ch
        INC     HL
        JR      .hit
.ch:
        LD      A,(HL)
        RET

; キーマトリクスのポート 2..7 の文字 (使わないキーは 0)
KEYCHARS:
        DB      0,"ABCDEFG"
        DB      "HIJKLMNO"
        DB      "PQRSTUVW"
        DB      "XYZ",0,0,0,0,0
        DB      "01234567"
        DB      "89",0,0,0,".",0,0

NAMECHARS:      DB      "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!? "
NAMECHARS_N     EQU 40

; ---------------------------------------------------------------------
; ACHSCREEN - 実績の一覧 (元の版の DrawAchievements)。8 列 x 3 行
; ---------------------------------------------------------------------
AC_X0           EQU 8           ; 台座の左 (バイト列)。8 バイトおき
AC_Y0           EQU 37          ; 台座の上 (行)。32 行おき
AC_DESCY        EQU 134

ACHSCREEN:
        CALL    MENUBACK
        LD      D,5
        LD      E,5
        LD      B,70
        LD      C,190
        CALL    MBOX
        LD      A,C_YELLOW
        LD      HL,S_AC_TITLE
        LD      C,11
        LD      E,1
        CALL    MCENTER
        ; "nn / 24 UNLOCKED"
        CALL    ACHCOUNT
        LD      L,A
        LD      H,0
        LD      DE,STRBUF
        LD      B,2
        CALL    NUMSTR
        LD      HL,S_AC_COUNT
        LD      DE,STRBUF+2
        LD      BC,S_AC_COUNT_END-S_AC_COUNT
        LDIR
        LD      A,C_BLUE
        LD      HL,STRBUF
        LD      C,24
        LD      E,0
        CALL    MCENTER
        ; 台座
        XOR     A
.pl:
        PUSH    AF
        CALL    ACPLATE
        POP     AF
        INC     A
        CP      ACH_N
        JR      C,.pl
        ; 説明の箱
        LD      A,C_BLUE
        LD      (TXTCOL),A
        LD      D,AC_DESCY
        LD      E,8
        LD      B,64
        LD      C,42
        CALL    FRAME
        LD      A,C_BLUE
        LD      HL,S_AC_HELP
        LD      C,183
        LD      E,0
        CALL    MCENTER
        XOR     A
        LD      (ACHCUR),A
        CALL    ACDESC
        LD      HL,60*TICKHZ
        LD      (HSVIEW),HL
        CALL    READKEYS
.loop:
        CALL    MENUWAIT
        ; 説明の描きなおし (1 ティックに 1 行。描いているあいだもキーを読めるように)
        LD      A,(AC_STEP)
        OR      A
        CALL    NZ,ACDESCSTEP
        ; カーソルの点滅
        LD      A,(FRAMECNT)
        AND     7
        JR      NZ,.keys
        LD      A,(FRAMECNT)
        AND     8
        LD      A,C_WHITE
        JR      Z,.bc
        LD      A,C_YELLOW
.bc:
        CALL    ACCURSOR
.keys:
        ; 抜ける: ESC / SPACE / RETURN
        LD      B,K_ESC_P
        LD      C,K_ESC_B
        CALL    KEYHIT
        JR      NZ,.back
        CALL    ANYKEY
        JR      NZ,.back
        ; 動かす
        CALL    KEYUP
        JR      Z,.nu
        LD      A,(ACHCUR)
        SUB     8
        JR      NC,.set
        ADD     A,ACH_N
        JR      .set
.nu:
        CALL    KEYDOWN
        JR      Z,.nd
        LD      A,(ACHCUR)
        ADD     A,8
        CP      ACH_N
        JR      C,.set
        SUB     ACH_N
        JR      .set
.nd:
        CALL    KEYLEFT
        JR      Z,.nl
        LD      A,(ACHCUR)
        LD      B,A
        AND     7
        LD      A,B
        JR      NZ,.l1
        ADD     A,8
.l1:
        DEC     A
        JR      .set
.nl:
        CALL    KEYRIGHT
        JR      Z,.time
        LD      A,(ACHCUR)
        LD      B,A
        INC     A
        AND     7
        LD      A,B
        JR      NZ,.r1
        SUB     8
.r1:
        INC     A
.set:
        PUSH    AF
        LD      A,C_DARK
        CALL    ACCURSOR                ; 前の枠を消す
        POP     AF
        LD      (ACHCUR),A
        LD      A,C_WHITE
        CALL    ACCURSOR
        LD      A,1
        LD      (AC_STEP),A             ; 説明はつぎのティックから少しずつ描きなおす
        CALL    NESELECT
        JP      .loop
.time:
        LD      HL,(HSVIEW)
        DEC     HL
        LD      (HSVIEW),HL
        LD      A,H
        OR      L
        JP      NZ,.loop
.back:
        LD      A,SFX_SELECT
        JP      SFXPLAY

; ACPLATE - A 番目の台座 (取っていればアイコン、まだなら ?)
ACPLATE:
        LD      (AC_I),A
        CALL    ACPOS                   ; D = 行, E = バイト列
        PUSH    DE
        LD      A,(AC_I)
        CALL    ACHHAS
        POP     DE
        JR      Z,.locked
        LD      A,C_YELLOW
        LD      (TXTCOL),A
        PUSH    DE
        LD      B,6
        LD      C,20
        CALL    FRAME
        POP     DE
        LD      A,D
        ADD     A,2
        LD      D,A
        INC     E
        LD      A,(AC_I)
        JP      ICONDRAW
.locked:
        LD      A,C_BLUE
        LD      (TXTCOL),A
        PUSH    DE
        LD      B,6
        LD      C,20
        CALL    FRAME
        POP     DE
        LD      A,1
        LD      (TXTFLG),A
        LD      A,C_BLUE
        LD      (TXTCOL),A
        LD      HL,S_AC_Q
        LD      A,E
        ADD     A,2
        LD      B,A
        LD      A,D
        ADD     A,6
        LD      C,A
        JP      TXT

; ACPOS - A 番目の台座の位置 -> D = 行, E = バイト列
ACPOS:
        LD      B,A
        AND     7
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,AC_X0
        LD      E,A
        LD      A,B
        RRCA
        RRCA
        RRCA
        AND     3
        RRCA
        RRCA
        RRCA                            ; *32
        ADD     A,AC_Y0
        LD      D,A
        RET

; ACCURSOR - 選んでいる台座 (ACHCUR) のまわりに色 A の二重線
ACCURSOR:
        LD      (TXTCOL),A
        LD      A,(ACHCUR)
        CALL    ACPOS
        LD      A,D
        SUB     3
        LD      D,A
        DEC     E
        PUSH    DE
        LD      B,8
        LD      C,26
        CALL    FRAME
        POP     DE
        INC     D
        LD      B,8
        LD      C,24
        JP      FRAME

; ACDESC - 選んでいる実績の名前・条件を全部描く
ACDESC:
        LD      A,1
        LD      (AC_STEP),A
.lp:
        CALL    ACDESCSTEP
        LD      A,(AC_STEP)
        OR      A
        JR      NZ,.lp
        RET

;ACDESCSTEP - 説明を 1 行だけ描きなおす (AC_STEP: 1 名前 / 2 条件 / 3 状態 -> 0)
;   全部まとめて描くと 6 フレームほどかかり、そのあいだの短いキー操作を
;   取りこぼすので、ティックごとに 1 行ずつ「その行の帯を消して描く」。
ACDESCSTEP:
        LD      A,(AC_STEP)
        LD      B,A
        INC     A
        CP      4
        JR      C,.st
        XOR     A
.st:
        LD      (AC_STEP),A
        DJNZ    .n2
        ; 1: 名前 (横 2 倍)
        LD      D,AC_DESCY+5
        CALL    .band
        LD      A,(ACHCUR)
        CALL    ACHHAS
        LD      HL,S_AC_Q6
        LD      A,C_BLUE
        JR      Z,.l2
        LD      A,(ACHCUR)
        LD      HL,ACHNAME
        CALL    PTRIDX
        LD      A,C_WHITE
.l2:
        LD      C,AC_DESCY+5
        LD      E,1
        JP      MCENTER
.n2:
        DJNZ    .n3
        ; 2: 条件
        LD      D,AC_DESCY+18
        CALL    .band
        LD      A,(ACHCUR)
        CALL    ACHHAS
        LD      HL,S_AC_Q18
        LD      A,C_BLUE
        JR      Z,.l3
        LD      A,(ACHCUR)
        LD      HL,ACHDESC
        CALL    PTRIDX
        LD      A,C_WHITE
.l3:
        LD      C,AC_DESCY+18
        LD      E,0
        JP      MCENTER
.n3:
        ; 3: 取ったかどうか
        LD      D,AC_DESCY+29
        CALL    .band
        LD      A,(ACHCUR)
        CALL    ACHHAS
        LD      HL,S_AC_LOCK
        LD      A,C_BLUE
        JR      Z,.l4
        LD      HL,S_AC_UNL
        LD      A,C_YELLOW
.l4:
        LD      C,AC_DESCY+29
        LD      E,0
        JP      MCENTER
; .band - 行 D から 8 行 (+影の 1 行) の帯を消す
.band:
        LD      E,9
        LD      B,62
        LD      C,9
        LD      A,C_DARK
        JP      FILLRECT

; ---------------------------------------------------------------------
; 文字列
; ---------------------------------------------------------------------
S_UNLOCKED:     DB      "UNLOCKED!",0
S_HS_TITLE:     DB      "HIGH SCORES",0
S_HS_HEAD:      DB      "RANK  NAME    SCORE  STAGE",0
S_ANYKEY:       DB      "PRESS ANY KEY",0
S_NE_TITLE:     DB      "YOU GOT A HIGH SCORE!",0
S_NE_SCORE:     DB      "SCORE 0000000   STAGE 00",0
S_NE_SCORE_END:
S_NE_ENTER:     DB      "ENTER YOUR INITIALS",0
S_NE_HELP1:     DB      "UP/DOWN OR TYPE: LETTER",0
S_NE_HELP2:     DB      "LEFT/RIGHT: MOVE   RETURN: OK",0
S_NE_UP:        DB      "^",0
S_NE_DN:        DB      "v",0
S_AC_TITLE:     DB      "ACHIEVEMENTS",0
S_AC_COUNT:     DB      " / 24 UNLOCKED",0
S_AC_COUNT_END:
S_AC_HELP:      DB      "ARROWS/2468: SELECT    ESC / SPACE: BACK",0
S_AC_Q:         DB      "?",0
S_AC_Q6:        DB      "??????",0
S_AC_Q18:       DB      "??????????????????",0
S_AC_UNL:       DB      "UNLOCKED",0
S_AC_LOCK:      DB      "LOCKED",0

ACHNAME:
        DW      AN_0, AN_1, AN_2, AN_3, AN_4, AN_5
        DW      AN_6, AN_7, AN_8, AN_9, AN_10, AN_11
        DW      AN_12, AN_13, AN_14, AN_15, AN_16, AN_17
        DW      AN_18, AN_19, AN_20, AN_21, AN_22, AN_23
ACHDESC:
        DW      AD_0, AD_1, AD_2, AD_3, AD_4, AD_5
        DW      AD_6, AD_7, AD_8, AD_9, AD_10, AD_11
        DW      AD_12, AD_13, AD_14, AD_15, AD_16, AD_17
        DW      AD_18, AD_19, AD_20, AD_21, AD_22, AD_23
AN_0:
        DB      "MY FIRST TURF",0
AD_0:
        DB      "CLAIM YOUR FIRST TERRITORY.",0
AN_1:
        DB      "BIG TURF",0
AD_1:
        DB      "CLAIM 100 OR MORE TILES AT ONCE.",0
AN_2:
        DB      "HALF THE TOWN",0
AD_2:
        DB      "OWN HALF OF THE FIELD IN ONE STAGE.",0
AN_3:
        DB      "GOTCHA!",0
AD_3:
        DB      "SURROUND ANOTHER DOG WITH YOUR TERRITORY.",0
AN_4:
        DB      "DOUBLE CATCH",0
AD_4:
        DB      "SURROUND TWO OR MORE DOGS AT ONCE.",0
AN_5:
        DB      "GIANT SLAYER",0
AD_5:
        DB      "SURROUND THE BOSS DOG.",0
AN_6:
        DB      "SURROUNDED...",0
AD_6:
        DB      "GET SURROUNDED BY ANOTHER DOG",0x27,"S TERRITORY.",0
AN_7:
        DB      "WATCH THE ROAD",0
AD_7:
        DB      "GET HIT BY A CAR.",0
AN_8:
        DB      "MY POLE NOW",0
AD_8:
        DB      "PEE OVER ANOTHER DOG",0x27,"S MARK.",0
AN_9:
        DB      "WASHED AWAY",0
AD_9:
        DB      "HAVE YOUR MARKS WASHED AWAY BY THE RAIN.",0
AN_10:
        DB      "GOOD BOY",0
AD_10:
        DB      "PICK UP A BONE.",0
AN_11:
        DB      "NINJA DOG",0
AD_11:
        DB      "WALK THROUGH ANOTHER DOG",0x27,"S TERRITORY.",0
AN_12:
        DB      "I GIVE UP",0
AD_12:
        DB      "GIVE UP A STAGE FROM THE PAUSE MENU.",0
AN_13:
        DB      "ONE MORE LIFE",0
AD_13:
        DB      "EARN AN EXTRA LIFE.",0
AN_14:
        DB      "FLAWLESS",0
AD_14:
        DB      "CLEAR A STAGE WITHOUT A SINGLE MISS.",0
AN_15:
        DB      "SPEED RUN",0
AD_15:
        DB      "CLEAR A STAGE WITHIN 2 MINUTES.",0
AN_16:
        DB      "STAGE 4 CLEAR",0
AD_16:
        DB      "CLEAR STAGE 4.",0
AN_17:
        DB      "STAGE 8 CLEAR",0
AD_17:
        DB      "CLEAR STAGE 8.",0
AN_18:
        DB      "STAGE 16 CLEAR",0
AD_18:
        DB      "CLEAR STAGE 16.",0
AN_19:
        DB      "NIGHT WALK",0
AD_19:
        DB      "FINISH A BONUS STAGE.",0
AN_20:
        DB      "SWEET DREAMS",0
AD_20:
        DB      "SURROUND ALL THE SLEEPING DOGS IN A BONUS STAGE.",0
AN_21:
        DB      "BIG SCORE",0
AD_21:
        DB      "SCORE 100,000 POINTS IN ONE GAME.",0
AN_22:
        DB      "SHIBA TRIO",0
AD_22:
        DB      "CLEAR A STAGE WITH ALL THREE SHIBA COLORS.",0
AN_23:
        DB      "HALL OF FAME",0
AD_23:
        DB      "ENTER YOUR NAME IN THE HIGH SCORE TABLE.",0
