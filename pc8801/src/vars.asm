; =====================================================================
; vars.asm - スカラ変数の置き場
; =====================================================================
; EQU を数えながら進めるので、ここでは何も出力しない (ディスクを使わない)。
; =====================================================================

_V              EQU VARS

; --- 描画作業用 -------------------------------------------------------
GFX_VA          EQU _V
_V              EQU _V + 2
GFX_ST          EQU _V
_V              EQU _V + 2
GFX_SRC         EQU _V
_V              EQU _V + 2
GFX_EV          EQU _V
_V              EQU _V + 1
GFX_OD          EQU _V
_V              EQU _V + 1
GFX_COL         EQU _V
_V              EQU _V + 1
GFX_TMP         EQU _V
_V              EQU _V + 1
GFX_EDGE        EQU _V
_V              EQU _V + 1
GFX_PL          EQU _V
_V              EQU _V + 1

; --- 乱数・時間 -------------------------------------------------------
RNGSEED         EQU _V
_V              EQU _V + 2
FRAMECNT        EQU _V
_V              EQU _V + 2

; --- ゲーム全体 -------------------------------------------------------
STAGE           EQU _V
_V              EQU _V + 1
LIVES           EQU _V
_V              EQU _V + 1
SCORE           EQU _V                  ; 24bit
_V              EQU _V + 3
SCORE0          EQU _V                  ; ステージ開始時 (ギブアップ用)
_V              EQU _V + 3
HISCORE         EQU _V
_V              EQU _V + 3
SHIBACOLOR      EQU _V
_V              EQU _V + 1
MUSICON         EQU _V
_V              EQU _V + 1

; --- ステージ内 -------------------------------------------------------
CLAIMED         EQU _V
_V              EQU _V + 2
SECLEFT         EQU _V                  ; 残り秒
_V              EQU _V + 1
SECTICK         EQU _V                  ; 次の 1 秒までのフレーム
_V              EQU _V + 1
NENEMY          EQU _V
_V              EQU _V + 1
NDOGS           EQU _V
_V              EQU _V + 1
HASBOSS         EQU _V
_V              EQU _V + 1
BONUSMODE       EQU _V
_V              EQU _V + 1
DEMOMODE        EQU _V
_V              EQU _V + 1
FINISHED        EQU _V
_V              EQU _V + 1
CLEARED         EQU _V
_V              EQU _V + 1
GAMEOVER        EQU _V
_V              EQU _V + 1
PERFECT         EQU _V
_V              EQU _V + 1
BONUSCAUGHT     EQU _V
_V              EQU _V + 1
PAUSED          EQU _V
_V              EQU _V + 1
GIVEUP          EQU _V
_V              EQU _V + 1
QUITFLAG        EQU _V
_V              EQU _V + 1
NPOLES          EQU _V
_V              EQU _V + 1

; --- 雨・アイテム -----------------------------------------------------
RAINWARN        EQU _V
_V              EQU _V + 2
RAINT           EQU _V
_V              EQU _V + 2
RAINNEXT        EQU _V
_V              EQU _V + 2
ITEMSPAWN       EQU _V
_V              EQU _V + 2

; --- 入力 -------------------------------------------------------------
HELDDIR         EQU _V                  ; 0xFF = なし
_V              EQU _V + 1
TAPDIR          EQU _V
_V              EQU _V + 1
ACTPRESS        EQU _V
_V              EQU _V + 1
ACTBUF          EQU _V
_V              EQU _V + 1
DIRBUF          EQU _V
_V              EQU _V + 1
DIRBUFT         EQU _V
_V              EQU _V + 1
KEYPREV         EQU _V                  ; 前フレームのキー状態 (16 バイト)
_V              EQU _V + 16
KEYNOW          EQU _V
_V              EQU _V + 16

