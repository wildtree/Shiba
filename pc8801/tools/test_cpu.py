#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""z80cpu.py のテスト。フラグの既知値と、アセンブルしたプログラムの実行結果で検査する。"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z80asm   # noqa: E402
import z80cpu   # noqa: E402


class FlatBus:
    def __init__(self, mem=None):
        self.mem = bytearray(mem or 0x10000)
        self.ports = {}
        self.out_log = []

    def rb(self, a):
        return self.mem[a & 0xFFFF]

    def wb(self, a, v):
        self.mem[a & 0xFFFF] = v & 0xFF

    def in_port(self, p):
        return self.ports.get(p & 0xFF, 0xFF)

    def out_port(self, p, v):
        self.out_log.append((p & 0xFF, v & 0xFF))
        self.ports[p & 0xFF] = v & 0xFF


def run_asm(src, max_steps=2000000, mem=None):
    """ORG 0x100 を前提に組んで、HALT まで走らせる。"""
    with tempfile.NamedTemporaryFile('w', suffix='.asm', delete=False,
                                     encoding='utf-8') as f:
        f.write(src)
        path = f.name
    try:
        image, written, syms = z80asm.assemble(path)
    finally:
        os.unlink(path)
    bus = FlatBus(mem)
    for i in range(0x10000):
        if written[i]:
            bus.mem[i] = image[i]
    cpu = z80cpu.Z80(bus)
    cpu.pc = syms.get('START', 0x100)
    cpu.sp = 0xFF00
    n = 0
    while not cpu.halted and n < max_steps:
        cpu.step()
        n += 1
    if not cpu.halted:
        raise RuntimeError("HALT に到達しませんでした (%d ステップ)" % n)
    return cpu, bus, syms


# ---------------------------------------------------------------- フラグ検査

def flag_cases():
    """(説明, 準備, 期待する a, 期待する f) ... 既知の Z80 フラグ値。"""
    out = []

    def case(name, setup, want_a, want_f):
        out.append((name, setup, want_a, want_f))

    S, Z, H, P, N, C = 0x80, 0x40, 0x10, 0x04, 0x02, 0x01

    case("ADD A,A (A=80h)", "LD A,0x80\n ADD A,A", 0x00, Z | P | C)
    case("ADD A,A (A=01h)", "LD A,0x01\n ADD A,A", 0x02, 0)
    case("ADD A,n 0F+01", "LD A,0x0F\n ADD A,0x01", 0x10, H)
    case("ADD A,n 7F+01", "LD A,0x7F\n ADD A,0x01", 0x80, S | H | P)
    case("ADD A,n FF+01", "LD A,0xFF\n ADD A,0x01", 0x00, Z | H | C)
    case("SUB 10-20", "LD A,0x10\n SUB 0x20", 0xF0, S | N | C)
    case("SUB 20-10", "LD A,0x20\n SUB 0x10", 0x10, N)
    case("SUB 00-01", "LD A,0x00\n SUB 0x01", 0xFF, S | H | N | C)
    case("SUB 80-01", "LD A,0x80\n SUB 0x01", 0x7F, H | P | N)
    case("SUB A,A", "LD A,0x5A\n SUB A", 0x00, Z | N)
    case("CP 10,20", "LD A,0x10\n CP 0x20", 0x10, S | N | C)
    case("CP equal", "LD A,0x42\n CP 0x42", 0x42, Z | N)
    case("AND", "LD A,0xF0\n AND 0x3C", 0x30, H | P)
    case("AND zero", "LD A,0xF0\n AND 0x0F", 0x00, Z | H | P)
    case("OR", "LD A,0x80\n OR 0x01", 0x81, S | P)
    case("XOR A", "LD A,0x37\n XOR A", 0x00, Z | P)
    case("INC 0F", "LD A,0x0F\n SCF\n INC A", 0x10, H | C)
    case("INC 7F", "LD A,0x7F\n INC A", 0x80, S | H | P)
    case("INC FF", "LD A,0xFF\n INC A", 0x00, Z | H)
    case("DEC 10", "LD A,0x10\n DEC A", 0x0F, H | N)
    case("DEC 01", "LD A,0x01\n DEC A", 0x00, Z | N)
    case("DEC 00", "LD A,0x00\n DEC A", 0xFF, S | H | N)
    case("DEC 80", "LD A,0x80\n DEC A", 0x7F, H | P | N)
    case("ADC with carry", "LD A,0x0F\n SCF\n ADC A,0x00", 0x10, H)
    case("SBC with carry", "LD A,0x10\n SCF\n SBC A,0x00", 0x0F, H | N)
    case("RLCA 80", "LD A,0x80\n RLCA", 0x01, C)
    case("RRCA 01", "LD A,0x01\n RRCA", 0x80, C)
    case("RLA c=1", "LD A,0x80\n SCF\n RLA", 0x01, C)
    case("RRA c=1", "LD A,0x01\n SCF\n RRA", 0x80, C)
    case("CPL", "LD A,0x55\n CPL", 0xAA, H | N)
    case("NEG 01", "LD A,0x01\n NEG", 0xFF, S | H | N | C)
    case("NEG 00", "LD A,0x00\n NEG", 0x00, Z | N)
    case("NEG 80", "LD A,0x80\n NEG", 0x80, S | P | N | C)
    case("SLA 80", "LD A,0x80\n SLA A", 0x00, Z | P | C)
    case("SRL 01", "LD A,0x01\n SRL A", 0x00, Z | P | C)
    case("SRA 81", "LD A,0x81\n SRA A", 0xC0, S | P | C)
    case("RLC 80", "LD A,0x80\n RLC A", 0x01, C)
    case("DAA 09+01", "LD A,0x09\n ADD A,0x01\n DAA", 0x10, H)
    case("DAA 19+01", "LD A,0x19\n ADD A,0x01\n DAA", 0x20, H)
    case("DAA 99+01", "LD A,0x99\n ADD A,0x01\n DAA", 0x00, Z | H | P | C)
    case("DAA 50+50", "LD A,0x50\n ADD A,0x50\n DAA", 0x00, Z | P | C)
    return out


