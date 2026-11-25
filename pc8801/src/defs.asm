; =====================================================================
; defs.asm - 柴犬陣取り PC-8801mkIISR 版 共通定義
; =====================================================================
; 画面: 640x200 8色 (V2 アナログパレット / 512色中8色)
;       1 マス = 16x8 ドット。フィールド 30x25 マス = 480x200 ドット。
;       右の 160 ドット (x=480..639) は HUD。
; =====================================================================

; ---------------------------------------------------------------- I/O ポート

P_KEY0          EQU 0x00        ; キーマトリクス 00h..0Eh (0 = 押されている)
P_SYS1          EQU 0x30        ; システム制御 1
P_SYS2          EQU 0x31        ; システム制御 2 (画面モード / RAM モード)
P_MISC          EQU 0x32        ; モード指定 (パレット種別 / 高速 RAM)
P_ALU1          EQU 0x34
P_ALU2          EQU 0x35
P_STROBE        EQU 0x40        ; 読み: bit5 = VRTC
P_OPN_ADDR      EQU 0x44        ; YM2203 レジスタ番号
P_OPN_DATA      EQU 0x45        ; YM2203 データ
P_CRTC0         EQU 0x50
P_CRTC1         EQU 0x51
P_BGCOL         EQU 0x52
P_LAYER         EQU 0x53        ; 表示制御 (bit0 = テキスト非表示)
P_PAL0          EQU 0x54        ; パレット 0..7 (54h..5Bh)
P_GV0           EQU 0x5C        ; GVRAM0 (青) を C000h-FFFFh に出す
P_GV1           EQU 0x5D        ; GVRAM1 (赤)
P_GV2           EQU 0x5E        ; GVRAM2 (緑)
P_GVOFF         EQU 0x5F        ; メイン RAM に戻す
P_INTLV         EQU 0xE4        ; 割り込みレベル
P_INTMASK       EQU 0xE6        ; 割り込みマスク
P_FDD_A         EQU 0xFC        ; サブシステム 8255 ポート A (読み)
P_FDD_B         EQU 0xFD        ; ポート B (書き)
P_FDD_C         EQU 0xFE        ; ポート C
P_FDD_CTRL      EQU 0xFF        ; 8255 コントロール

; 8255 のビットセット/リセット用コントロール値
; コントロール = 0BBB_BBBS (bit3-1 = ビット番号, bit0 = 1 でセット)
FDC_ATN_SET     EQU 0x0F        ; bit7 ATN = 1
FDC_ATN_CLR     EQU 0x0E
FDC_DAC_SET     EQU 0x0D        ; bit6 DAC = 1
FDC_DAC_CLR     EQU 0x0C
FDC_RFD_SET     EQU 0x0B        ; bit5 RFD = 1
FDC_RFD_CLR     EQU 0x0A
FDC_DAV_SET     EQU 0x09        ; bit4 DAV = 1
FDC_DAV_CLR     EQU 0x08
FDC_MODE        EQU 0x91        ; モードセット (A 入力 / B 出力 / C 上位出力・下位入力)

; サブシステムから読むステータスのビット
FDC_S_DAC       EQU 0x04
FDC_S_RFD       EQU 0x02
FDC_S_DAV       EQU 0x01

; ---------------------------------------------------------------- 画面モード

; ポート 31h: bit5=25LINE bit4=HCOLOR bit3=GRAPH bit2=RMODE bit1=MMODE bit0=200LINE
SYS2_GAME       EQU 0x3B        ; 25行/カラー/グラフィック表示/64K RAM/200行
; ポート 32h: bit7=SINTM bit6=GVAM bit5=PMODE bit4=TMODE bit3-2=AVC bit1-0=EROMSL
MISC_GAME       EQU 0xB8        ; 音源割り込み禁止/独立アクセス/アナログパレット/
                                ; F000-FFFFはメインRAM/コンピュータ出力
LAYER_GAME      EQU 0x01        ; テキスト面を隠してグラフィックだけ出す

; ---------------------------------------------------------------- 色 (パレット番号)

; 色番号はプレーンのビットそのもの (bit0=青プレーン, bit1=赤, bit2=緑)。
; スプライトの輪郭はプレーン0だけ = 1 番、白は 3 プレーン全部 = 7 番になるので、
; 1 を輪郭色、7 を白に固定してある。
C_GRASS         EQU 0           ; 草 (GVRAM が 0 のところ)
C_DARK          EQU 1           ; 輪郭・アスファルト
C_RED           EQU 2
C_ORANGE        EQU 3           ; 柴犬
C_BLUE          EQU 4
C_GRASS2        EQU 5           ; 濃い草 (地面の模様)
C_YELLOW        EQU 6
C_WHITE         EQU 7           ; 文字・白線・電柱
; 旧名
C_GROUND        EQU C_GRASS
C_BLACK         EQU C_DARK
C_GREEN         EQU C_GRASS2

