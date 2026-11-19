#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""z80asm.py の符号化テスト。既知のオペコードと突き合わせる。"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z80asm  # noqa: E402

CASES = [
    # --- 8bit ロード
    ("LD A,B", "78"),
    ("LD B,A", "47"),
    ("LD L,(HL)", "6E"),
    ("LD (HL),E", "73"),
    ("LD A,0x12", "3E12"),
    ("LD (HL),0xFF", "36FF"),
    ("LD A,(0x1234)", "3A3412"),
    ("LD (0x1234),A", "323412"),
    ("LD A,(BC)", "0A"),
    ("LD A,(DE)", "1A"),
    ("LD (BC),A", "02"),
    ("LD (DE),A", "12"),
    ("LD A,I", "ED57"),
    ("LD R,A", "ED4F"),
    ("LD C,(IX+5)", "DD4E05"),
    ("LD (IY-3),A", "FD77FD"),
    ("LD (IX+0),0x7F", "DD3600 7F"),
    # --- 16bit ロード
    ("LD BC,0x1234", "013412"),
    ("LD DE,0xFFFF", "11FFFF"),
    ("LD HL,0x8000", "210080"),
    ("LD SP,0xBFF0", "31F0BF"),
    ("LD IX,0x1000", "DD210010"),
    ("LD IY,0x2000", "FD210020"),
    ("LD HL,(0x4000)", "2A0040"),
    ("LD (0x4000),HL", "220040"),
    ("LD BC,(0x4000)", "ED4B0040"),
    ("LD (0x4000),DE", "ED530040"),
    ("LD (0x4000),SP", "ED730040"),
    ("LD SP,HL", "F9"),
    ("LD SP,IX", "DDF9"),
    # --- 算術
    ("ADD A,B", "80"),
    ("ADD B", "80"),
    ("ADD A,(HL)", "86"),
    ("ADD A,0x10", "C610"),
    ("ADC A,C", "89"),
    ("SUB D", "92"),
    ("SBC A,E", "9B"),
    ("AND H", "A4"),
    ("XOR A", "AF"),
    ("OR L", "B5"),
    ("CP 0x20", "FE20"),
    ("CP (IX+1)", "DDBE01"),
    ("ADD HL,BC", "09"),
    ("ADD HL,SP", "39"),
    ("ADD IX,DE", "DD19"),
    ("ADC HL,DE", "ED5A"),
    ("SBC HL,HL", "ED62"),
    ("INC A", "3C"),
    ("INC (HL)", "34"),
    ("INC BC", "03"),
    ("INC IX", "DD23"),
    ("DEC E", "1D"),
    ("DEC HL", "2B"),
    ("DEC (IY+2)", "FD3502"),
    # --- 分岐
    ("JP 0x1234", "C33412"),
    ("JP NZ,0x1234", "C23412"),
    ("JP Z,0x1234", "CA3412"),
    ("JP C,0x1234", "DA3412"),
    ("JP NC,0x1234", "D23412"),
    ("JP PE,0x1234", "EA3412"),
    ("JP M,0x1234", "FA3412"),
    ("JP (HL)", "E9"),
    ("CALL 0x1234", "CD3412"),
    ("CALL NZ,0x1234", "C43412"),
    ("RET", "C9"),
    ("RET Z", "C8"),
    ("RET C", "D8"),
    ("RST 0x38", "FF"),
    ("RST 8", "CF"),
    # --- スタック / 交換
    ("PUSH AF", "F5"),
    ("PUSH BC", "C5"),
    ("POP HL", "E1"),
    ("PUSH IX", "DDE5"),
    ("POP IY", "FDE1"),
    ("EX DE,HL", "EB"),
    ("EX AF,AF'", "08"),
    ("EX (SP),HL", "E3"),
    ("EX (SP),IX", "DDE3"),
    # --- 入出力
    ("IN A,(0x40)", "DB40"),
    ("OUT (0x5C),A", "D35C"),
    ("IN B,(C)", "ED40"),
    ("OUT (C),D", "ED51"),
    ("IM 1", "ED56"),
    # --- シフト・ビット
    ("RLC A", "CB07"),
    ("RL B", "CB10"),
    ("RR (HL)", "CB1E"),
    ("SLA C", "CB21"),
    ("SRL A", "CB3F"),
    ("SRA E", "CB2B"),
    ("BIT 0,A", "CB47"),
    ("BIT 7,(HL)", "CB7E"),
    ("RES 3,B", "CB98"),
    ("SET 5,(HL)", "CBEE"),
    ("SET 2,(IX+4)", "DDCB04D6"),
    ("RLC (IY+1)", "FDCB0106"),
    # --- 引数なし
    ("NOP", "00"),
    ("HALT", "76"),
    ("DI", "F3"),
    ("EI", "FB"),
    ("EXX", "D9"),
    ("LDIR", "EDB0"),
    ("LDDR", "EDB8"),
    ("CPIR", "EDB1"),
    ("NEG", "ED44"),
    ("RLCA", "07"),
    ("RRCA", "0F"),
    ("DAA", "27"),
    ("CPL", "2F"),
    ("SCF", "37"),
    ("CCF", "3F"),
]

