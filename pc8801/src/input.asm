; =====================================================================
; input.asm - キーボードとジョイスティック
; =====================================================================
; PC-8801 のキーマトリクスはポート 00h-0Eh を読む。押されているビットは 0。
; 読んだあと反転して KEYNOW に入れるので、1 = 押されている。
; =====================================================================

; キーの位置 (ポート, ビットマスク)
K_UP_P          EQU 0x08
K_UP_B          EQU 0x02
K_RIGHT_P       EQU 0x08
K_RIGHT_B       EQU 0x04
K_DOWN_P        EQU 0x0A
K_DOWN_B        EQU 0x02
K_LEFT_P        EQU 0x0A
K_LEFT_B        EQU 0x04
K_W_P           EQU 0x04
K_W_B           EQU 0x80
K_A_P           EQU 0x02
K_A_B           EQU 0x02
K_S_P           EQU 0x04
K_S_B           EQU 0x08
K_D_P           EQU 0x02
K_D_B           EQU 0x10
K_SPACE_P       EQU 0x09
K_SPACE_B       EQU 0x40
K_Z_P           EQU 0x05
K_Z_B           EQU 0x04
K_X_P           EQU 0x05
K_X_B           EQU 0x01
K_P_P           EQU 0x04
K_P_B           EQU 0x01
K_R_P           EQU 0x04
K_R_B           EQU 0x04
K_T_P           EQU 0x04        ; T (速さの表示切り替え) ポート4 bit4
K_T_B           EQU 0x10
K_M_P           EQU 0x03
K_M_B           EQU 0x20
K_ESC_P         EQU 0x09
K_ESC_B         EQU 0x80
K_RET_P         EQU 0x01
K_RET_B         EQU 0x80
K_STOP_P        EQU 0x09
K_STOP_B        EQU 0x01
; テンキー (PC-8801 のゲームはこちらで動かすのがふつう)。ポート 0 = 0..7, ポート 1 bit0 = 8
K_N2_P          EQU 0x00
K_N2_B          EQU 0x04
K_N4_P          EQU 0x00
K_N4_B          EQU 0x10
K_N6_P          EQU 0x00
K_N6_B          EQU 0x40
K_N8_P          EQU 0x01
K_N8_B          EQU 0x01

; ---------------------------------------------------------------------
; READKEYS - キーマトリクスを読んで KEYNOW に入れる (1 = 押されている)
;            前の状態は KEYPREV に残す
; ---------------------------------------------------------------------
READKEYS:
        LD      HL,KEYNOW
        LD      DE,KEYPREV
        LD      BC,15
        LDIR
        LD      HL,KEYNOW
        LD      C,0
        LD      B,15
.lp:
        IN      A,(C)
        CPL
        LD      (HL),A
        INC     HL
        INC     C
        DJNZ    .lp
        ; ジョイスティックを方向キーに合わせて取り込む
        CALL    READJOY
        RET

; ---------------------------------------------------------------------
; READJOY - ジョイスティックを SSG の I/O ポートから読む
;   レジスタ 0Eh を読む (bit0 上 / bit1 下 / bit2 左 / bit3 右)
;   レジスタ 0Fh の bit0/bit1 がトリガ 1/2。いずれも 0 で押されている。
;   ポート A/B を入力にするのは SNDINIT の一度きり (レジスタ 07h の bit6/7)。
;   ここで 07h を書くと効果音のミキサ設定を毎ティック消してしまう。
; ---------------------------------------------------------------------
READJOY:
        LD      A,0x0E
        OUT     (P_OPN_ADDR),A
        EX      (SP),HL                 ; OPN のアドレス設定からデータまでの間合い
        EX      (SP),HL
        IN      A,(P_OPN_DATA)
        LD      (JOYRAW),A              ; 診断表示用 (FF = 何もつながっていない)
        CPL
        AND     0x0F
        RET     Z                       ; 何も倒れていない
        LD      C,A
        LD      HL,KEYNOW
        ; 上
        BIT     0,C
        JR      Z,.nu
        LD      A,(HL)
        ; KEYNOW+8 の bit1
        PUSH    HL
        LD      DE,K_UP_P
        ADD     HL,DE
        LD      A,(HL)
        OR      K_UP_B
        LD      (HL),A
        POP     HL
