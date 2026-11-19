; =====================================================================
; disk.asm - ハイスコアをディスクに保存する
; =====================================================================
; 論理トラック 78 (シリンダ 39 / 表) のセクタ 1 を使う。
; 書き込み禁止のディスクでも落ちないように、結果ステータスは見るだけ。
;   +0      目印 (HS_MAGIC2)
;   +1..80  ハイスコア 10 件 x 8 バイト (点 3 / 名前 3 / ステージ 1 / 予備)
;   +81..83 実績 24 個のビット
;   +84     途中経過 (3 色の柴犬でクリアしたか)
; 前の版の形 (目印 HS_MAGIC、1 位の点だけ) も読める。
; =====================================================================

HS_TRACK        EQU 78
HS_SECTOR       EQU 1
HS_MAGIC        EQU 0x8A        ; 前の版 (1 位の点だけ)
HS_MAGIC2       EQU 0x8B

; ---------------------------------------------------------------------
; LOADHISCORE - ディスクからハイスコアを読む
; ---------------------------------------------------------------------
LOADHISCORE:
        LD      A,0x02                  ; Read Data
        CALL    DPUTCMD
        LD      A,1
        CALL    DPUTDAT                 ; 1 セクタ
        XOR     A
        CALL    DPUTDAT                 ; ドライブ 0
        LD      A,HS_TRACK
        CALL    DPUTDAT
        LD      A,HS_SECTOR
        CALL    DPUTDAT
        LD      A,0x03                  ; Send Data
        CALL    DPUTCMD
        LD      HL,SECBUF
        LD      B,0                     ; 256 バイト
.lp:
        CALL    DGETDAT
        LD      (HL),A
        INC     HL
        DJNZ    .lp
        ; 目印を確かめる
        CALL    HSRESET                 ; まず最初の表に
        LD      A,(SECBUF)
        CP      HS_MAGIC2
        JR      Z,.new
        CP      HS_MAGIC
        RET     NZ
        ; 前の版: 1 位の点を "---" で載せる
        LD      HL,SECBUF+1
        LD      DE,HSNEW
        LD      BC,3
        LDIR
        LD      HL,S_OLDNAME
        LD      BC,3
        LDIR
        LD      A,1
        LD      (DE),A
        LD      HL,HISCORES+9*8
        LD      DE,HSNEW
        CALL    CMP24
        RET     NC
        CALL    HSINSERT
        LD      A,1
        LD      (ACHDIRTY),A            ; 新しい形で書きなおす
        RET
.new:
        LD      HL,SECBUF+1
        LD      DE,HISCORES
        LD      BC,10*8
        LDIR
        LD      DE,ACHBITS
        LD      BC,4
        LDIR
        JP      HSSETTOP

S_OLDNAME:      DB      "---"

; ---------------------------------------------------------------------
; SAVEHISCORE - ハイスコアをディスクに書く
; ---------------------------------------------------------------------
SAVEHISCORE:
        LD      HL,SECBUF
        LD      BC,256
        XOR     A
        CALL    MEMFILL
        LD      A,HS_MAGIC2
        LD      (SECBUF),A
        LD      HL,HISCORES
        LD      DE,SECBUF+1
        LD      BC,10*8
        LDIR
        LD      HL,ACHBITS
        LD      BC,4
        LDIR

        LD      A,0x01                  ; Write Data
        CALL    DPUTCMD
        LD      A,1
        CALL    DPUTDAT
        XOR     A
        CALL    DPUTDAT
        LD      A,HS_TRACK
        CALL    DPUTDAT
        LD      A,HS_SECTOR
        CALL    DPUTDAT
        LD      HL,SECBUF
        LD      B,0
.lp:
        LD      A,(HL)
        CALL    DPUTDAT
        INC     HL
        DJNZ    .lp
        ; 結果ステータスを読み捨てる
        LD      A,0x06
        CALL    DPUTCMD
        CALL    DGETDAT
        RET

; =====================================================================
; ディスクサブシステムとの 8255 ハンドシェイク (起動セクタと同じ手順)
; =====================================================================

DPUTCMD:
        EX      AF,AF'
        LD      A,FDC_ATN_SET
        OUT     (P_FDD_CTRL),A
.wrfd:
        IN      A,(P_FDD_C)
        AND     FDC_S_RFD
        JR      Z,.wrfd
        LD      A,FDC_ATN_CLR
        OUT     (P_FDD_CTRL),A
        JR      DPUTCOMMON

DPUTDAT:
        EX      AF,AF'
.wrfd:
        IN      A,(P_FDD_C)
        AND     FDC_S_RFD
        JR      Z,.wrfd
DPUTCOMMON:
        EX      AF,AF'
        OUT     (P_FDD_B),A
        LD      A,FDC_DAV_SET
        OUT     (P_FDD_CTRL),A
.wdac:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAC
        JR      Z,.wdac
        LD      A,FDC_DAV_CLR
        OUT     (P_FDD_CTRL),A
        RET

DGETDAT:
        LD      A,FDC_RFD_SET
        OUT     (P_FDD_CTRL),A
.wdav:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAV
        JR      Z,.wdav
        LD      A,FDC_RFD_CLR
        OUT     (P_FDD_CTRL),A
        IN      A,(P_FDD_A)
        EX      AF,AF'
        LD      A,FDC_DAC_SET
        OUT     (P_FDD_CTRL),A
.wdav0:
        IN      A,(P_FDD_C)
        AND     FDC_S_DAV
        JR      NZ,.wdav0
        LD      A,FDC_DAC_CLR
        OUT     (P_FDD_CTRL),A
        EX      AF,AF'
        RET
