; =====================================================================
; game.asm - 柴犬陣取り PC-8801mkIISR (V2 モード) 版  本体
; =====================================================================
;   もとの .NET + SDL3 版 (ShibaJintori) を Z80 の機械語に移植したもの。
;   画面は 640x200 8 色、1 マス 16x8 ドット、フィールドは 30x25 マス。
; =====================================================================

        INCLUDE "defs.asm"
        INCLUDE "vars.asm"

        ORG     GAME_ORG

GAME_ENTRY:
        DI
        LD      SP,STACK_TOP
        XOR     A
        OUT     (P_INTMASK),A
        OUT     (P_INTLV),A
        IM      1
        ; GVRAM の裏で動く部分を本体のうしろから C000h へ写す
        LD      HL,GAME_END
        LD      DE,HIGH_START
        LD      BC,HIGH_END-HIGH_START
        LDIR
        ; 変数の置き場をすべて 0 にしておく
        LD      HL,VARS
        LD      (HL),0
        LD      DE,VARS+1
        LD      BC,VARS_END-VARS-1
        LDIR
        ; 乱数の種
        LD      HL,0xACE1
        LD      (RNGSEED),HL
        LD      HL,0
        LD      (FRAMECNT),HL
        LD      A,0x3F
        LD      (MIXER),A

        CALL    GFX_INIT
        CALL    TEXTINIT
        CALL    SNDINIT

        ; ハイスコアの初期値
        LD      HL,0
        LD      (HISCORE),HL
        XOR     A
        LD      (HISCORE+2),A
        LD      A,1
        LD      (MUSICON),A
        XOR     A
        LD      (SHIBACOLOR),A
        CALL    LOADHISCORE

; =====================================================================
; タイトル -> ゲーム -> ゲームオーバー の繰り返し
; =====================================================================
OUTERLOOP:
        CALL    TITLESCREEN
        CALL    NEWGAME
        JR      OUTERLOOP

; ---------------------------------------------------------------------
; NEWGAME - 1 回のゲーム
; ---------------------------------------------------------------------
NEWGAME:
        LD      A,1
        LD      (STAGE),A
        LD      A,3
        LD      (LIVES),A
        LD      HL,0
        LD      (SCORE),HL
        XOR     A
        LD      (SCORE+2),A
        LD      HL,FIRSTEXTEND & 0xFFFF ; 最初の 1UP は 20000 点
        LD      (NEXTEXT),HL
        XOR     A
        LD      (NEXTEXT+2),A
        LD      (BONUSMODE),A
        LD      (DEMOMODE),A
        LD      (GAMEOVER),A
.stageloop:
        ; スコアをステージ開始時の値として覚えておく (ギブアップ用)
        LD      HL,(SCORE)
        LD      (SCORE0),HL
        LD      A,(SCORE+2)
        LD      (SCORE0+2),A
        CALL    PLAYSTAGE
        CALL    NIGHTOFF
        CALL    ACHSAVEIF               ; 実績が増えていたらステージの切れ目で書く
        LD      A,(GAMEOVER)
        OR      A
        JR      NZ,.over
        LD      A,(QUITFLAG)
        OR      A
        RET     NZ
        LD      A,(CLEARED)
        OR      A
        JR      Z,.retry
        ; --- クリア ---
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.normalclear
        ; ボーナス面のあとは次のステージへ
        XOR     A
        LD      (BONUSMODE),A
        JR      .stageloop
.normalclear:
        ; 4 の倍数のステージをクリアしたら夜のボーナス面
        LD      A,(STAGE)
        LD      C,4
        CALL    MOD8A
        OR      A
        JR      NZ,.nextstage
        LD      A,(STAGE)
        INC     A
        LD      (STAGE),A
        LD      A,1
        LD      (BONUSMODE),A
        JR      .stageloop
.nextstage:
        LD      A,(STAGE)
        INC     A
        LD      (STAGE),A
        JR      .stageloop
.retry:
        ; 面クリアできなかったので同じステージをやり直し
        LD      HL,(SCORE0)
        LD      (SCORE),HL
        LD      A,(SCORE0+2)
        LD      (SCORE+2),A
        JR      .stageloop
.over:
        CALL    GAMEOVERSCREEN
        LD      A,BGM_TITLE
        CALL    BGMSTART
        LD      A,0xFF
        LD      (NEWRANK),A
        CALL    HSQUALIFY
        CALL    C,NAMEENTRY             ; 表に入るなら名前を入れる
        CALL    ACHSAVEIF
        LD      HL,8*TICKHZ
        LD      (HSVIEW),HL
        JP      HSSCREEN