; --- 作業 -------------------------------------------------------------
CURDOG          EQU _V                  ; いま処理している犬
_V              EQU _V + 1
DOGPTR          EQU _V                  ; その犬の構造体アドレス
_V              EQU _V + 2
BFSHEAD         EQU _V
_V              EQU _V + 2
BFSTAIL         EQU _V
_V              EQU _V + 2
FILLHEAD        EQU _V
_V              EQU _V + 2
FILLTAIL        EQU _V
_V              EQU _V + 2
FILLOWNER       EQU _V
_V              EQU _V + 1
EVAL_ID         EQU _V                  ; Evaluate 中の犬 ID
_V              EQU _V + 1
EVAL_STEAL      EQU _V
_V              EQU _V + 1
EVAL_N          EQU _V                  ; 新しく取れるマス数
_V              EQU _V + 2
EVAL_OTHER      EQU _V                  ; 他のなわばりが内側にあったか
_V              EQU _V + 1
EVAL_COLLECT    EQU _V                  ; セルを集めるか
_V              EQU _V + 1
TRI_AX          EQU _V
_V              EQU _V + 1
TRI_AY          EQU _V
_V              EQU _V + 1
TRI_BX          EQU _V
_V              EQU _V + 1
TRI_BY          EQU _V
_V              EQU _V + 1
TRI_CX          EQU _V
_V              EQU _V + 1
TRI_CY          EQU _V
_V              EQU _V + 1
TMPW0           EQU _V
_V              EQU _V + 2
TMPW1           EQU _V
_V              EQU _V + 2
TMPW2           EQU _V
_V              EQU _V + 2
TMPW3           EQU _V
_V              EQU _V + 2
TMPB0           EQU _V
_V              EQU _V + 1
TMPB1           EQU _V
_V              EQU _V + 1
TMPB2           EQU _V
_V              EQU _V + 1
TMPB3           EQU _V
_V              EQU _V + 1
BESTSCORE       EQU _V                  ; AI の評価値 (符号付き 16bit)
_V              EQU _V + 2
BESTIDX         EQU _V
_V              EQU _V + 1
HUDDIRTY        EQU _V
_V              EQU _V + 1
MSGTIMER        EQU _V
_V              EQU _V + 1
SPRCOUNT        EQU _V                  ; スプライトを描いたマスの数
_V              EQU _V + 1
RND_CX          EQU _V                  ; DRAWCELL の作業用
_V              EQU _V + 1
RND_CY          EQU _V
_V              EQU _V + 1
TERROWNER       EQU _V
_V              EQU _V + 1
DIRTYTAIL       EQU _V
_V              EQU _V + 2
DIRTYALLF       EQU _V
_V              EQU _V + 1
DRAWX           EQU _V                  ; 犬を描いた位置 (消去判定用)
_V              EQU _V + NDOG
DRAWY           EQU _V
_V              EQU _V + NDOG
POLEORDER       EQU _V                  ; AI が電柱を見る順番
_V              EQU _V + NPOLE
TRAVEL          EQU _V                  ; 各電柱までの歩数
_V              EQU _V + NPOLE
STAGEPHASE      EQU _V
_V              EQU _V + 1
PHASETIMER      EQU _V
_V              EQU _V + 2
IDLETIMER       EQU _V
_V              EQU _V + 2
TITLESEL        EQU _V
_V              EQU _V + 1
DEMOSTAGE       EQU _V
_V              EQU _V + 1
NEEDHUD         EQU _V
_V              EQU _V + 1

; --- 音 ---------------------------------------------------------------
SFXCH           EQU _V                  ; 効果音を鳴らしている SSG チャンネル
_V              EQU _V + 1
SFXTIMER        EQU _V
_V              EQU _V + 1
SFXPTR          EQU _V
_V              EQU _V + 2
BGMPTR          EQU _V
_V              EQU _V + 2
BGMWAIT         EQU _V
_V              EQU _V + 1
BGMTUNE         EQU _V
_V              EQU _V + 1
BGMTEMPO        EQU _V              ; いまの曲の 1 ステップのティック数
_V              EQU _V + 1
LEADNOW         EQU _V              ; ch0 に積んである主旋律の音色 (BGMLEADS の値)
_V              EQU _V + 1
SFXCUR          EQU _V
_V              EQU _V + 1
SFXREQ          EQU _V
_V              EQU _V + 1
SFXVOL          EQU _V
_V              EQU _V + 1
SND_NOTE        EQU _V
_V              EQU _V + 1
SND_CH          EQU _V
_V              EQU _V + 1
SND_FL          EQU _V
_V              EQU _V + 1
SND_FH          EQU _V
_V              EQU _V + 1
BGMHEAD         EQU _V
_V              EQU _V + 2
BFSUSED         EQU _V
_V              EQU _V + 1