; ---------------------------------------------------------------- フィールド

FW              EQU 30          ; 横のマス数
FH              EQU 25          ; 縦のマス数
CSTRIDE         EQU 32          ; 配列の 1 行の間隔 (シフトで計算できるよう 32)
NCELL           EQU FH * CSTRIDE        ; 800
CELLW           EQU 16          ; 1 マスの幅 (ドット)
CELLH           EQU 8           ; 1 マスの高さ (ドット)
VRAM            EQU 0xC000
VSTRIDE         EQU 80          ; 1 ライン = 80 バイト
VROW            EQU VSTRIDE * CELLH     ; 1 マス行 = 640 バイト
HUD_X           EQU 60          ; HUD の左端 (バイト単位 = 480 ドット)

NPOLE           EQU 30          ; 電柱の本数 (5x6 ブロック)
NDOG            EQU 9           ; 柴犬 + 敵 8 匹
NCAR            EQU 6
NITEM           EQU 2
NPOPUP          EQU 4

GOALCELL        EQU 563         ; FW*FH*3/4 = 562.5 -> 563
; ゲームの進行は 30Hz (垂直帰線 2 回で 1 ティック)。
; 時間の定数はすべて「ティック数」で持つ。
TICKHZ          EQU 30
VSYNCPERTICK    EQU 2
STAGETIME       EQU 240         ; 秒
BONUSTIME       EQU 60
PEEFRAMES       EQU 3*TICKHZ    ; 3 秒
BOSSPEEFRAMES   EQU 5*TICKHZ    ; 5 秒
ITEMLIFE        EQU 12*TICKHZ
BONETIME        EQU 12*TICKHZ
PASSTIME        EQU 10*TICKHZ
ITEMFROMSTAGE   EQU 5
RAINFROMSTAGE   EQU 8
BOSSEVERY       EQU 8
FIRSTEXTEND     EQU 20000       ; 最初の 1UP
EXTENDEVERY     EQU 40000       ; そのあとの 1UP の間隔
AIBUDGET        EQU 1           ; 1 ティックに考え直す敵の数
FLUSHBUDGET     EQU 64          ; 1 ティックに描き直すマスの上限
EVALQUICK       EQU 260         ; AI の下見でこれより広い箱は概算にする
WAKEWALK        EQU 2
WAKEPEE         EQU 3

; ---------------------------------------------------------------- メモリ配置
;   0000-00FF  ワーク (ゼロページ的に使う変数)
;   0100-8FFF  コード + データ
;   9000-B4FF  配列
;   B500-BBFF  作業バッファ
;   BC00-BCFF  ブートローダ (起動後は未使用)
;   BA00-BA11  夜の面: 犬ごとの zZ / 目の位置 (NIGHTPOS)
;   BD00-BFFF  スタック
;   C000-FFFF  GVRAM の窓。裏のメイン RAM は GVRAM を出していないときだけ見える:
;     C000-      night.asm (起動時に本体のうしろから写す)
;     D800-DB1F  夜の面の暗さ (NM_MASK, 800)
;     DC00-DF1F  夜の面の印のマス (NM_IND, 800)
;     E000-EBB7  テキスト面 (TXTBUF, 25 行 x 120 バイト。DMA で表示)

GAME_ORG        EQU 0x0100
LOADER_ORG      EQU 0xBC00
STACK_TOP       EQU 0xC000
HIGH_ORG        EQU 0xC000      ; GVRAM の裏で動くコード
NM_MASK         EQU 0xD800
NM_IND          EQU 0xDC00
NM_PGX          EQU 0x04        ; NM_MASK と NM_IND の上位バイトの違い
TXTBUF          EQU 0xE000
NIGHTPOS        EQU 0xBA00      ; NDOG * 2 (ドット行, バイト列)。FFh = なし

ARR_TERR        EQU 0x9000      ; 800: なわばりの持ち主 (0xFF = なし)
ARR_POLEAT      EQU 0x9320      ; 800: 電柱番号 (0xFF = なし)
ARR_DIRTY       EQU 0x9640      ; 800: 背景の再描画フラグ (0/1)
ARR_INTRI       EQU 0x9960      ; 800: 三角形の内側 (bit0) / 今回取った (bit3)
ARR_SPRCELL     EQU 0x9C80      ; 512: スプライトを描いたマス (ワード)
ARR_DIRTYQ      EQU 0x9E80      ; 1600: 描き直すマスの待ち行列 (ワード)
ARR_FILLQ       EQU 0xA4C0      ; 1600: なわばりにしたマス (ワード)

