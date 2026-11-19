#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
z80cpu.py - Z80 CPU コア (テスト用)

メモリと I/O は bus オブジェクトに委譲する:
    bus.rb(addr) -> int      メモリ読み
    bus.wb(addr, val)        メモリ書き
    bus.in_port(port) -> int I/O 読み  (port は 16bit、下位8bitが一般的)
    bus.out_port(port, val)  I/O 書き
"""

SF, ZF, YF, HF, XF, PF, NF, CF = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

PARITY = [0] * 256
for _i in range(256):
    _b = _i
    _p = 0
    while _b:
        _p ^= _b & 1
        _b >>= 1
    PARITY[_i] = PF if _p == 0 else 0

# 各命令のおおまかな実行クロック (M1 ウェイトなし)
CYC = [
    4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
    8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
    7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
    7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    7, 7, 7, 7, 7, 7, 4, 7, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 10, 10, 17, 7, 11,
    5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 4, 7, 11,
    5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 4, 7, 11,
    5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 4, 7, 11,
]


class Z80:
    def __init__(self, bus):
        self.bus = bus
        self.reset()

    def reset(self):
        self.a = self.f = 0
        self.b = self.c = self.d = self.e = self.h = self.l = 0
        self.a_ = self.f_ = 0
        self.b_ = self.c_ = self.d_ = self.e_ = self.h_ = self.l_ = 0
        self.ix = self.iy = 0
        self.sp = 0xFFFF
        self.pc = 0
        self.i = self.r = 0
        self.iff1 = self.iff2 = 0
        self.im = 0
        self.halted = False
        self.cycles = 0
        self.int_pending = False

    # ------------------------------------------------------------ レジスタ対

    def _get_bc(self):
        return (self.b << 8) | self.c

    def _set_bc(self, v):
        self.b = (v >> 8) & 0xFF
        self.c = v & 0xFF

    def _get_de(self):
        return (self.d << 8) | self.e

    def _set_de(self, v):
        self.d = (v >> 8) & 0xFF
        self.e = v & 0xFF

    def _get_hl(self):
        return (self.h << 8) | self.l

    def _set_hl(self, v):
        self.h = (v >> 8) & 0xFF
        self.l = v & 0xFF

    def _get_af(self):
        return (self.a << 8) | self.f

    def _set_af(self, v):
        self.a = (v >> 8) & 0xFF
        self.f = v & 0xFF

    bc = property(_get_bc, _set_bc)
    de = property(_get_de, _set_de)
    hl = property(_get_hl, _set_hl)
    af = property(_get_af, _set_af)

    # ------------------------------------------------------------ メモリ補助

    def fetch(self):
        v = self.bus.rb(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetch16(self):
        lo = self.fetch()
        return lo | (self.fetch() << 8)

    def rw(self, a):
        return self.bus.rb(a) | (self.bus.rb((a + 1) & 0xFFFF) << 8)

    def ww(self, a, v):
        self.bus.wb(a, v & 0xFF)
        self.bus.wb((a + 1) & 0xFFFF, (v >> 8) & 0xFF)

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        self.ww(self.sp, v)

    def pop(self):
        v = self.rw(self.sp)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    # ------------------------------------------------------------ 8bit アクセス

    REGNAMES = ('b', 'c', 'd', 'e', 'h', 'l', None, 'a')

    def getr(self, i, idx=None, disp=0):
        if i == 6:
            return self.bus.rb(self.addr_hl(idx, disp))
        if idx is not None and i in (4, 5):
            base = self.ix if idx == 'ix' else self.iy
            return (base >> 8) & 0xFF if i == 4 else base & 0xFF
        return getattr(self, self.REGNAMES[i])

    def setr(self, i, v, idx=None, disp=0):
        v &= 0xFF
        if i == 6:
            self.bus.wb(self.addr_hl(idx, disp), v)
            return
        if idx is not None and i in (4, 5):
            base = self.ix if idx == 'ix' else self.iy
            if i == 4:
                base = (base & 0x00FF) | (v << 8)
            else:
                base = (base & 0xFF00) | v
            if idx == 'ix':
                self.ix = base
            else:
                self.iy = base
            return
        setattr(self, self.REGNAMES[i], v)

    def addr_hl(self, idx, disp):
        if idx is None:
            return self.hl
        base = self.ix if idx == 'ix' else self.iy
        return (base + disp) & 0xFFFF

    def get_rp(self, i, idx=None):
        if i == 0:
            return self.bc
        if i == 1:
            return self.de
        if i == 2:
            if idx == 'ix':
                return self.ix
            if idx == 'iy':
                return self.iy
            return self.hl
        return self.sp

    def set_rp(self, i, v, idx=None):
        v &= 0xFFFF
        if i == 0:
            self.bc = v
        elif i == 1:
            self.de = v
        elif i == 2:
            if idx == 'ix':
                self.ix = v
            elif idx == 'iy':
                self.iy = v
            else:
                self.hl = v
        else:
            self.sp = v

    # ------------------------------------------------------------ 演算

    def add8(self, v, carry=0):
        a = self.a
        r = a + v + carry
        rr = r & 0xFF
        self.f = ((rr & SF)
                  | (ZF if rr == 0 else 0)
                  | (HF if ((a & 0xF) + (v & 0xF) + carry) > 0xF else 0)
                  | (PF if ((a ^ ~v) & (a ^ rr) & 0x80) else 0)
                  | (CF if r > 0xFF else 0))
        self.a = rr

    def sub8(self, v, carry=0):
        a = self.a
        r = a - v - carry
        rr = r & 0xFF
        self.f = ((rr & SF)
                  | (ZF if rr == 0 else 0)
                  | (HF if ((a & 0xF) - (v & 0xF) - carry) < 0 else 0)
                  | (PF if ((a ^ v) & (a ^ rr) & 0x80) else 0)
                  | NF
                  | (CF if r < 0 else 0))
        self.a = rr

    def cp8(self, v):
        a = self.a
        r = a - v
        rr = r & 0xFF
        self.f = ((rr & SF)
                  | (ZF if rr == 0 else 0)
                  | (HF if ((a & 0xF) - (v & 0xF)) < 0 else 0)
                  | (PF if ((a ^ v) & (a ^ rr) & 0x80) else 0)
                  | NF
                  | (CF if r < 0 else 0))

    def and8(self, v):
        self.a &= v
        self.f = (self.a & SF) | (ZF if self.a == 0 else 0) | HF | PARITY[self.a]

    def or8(self, v):
        self.a |= v
        self.f = (self.a & SF) | (ZF if self.a == 0 else 0) | PARITY[self.a]

    def xor8(self, v):
        self.a ^= v
        self.f = (self.a & SF) | (ZF if self.a == 0 else 0) | PARITY[self.a]

    def inc8(self, v):
        r = (v + 1) & 0xFF
        self.f = ((self.f & CF)
                  | (r & SF)
                  | (ZF if r == 0 else 0)
                  | (HF if (v & 0xF) == 0xF else 0)
                  | (PF if v == 0x7F else 0))
        return r

    def dec8(self, v):
        r = (v - 1) & 0xFF
        self.f = ((self.f & CF)
                  | (r & SF)
                  | (ZF if r == 0 else 0)
                  | (HF if (v & 0xF) == 0 else 0)
                  | (PF if v == 0x80 else 0)
                  | NF)
        return r

    def add16(self, a, b):
        r = a + b
        self.f = ((self.f & (SF | ZF | PF))
                  | (HF if ((a & 0x0FFF) + (b & 0x0FFF)) > 0x0FFF else 0)
                  | (CF if r > 0xFFFF else 0))
        return r & 0xFFFF

    def adc16(self, a, b):
        c = self.f & CF
        r = a + b + c
        rr = r & 0xFFFF
        self.f = (((rr >> 8) & SF)
                  | (ZF if rr == 0 else 0)
                  | (HF if ((a & 0x0FFF) + (b & 0x0FFF) + c) > 0x0FFF else 0)
                  | (PF if ((a ^ ~b) & (a ^ rr) & 0x8000) else 0)
                  | (CF if r > 0xFFFF else 0))
        return rr

    def sbc16(self, a, b):
        c = self.f & CF
        r = a - b - c
        rr = r & 0xFFFF
        self.f = (((rr >> 8) & SF)
                  | (ZF if rr == 0 else 0)
                  | (HF if ((a & 0x0FFF) - (b & 0x0FFF) - c) < 0 else 0)
                  | (PF if ((a ^ b) & (a ^ rr) & 0x8000) else 0)
                  | NF
                  | (CF if r < 0 else 0))
        return rr

    def daa(self):
        a = self.a
        cf = self.f & CF
        hf = self.f & HF
        nf = self.f & NF
        diff = 0
        if cf or a > 0x99:
            diff += 0x60
        if hf or (a & 0xF) > 9:
            diff += 0x06
        if nf:
            self.a = (a - diff) & 0xFF
        else:
            self.a = (a + diff) & 0xFF
        newc = CF if (cf or a > 0x99) else 0
        if nf:
            newh = HF if (hf and (a & 0xF) < 6) else 0
        else:
            newh = HF if (a & 0xF) > 9 else 0
        self.f = ((self.a & SF) | (ZF if self.a == 0 else 0)
                  | newh | PARITY[self.a] | nf | newc)

    # ------------------------------------------------------------ 回転・シフト

    def rot(self, op, v):
        c = self.f & CF
        if op == 0:      # RLC
            nc = (v >> 7) & 1
            v = ((v << 1) | nc) & 0xFF
        elif op == 1:    # RRC
            nc = v & 1
            v = ((v >> 1) | (nc << 7)) & 0xFF
        elif op == 2:    # RL
            nc = (v >> 7) & 1
            v = ((v << 1) | (1 if c else 0)) & 0xFF
        elif op == 3:    # RR
            nc = v & 1
            v = ((v >> 1) | (0x80 if c else 0)) & 0xFF
        elif op == 4:    # SLA
            nc = (v >> 7) & 1
            v = (v << 1) & 0xFF
        elif op == 5:    # SRA
            nc = v & 1
            v = ((v >> 1) | (v & 0x80)) & 0xFF
        elif op == 6:    # SLL (未定義命令)
            nc = (v >> 7) & 1
            v = ((v << 1) | 1) & 0xFF
        else:            # SRL
            nc = v & 1
            v = (v >> 1) & 0xFF
        self.f = ((v & SF) | (ZF if v == 0 else 0) | PARITY[v]
                  | (CF if nc else 0))
        return v

    # ------------------------------------------------------------ 実行

    def interrupt(self, vector=0):
        """マスカブル割り込みを受け付ける。vector はデータバスに乗る値。"""
        if not self.iff1:
            return False
        self.halted = False
        self.iff1 = self.iff2 = 0
        self.push(self.pc)
        if self.im == 2:
            self.pc = self.rw(((self.i << 8) | (vector & 0xFF)) & 0xFFFF)
            self.cycles += 19
        else:
            self.pc = 0x0038
            self.cycles += 13
        return True

    def nmi(self):
        self.halted = False
        self.iff1 = 0
        self.push(self.pc)
        self.pc = 0x0066
        self.cycles += 11

    def step(self):
        if self.halted:
            self.cycles += 4
            return 4
        start = self.cycles
        self.r = (self.r + 1) & 0x7F
        op = self.fetch()
        if op == 0xCB:
            self.do_cb(None, 0)
        elif op == 0xED:
            self.do_ed()
        elif op == 0xDD:
            self.do_idx('ix')
        elif op == 0xFD:
            self.do_idx('iy')
        else:
            self.cycles += CYC[op]
            self.do_main(op, None)
        return self.cycles - start

    # -------------------------------------------------- 基本命令

    def do_main(self, op, idx):
        x = op >> 6
        y = (op >> 3) & 7
        z = op & 7

        disp = 0
        if idx is not None and (z == 6 or y == 6) and x in (0, 1, 2):
            # (IX+d) を使う形は変位バイトを読む
            if x == 1 and y == 6 and z == 6:
                pass    # HALT
            elif (x == 1 and (y == 6 or z == 6)) or \
                 (x == 2 and z == 6) or \
                 (x == 0 and z in (4, 5, 6) and y == 6):
                disp = sign8(self.fetch())
                self.cycles += 8

        if x == 0:
            self.main_x0(op, y, z, idx, disp)
        elif x == 1:
            if op == 0x76:
                self.halted = True
            elif y == 6 or z == 6:
                # LD r,(IX+d) / LD (IX+d),r のレジスタ側は通常の H/L を使う
                # (IXH/IXL になるのはメモリを触らない命令だけ)
                v = self.getr(z, idx if z == 6 else None, disp)
                self.setr(y, v, idx if y == 6 else None, disp)
            else:
                self.setr(y, self.getr(z, idx, disp), idx, disp)
        elif x == 2:
            v = self.getr(z, idx, disp)
            self.alu(y, v)
        else:
            self.main_x3(op, y, z, idx)

    def alu(self, y, v):
        if y == 0:
            self.add8(v)
        elif y == 1:
            self.add8(v, 1 if self.f & CF else 0)
        elif y == 2:
            self.sub8(v)
        elif y == 3:
            self.sub8(v, 1 if self.f & CF else 0)
        elif y == 4:
            self.and8(v)
        elif y == 5:
            self.xor8(v)
        elif y == 6:
            self.or8(v)
        else:
            self.cp8(v)

    def cond(self, y):
        f = self.f
        if y == 0:
            return not (f & ZF)
        if y == 1:
            return bool(f & ZF)
        if y == 2:
            return not (f & CF)
        if y == 3:
            return bool(f & CF)
        if y == 4:
            return not (f & PF)
        if y == 5:
            return bool(f & PF)
        if y == 6:
            return not (f & SF)
        return bool(f & SF)

    def main_x0(self, op, y, z, idx, disp):
        if z == 0:
            if y == 0:
                return
            if y == 1:                      # EX AF,AF'
                self.a, self.a_ = self.a_, self.a
                self.f, self.f_ = self.f_, self.f
                return
            if y == 2:                      # DJNZ
                d = sign8(self.fetch())
                self.b = (self.b - 1) & 0xFF
                if self.b:
                    self.pc = (self.pc + d) & 0xFFFF
                    self.cycles += 5
                return
            if y == 3:                      # JR
                d = sign8(self.fetch())
                self.pc = (self.pc + d) & 0xFFFF
                return
            d = sign8(self.fetch())         # JR cc
            if self.cond(y - 4):
                self.pc = (self.pc + d) & 0xFFFF
                self.cycles += 5
            return
        if z == 1:
            if y & 1:                       # ADD HL,rp
                p = y >> 1
                self.set_rp(2, self.add16(self.get_rp(2, idx),
                                          self.get_rp(p, idx)), idx)
            else:                           # LD rp,nn
                self.set_rp(y >> 1, self.fetch16(), idx)
            return
        if z == 2:
            p = y >> 1
            if y == 0:
                self.bus.wb(self.bc, self.a)
            elif y == 1:
                self.a = self.bus.rb(self.bc)
            elif y == 2:
                self.bus.wb(self.de, self.a)
            elif y == 3:
                self.a = self.bus.rb(self.de)
            elif y == 4:
                self.ww(self.fetch16(), self.get_rp(2, idx))
            elif y == 5:
                self.set_rp(2, self.rw(self.fetch16()), idx)
            elif y == 6:
                self.bus.wb(self.fetch16(), self.a)
            else:
                self.a = self.bus.rb(self.fetch16())
            return
        if z == 3:
            p = y >> 1
            v = self.get_rp(p, idx)
            self.set_rp(p, v + (1 if not (y & 1) else -1), idx)
            return
        if z == 4:
            self.setr(y, self.inc8(self.getr(y, idx, disp)), idx, disp)
            return
        if z == 5:
            self.setr(y, self.dec8(self.getr(y, idx, disp)), idx, disp)
            return
        if z == 6:
            self.setr(y, self.fetch(), idx, disp)
            return
        # z == 7
        if y == 0:          # RLCA
            c = (self.a >> 7) & 1
            self.a = ((self.a << 1) | c) & 0xFF
            self.f = (self.f & (SF | ZF | PF)) | (CF if c else 0)
        elif y == 1:        # RRCA
            c = self.a & 1
            self.a = ((self.a >> 1) | (c << 7)) & 0xFF
            self.f = (self.f & (SF | ZF | PF)) | (CF if c else 0)
        elif y == 2:        # RLA
            c = (self.a >> 7) & 1
            self.a = ((self.a << 1) | (1 if self.f & CF else 0)) & 0xFF
            self.f = (self.f & (SF | ZF | PF)) | (CF if c else 0)
        elif y == 3:        # RRA
            c = self.a & 1
            self.a = ((self.a >> 1) | (0x80 if self.f & CF else 0)) & 0xFF
            self.f = (self.f & (SF | ZF | PF)) | (CF if c else 0)
        elif y == 4:        # DAA
            self.daa()
        elif y == 5:        # CPL
            self.a ^= 0xFF
            self.f = (self.f & (SF | ZF | PF | CF)) | HF | NF
        elif y == 6:        # SCF
            self.f = (self.f & (SF | ZF | PF)) | CF
        else:               # CCF
            c = self.f & CF
            self.f = (self.f & (SF | ZF | PF)) | (HF if c else 0) | (0 if c else CF)

    def main_x3(self, op, y, z, idx):
        if z == 0:                          # RET cc
            if self.cond(y):
                self.pc = self.pop()
                self.cycles += 6
            return
        if z == 1:
            if y & 1:
                q = y >> 1
                if q == 0:                  # RET
                    self.pc = self.pop()
                elif q == 1:                # EXX
                    self.b, self.b_ = self.b_, self.b
                    self.c, self.c_ = self.c_, self.c
                    self.d, self.d_ = self.d_, self.d
                    self.e, self.e_ = self.e_, self.e
                    self.h, self.h_ = self.h_, self.h
                    self.l, self.l_ = self.l_, self.l
                elif q == 2:                # JP (HL)
                    self.pc = self.get_rp(2, idx)
                else:                       # LD SP,HL
                    self.sp = self.get_rp(2, idx)
            else:                           # POP rp2
                p = y >> 1
                v = self.pop()
                if p == 3:
                    self.af = v
                else:
                    self.set_rp(p, v, idx)
            return
        if z == 2:                          # JP cc,nn
            a = self.fetch16()
            if self.cond(y):
                self.pc = a
            return
        if z == 3:
            if y == 0:                      # JP nn
                self.pc = self.fetch16()
            elif y == 1:                    # CB prefix (ここには来ない)
                self.do_cb(idx, 0)
            elif y == 2:                    # OUT (n),A
                p = self.fetch()
                self.bus.out_port(p | (self.a << 8), self.a)
            elif y == 3:                    # IN A,(n)
                p = self.fetch()
                self.a = self.bus.in_port(p | (self.a << 8))
            elif y == 4:                    # EX (SP),HL
                v = self.rw(self.sp)
                self.ww(self.sp, self.get_rp(2, idx))
                self.set_rp(2, v, idx)
            elif y == 5:                    # EX DE,HL
                self.de, self.hl = self.hl, self.de
            elif y == 6:                    # DI
                self.iff1 = self.iff2 = 0
            else:                           # EI
                self.iff1 = self.iff2 = 1
            return
        if z == 4:                          # CALL cc,nn
            a = self.fetch16()
            if self.cond(y):
                self.push(self.pc)
                self.pc = a
                self.cycles += 7
            return
        if z == 5:
            if y & 1:
                if y == 1:                  # CALL nn
                    a = self.fetch16()
                    self.push(self.pc)
                    self.pc = a
                return
            p = y >> 1                      # PUSH rp2
            self.push(self.af if p == 3 else self.get_rp(p, idx))
            return
        if z == 6:                          # alu n
            self.alu(y, self.fetch())
            return
        # z == 7 : RST
        self.push(self.pc)
        self.pc = y * 8

    # -------------------------------------------------- CB

    def do_cb(self, idx, _):
        if idx is not None:
            disp = sign8(self.fetch())
            op = self.fetch()
            self.cycles += 23
        else:
            disp = 0
            op = self.fetch()
            self.cycles += 8 if (op & 7) != 6 else 15
        x = op >> 6
        y = (op >> 3) & 7
        z = op & 7

        if idx is not None:
            addr = self.addr_hl(idx, disp)
            v = self.bus.rb(addr)
        else:
            v = self.getr(z, None, 0)

        if x == 0:
            r = self.rot(y, v)
        elif x == 1:                        # BIT
            bit = v & (1 << y)
            self.f = ((self.f & CF) | HF
                      | (ZF | PF if not bit else 0)
                      | (SF if (y == 7 and bit) else 0))
            return
        elif x == 2:
            r = v & ~(1 << y) & 0xFF
        else:
            r = v | (1 << y)

        if idx is not None:
            self.bus.wb(addr, r)
            if z != 6:
                self.setr(z, r, None, 0)
        else:
            self.setr(z, r, None, 0)

    # -------------------------------------------------- ED

    def do_ed(self):
        op = self.fetch()
        x = op >> 6
        y = (op >> 3) & 7
        z = op & 7
        self.cycles += 8

        if x == 1:
            if z == 0:                      # IN r,(C)
                v = self.bus.in_port(self.bc)
                self.f = ((self.f & CF) | (v & SF)
                          | (ZF if v == 0 else 0) | PARITY[v])
                if y != 6:
                    self.setr(y, v, None, 0)
                self.cycles += 4
                return
            if z == 1:                      # OUT (C),r
                v = 0 if y == 6 else self.getr(y, None, 0)
                self.bus.out_port(self.bc, v)
                self.cycles += 4
                return
            if z == 2:                      # SBC/ADC HL,rp
                p = y >> 1
                if y & 1:
                    self.hl = self.adc16(self.hl, self.get_rp(p))
                else:
                    self.hl = self.sbc16(self.hl, self.get_rp(p))
                self.cycles += 7
                return
            if z == 3:                      # LD (nn),rp / LD rp,(nn)
                p = y >> 1
                a = self.fetch16()
                if y & 1:
                    self.set_rp(p, self.rw(a))
                else:
                    self.ww(a, self.get_rp(p))
                self.cycles += 12
                return
            if z == 4:                      # NEG
                v = self.a
                self.a = 0
                self.sub8(v)
                return
            if z == 5:                      # RETN / RETI
                self.pc = self.pop()
                self.iff1 = self.iff2
                self.cycles += 6
                return
            if z == 6:                      # IM n
                self.im = (0, 0, 1, 2, 0, 0, 1, 2)[y]
                return
            # z == 7
            if y == 0:                      # LD I,A
                self.i = self.a
            elif y == 1:                    # LD R,A
                self.r = self.a
            elif y == 2:                    # LD A,I
                self.a = self.i
                self.f = ((self.f & CF) | (self.a & SF)
                          | (ZF if self.a == 0 else 0)
                          | (PF if self.iff2 else 0))
            elif y == 3:                    # LD A,R
                self.a = self.r
                self.f = ((self.f & CF) | (self.a & SF)
                          | (ZF if self.a == 0 else 0)
                          | (PF if self.iff2 else 0))
            elif y == 4:                    # RRD
                v = self.bus.rb(self.hl)
                self.bus.wb(self.hl, ((v >> 4) | (self.a << 4)) & 0xFF)
                self.a = (self.a & 0xF0) | (v & 0x0F)
                self.f = ((self.f & CF) | (self.a & SF)
                          | (ZF if self.a == 0 else 0) | PARITY[self.a])
            elif y == 5:                    # RLD
                v = self.bus.rb(self.hl)
                self.bus.wb(self.hl, ((v << 4) | (self.a & 0x0F)) & 0xFF)
                self.a = (self.a & 0xF0) | ((v >> 4) & 0x0F)
                self.f = ((self.f & CF) | (self.a & SF)
                          | (ZF if self.a == 0 else 0) | PARITY[self.a])
            return

        if x == 2 and z < 4 and y >= 4:
            self.block(y, z)
            return
        # それ以外の ED は NOP 扱い

    def block(self, y, z):
        inc = 1 if (y & 1) == 0 else -1
        repeat = bool(y & 2)
        if z == 0:                          # LDI/LDD/LDIR/LDDR
            v = self.bus.rb(self.hl)
            self.bus.wb(self.de, v)
            self.hl = (self.hl + inc) & 0xFFFF
            self.de = (self.de + inc) & 0xFFFF
            self.bc = (self.bc - 1) & 0xFFFF
            self.f = ((self.f & (SF | ZF | CF))
                      | (PF if self.bc else 0))
            self.cycles += 8
            if repeat and self.bc:
                self.pc = (self.pc - 2) & 0xFFFF
                self.cycles += 5
            return
        if z == 1:                          # CPI/CPD/CPIR/CPDR
            v = self.bus.rb(self.hl)
            a = self.a
            r = (a - v) & 0xFF
            self.hl = (self.hl + inc) & 0xFFFF
            self.bc = (self.bc - 1) & 0xFFFF
            self.f = ((self.f & CF) | NF
                      | (r & SF) | (ZF if r == 0 else 0)
                      | (HF if ((a & 0xF) - (v & 0xF)) < 0 else 0)
                      | (PF if self.bc else 0))
            self.cycles += 8
            if repeat and self.bc and r != 0:
                self.pc = (self.pc - 2) & 0xFFFF
                self.cycles += 5
            return
        if z == 2:                          # INI/IND/INIR/INDR
            v = self.bus.in_port(self.bc)
            self.bus.wb(self.hl, v)
            self.hl = (self.hl + inc) & 0xFFFF
            self.b = (self.b - 1) & 0xFF
            self.f = (ZF if self.b == 0 else 0) | NF
            self.cycles += 8
            if repeat and self.b:
                self.pc = (self.pc - 2) & 0xFFFF
                self.cycles += 5
            return
        # z == 3                            # OUTI/OUTD/OTIR/OTDR
        v = self.bus.rb(self.hl)
        self.b = (self.b - 1) & 0xFF
        self.bus.out_port(self.bc, v)
        self.hl = (self.hl + inc) & 0xFFFF
        self.f = (ZF if self.b == 0 else 0) | NF
        self.cycles += 8
        if repeat and self.b:
            self.pc = (self.pc - 2) & 0xFFFF
            self.cycles += 5

    # -------------------------------------------------- DD / FD

    def do_idx(self, idx):
        op = self.fetch()
        if op == 0xCB:
            self.do_cb(idx, 0)
            return
        if op in (0xDD, 0xFD, 0xED):
            # 連続プレフィクスは直前を無効にして再解釈
            self.pc = (self.pc - 1) & 0xFFFF
            self.cycles += 4
            return
        self.cycles += CYC[op] + 4
        self.do_main(op, idx)

    # -------------------------------------------------- 状態表示

    def state(self):
        return ("PC=%04X SP=%04X AF=%04X BC=%04X DE=%04X HL=%04X IX=%04X IY=%04X"
                % (self.pc, self.sp, self.af, self.bc, self.de, self.hl,
                   self.ix, self.iy))


def sign8(v):
    return v - 256 if v & 0x80 else v