; --- AI の作業用 -------------------------------------------------------
AI_PX           EQU _V
_V              EQU _V + 1
AI_PY           EQU _V
_V              EQU _V + 1
AI_PLX          EQU _V
_V              EQU _V + 1
AI_PLY          EQU _V
_V              EQU _V + 1
AI_DIR          EQU _V
_V              EQU _V + 1
AI_DIST         EQU _V
_V              EQU _V + 1
AI_BESTD        EQU _V
_V              EQU _V + 1
AI_TRAVEL       EQU _V
_V              EQU _V + 1
AI_TMP1         EQU _V
_V              EQU _V + 1
AI_ATTEMPT      EQU _V
_V              EQU _V + 1
AI_CAUT         EQU _V
_V              EQU _V + 1
AI_LOOK         EQU _V
_V              EQU _V + 1
AI_STAM         EQU _V
_V              EQU _V + 1
AI_REST         EQU _V
_V              EQU _V + 1
AI_CROW         EQU _V
_V              EQU _V + 1
AI_CX0          EQU _V
_V              EQU _V + 2
AI_CX1          EQU _V
_V              EQU _V + 2
AI_REACH        EQU _V
_V              EQU _V + 2
AI_LO           EQU _V
_V              EQU _V + 2
AI_HI           EQU _V
_V              EQU _V + 2