DISTB           EQU 0xAB00      ; 864: 道さがしの歩数 (上下に番兵の 1 行)
DIST0           EQU DISTB + CSTRIDE     ; マス (0,0)
DOGS            EQU 0xAF40      ; NDOG * 32
POLES           EQU 0xB060      ; NPOLE * 4
CARS            EQU 0xB0E0      ; NCAR * 8
ITEMS           EQU 0xB140      ; NITEM * IT_SIZE
POPUPS          EQU 0xB150      ; NPOPUP * 16
LANEOF          EQU 0xB1A0      ; FH バイト: 0 なし / 1 左行き / 2 右行き
LANESPAWN       EQU 0xB1C0      ; FH バイト: 次の車までのフレーム
LANESPEED       EQU 0xB1E0      ; FH バイト: 車の速さ (フレームあたりのドット)
HISCORES        EQU 0xB200      ; 10 件 x 8 バイト (スコア 3 + 名前 4 + ステージ 1)
ROUTES          EQU 0xB260      ; NDOG * 48 = 432: AI の経路 (方向の列)
CELLBUF         EQU 0xB410      ; 48: マス 1 個分のビットマップ (プレーン順)
SPRBUF          EQU 0xB440      ; 64: スプライト合成用
TMPBUF          EQU 0xB480      ; 64: 汎用
STRBUF          EQU 0xB4C0      ; 32: 文字列組み立て
VARS            EQU 0xB500      ; スカラ変数 (vars.asm で定義)
SECBUF          EQU 0xB700      ; 256: ディスクのセクタ 1 個分
QLOP            EQU 0xB8        ; 道さがしの待ち行列 (下位バイト) B800-B8FF
QHIP            EQU 0xB9        ; 同 (上位バイト) B900-B9FF

; ---------------------------------------------------------------- 犬の構造体 (32 バイト)

D_X             EQU 0
D_Y             EQU 1
D_FROMX         EQU 2
D_FROMY         EQU 3
D_DIR           EQU 4           ; 0 下 / 1 左 / 2 右 / 3 上
D_FLAGS         EQU 5
D_MOVET         EQU 6
D_STEPTIME      EQU 7
D_PEET          EQU 8           ; 16bit
D_PEETOTAL      EQU 10          ; 16bit
D_PEEPOLE       EQU 12
D_CHAIN         EQU 13          ; 3 バイト
D_CHAINN        EQU 16
D_BREED         EQU 17
D_INVULN        EQU 18
D_AREA          EQU 19          ; 16bit
D_THINK         EQU 21
D_TARGET        EQU 22
D_STEPS         EQU 23
D_BONET         EQU 24          ; 16bit
D_PASST         EQU 26          ; 16bit
D_STUCK         EQU 28          ; 進めなかった回数
D_SPARE1        EQU 29
D_AWAKE         EQU 30          ; ボーナス面: 起きている残りフレーム (8bit)
D_TERRID        EQU 31          ; なわばり ID (= 犬 ID)
D_SIZE          EQU 32

; D_FLAGS のビット
DF_ALIVE        EQU 0x01
DF_MOVING       EQU 0x02
DF_PLAYER       EQU 0x04
DF_BOSS         EQU 0x08
DF_ASLEEP       EQU 0x10
DF_STEPFLIP     EQU 0x20
DF_DRAWN        EQU 0x40        ; 画面に描いてある
DF_WANTPATH     EQU 0x80        ; 道さがしの順番待ち (path.asm)

; 道さがし (path.asm)
FL_DBASE        EQU 16          ; 歩数は 16 + d で入れる (0..8 はなわばり)
FL_WALL         EQU 0xFE
RT_MAX          EQU 46          ; 覚えておく歩数

; ---------------------------------------------------------------- 電柱 (4 バイト)

PL_X            EQU 0
PL_Y            EQU 1
PL_OWNER        EQU 2           ; 0xFF = なし
PL_LOCKED       EQU 3
PL_SIZE         EQU 4

; ---------------------------------------------------------------- 車 (8 バイト)

CR_ACTIVE       EQU 0
CR_XLO          EQU 1           ; ドット単位の x (16bit)
CR_XHI          EQU 2
CR_ROW          EQU 3
CR_SIGN         EQU 4           ; 0 = 右へ / 1 = 左へ
CR_SPEED        EQU 5
CR_COLOR        EQU 6
CR_FRAC         EQU 7           ; 端数 (1/16 ドット)
CR_SIZE         EQU 8

; ---------------------------------------------------------------- アイテム (4 バイト)

IT_ACTIVE       EQU 0
IT_X            EQU 1
IT_Y            EQU 2
IT_KIND         EQU 3           ; 0 = 骨 / 1 = 巻物
IT_T            EQU 4           ; 消えるまでの残りフレーム (16bit)
IT_SIZE         EQU 6