.nu:
        BIT     1,C
        JR      Z,.nd
        PUSH    HL
        LD      DE,K_DOWN_P
        ADD     HL,DE
        LD      A,(HL)
        OR      K_DOWN_B
        LD      (HL),A
        POP     HL
.nd:
        BIT     2,C
        JR      Z,.nl
        PUSH    HL
        LD      DE,K_LEFT_P
        ADD     HL,DE
        LD      A,(HL)
        OR      K_LEFT_B
        LD      (HL),A
        POP     HL
.nl:
        BIT     3,C
        JR      Z,.nr
        PUSH    HL
        LD      DE,K_RIGHT_P
        ADD     HL,DE
        LD      A,(HL)
        OR      K_RIGHT_B
        LD      (HL),A
        POP     HL
.nr:
        ; トリガ
        LD      A,0x0F
        OUT     (P_OPN_ADDR),A
        EX      (SP),HL
        EX      (SP),HL
        IN      A,(P_OPN_DATA)
        CPL
        AND     0x03
        RET     Z
        LD      HL,KEYNOW+K_SPACE_P
        LD      A,(HL)
        OR      K_SPACE_B
        LD      (HL),A
        RET

; ---------------------------------------------------------------------
; KEYCHK - キーが押されているか
;   入力: B = ポート番号, C = ビットマスク / 出力: A != 0 なら押されている
; ---------------------------------------------------------------------
KEYCHK:
        LD      HL,KEYNOW
        LD      D,0
        LD      E,B
        ADD     HL,DE
        LD      A,(HL)
        AND     C
        RET     Z
        LD      A,1
        OR      A
        RET

; ---------------------------------------------------------------------
; KEYHIT - このフレームに押されたか (前のフレームは離れていた)
;   入力: B = ポート番号, C = ビットマスク
; ---------------------------------------------------------------------
KEYHIT:
        LD      HL,KEYNOW
        LD      D,0
        LD      E,B
        ADD     HL,DE
        LD      A,(HL)
        AND     C
        RET     Z                       ; いま押されていない
        LD      HL,KEYPREV
        ADD     HL,DE
        LD      A,(HL)
        AND     C
        JR      Z,.new
        XOR     A                       ; 前も押されていた = 新しい入力ではない
        RET
.new:
        LD      A,1
        OR      A
        RET

; ---------------------------------------------------------------------
; SCANINPUT - 押されている方向と決定キーをまとめる
;   出力: HELDDIR (0xFF = なし), TAPDIR, ACTPRESS
; ---------------------------------------------------------------------
SCANINPUT:
        LD      A,0xFF
        LD      (TAPDIR),A
        XOR     A
        LD      (ACTPRESS),A
        LD      (DIRMASK),A

        ; --- 4 方向それぞれ押されているか (bit0 下 / bit1 左 / bit2 右 / bit3 上) ---
        ;     矢印キー / WASD / テンキー 2468 のどれでもよい
        LD      B,K_DOWN_P
        LD      C,K_DOWN_B
        CALL    KEYCHK
        JR      NZ,.on0
        LD      B,K_S_P
        LD      C,K_S_B
        CALL    KEYCHK
        JR      NZ,.on0
        LD      B,K_N2_P
        LD      C,K_N2_B
        CALL    KEYCHK
        JR      Z,.off0
.on0:
        LD      HL,DIRMASK
        SET     0,(HL)
.off0:
        LD      B,K_LEFT_P
        LD      C,K_LEFT_B
        CALL    KEYCHK
        JR      NZ,.on1
        LD      B,K_A_P
        LD      C,K_A_B
        CALL    KEYCHK
        JR      NZ,.on1
        LD      B,K_N4_P
        LD      C,K_N4_B
        CALL    KEYCHK
        JR      Z,.off1
.on1:
        LD      HL,DIRMASK
        SET     1,(HL)
.off1:
        LD      B,K_RIGHT_P
        LD      C,K_RIGHT_B
        CALL    KEYCHK
        JR      NZ,.on2
        LD      B,K_D_P
        LD      C,K_D_B
        CALL    KEYCHK
        JR      NZ,.on2
        LD      B,K_N6_P
        LD      C,K_N6_B
        CALL    KEYCHK
        JR      Z,.off2
