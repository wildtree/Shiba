; ブートセクタが本当に実行されるかを確かめるだけのテスト。
; ROM の IPL はトラック0/セクタ1 の 256 バイトを C000h に読み込んで実行する。
        ORG 0xC000
START:
        DI
        LD      SP,0xC000
        LD      A,0x5A
        LD      (0x8100),A
        LD      A,0xA5
        LD      (0x8101),A
        ; 入口の状態を記録しておく
        LD      A,0x11
        LD      (0x8102),A
        HALT
        ASSERT  $ - START <= 256, "IPL が 256 バイトを超えました"