; ---------------------------------------------------------------------
; PLAYSTAGE - 1 ステージを遊ぶ
; ---------------------------------------------------------------------
PLAYSTAGE:
        XOR     A
        LD      (QUITFLAG),A
        LD      (MISSES),A
        LD      (ACHTT),A
        CALL    PALNORMAL
        CALL    STAGEINIT
        CALL    CLS
        CALL    DIRTYRESET
        CALL    DIRTYALL
        CALL    FLUSHDIRTY
        CALL    HUDALL
        CALL    NIGHTSTART              ; 夜のボーナス面はテキスト面で暗がりを出す
        CALL    STAGEANNOUNCE
        CALL    STAGEBGM
.loop:
        CALL    WAITVSYNC
        LD      HL,(FRAMECNT)
        INC     HL
        LD      (FRAMECNT),HL
        CALL    READKEYS

        ; --- T で速さの表示を切り替える ---
        LD      B,K_T_P
        LD      C,K_T_B
        CALL    KEYHIT
        JR      Z,.nodbg
        LD      A,(DBGON)
        XOR     1
        LD      (DBGON),A
        OR      A
        JR      NZ,.nodbg
        CALL    HUDFPSCLR               ; 消す
.nodbg:
        ; --- ポーズ ---
        LD      B,K_P_P
        LD      C,K_P_B
        CALL    KEYHIT
        JR      Z,.nopause
        LD      A,(PAUSED)
        XOR     1
        LD      (PAUSED),A
        LD      A,SFX_SELECT
        CALL    SFXPLAY
        LD      A,(PAUSED)
        OR      A
        JR      Z,.unpause
        LD      HL,S_PAUSE
        LD      A,C_YELLOW
        CALL    HUDMSG
        JR      .nopause
.unpause:
        LD      HL,S_EMPTY
        LD      A,C_WHITE
        CALL    HUDMSG
.nopause:
        ; --- BGM の切り替え ---
        LD      B,K_M_P
        LD      C,K_M_B
        CALL    KEYHIT
        JR      Z,.nomusic
        LD      A,(MUSICON)
        XOR     1
        LD      (MUSICON),A
        CALL    STAGEBGM
.nomusic:
        ; --- タイトルへ戻る ---
        LD      B,K_ESC_P
        LD      C,K_ESC_B
        CALL    KEYHIT
        JR      Z,.noesc
        LD      A,1
        LD      (QUITFLAG),A
        CALL    BGMSTOP
        RET
.noesc:
        LD      A,(PAUSED)
        OR      A
        JR      Z,.running
        ; ポーズ中: R でギブアップ
        LD      B,K_R_P
        LD      C,K_R_B
        CALL    KEYHIT
        JR      Z,.loop
        ; ステージをやり直す
        CALL    ACH
        DB      ACH_GIVE_UP
        LD      HL,(SCORE0)
        LD      (SCORE),HL
        LD      A,(SCORE0+2)
        LD      (SCORE+2),A
        CALL    BGMSTOP
        JP      PLAYSTAGE

.running:
        XOR     A
        LD      (BFSUSED),A
        CALL    SCANINPUT
        CALL    SPRCLEAR
        CALL    WORLDTICK
        CALL    CHECKEXTEND
        CALL    CARSMARK
        CALL    FLUSHDIRTY
        CALL    DRAWCARS
        CALL    DRAWDOGS
        CALL    NIGHTTICK
        LD      A,(DBGON)
        OR      A
        CALL    NZ,HUDFPS
        LD      A,(NEEDHUD)
        OR      A
        JR      Z,.nohud
        XOR     A
        LD      (NEEDHUD),A
        CALL    HUDVALUES
.nohud:
        ; メッセージの時間切れ
        LD      A,(MSGTIMER)
        OR      A
        JR      Z,.nomsg
        DEC     A
        LD      (MSGTIMER),A
        JR      NZ,.nomsg
        LD      HL,S_EMPTY
        LD      A,C_WHITE
        CALL    HUDMSG
.nomsg:
        CALL    ACHTOAST                ; 実績の通知
        CALL    FLOODSTEP               ; 帰線までの空き時間で敵の道さがし
        LD      A,(GAMEOVER)
        OR      A
        JR      NZ,.fin
        LD      A,(FINISHED)
        OR      A
        JR      Z,.loop
.fin:
        CALL    BGMSTOP
        CALL    HUDVALUES
        ; 結果の表示
        LD      A,(GAMEOVER)
        OR      A
        RET     NZ
        LD      A,(CLEARED)
        OR      A
        JR      Z,.failed
        CALL    STAGECLEARACH
        LD      A,BGM_CLEAR
        CALL    BGMSTART
        LD      HL,S_CLEAR
        LD      A,C_YELLOW
        CALL    HUDMSG
        LD      A,(PERFECT)
        OR      A
        JR      Z,.w
        LD      HL,S_PERFECT
        LD      A,C_YELLOW
        CALL    HUDMSG
.w:
        CALL    WAIT2SEC
        RET