; --- 三角形判定の作業用 -----------------------------------------------
EV_UX           EQU _V
_V              EQU _V + 1
EV_UY           EQU _V
_V              EQU _V + 1
EV_VX           EQU _V
_V              EQU _V + 1
EV_VY           EQU _V
_V              EQU _V + 1
EV_WX           EQU _V
_V              EQU _V + 1
EV_WY           EQU _V
_V              EQU _V + 1
EV_AREA         EQU _V
_V              EQU _V + 2
EV_X0           EQU _V
_V              EQU _V + 1
EV_X1           EQU _V
_V              EQU _V + 1
EV_Y0           EQU _V
_V              EQU _V + 1
EV_Y1           EQU _V
_V              EQU _V + 1
EV_SX           EQU _V
_V              EQU _V + 1
EV_SY           EQU _V
_V              EQU _V + 1
EV_PX           EQU _V
_V              EQU _V + 1
EV_PY           EQU _V
_V              EQU _V + 1
EV_ROW          EQU _V
_V              EQU _V + 2
EV_SX16         EQU _V
_V              EQU _V + 2
EV_SY16         EQU _V
_V              EQU _V + 2
EV_CX           EQU _V
_V              EQU _V + 1
EV_CY           EQU _V
_V              EQU _V + 1
EV_N            EQU _V
_V              EQU _V + 2
MUL_SGN         EQU _V
_V              EQU _V + 1
EV_PASS         EQU _V
_V              EQU _V + 1
EV_W            EQU _V
_V              EQU _V + 1
EV_T1           EQU _V
_V              EQU _V + 2
AI_SCORE        EQU _V
_V              EQU _V + 2
AI_BW           EQU _V
_V              EQU _V + 1
AI_BH           EQU _V
_V              EQU _V + 1
MAN_T           EQU _V
_V              EQU _V + 1
SPC_D           EQU _V
_V              EQU _V + 1
SPC_E           EQU _V
_V              EQU _V + 1
OPQ_VA          EQU _V
_V              EQU _V + 2
OPQ_SRC         EQU _V
_V              EQU _V + 2
OPQ_STEP        EQU _V
_V              EQU _V + 2
OPQ_PL          EQU _V
_V              EQU _V + 1
OPQ_W           EQU _V
_V              EQU _V + 1
CARBX           EQU _V
_V              EQU _V + 1
CARW            EQU _V
_V              EQU _V + 1
CARN            EQU _V
_V              EQU _V + 1
VBCOUNT         EQU _V
_V              EQU _V + 1
VBLAST          EQU _V
_V              EQU _V + 1
VBTARGET        EQU _V
_V              EQU _V + 1
AITHINKS        EQU _V
_V              EQU _V + 1
FLUSHLEFT       EQU _V
_V              EQU _V + 1
DBGON           EQU _V                  ; 1 = 速さを画面に出す
_V              EQU _V + 1
FPSTICKS        EQU _V                  ; この 1 秒で回ったティック数
_V              EQU _V + 1
FPSVAL          EQU _V                  ; 前の 1 秒のティック数
_V              EQU _V + 1
FPSVB           EQU _V                  ; 数えた帰線の数
_V              EQU _V + 1
DIRMASK         EQU _V                  ; いま押されている方向 (bit0 下..bit3 上)
_V              EQU _V + 1
DIRPREV         EQU _V                  ; 前のティックの DIRMASK
_V              EQU _V + 1
LASTDIR         EQU _V                  ; いちばん新しく押した方向 (FF = なし)
_V              EQU _V + 1
JOYRAW          EQU _V                  ; ジョイスティックの生の値
_V              EQU _V + 1
DRIPT           EQU _V                  ; おしっこのしずくの音までのティック
_V              EQU _V + 1
HUDBG           EQU _V                  ; HUD の文字の背景色 (0 = 使わない)
_V              EQU _V + 1
GFX_BGT         EQU _V                  ; DRAWCHAR の作業用
_V              EQU _V + 1
; ---- タイトル画面 (title.asm) ----
TXTCOL          EQU _V
_V              EQU _V + 1
TXTFLG          EQU _V
_V              EQU _V + 1
TXSHCOL         EQU _V
_V              EQU _V + 1
TX_SRC          EQU _V
_V              EQU _V + 2
TX_VA           EQU _V
_V              EQU _V + 2
TX_PL           EQU _V
_V              EQU _V + 1
TX_BIT          EQU _V
_V              EQU _V + 1
BL_SRC          EQU _V
_V              EQU _V + 2
BL_W            EQU _V
_V              EQU _V + 1
BL_H            EQU _V
_V              EQU _V + 1
BL_VA           EQU _V
_V              EQU _V + 2
FR_W            EQU _V
_V              EQU _V + 1
FR_H            EQU _V
_V              EQU _V + 1
FR_VA           EQU _V
_V              EQU _V + 2
FR_TMP          EQU _V
_V              EQU _V + 1
FR_V            EQU _V
_V              EQU _V + 1
TP_X0           EQU _V
_V              EQU _V + 1
TP_X1           EQU _V
_V              EQU _V + 1
TP_Y1           EQU _V
_V              EQU _V + 1
BIG_COL         EQU _V
_V              EQU _V + 1
BIG_PC          EQU _V
_V              EQU _V + 1
BIG_X           EQU _V
_V              EQU _V + 1
BIG_Y           EQU _V
_V              EQU _V + 1
PK_I            EQU _V
_V              EQU _V + 1
PK_X            EQU _V
_V              EQU _V + 1
TPSTEP          EQU _V
_V              EQU _V + 1
PR_I            EQU _V
_V              EQU _V + 1
PR_X            EQU _V
_V              EQU _V + 1
PR_COL          EQU _V
_V              EQU _V + 1
TBOUNCE         EQU _V
_V              EQU _V + 1
TBLINK          EQU _V
_V              EQU _V + 1
SN_DIR          EQU _V
_V              EQU _V + 1
SN_BUF          EQU _V
_V              EQU _V + 2
SN_W            EQU _V
_V              EQU _V + 1
SN_H            EQU _V
_V              EQU _V + 1
SN_VA           EQU _V
_V              EQU _V + 2
TX_TC           EQU _V
_V              EQU _V + 1
TX_SC           EQU _V
_V              EQU _V + 1
PK_FULL         EQU _V
_V              EQU _V + 1
NEXTEXT         EQU _V                  ; 次の 1UP の点数 (24bit)
_V              EQU _V + 3
CARNBX          EQU _V
_V              EQU _V + 1
CARPBX          EQU _V
_V              EQU _V + NCAR
CARPROW         EQU _V
_V              EQU _V + NCAR
FINDMODE        EQU _V
_V              EQU _V + 1
FOUNDX          EQU _V
_V              EQU _V + 1
FOUNDY          EQU _V
_V              EQU _V + 1
GAINLO          EQU _V
_V              EQU _V + 2
TERRCNT         EQU _V
_V              EQU _V + 2
POLEI           EQU _V
_V              EQU _V + 1
GP_BX           EQU _V
_V              EQU _V + 1
GP_BY           EQU _V
_V              EQU _V + 1
RFOPOLE         EQU _V
_V              EQU _V + 1
CDID            EQU _V
_V              EQU _V + 1
CDFLAGS         EQU _V
_V              EQU _V + 1
MIXER           EQU _V
_V              EQU _V + 1
AITMP           EQU _V
_V              EQU _V + 12