.on2:
        LD      HL,DIRMASK
        SET     2,(HL)
.off2:
        LD      B,K_UP_P
        LD      C,K_UP_B
        CALL    KEYCHK
        JR      NZ,.on3
        LD      B,K_W_P
        LD      C,K_W_B
        CALL    KEYCHK
        JR      NZ,.on3
        LD      B,K_N8_P
        LD      C,K_N8_B
        CALL    KEYCHK
        JR      Z,.off3
.on3:
        LD      HL,DIRMASK
        SET     3,(HL)
.off3:

        ; --- いちばん新しく押した方向を使う (元の版の Input.Held と同じ) ---
        ; 決まった優先順で選ぶと、前のキーがまだ押されているあいだ
        ; 新しく押したキーが無視されて「向きが変わらない」ことになる。
        LD      A,(DIRPREV)
        CPL
        LD      B,A
        LD      A,(DIRMASK)
        LD      (DIRPREV),A             ; 次のティックのために覚えておく
        AND     B                       ; このティックで新しく押された方向
        JR      Z,.nonew
        CALL    LOWBIT
        LD      (LASTDIR),A
        JR      .resolve
.nonew:
        ; 新しい押下がないとき: いちばん新しい方向がまだ押されていればそのまま
        LD      A,(LASTDIR)
        CP      4
        JR      NC,.pickany
        LD      E,A
        LD      D,0
        LD      HL,BIT4TBL
        ADD     HL,DE
        LD      A,(DIRMASK)
        AND     (HL)
        JR      NZ,.resolve
.pickany:
        ; 離された: 残っている方向があればそれ、なければ「なし」
        LD      A,(DIRMASK)
        OR      A
        LD      A,0xFF
        JR      Z,.setlast
        LD      A,(DIRMASK)
        CALL    LOWBIT
.setlast:
        LD      (LASTDIR),A
.resolve:
        LD      A,(LASTDIR)
        LD      (HELDDIR),A
.act:
        ; おしっこ (スペース / Z / X)
        LD      B,K_SPACE_P
        LD      C,K_SPACE_B
        CALL    KEYHIT
        JR      NZ,.doact
        LD      B,K_Z_P
        LD      C,K_Z_B
        CALL    KEYHIT
        JR      NZ,.doact
        LD      B,K_X_P
        LD      C,K_X_B
        CALL    KEYHIT
        RET     Z
.doact:
        LD      A,1
        LD      (ACTPRESS),A
        RET

; ---------------------------------------------------------------------
; LOWBIT - A (0 でない) のいちばん下の立っているビットの番号を A に返す
; ---------------------------------------------------------------------
LOWBIT:
        LD      B,0
.lp:
        RRCA
        JR      C,.got
        INC     B
        JR      .lp
.got:
        LD      A,B
        RET

BIT4TBL:        DB      0x01,0x02,0x04,0x08

; ---------------------------------------------------------------------
; ANYKEY - 決定キーが押されたか (A != 0)
; ---------------------------------------------------------------------
ANYKEY:
        LD      B,K_SPACE_P
        LD      C,K_SPACE_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_RET_P
        LD      C,K_RET_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_Z_P
        LD      C,K_Z_B
        CALL    KEYHIT
        RET

; ---------------------------------------------------------------------
; KEYUP / KEYDOWN / KEYLEFT / KEYRIGHT - メニューで方向が新しく押されたか (NZ)
;   矢印キーとテンキー 8 2 4 6。WASD は名前入力で文字として使うので見ない。
; ---------------------------------------------------------------------
KEYUP:
        LD      B,K_UP_P
        LD      C,K_UP_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_N8_P
        LD      C,K_N8_B
        JP      KEYHIT
KEYDOWN:
        LD      B,K_DOWN_P
        LD      C,K_DOWN_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_N2_P
        LD      C,K_N2_B
        JP      KEYHIT
KEYLEFT:
        LD      B,K_LEFT_P
        LD      C,K_LEFT_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_N4_P
        LD      C,K_N4_B
        JP      KEYHIT
KEYRIGHT:
        LD      B,K_RIGHT_P
        LD      C,K_RIGHT_B
        CALL    KEYHIT
        RET     NZ
        LD      B,K_N6_P
        LD      C,K_N6_B
        JP      KEYHIT