# 相対分岐やラベルを含むもの (ORG 0x100 を前提にプログラム全体で比較)
PROGRAMS = [
    ("""
        ORG 0x100
    lbl:
        JR lbl
        JR NZ,lbl
        DJNZ lbl
        JR fwd
    fwd:
        NOP
    """, "18FE 20FC 10FA 1800 00"),
    ("""
        ORG 0x200
    v   EQU 0x1234
        LD HL,v
        LD A,v & 0xFF
        LD B,v >> 8
        LD C,(v >> 4) & 0x0F
        DB 1,2,3
        DW 0x1234,0x5678
        DB "AB",0
        DS 3,0xAA
    """, "213412 3E34 0612 0E03 010203 34127856 414200 AAAAAA"),
    ("""
        ORG 0x300
    glob:
    .loop:
        DEC A
        JR NZ,.loop
    other:
    .loop:
        INC A
        JR NZ,.loop
    """, "3D20FD 3C20FD"),
]


def asm_text(text):
    with tempfile.NamedTemporaryFile('w', suffix='.asm', delete=False,
                                     encoding='utf-8') as f:
        f.write(text)
        path = f.name
    try:
        image, written, syms = z80asm.assemble(path)
    finally:
        os.unlink(path)
    used = [i for i in range(0x10000) if written[i]]
    if not used:
        return b''
    return bytes(image[used[0]:used[-1] + 1])


def main():
    bad = 0
    for src, want in CASES:
        want_b = bytes.fromhex(want.replace(' ', ''))
        try:
            got = asm_text("    ORG 0x100\n    " + src + "\n")
        except Exception as e:
            print("FAIL %-24s 例外: %s" % (src, e))
            bad += 1
            continue
        if got != want_b:
            print("FAIL %-24s 期待 %s / 実際 %s"
                  % (src, want_b.hex().upper(), got.hex().upper()))
            bad += 1
    for src, want in PROGRAMS:
        want_b = bytes.fromhex(want.replace(' ', ''))
        try:
            got = asm_text(src)
        except Exception as e:
            print("FAIL (program) 例外: %s" % e)
            bad += 1
            continue
        if got != want_b:
            print("FAIL (program) 期待 %s / 実際 %s"
                  % (want_b.hex().upper(), got.hex().upper()))
            bad += 1

    # エラーになるべきもの
    must_fail = [
        "LD (HL),(HL)",
        "ADD HL,IX",
        "JR PE,0x100",
        "BIT 8,A",
        "RST 7",
        "FOO A",
    ]
    for src in must_fail:
        try:
            asm_text("    ORG 0x100\n    " + src + "\n")
        except Exception:
            continue
        print("FAIL %-24s エラーになるべきなのに通った" % src)
        bad += 1

    total = len(CASES) + len(PROGRAMS) + len(must_fail)
    print("%d / %d 件 OK" % (total - bad, total))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