; ---- 道さがし (path.asm) ----
FL_STATE        EQU _V
_V              EQU _V + 1
FL_DOG          EQU _V
_V              EQU _V + 1
FL_OX           EQU _V
_V              EQU _V + 1
FL_OY           EQU _V
_V              EQU _V + 1
FL_ID           EQU _V
_V              EQU _V + 1
FL_ALL          EQU _V
_V              EQU _V + 1
FL_CHUNK        EQU _V
_V              EQU _V + 1
FL_HEAD         EQU _V
_V              EQU _V + 1
FL_TAIL         EQU _V
_V              EQU _V + 1
FL_CNT          EQU _V
_V              EQU _V + 1
FL_LEFT         EQU _V
_V              EQU _V + 1
FL_EARLY        EQU _V
_V              EQU _V + 1
FL_NEXT         EQU _V
_V              EQU _V + 1
FL_AGE          EQU _V
_V              EQU _V + 1
VBFRESH         EQU _V
_V              EQU _V + 1
SNDPHASE        EQU _V              ; 音を進めるまでの帰線の残り
_V              EQU _V + 1
SNDPEND         EQU _V              ; まだ進めていない音のティック数
_V              EQU _V + 1
PT_MIN          EQU _V
_V              EQU _V + 1
PT_ADDR         EQU _V
_V              EQU _V + 2
RT_GOAL         EQU _V
_V              EQU _V + 2
RT_D            EQU _V
_V              EQU _V + 1
RT_FLIP         EQU _V
_V              EQU _V + 1
; ---- ハイスコア表と実績 (records.asm)。ACHBITS/ACHPROG と HSNEW/HSNAME/HSSTAGE は続けて置くこと ----
ACHBITS         EQU _V
_V              EQU _V + 3
ACHPROG         EQU _V
_V              EQU _V + 1
ACHQ            EQU _V
_V              EQU _V + 3
ACHDIRTY        EQU _V
_V              EQU _V + 1
ACHTT           EQU _V
_V              EQU _V + 1
ACHSHOW         EQU _V
_V              EQU _V + 1
MISSES          EQU _V
_V              EQU _V + 1
CDCOUNT         EQU _V
_V              EQU _V + 1
HSNEW           EQU _V
_V              EQU _V + 3
HSNAME          EQU _V
_V              EQU _V + 3
HSSTAGE         EQU _V
_V              EQU _V + 1
NEWRANK         EQU _V
_V              EQU _V + 1
NAMEPOS         EQU _V
_V              EQU _V + 1
HSVIEW          EQU _V
_V              EQU _V + 2
HS_I            EQU _V
_V              EQU _V + 1
HS_COL          EQU _V
_V              EQU _V + 1
HS_Y            EQU _V
_V              EQU _V + 1
HS_P            EQU _V
_V              EQU _V + 2
NE_I            EQU _V
_V              EQU _V + 1
NE_X            EQU _V
_V              EQU _V + 1
NE_ARROW        EQU _V
_V              EQU _V + 1
IC_POS          EQU _V
_V              EQU _V + 2
ACHCUR          EQU _V
_V              EQU _V + 1
AC_I            EQU _V
_V              EQU _V + 1
AC_STEP         EQU _V
_V              EQU _V + 1
; ---- HUD (render.asm) ----
AREADIRTY       EQU _V
_V              EQU _V + 1
LISTDIRTY       EQU _V
_V              EQU _V + 1
BAR_X0          EQU _V
_V              EQU _V + 1
BAR_X1          EQU _V
_V              EQU _V + 1
BAR_I           EQU _V
_V              EQU _V + 1
BAR_COL         EQU _V
_V              EQU _V + 1
BAR_CUM         EQU _V
_V              EQU _V + 2
BAR_Y           EQU _V
_V              EQU _V + 1
BAR_FL          EQU _V
_V              EQU _V + 1
BAR_BIT         EQU _V
_V              EQU _V + 1
LIVESSHOWN      EQU _V
_V              EQU _V + 1

VARS_END        EQU _V
        ASSERT  VARS_END < SECBUF, "変数が多すぎてセクタバッファにかかります"
