; =====================================================================
; data.asm - 固定テーブル
; =====================================================================

; ---------------------------------------------------------------- 方向

; 0 = 下, 1 = 左, 2 = 右, 3 = 上 (元の C# 版の Dir と同じ順)
DIRDX:  DB      0, -1, 1, 0
DIRDY:  DB      1, 0, 0, -1

; ---------------------------------------------------------------- 犬種

; 犬種番号
;   0 柴犬(茶) 1 柴犬(黒) 2 柴犬(白)
;   3 コーギー 4 チワワ 5 シェルティー 6 ハスキー
;   7 パグ 8 ダルメシアン 9 プードル 10 ビーグル
;   11 セントバーナード (ボス)
NBREED          EQU 12
BOSSBREED       EQU 11
SHIBACOUNT      EQU 3
ENEMYBREEDS     EQU 8           ; 3..10

B_STYLE         EQU 0           ; なわばりの塗りスタイル番号
B_TCOL          EQU 1           ; なわばりの代表色 (印の帯の色)
B_BODY          EQU 2           ; 体の色
B_EAR           EQU 3           ; 0 = 立ち耳 / 1 = たれ耳
B_NAME          EQU 4           ; 名前 (2 バイト)
B_SIZE          EQU 6

BREEDTBL:
        ;       style tcol      body      ear  name
        DB      0, C_ORANGE, C_ORANGE, 0
        DW      NM_SHIBA
        DB      0, C_ORANGE, C_DARK,   0
        DW      NM_SHIBA
        DB      0, C_ORANGE, C_WHITE,  0
        DW      NM_SHIBA
        DB      1, C_YELLOW, C_ORANGE, 1
        DW      NM_CORGI
        DB      2, C_RED,    C_WHITE,  1
        DW      NM_CHIHUA
        DB      3, C_BLUE,   C_RED,    0
        DW      NM_SHELTIE
        DB      4, C_BLUE,   C_BLUE,   0
        DW      NM_HUSKY
        DB      5, C_RED,    C_YELLOW, 2
        DW      NM_PUG
        DB      6, C_WHITE,  C_WHITE,  2
        DW      NM_DALMA
        DB      7, C_RED,    C_ORANGE, 2
        DW      NM_POODLE
        DB      8, C_BLUE,   C_RED,    2
        DW      NM_BEAGLE
        DB      9, C_RED,    C_RED,    2
        DW      NM_STBERN

NM_SHIBA:       DB      "SHIBA",0
NM_CORGI:       DB      "CORGI",0
NM_CHIHUA:      DB      "CHIHUAHUA",0
NM_SHELTIE:     DB      "SHELTIE",0
NM_HUSKY:       DB      "HUSKY",0
NM_PUG:         DB      "PUG",0
NM_DALMA:       DB      "DALMATIAN",0
NM_POODLE:      DB      "POODLE",0
NM_BEAGLE:      DB      "BEAGLE",0
NM_STBERN:      DB      "ST.BERNARD",0

; ---------------------------------------------------------------- 性格

; 16 = 1.0 の固定小数。元の Breeds.cs の Temper を整数にしたもの。
T_SPEED         EQU 0           ; 1 歩の時間の倍率 (大きいほど遅い)
T_REACH         EQU 1           ; 2 本目に選びたい距離
T_SIZEW         EQU 2           ; 面積をどれだけ重視するか
T_AGGRO         EQU 3           ; 柴犬を囲もうとする強さ
T_HERD          EQU 4           ; ほかの敵を囲もうとする強さ
T_STEAL         EQU 5           ; 印を上書きしたがる強さ
T_CAUTION       EQU 6           ; 道路の用心深さ
T_STAMINA       EQU 7           ; 何歩で休むか (0 = 休まない)
T_REST          EQU 8           ; 休むフレーム数
T_DITHER        EQU 9           ; おしっこ後のぼんやり
T_NOISE         EQU 10          ; 気まぐれさ
T_SIZE          EQU 11

TEMPERTBL:
        ; 0..2 柴犬 (AI に使うのはデモのときだけ)
        DB      16,  7, 16, 16, 26, 16, 16,  0,   0, 16, 16
        DB      16,  7, 16, 16, 26, 16, 16,  0,   0, 16, 16
        DB      16,  7, 16, 16, 26, 16, 16,  0,   0, 16, 16
        ; 3 コーギー  STEADY  足が短く少し遅いが用心深い
        DB      17,  6, 16, 13,  8, 16, 26,  0,   0, 16, 16
        ; 4 チワワ    QUICK   速いがスタミナがなく小さななわばり
        DB      11,  3,  4,  6,  0,  8, 19, 28, 144,  8, 19
        ; 5 シェルティー HERDER 牧羊犬。ほかの犬を囲い込む
        DB      15,  8, 16, 19, 32, 16, 19,  0,   0, 11, 10
        ; 6 ハスキー  FIERCE  攻撃的。柴犬を囲みに来る。車に無頓着
        DB      14, 13, 26, 38,  8, 24, 10,  0,   0, 10, 13
        ; 7 パグ      LAZY    のんびり屋。すぐ昼寝
        DB      22,  5, 11,  8,  0,  8, 24, 16, 192, 32, 16
        ; 8 ダルメシアン RUNNER 足が速く遠くまで。道路を気にしない
        DB      12, 11, 19, 13,  0, 16,  4,  0,   0, 13, 24
        ; 9 プードル  CLEVER  迷いがなく印を上書きする
        DB      15,  7, 16, 16,  5, 48, 21,  0,   0,  8,  6
        ; 10 ビーグル NOSY    においに夢中。寄り道する
        DB      16,  7, 14, 11,  0, 32, 13, 20,  72, 19, 48
        ; 11 セントバーナード BOSS
        DB      23, 12, 24, 32, 16, 16, 32,  0,   0, 24, 10

; 性格の名前 (HUD に出す)
TRAITTBL:
        DW      NM_NONE, NM_NONE, NM_NONE
        DW      TR_STEADY, TR_QUICK, TR_HERDER, TR_FIERCE
        DW      TR_LAZY, TR_RUNNER, TR_CLEVER, TR_NOSY
        DW      TR_BOSS

NM_NONE:        DB      0
TR_STEADY:      DB      "STEADY",0
TR_QUICK:       DB      "QUICK",0
TR_HERDER:      DB      "HERDER",0
TR_FIERCE:      DB      "FIERCE",0
TR_LAZY:        DB      "LAZY",0
TR_RUNNER:      DB      "RUNNER",0
TR_CLEVER:      DB      "CLEVER",0
TR_NOSY:        DB      "NOSY",0
TR_BOSS:        DB      "BOSS",0

; 休むときのせりふ
RESTTBL:
        DW      NM_NONE, NM_NONE, NM_NONE
        DW      NM_NONE, RT_HAH, NM_NONE, NM_NONE
        DW      RT_ZZZ, NM_NONE, NM_NONE, RT_SNIFF
        DW      NM_NONE
RT_HAH:         DB      "HAH..",0
RT_ZZZ:         DB      "ZZZ",0
RT_SNIFF:       DB      "SNIFF",0

; ---------------------------------------------------------------- 犬のスプライト

; 添字 = 耳*16 + コマ*8 + 方向*2   (方向 0 下 / 1 左 / 2 右 / 3 上)
SPRDOG:
        DW      SPR_DOG_POINTY_D0, SPR_DOG_POINTY_L0
        DW      SPR_DOG_POINTY_R0, SPR_DOG_POINTY_U0
        DW      SPR_DOG_POINTY_D1, SPR_DOG_POINTY_L1
        DW      SPR_DOG_POINTY_R1, SPR_DOG_POINTY_U1
        DW      SPR_DOG_BIG_D0, SPR_DOG_BIG_L0
        DW      SPR_DOG_BIG_R0, SPR_DOG_BIG_U0
        DW      SPR_DOG_BIG_D1, SPR_DOG_BIG_L1
        DW      SPR_DOG_BIG_R1, SPR_DOG_BIG_U1
        DW      SPR_DOG_FLOPPY_D0, SPR_DOG_FLOPPY_L0
        DW      SPR_DOG_FLOPPY_R0, SPR_DOG_FLOPPY_U0
        DW      SPR_DOG_FLOPPY_D1, SPR_DOG_FLOPPY_L1
        DW      SPR_DOG_FLOPPY_R1, SPR_DOG_FLOPPY_U1

; おしっこの絵: 添字 = 耳*8 + 方向*2
SPRPEE:
        DW      SPR_PEE_POINTY_D, SPR_PEE_POINTY_L
        DW      SPR_PEE_POINTY_R, SPR_PEE_POINTY_U
        DW      SPR_PEE_BIG_D, SPR_PEE_BIG_L
        DW      SPR_PEE_BIG_R, SPR_PEE_BIG_U
        DW      SPR_PEE_FLOPPY_D, SPR_PEE_FLOPPY_L
        DW      SPR_PEE_FLOPPY_R, SPR_PEE_FLOPPY_U

; 道路のマス: 添字 = 車線(0=上,1=下)*2 + (x が奇数)
SPRROAD:
        DW      SPR_ROAD_UP_A, SPR_ROAD_UP_B
        DW      SPR_ROAD_DN_A, SPR_ROAD_DN_B

; タイトルの大きい柴犬 (3 行 x 3 列)
; SPRBIG / SPRBIGM / SPRBIGT (大きい柴犬の 9 枚の表) は gen_art.asm にある

SPRITEM:
        DW      SPR_BONE, SPR_SCROLL

; 車の絵 (色 x 向き)。向き 0 = 右へ / 1 = 左へ
SPRCAR:
        DW      OPQ_CAR_R0, OPQ_CAR_L0
        DW      OPQ_CAR_R1, OPQ_CAR_L1
        DW      OPQ_CAR_R2, OPQ_CAR_L2
        DW      OPQ_CAR_R3, OPQ_CAR_L3

; 車の色 (当たり判定の表示などに使う)
CARCOLS:        DB      C_RED, C_BLUE, C_YELLOW, C_WHITE

; ---------------------------------------------------------------- 文字列

; 16x8 を背景色 (0) で消すための不透明データ (3 プレーン x 8 行 x 2 バイト)
OPQ_ERASE:
        DB      0,0,0,0,0,0,0,0,0,0,0,0
        DB      0,0,0,0,0,0,0,0,0,0,0,0
        DB      0,0,0,0,0,0,0,0,0,0,0,0
        DB      0,0,0,0,0,0,0,0,0,0,0,0

; HUD の背景色 (色 1) で 16x8 を塗る不透明データ
OPQ_HUDBG:
        DB      0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
        DB      0xFF,0xFF,0xFF,0xFF
        DB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DB      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

S_1UP:          DB      "1UP!",0
S_TPS:          DB      "TPS",0
S_TPSCLR:       DB      "                   ",0
S_SCORE:        DB      "SCORE",0
S_HI:           DB      "HI",0
S_STAGE:        DB      "STAGE",0
S_TIME:         DB      "TIME",0
S_LIVES:        DB      "LIVES",0
S_AREA:         DB      "AREA",0
S_PAUSE:        DB      "PAUSED",0
S_PAUSE2:       DB      "P:RESUME R:RETRY",0
S_GAMEOVER:     DB      "GAME OVER",0
S_CLEAR:        DB      "STAGE CLEAR",0
S_FAILED:       DB      "TRY AGAIN",0
S_READY:        DB      "READY",0
S_NOGOOD:       DB      "NO GOOD",0
S_MARKED:       DB      "MARKED",0
S_CAUGHT:       DB      "CAUGHT",0
S_OUCH:         DB      "OUCH",0
S_TRAPPED:      DB      "TRAPPED",0
S_LOST:         DB      "LOST",0
S_OUT:          DB      "OUT",0
S_KYAN:         DB      "KYAN",0
S_BONE:         DB      "BONE",0
S_NINJA:        DB      "NINJA",0
S_WASHED:       DB      "WASHED AWAY",0
S_KICKED:       DB      "KICKED OUT",0
S_RAINCOME:     DB      "RAIN IS COMING",0
S_RAIN:         DB      "RAIN",0
S_BONUS:        DB      "BONUS STAGE",0
S_NIGHT:        DB      "NIGHT",0
S_PERFECT:      DB      "PERFECT",0
S_TITLE1:       DB      "SHIBA JINTORI",0
S_TITLE2:       DB      "PC-8801 MKIISR V2",0
S_TITLE3:       DB      "PUSH SPACE TO START",0
S_TITLE4:       DB      "ARROWS:MOVE  SPACE:PEE",0
S_TITLE5:       DB      "LEFT/RIGHT TO PICK A SHIBA",0
S_HISCORE:      DB      "HIGH SCORES",0
S_BOSSCOME:     DB      "BOSS DOG",0
S_EMPTY:        DB      0