.failed:
        LD      A,BGM_FAIL
        CALL    BGMSTART
        LD      HL,S_FAILED
        LD      A,C_RED
        CALL    HUDMSG
        CALL    WAIT2SEC
        RET

; ---------------------------------------------------------------------
; STAGEBGM - ステージに合った曲をかける
; ---------------------------------------------------------------------
STAGEBGM:
        LD      A,(BONUSMODE)
        OR      A
        LD      A,BGM_BONUS
        JR      NZ,.go
        LD      A,(HASBOSS)
        OR      A
        LD      A,BGM_BOSS
        JR      NZ,.go
        LD      A,BGM_STAGE
.go:
        JP      BGMSTART

; ---------------------------------------------------------------------
; STAGEANNOUNCE - ステージの始まりを知らせる
; ---------------------------------------------------------------------
STAGEANNOUNCE:
        LD      A,(BONUSMODE)
        OR      A
        JR      Z,.normal
        LD      HL,S_BONUS
        LD      A,C_GREEN
        CALL    HUDMSG
        JR      .wait
.normal:
        LD      A,(HASBOSS)
        OR      A
        JR      Z,.ready
        LD      HL,S_BOSSCOME
        LD      A,C_RED
        CALL    HUDMSG
        JR      .wait
.ready:
        LD      HL,S_READY
        LD      A,C_WHITE
        CALL    HUDMSG
.wait:
        CALL    WAIT2SEC
        LD      HL,S_EMPTY
        LD      A,C_WHITE
        CALL    HUDMSG
        RET

; ---------------------------------------------------------------------
; CHECKEXTEND - 点数が次の 1UP に届いたら残機を増やす
;   元の版と同じく最初は 20000 点、そのあとは 40000 点ごと。
; ---------------------------------------------------------------------
CHECKEXTEND:
        ; 10 万点 (0x0186A0) の実績
        LD      A,(SCORE+2)
        CP      2
        JR      NC,.k100
        DEC     A
        JR      NZ,.no100
        LD      HL,(SCORE)
        LD      DE,0x86A0
        OR      A
        SBC     HL,DE
        JR      C,.no100
.k100:
        CALL    ACH
        DB      ACH_SCORE_100K
.no100:
        ; SCORE >= NEXTEXT か (24bit を上の桁から比べる)
        LD      A,(SCORE+2)
        LD      HL,NEXTEXT+2
        CP      (HL)
        RET     C
        JR      NZ,.yes
        LD      A,(SCORE+1)
        DEC     HL
        CP      (HL)
        RET     C
        JR      NZ,.yes
        LD      A,(SCORE)
        DEC     HL
        CP      (HL)
        RET     C
.yes:
        LD      HL,(NEXTEXT)
        LD      DE,EXTENDEVERY & 0xFFFF
        ADD     HL,DE
        LD      (NEXTEXT),HL
        LD      A,(NEXTEXT+2)
        ADC     A,EXTENDEVERY >> 16
        LD      (NEXTEXT+2),A
        LD      A,(LIVES)
        CP      9
        JR      NC,.full
        INC     A
        LD      (LIVES),A
.full:
        LD      A,1
        LD      (NEEDHUD),A
        LD      HL,S_1UP
        LD      A,C_RED
        CALL    HUDMSG
        LD      A,25
        LD      (MSGTIMER),A
        CALL    ACH
        DB      ACH_ONE_UP
        LD      A,SFX_EXTEND
        CALL    SFXPLAY
        JR      CHECKEXTEND             ; 一度に何回分も超えていたら続けて

; ---------------------------------------------------------------------
; WAIT2SEC - 2 秒ほど待つ (キーで飛ばせる)
; ---------------------------------------------------------------------
WAIT2SEC:
        LD      B,2*TICKHZ
.lp:
        PUSH    BC
        CALL    WAITVSYNC
        CALL    ACHTOAST
        CALL    READKEYS
        CALL    ANYKEY
        POP     BC
        RET     NZ
        DJNZ    .lp
        RET

; ---------------------------------------------------------------------
; WAITVSYNC - 垂直帰線を 1 回待つ
; ---------------------------------------------------------------------
WAITVSYNC:
        ; FLOODSTEP が帰線の始まりを見つけて戻ってきたなら、もう待たない
        LD      A,(VBFRESH)
        OR      A
        JR      Z,.normal
        XOR     A
        LD      (VBFRESH),A
        LD      A,(VBCOUNT)
        LD      (VBTARGET),A
        JR      .fps
.normal:
        ; 処理中に VBPOLL が数えた帰線のぶんはもう待たない。
        ; (重いときに 1 フレームぶん余計に待ってしまうのを防ぐ)
        LD      A,(VBCOUNT)
        INC     A                       ; すくなくともつぎの帰線までは待つ
        LD      B,VSYNCPERTICK
        CP      B
        JR      NC,.tgt
        LD      A,B