def check_flags():
    bad = 0
    for (name, setup, want_a, want_f) in flag_cases():
        src = "    ORG 0x100\nSTART:\n    " + setup.replace("\n ", "\n    ") + "\n    HALT\n"
        try:
            cpu, bus, syms = run_asm(src)
        except Exception as e:
            print("FAIL %-22s 例外 %s" % (name, e))
            bad += 1
            continue
        # 未定義フラグ (bit3, bit5) は比較から外す
        got_f = cpu.f & ~(0x28)
        if cpu.a != want_a or got_f != want_f:
            print("FAIL %-22s A 期待%02X/実際%02X  F 期待%02X/実際%02X"
                  % (name, want_a, cpu.a, want_f, got_f))
            bad += 1
    return bad, len(flag_cases())


# ---------------------------------------------------------------- プログラム検査

PROGS = [
    # 16bit 演算
    ("ADD HL,DE", """
        ORG 0x100
    START:
        LD HL,0x1234
        LD DE,0x5678
        ADD HL,DE
        LD (0x200),HL
        HALT
    """, {0x200: 0xAC, 0x201: 0x68}),
    ("SBC HL,HL zero", """
        ORG 0x100
    START:
        LD HL,0x1234
        SCF
        CCF
        SBC HL,HL
        LD (0x200),HL
        LD A,F_DUMMY
        HALT
    F_DUMMY EQU 0
    """, {0x200: 0x00, 0x201: 0x00}),
    ("ADC HL,DE with carry", """
        ORG 0x100
    START:
        LD HL,0xFFFF
        LD DE,0x0000
        SCF
        ADC HL,DE
        LD (0x200),HL
        HALT
    """, {0x200: 0x00, 0x201: 0x00}),
    # ループと DJNZ
    ("sum 1..10 via DJNZ", """
        ORG 0x100
    START:
        LD B,10
        XOR A
    .lp:
        ADD A,B
        DJNZ .lp
        LD (0x200),A
        HALT
    """, {0x200: 55}),
    # LDIR
    ("LDIR copy", """
        ORG 0x100
    START:
        LD HL,src
        LD DE,0x300
        LD BC,5
        LDIR
        HALT
    src:
        DB 1,2,3,4,5
    """, {0x300: 1, 0x301: 2, 0x302: 3, 0x303: 4, 0x304: 5}),
    # LDDR
    ("LDDR copy", """
        ORG 0x100
    START:
        LD HL,src+4
        LD DE,0x304
        LD BC,5
        LDDR
        HALT
    src:
        DB 9,8,7,6,5
    """, {0x300: 9, 0x304: 5}),
    # CPIR
    ("CPIR find", """
        ORG 0x100
    START:
        LD HL,tbl
        LD BC,8
        LD A,0x33
        CPIR
        DEC HL
        LD A,L
        SUB tbl & 0xFF
        LD (0x200),A
        HALT
    tbl:
        DB 0x11,0x22,0x33,0x44,0,0,0,0
    """, {0x200: 2}),
    # IX/IY
    ("IX indexed", """
        ORG 0x100
    START:
        LD IX,0x300
        LD (IX+0),0x11
        LD (IX+1),0x22
        LD A,(IX+1)
        LD (IX+2),A
        LD IY,0x310
        LD (IY-1),0x99
        HALT
    """, {0x300: 0x11, 0x301: 0x22, 0x302: 0x22, 0x30F: 0x99}),
    # スタックと CALL/RET
    ("call/ret", """
        ORG 0x100
    START:
        LD A,1
        CALL sub
        CALL sub
        LD (0x200),A
        HALT
    sub:
        ADD A,A
        RET
    """, {0x200: 4}),
    # 条件分岐の網羅
    ("conditions", """
        ORG 0x100
    START:
        LD HL,0x200
        ; Z
        XOR A
        LD A,0
        JR Z,.z
        LD (HL),0xEE
        JR .n1
    .z: LD (HL),1
    .n1:
        INC HL
        ; NZ
        LD A,5
        OR A
        JR NZ,.nz
        LD (HL),0xEE
        JR .n2
    .nz: LD (HL),2
    .n2:
        INC HL
        ; C
        LD A,0
        SUB 1
        JP C,.c
        LD (HL),0xEE
        JP .n3
    .c: LD (HL),3
    .n3:
        INC HL
        ; M (negative)
        LD A,0x80
        OR A
        JP M,.m
        LD (HL),0xEE
        JP .n4
    .m: LD (HL),4
    .n4:
        INC HL
        ; PE (parity even)
        LD A,0x03
        OR A
        JP PE,.pe
        LD (HL),0xEE
        JP .n5
    .pe: LD (HL),5
    .n5:
        HALT
    """, {0x200: 1, 0x201: 2, 0x202: 3, 0x203: 4, 0x204: 5}),
    # BIT / SET / RES
    ("bit ops", """
        ORG 0x100
    START:
        LD A,0x00
        SET 0,A
        SET 7,A
        LD (0x200),A
        RES 0,A
        LD (0x201),A
        BIT 7,A
        LD A,0
        JR Z,.zero
        LD A,1
    .zero:
        LD (0x202),A
        HALT
    """, {0x200: 0x81, 0x201: 0x80, 0x202: 1}),
    # 16bit 乗算 (実際のゲームで使う形)
    ("mul 8x8", """
        ORG 0x100
    START:
        LD H,0
        LD E,13
        LD D,0
        LD A,17
        LD B,8
        LD HL,0
    .lp:
        ADD HL,HL
        RLCA
        JR NC,.skip
        ADD HL,DE
    .skip:
        DJNZ .lp
        LD (0x200),HL
        HALT
    """, {0x200: (13 * 17) & 0xFF, 0x201: (13 * 17) >> 8}),
    # OUT/IN
    ("out port", """
        ORG 0x100
    START:
        LD A,0x5A
        OUT (0x5C),A
        LD A,0x01
        OUT (0x53),A
        HALT
    """, {}),
    # EX / EXX
    ("ex and exx", """
        ORG 0x100
    START:
        LD HL,0x1111
        LD DE,0x2222
        EX DE,HL
        LD (0x200),HL
        LD BC,0x3333
        EXX
        LD BC,0x4444
        EXX
        LD (0x202),BC
        HALT
    """, {0x200: 0x22, 0x201: 0x22, 0x202: 0x33, 0x203: 0x33}),
]


def check_progs():
    bad = 0
    for (name, src, expect) in PROGS:
        try:
            cpu, bus, syms = run_asm(src)
        except Exception as e:
            print("FAIL %-22s 例外 %s" % (name, e))
            bad += 1
            continue
        for addr, want in expect.items():
            got = bus.mem[addr]
            if got != want:
                print("FAIL %-22s [%04X] 期待%02X / 実際%02X"
                      % (name, addr, want, got))
                bad += 1
                break
    return bad, len(PROGS)


def main():
    b1, t1 = check_flags()
    b2, t2 = check_progs()
    print("フラグ %d/%d、プログラム %d/%d" % (t1 - b1, t1, t2 - b2, t2))
    return 1 if (b1 or b2) else 0


if __name__ == '__main__':
    sys.exit(main())
