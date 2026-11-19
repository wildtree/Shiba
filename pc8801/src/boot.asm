; =====================================================================
; boot.asm - 起動セクタ (トラック0 / セクタ1)
; =====================================================================
; PC-8801 の N88-BASIC ROM は、ディスクから起動するとき
;   ドライブ1 / トラック0 / セクタ1 の 256 バイトを C000h に読み込んで実行する。
; ここはその 256 バイト。本体をディスクから 0100h 以降に読み込んで飛ぶ。
;
; C000h-FFFFh は GVRAM の窓と重なっているが、ここでは GVRAM を選択しないので
; メイン RAM として見えている。本体を読み込み終えるまで GVRAM に触らない。
; =====================================================================

        INCLUDE "defs.asm"
        INCLUDE "gen_size.asm"          ; GAME_SECTORS / GAME_ENTRY (build.py が生成)

        ORG 0xC000

BOOT:
        DI
        LD      SP,STACK_TOP
        ; ROM の割り込みハンドラはこれから消えるので、割り込みを止める
        XOR     A
        OUT     (P_INTMASK),A
        OUT     (P_INTLV),A
        IM      1

        ; 64K RAM モードにする (0000h-7FFFh も RAM になる)
        ;   bit5=25行 bit4=カラー bit3=グラフィック表示 bit2=0(N88) bit1=1(64K RAM) bit0=200行
        LD      A,SYS2_GAME
        OUT     (P_SYS2),A
        ; GVRAM は外しておく
        XOR     A
        OUT     (P_GVOFF),A

        ; 8255 を念のため初期化
        LD      A,FDC_MODE
        OUT     (P_FDD_CTRL),A

        ; ----------------------------------------------------- 本体の読み込み
        ; DE = 転送先, B = 残りセクタ数, H = トラック, L = セクタ
        LD      DE,GAME_ENTRY
        LD      B,GAME_SECTORS
        LD      HL,0x0002               ; トラック0 / セクタ2 から

LOADLOOP:
        LD      A,B
        OR      A
        JR      Z,LOADDONE
        ; このトラックに残っているセクタ数 = 17 - L
        LD      A,17
        SUB     L
        LD      C,A                     ; C = 今回読むセクタ数の上限
        LD      A,B
        CP      C
        JR      NC,.use_c
        LD      C,A                     ; 残りの方が少ないならそれだけ
.use_c:
        ; --- Read Data (02h) ---
        PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      A,0x02
        CALL    PUTCMD
        LD      A,C
        CALL    PUTDAT                  ; セクタ数
        XOR     A
        CALL    PUTDAT                  ; ドライブ 0
        LD      A,H
        CALL    PUTDAT                  ; トラック
        LD      A,L
        CALL    PUTDAT                  ; セクタ
        ; --- Send Data (03h) ---
        LD      A,0x03
        CALL    PUTCMD
        POP     DE
        PUSH    DE
        ; 転送バイト数 = C * 256
        LD      B,C                     ; B = セクタ数 (外側のループ数)
.sect:
        LD      C,0                     ; 内側 256 回
.byte:
        CALL    GETDAT
        LD      (DE),A
        INC     DE
        DEC     C
        JR      NZ,.byte
        DJNZ    .sect

        POP     DE
        POP     HL
        POP     BC                      ; C = 今回読んだセクタ数が戻る
        ; 進める
        LD      A,B
        SUB     C
        LD      B,A                     ; 残りセクタ数
        LD      A,L
        ADD     A,C
        LD      L,A                     ; セクタを進める
        ; 転送先を C * 256 進める
        LD      A,D
        ADD     A,C
        LD      D,A
        ; セクタが 16 を超えたら次のトラック
        LD      A,L
        CP      17
        JR      C,LOADLOOP
        LD      L,1
        INC     H
        JR      LOADLOOP

LOADDONE:
        JP      GAME_ENTRY

; =====================================================================
; ディスクサブシステムとの 8255 ハンドシェイク
; =====================================================================

; どれも A 以外のレジスタを壊さない (データは裏の A' に退避する)

; --- A をコマンドとして送る (ATN を使う) -----------------------------
PUTCMD:
        EX      AF,AF'                  ; データを A' へ
        LD      A,FDC_ATN_SET
        OUT     (P_FDD_CTRL),A          ; ATN = 1
.wrfd:
        IN      A,(P_FDD_C)
        AND     FDC_S_RFD
        JR      Z,.wrfd                 ; サブが RFD = 1 にするのを待つ
        LD      A,FDC_ATN_CLR
        OUT     (P_FDD_CTRL),A          ; ATN = 0
        JR      PUTCOMMON

; --- A をデータとして送る (通常ハンドシェイク) -----------------------
PUTDAT:
        EX      AF,AF'
.wrfd:
        IN      A,(P_FDD_C)
        AND     FDC_S_RFD
        JR      Z,.wrfd
PUTCOMMON:
        EX      AF,AF'                  ; データを A に戻す
        OUT     (P_FDD_B),A             ; データを出す
        LD      A,FDC_DAV_SET
        OUT     (P_FDD_CTRL),A          ; DAV = 1
.wdac:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAC
        JR      Z,.wdac                 ; サブが受け取るのを待つ
        LD      A,FDC_DAV_CLR
        OUT     (P_FDD_CTRL),A          ; DAV = 0
        RET

; --- サブシステムから 1 バイト受け取る -> A --------------------------
GETDAT:
        LD      A,FDC_RFD_SET
        OUT     (P_FDD_CTRL),A          ; RFD = 1 (受け取る用意ができた)
.wdav:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAV
        JR      Z,.wdav
        LD      A,FDC_RFD_CLR
        OUT     (P_FDD_CTRL),A          ; RFD = 0
        IN      A,(P_FDD_A)             ; データを取る
        EX      AF,AF'                  ; 退避
        LD      A,FDC_DAC_SET
        OUT     (P_FDD_CTRL),A          ; DAC = 1
.wdav0:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAV
        JR      NZ,.wdav0               ; DAV が下がるのを待つ
        LD      A,FDC_DAC_CLR
        OUT     (P_FDD_CTRL),A          ; DAC = 0
        EX      AF,AF'
        RET

BOOTEND:
        ASSERT  BOOTEND - BOOT <= 256, "起動セクタが 256 バイトを超えました"