.tgt:
        LD      (VBTARGET),A
.w:
        CALL    VBPOLL
        LD      A,(VBCOUNT)
        LD      HL,VBTARGET
        CP      (HL)
        JR      C,.w
.fps:
        ; --- 実際の速さを数える (帰線 60 回で 1 秒) ---
        LD      A,(VBTARGET)
        LD      B,A
        LD      A,(FPSVB)
        ADD     A,B
        LD      (FPSVB),A
        LD      HL,FPSTICKS
        INC     (HL)
        CP      60
        JR      C,.nosec
        SUB     60
        LD      (FPSVB),A
        LD      A,(FPSTICKS)
        LD      (FPSVAL),A
        XOR     A
        LD      (FPSTICKS),A
.nosec:
        ; 描画の途中で鳴らせなかったぶん (ここはかならずメイン RAM)
        PUSH    BC
        PUSH    DE
        CALL    SNDPUMP
        POP     DE
        POP     BC
        XOR     A
        LD      (VBCOUNT),A
        RET

; ---------------------------------------------------------------------
; VBPOLL - 垂直帰線の立ち上がりを数える
;   重い処理の途中でときどき呼ぶ。レジスタは壊さない。
;   帰線 VSYNCPERTICK 回ごとに音 (BGM と効果音) も 1 ティック進める。
;   ゲームのループとは別に進むので、画面を描き換えているあいだや
;   処理が重いときも曲がもたつかない。
;   GVRAM を C000h に出している最中に音源をさわると、エミュレータによっては
;   音がブツブツ切れるので、いったんメイン RAM に戻してから鳴らし、
;   出していたプレーンに戻す (どのプレーンかはポート 5Ch を読むとわかる)。
; ---------------------------------------------------------------------
VBPOLL:
        PUSH    AF
        PUSH    BC
        PUSH    HL
        IN      A,(P_STROBE)
        AND     0x20
        LD      HL,VBLAST
        LD      B,(HL)
        LD      (HL),A
        OR      A
        JR      Z,.out                  ; いまは帰線中でない
        LD      A,B
        OR      A
        JR      NZ,.out                 ; さっきも帰線中 = 立ち上がりではない
        LD      HL,VBCOUNT
        INC     (HL)
        LD      HL,SNDPHASE
        LD      A,(HL)
        OR      A
        JR      Z,.snd
        DEC     (HL)
        JR      .out
.snd:
        LD      (HL),VSYNCPERTICK-1
        LD      HL,SNDPEND
        INC     (HL)
.out:
        LD      A,(SNDPEND)
        OR      A
        JR      Z,.ret
        IN      A,(P_GV0)               ; いま出している GVRAM (bit0..2)
        AND     7
        JR      Z,.pump                 ; メイン RAM: そのまま鳴らす
        LD      C,P_GV0
        CP      1
        JR      Z,.gv
        INC     C
        CP      2
        JR      Z,.gv
        INC     C
        CP      4
        JR      NZ,.ret                 ; 読めない値なら WAITVSYNC にまかせる
.gv:
        OUT     (P_GVOFF),A
        PUSH    DE
        PUSH    BC
        CALL    SNDPUMP
        POP     BC
        POP     DE
        OUT     (C),A                   ; 出していたプレーンに戻す
        JR      .ret
.pump:
        PUSH    DE
        CALL    SNDPUMP
        POP     DE
.ret:
        POP     HL
        POP     BC
        POP     AF
        RET

        INCLUDE "gfx.asm"
        INCLUDE "render.asm"
        INCLUDE "world.asm"
        INCLUDE "stage.asm"
        INCLUDE "tick.asm"
        INCLUDE "events.asm"
        INCLUDE "ai.asm"
        INCLUDE "input.asm"
        INCLUDE "sound.asm"
        INCLUDE "screens.asm"
        INCLUDE "title.asm"
        INCLUDE "records.asm"
        INCLUDE "disk.asm"
        INCLUDE "data.asm"
        INCLUDE "gen_art.asm"

GAME_END:
        ASSERT  GAME_END < 0x9000, "コードとデータが配列の領域にかかります"

; ---------------------------------------------------------------------
; ここから GVRAM の裏 (C000h-) で動く部分。ディスクでは本体のすぐうしろに
; 続けて置いてあり、GAME_ENTRY が写す。
; ---------------------------------------------------------------------
        ORG     HIGH_ORG
HIGH_START:
        INCLUDE "night.asm"
        INCLUDE "path.asm"                ; 道さがし (GVRAM を触らない計算だけ)
HIGH_END:
        ASSERT  HIGH_END <= NM_MASK, "裏の部分が夜の面の配列にかかります"
        ASSERT  GAME_END + HIGH_END - HIGH_START <= VARS, "読み込むと変数の領域にかかります"
