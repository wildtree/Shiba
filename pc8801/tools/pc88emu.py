#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pc88emu.py - PC-8801mkIISR エミュレータ (テスト用)

実機 ROM (emulator/ROM/n88.rom など) を読み込み、D88 イメージから
本物の N88-BASIC ROM の IPL でブートできる。ディスクサブシステムは
8255 ハンドシェイクのレベルで模擬する (サブ CPU は走らせない)。

使い方:
    python pc88emu.py disk.d88 --frames 120 --png out.png
    python pc88emu.py disk.d88 --boot direct --entry 0x0000 --bin game.bin
"""

import argparse
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import d88 as d88mod   # noqa: E402
import z80cpu          # noqa: E402

CPU_HZ = 3993600            # 4MHz 相当
FRAME_CYCLES = CPU_HZ // 60
TIMER_CYCLES = CPU_HZ // 600
VBLANK_START = FRAME_CYCLES * 86 // 100

ROMDIR_DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              '..', 'emulator', 'ROM')


# ==========================================================================
# ディスクサブシステム (8255 ハンドシェイクの模擬)
# ==========================================================================

DRIVE_STATUS = [0x10]
# テスト用の設定: [port40 bit3, DIP SW1(port30), DIP SW2(port31)]
SENSE = {'p40b3': 0, 'dsw1': 0x03, 'dsw2': 0x40}


class DiskSub:
    # 結果ステータス: bit7 I/O 終了, bit6 読み出しバッファにデータあり, bit0 エラー
    def __init__(self, disk, verbose=0, subrom=None):
        self.disk = disk
        self.verbose = verbose
        # サブシステム側のメモリ (0000-07FF がシステム ROM、5000- が読み出しバッファ)
        self.subram = bytearray(0x10000)
        if subrom:
            self.subram[0:len(subrom)] = subrom
        self.portc_out = 0      # ホストが書いた port C (bit7 ATN,6 DAC,5 RFD,4 DAV)
        self.portb = 0          # ホスト → サブ
        self.porta = 0          # サブ → ホスト
        self.atn_latch = 0
        self.sdac = 0
        self.srfd = 0
        self.sdav = 0
        self.buffer = bytearray()
        self.buffer_addr = 0x5000
        self.status = 0x80
        self.motor = False
        self.surface = 0x0F
        self.log = []
        self.task = self.main()
        self.advance()

    # ------------------------------------------------------------ ホスト側 I/O

    @property
    def atn(self):
        return (self.portc_out >> 7) & 1

    @property
    def hdac(self):
        return (self.portc_out >> 6) & 1

    @property
    def hrfd(self):
        return (self.portc_out >> 5) & 1

    @property
    def hdav(self):
        return (self.portc_out >> 4) & 1

    def write_porta(self, v):      # 通常は入力なので無視
        pass

    def write_portb(self, v):
        self.portb = v & 0xFF
        self.advance()

    def write_portc(self, v):
        old = self.portc_out
        self.portc_out = v & 0xFF
        if (v & 0x80) and not (old & 0x80):
            self.atn_latch = 1
        self.advance()

    def write_control(self, v):
        if v & 0x80:
            # モードセット: port C をクリア
            self.portc_out = 0
            self.atn_latch = 0
        else:
            # ビットセット/リセット: bit3-1 = ビット番号, bit0 = 1 セット
            bit = (v >> 1) & 7
            if v & 1:
                self.portc_out |= (1 << bit)
                if bit == 7:
                    self.atn_latch = 1
            else:
                self.portc_out &= ~(1 << bit) & 0xFF
        self.advance()

    def read_porta(self):
        return self.porta

    def read_portc(self):
        return (self.sdac << 2) | (self.srfd << 1) | self.sdav

    # ------------------------------------------------------------ 状態機械

    def advance(self):
        for _ in range(4096):
            before = (self.srfd, self.sdac, self.sdav, self.porta)
            try:
                next(self.task)
            except StopIteration:
                return
            if (self.srfd, self.sdac, self.sdav, self.porta) == before:
                return

    @staticmethod
    def wait(pred):
        while not pred():
            yield

    def recv(self):
        """1 バイト受信して (data, コマンドか) を返す。"""
        self.srfd = 1
        yield from self.wait(lambda: self.hdav == 1)
        was_atn = self.atn_latch
        self.atn_latch = 0
        self.srfd = 0
        data = self.portb
        self.sdac = 1
        yield from self.wait(lambda: self.hdav == 0)
        self.sdac = 0
        return data, was_atn

    def send(self, v):
        yield from self.wait(lambda: self.hrfd == 1)
        self.porta = v & 0xFF
        self.sdav = 1
        yield from self.wait(lambda: self.hdac == 1)
        self.sdav = 0
        yield from self.wait(lambda: self.hdac == 0)

    def send_fast(self, data):
        """高速ハンドシェイク: DAV の立ち下がりも 1 バイト分として使う。"""
        i = 0
        n = len(data)
        while i < n:
            yield from self.wait(lambda: self.hrfd == 1)
            self.porta = data[i] & 0xFF
            self.sdav = 1
            i += 1
            yield from self.wait(lambda: self.hdac == 1)
            if i < n:
                self.porta = data[i] & 0xFF
                i += 1
            self.sdav = 0
            yield from self.wait(lambda: self.hdac == 0)

    # ------------------------------------------------------------ コマンド

    def main(self):
        while True:
            data, is_cmd = yield from self.recv()
            if not is_cmd:
                continue
            yield from self.command(data)

    def note(self, msg):
        self.log.append(msg)
        if self.verbose:
            print("[FDD] " + msg)

    def command(self, cmd):
        self.log.append("cmd %02X" % cmd)
        if cmd == 0x00:                                  # Initialize
            self.note("Initialize")
            self.motor = True
            self.status = 0x80
            return
        if cmd in (0x01, 0x11):                          # Write Data
            nsec, _ = yield from self.recv()
            drv, _ = yield from self.recv()
            trk, _ = yield from self.recv()
            sec, _ = yield from self.recv()
            self.note("Write drv=%d trk=%d sec=%d nsec=%d" % (drv, trk, sec, nsec))
            total = (nsec or 256) * 256
            buf = bytearray()
            for _ in range(total):
                b, _ = yield from self.recv()
                buf.append(b)
            ok = True
            for i in range(nsec or 256):
                try:
                    self.disk.put(trk, sec + i, buf[i * 256:(i + 1) * 256])
                except ValueError:
                    ok = False
            self.status = 0x80 if ok else 0x81
            return
        if cmd == 0x02:                                  # Read Data
            nsec, _ = yield from self.recv()
            drv, _ = yield from self.recv()
            trk, _ = yield from self.recv()
            sec, _ = yield from self.recv()
            self.note("Read drv=%d trk=%d sec=%d nsec=%d" % (drv, trk, sec, nsec))
            self.buffer = bytearray()
            n = nsec or 256
            err = False
            for i in range(n):
                s = self.disk.get(trk, sec + i)
                if s is None:
                    err = True
                    s = bytearray(256)
                self.buffer += s
            self.subram[0x5000:0x5000 + len(self.buffer)] = self.buffer
            self.status = 0x81 if err else 0xC0
            return
        if cmd in (0x03, 0x12):                          # Send Data
            self.note("Send Data %d バイト%s"
                      % (len(self.buffer), " (高速)" if cmd == 0x12 else ""))
            data = bytes(self.buffer)
            if cmd == 0x12:
                yield from self.send_fast(data)
            else:
                for b in data:
                    yield from self.send(b)
            self.status = 0x80
            return
        if cmd == 0x06:                                  # Send Result Status
            yield from self.send(self.status)
            return
        if cmd == 0x07:                                  # Send Drive Status
            yield from self.send(DRIVE_STATUS[0])
            return
        if cmd == 0x08:                                  # Test Memory
            yield from self.send(0x80)
            return
        if cmd == 0x14:                                  # Sense Device Status
            drv, _ = yield from self.recv()
            yield from self.send(0x38)                   # 両面・トラック0・レディ
            return
        if cmd == 0x17:                                  # Set Surface Mode
            m, _ = yield from self.recv()
            self.surface = m
            self.note("Set Surface Mode %02X" % m)
            return
        if cmd == 0x18:                                  # Send Surface Mode
            yield from self.send(self.surface)
            return
        if cmd == 0x1F:                                  # Set Disk Mode
            drv, _ = yield from self.recv()
            code, _ = yield from self.recv()
            self.note("Set Disk Mode drv=%d code=%02X" % (drv, code))
            return
        if cmd == 0x20:                                  # Send Disk Mode
            drv, _ = yield from self.recv()
            yield from self.send(0x01)                   # 2D / 256 バイト
            return
        if cmd == 0x21:                                  # Set Boundary Mode
            m, _ = yield from self.recv()
            return
        if cmd == 0x22:
            yield from self.send(0x02)
            return
        if cmd == 0x23:                                  # Drive Ready Check
            drv, _ = yield from self.recv()
            yield from self.send(0x00)                   # ディスク挿入済み
            return
        if cmd == 0x13:                                  # Error Info
            for b in (0x02, 0x00, 0x00, 0x00, 0, 0, 1, 1):
                yield from self.send(b)
            return
        if cmd in (0x09, 0x0B, 0x15):                    # Send Memory 系
            ah, _ = yield from self.recv()
            al, _ = yield from self.recv()
            bh, _ = yield from self.recv()
            bl, _ = yield from self.recv()
            start = (ah << 8) | al
            if cmd == 0x09:
                end = (bh << 8) | bl
                n = (end - start + 1) & 0xFFFF
            else:
                n = (bh << 8) | bl
            if n == 0:
                n = 0x10000
            self.note("Send Memory%s %04X..%04X (%d バイト)"
                      % ('2' if cmd == 0x0B else ('(高速)' if cmd == 0x15 else ''),
                         start, (start + n - 1) & 0xFFFF, n))
            data = bytes(self.subram[start:start + n])
            if len(data) < n:
                data = data + bytes(n - len(data))
            if cmd == 0x15:
                yield from self.send_fast(data)
            else:
                for b in data:
                    yield from self.send(b)
            self.status = 0x80
            return
        if cmd in (0x0C, 0x16):                          # Receive Memory 系
            ah, _ = yield from self.recv()
            al, _ = yield from self.recv()
            bh, _ = yield from self.recv()
            bl, _ = yield from self.recv()
            start = (ah << 8) | al
            n = ((bh << 8) | bl) or 0x10000
            self.note("Receive Memory %04X (%d バイト)" % (start, n))
            for i in range(n):
                b, _ = yield from self.recv()
                self.subram[(start + i) & 0xFFFF] = b
            self.status = 0x80
            return
        if cmd == 0x0E:                                  # Load Data
            nsec, _ = yield from self.recv()
            drv, _ = yield from self.recv()
            trk, _ = yield from self.recv()
            sec, _ = yield from self.recv()
            ah, _ = yield from self.recv()
            al, _ = yield from self.recv()
            addr = (ah << 8) | al
            self.note("Load Data drv=%d trk=%d sec=%d nsec=%d -> %04X"
                      % (drv, trk, sec, nsec, addr))
            err = False
            for i in range(nsec or 256):
                srec = self.disk.get(trk, sec + i)
                if srec is None:
                    err = True
                    srec = bytearray(256)
                self.subram[(addr + i * 256) & 0xFFFF:
                            (addr + i * 256 + 256) & 0x1FFFF] = srec
            self.status = 0x81 if err else 0x80
            return
        if cmd == 0x0F:                                  # Save Data
            nsec, _ = yield from self.recv()
            drv, _ = yield from self.recv()
            trk, _ = yield from self.recv()
            sec, _ = yield from self.recv()
            ah, _ = yield from self.recv()
            al, _ = yield from self.recv()
            addr = (ah << 8) | al
            self.note("Save Data drv=%d trk=%d sec=%d nsec=%d <- %04X"
                      % (drv, trk, sec, nsec, addr))
            ok = True
            for i in range(nsec or 256):
                try:
                    self.disk.put(trk, sec + i,
                                  self.subram[addr + i * 256: addr + i * 256 + 256])
                except ValueError:
                    ok = False
            self.status = 0x80 if ok else 0x81
            return
        if cmd == 0x0D:                                  # Execute
            ah, _ = yield from self.recv()
            al, _ = yield from self.recv()
            self.note("Execute %04X (無視)" % ((ah << 8) | al))
            self.status = 0x80
            return
        if cmd == 0x0A:                                  # Outmargin Support
            d, _ = yield from self.recv()
            return
        if cmd == 0x10:                                  # Load & Go
            self.note("Load & Go")
            srec = self.disk.get(0, 1) or bytearray(256)
            self.subram[0x5000:0x5100] = srec
            self.status = 0x80
            return
        if cmd in (0x19, 0x1A, 0x05):
            self.note("コマンド %02X (無視)" % cmd)
            self.status = 0x80
            return
        self.note("未対応コマンド %02X" % cmd)
        self.status = 0x81


# ==========================================================================
# 本体
# ==========================================================================

class PC88:
    def __init__(self, romdir=ROMDIR_DEFAULT, disk=None, verbose=0):
        self.verbose = verbose
        self.ram = bytearray(0x10000)
        self.hi_tvram = bytearray(0x1000)
        self.gvram = [bytearray(0x4000) for _ in range(3)]
        self.romdir = romdir
        self.rom_n88 = self.load_rom('n88.rom', 0x8000)
        self.rom_n88_ext = [self.load_rom('n88_%d.rom' % i, 0x2000, True)
                            for i in range(4)]
        self.rom_n80 = self.load_rom('n80.rom', 0x8000, True)

        self.port30 = 0x00
        self.port31 = 0x31       # MAME のリセット値
        self.port32 = 0x00
        self.port34 = 0x00
        self.port35 = 0x00
        self.port40 = 0x00
        self.port53 = 0x00
        self.palette = list(range(8))
        # アナログパレット: 各色の R,G,B (0..7)
        self.palram = [[7 if (i & 2) else 0, 7 if (i & 4) else 0,
                        7 if (i & 1) else 0] for i in range(8)]
        self.border = [0, 0, 0]
        self.bgpal = [0, 0, 0]
        self.bgcolor = 0
        self.vram_sel = -1       # -1: メイン RAM, 0..2: GVRAM プレーン
        self.text_win = 0x80
        # テキスト面 (DMAC チャネル 2 と CRTC の設定だけ覚えて、描くときに読む)
        self.dma_addr2 = 0xF3C8
        self.dma_ff = 0
        self.crtc_cmd = None
        self.crtc_params = []
        self.crtc_p5 = 0x13
        # GVRAM のプレーンを出しているのに C000h-EFFFh のコードが動いた回数
        self.hi_conflict = 0
        self.ext_rom_bank = 0xFF
        self.alu_latch = [0, 0, 0]

        self.keys = {}           # ポート番号 -> 押されているビットのマスク
        self.opn_addr = 0
        self.opn_regs = bytearray(256)
        self.opn_log = None             # [] にすると書き込みを記録する
        self.io_unknown = {}
        self.trace_fdd = None
        # 割り込みコントローラ
        self.int_level = 0      # ポート E4h (この値より小さいレベルだけ許可)
        self.int_mask = 0       # ポート E6h (bit0 タイマ, bit1 VRTC, bit2 RS-232C)
        self.pending = 0
        self.next_timer = TIMER_CYCLES
        self.next_vrtc = VBLANK_START
        self.int_count = [0] * 8

        self.disk = disk or d88mod.blank_2d()
        subrom = self.load_rom('disk.rom', 0x800, True)
        self.fdd = DiskSub(self.disk, verbose=verbose, subrom=bytes(subrom))
        self.cpu = z80cpu.Z80(self)
        self.frame = 0

    # ------------------------------------------------------------------ ROM

    def load_rom(self, name, size, optional=False):
        p = os.path.join(self.romdir, name)
        if not os.path.isfile(p):
            if optional:
                return bytearray(size)
            raise SystemExit("ROM が見つかりません: " + p)
        with open(p, 'rb') as f:
            raw = bytearray(f.read())
        if len(raw) < size:
            raw += bytearray(size - len(raw))
        return raw[:size]

    # ------------------------------------------------------------------ メモリ

    @property
    def mmode(self):      # 1: 64K RAM モード
        return (self.port31 >> 1) & 1

    @property
    def rmode(self):      # 1: N-BASIC
        return (self.port31 >> 2) & 1

    @property
    def tmode(self):      # 0: F000-FFFF が高速 TVRAM
        return (self.port32 >> 4) & 1

    def rb(self, a):
        a &= 0xFFFF
        if a < 0x8000:
            if self.mmode:
                return self.ram[a]
            if self.rmode:
                return self.rom_n80[a]
            if 0x6000 <= a <= 0x7FFF and not (self.ext_rom_bank & 1):
                bank = self.port32 & 3
                return self.rom_n88_ext[bank][a - 0x6000]
            return self.rom_n88[a]
        if a < 0xC000:
            if 0x8000 <= a <= 0x83FF and not self.mmode and not self.rmode:
                base = (self.text_win << 8) & 0xFFFF
                return self.ram[(base + (a - 0x8000)) & 0xFFFF]
            return self.ram[a]
        if self.vram_sel >= 0:
            if 0xC000 <= self.cpu.pc < 0xF000:
                self.hi_conflict += 1
            return self.gvram[self.vram_sel][a - 0xC000]
        if a >= 0xF000 and not self.tmode:
            return self.hi_tvram[a - 0xF000]
        return self.ram[a]

    def wb(self, a, v):
        a &= 0xFFFF
        v &= 0xFF
        if a < 0x8000:
            # ROM 選択中でも書き込みはメイン RAM へ行く
            self.ram[a] = v
            return
        if a < 0xC000:
            if 0x8000 <= a <= 0x83FF and not self.mmode and not self.rmode:
                base = (self.text_win << 8) & 0xFFFF
                self.ram[(base + (a - 0x8000)) & 0xFFFF] = v
                return
            self.ram[a] = v
            return
        if self.vram_sel >= 0:
            self.gvram[self.vram_sel][a - 0xC000] = v
            return
        if (self.port35 & 0x80):
            self.alu_write(a - 0xC000, v)
            return
        if a >= 0xF000 and not self.tmode:
            self.hi_tvram[a - 0xF000] = v
            return
        self.ram[a] = v

    def alu_write(self, off, v):
        """拡張アクセスモード (ポート 34h/35h) の 3 プレーン同時書き込み。"""
        gdm = (self.port35 >> 4) & 3
        if gdm != 0:
            # 本移植では使わないので単純化
            for p in range(3):
                self.gvram[p][off] = v
            return
        for p in range(3):
            mode = ((self.port34 >> (p * 4)) & 1) | (((self.port34 >> (p * 4 + 3)) & 1) << 1)
            cur = self.gvram[p][off]
            if mode == 0:        # ビットリセット
                self.gvram[p][off] = cur & (~v & 0xFF)
            elif mode == 1:      # ビットセット
                self.gvram[p][off] = cur | v
            elif mode == 2:      # ビット反転
                self.gvram[p][off] = cur ^ v
            # mode == 3 は何もしない

    # ------------------------------------------------------------------ I/O

    def in_port(self, p):
        port = p & 0xFF
        if port <= 0x0E:
            return 0xFF & ~self.keys.get(port, 0) & 0xFF
        if port == 0x30:
            return SENSE['dsw1']
        if port == 0x31:
            return SENSE['dsw2']
        if port == 0x32:
            return self.port32
        if port == 0x40:
            v = 0x00
            if (self.cpu.cycles % FRAME_CYCLES) >= VBLANK_START:
                v |= 0x20                   # VRTC
            v |= 0x02                       # /SHG = 1 (標準 15kHz)
            if SENSE['p40b3']:
                v |= 0x08
            return v
        if port == 0x44:
            return 0x00                     # OPN ステータス (BUSY なし)
        if port == 0x45:
            r = self.opn_addr
            if r in (0x0E, 0x0F):
                return 0xFF                 # ジョイスティック未接続
            return self.opn_regs[r]
        if port == 0x50 or port == 0x51:
            return 0x00
        if port == 0x5C:
            return 0x00 if self.vram_sel < 0 else (1 << self.vram_sel)
        if port == 0x6E:
            return 0xFF                     # 4MHz
        if port == 0x71:
            return self.ext_rom_bank
        if port == 0xE2:
            return 0x00
        if port == 0xFC:
            v = self.fdd.read_porta()
            self.trace8255('IN  FC', v)
            return v
        if port == 0xFE:
            v = self.fdd.read_portc()
            self.trace8255('IN  FE', v)
            return v
        self.io_unknown[('in', port)] = self.io_unknown.get(('in', port), 0) + 1
        return 0xFF

    def out_port(self, p, v):
        port = p & 0xFF
        v &= 0xFF
        if port == 0x30:
            self.port30 = v
            return
        if port == 0x31:
            self.port31 = v
            return
        if port == 0x32:
            self.port32 = v
            return
        if port == 0x34:
            self.port34 = v
            return
        if port == 0x35:
            self.port35 = v
            return
        if port == 0x40:
            self.port40 = v
            return
        if port == 0x44:
            self.opn_addr = v
            return
        if port == 0x45:
            self.opn_regs[self.opn_addr] = v
            if self.opn_log is not None:
                self.opn_log.append((self.cpu.cycles, self.opn_addr, v))
            return
        if port == 0x51:
            self.crtc_cmd = v
            self.crtc_params = []
            return
        if port == 0x50:
            self.crtc_params.append(v)
            if self.crtc_cmd == 0x00 and len(self.crtc_params) == 5:
                self.crtc_p5 = v
            return
        if port == 0x52:
            self.bgcolor = v >> 5
            return
        if port == 0x53:
            self.port53 = v
            return
        if 0x54 <= port <= 0x5B:
            idx = port - 0x54
            if self.port32 & 0x20:
                # アナログパレット (512 色中 8 色)
                tgt = self.border if (v & 0x80) else self.palram[idx]
                if (v & 0x40) == 0:
                    tgt[2] = v & 7              # 青
                    tgt[0] = (v >> 3) & 7       # 赤
                else:
                    tgt[1] = v & 7              # 緑
            else:
                self.palram[idx] = [7 if (v & 2) else 0,
                                    7 if (v & 4) else 0,
                                    7 if (v & 1) else 0]
                self.palette[idx] = v & 7
            return
        if port == 0x5C:
            self.vram_sel = 0
            return
        if port == 0x5D:
            self.vram_sel = 1
            return
        if port == 0x5E:
            self.vram_sel = 2
            return
        if port == 0x5F:
            self.vram_sel = -1
            return
        if port == 0x68:
            self.dma_ff = 0
            return
        if port == 0x64:
            if self.dma_ff == 0:
                self.dma_addr2 = (self.dma_addr2 & 0xFF00) | v
            else:
                self.dma_addr2 = (self.dma_addr2 & 0x00FF) | (v << 8)
            self.dma_ff ^= 1
            return
        if 0x60 <= port <= 0x67:
            if port != 0x64:
                self.dma_ff ^= 1
            return                       # ほかの DMAC レジスタは受けるだけ
        if port == 0x70:
            self.text_win = v
            return
        if port == 0x71:
            self.ext_rom_bank = v
            return
        if port == 0xE4:
            self.int_level = v & 7
            return
        if port == 0xE6:
            self.int_mask = v & 7
            self.pending &= ~(((~v) & 7) << 1) & 0xFF
            return
        if port == 0x78:
            self.text_win = (self.text_win + 1) & 0xFF
            return
        if port in (0xE2, 0xE3, 0x20, 0x21, 0x10,
                    0xE8, 0xE9, 0xEA, 0xEB):
            return
        if port == 0xFC:
            self.trace8255('OUT FC', v)
            self.fdd.write_porta(v)
            return
        if port == 0xFD:
            self.trace8255('OUT FD', v)
            self.fdd.write_portb(v)
            return
        if port == 0xFE:
            self.trace8255('OUT FE', v)
            self.fdd.write_portc(v)
            return
        if port == 0xFF:
            self.trace8255('OUT FF', v)
            self.fdd.write_control(v)
            return
        self.io_unknown[('out', port)] = self.io_unknown.get(('out', port), 0) + 1

    def trace8255(self, what, v):
        if self.trace_fdd is None:
            return
        if len(self.trace_fdd) < 4000:
            self.trace_fdd.append("PC=%04X %s=%02X  sub: RFD=%d DAC=%d DAV=%d"
                                  % (self.cpu.pc, what, v,
                                     self.fdd.srfd, self.fdd.sdac, self.fdd.sdav))

    # ------------------------------------------------------------------ キー

    def key_down(self, port, bit):
        self.keys[port] = self.keys.get(port, 0) | (1 << bit)

    def key_up(self, port, bit):
        self.keys[port] = self.keys.get(port, 0) & ~(1 << bit)

    def keys_clear(self):
        self.keys = {}

    # ------------------------------------------------------------------ 実行

    def service_int(self):
        if not self.pending or not self.cpu.iff1:
            return
        for lvl in range(8):
            if not (self.pending & (1 << lvl)):
                continue
            if lvl >= self.int_level:
                continue            # ポート E4h で禁止されている
            self.pending &= ~(1 << lvl)
            self.int_count[lvl] += 1
            self.cpu.interrupt(lvl * 2)
            return

    def run_cycles(self, n):
        end = self.cpu.cycles + n
        while self.cpu.cycles < end:
            if self.cpu.cycles >= self.next_timer:
                self.next_timer += TIMER_CYCLES
                if self.int_mask & 1:
                    self.pending |= 1 << 2
            if self.cpu.cycles >= self.next_vrtc:
                self.next_vrtc += FRAME_CYCLES
                if self.int_mask & 2:
                    self.pending |= 1 << 1
            self.service_int()
            self.cpu.step()

    def run_frames(self, n):
        for _ in range(n):
            self.run_cycles(FRAME_CYCLES)
            self.frame += 1

    # ------------------------------------------------------------------ 画面

    def render(self):
        """640x200 の色番号 (0..7) の 2 次元配列を返す。"""
        rows = []
        text_hidden = bool(self.port53 & 1)
        gfx_on = bool(self.port31 & 0x08)
        for y in range(200):
            row = bytearray(640)
            if gfx_on:
                base = y * 80
                p0, p1, p2 = self.gvram[0], self.gvram[1], self.gvram[2]
                for bx in range(80):
                    b0 = p0[base + bx]
                    b1 = p1[base + bx]
                    b2 = p2[base + bx]
                    x0 = bx * 8
                    for bit in range(8):
                        m = 0x80 >> bit
                        c = ((1 if b0 & m else 0)
                             | (2 if b1 & m else 0)
                             | (4 if b2 & m else 0))
                        row[x0 + bit] = c
            rows.append(row)
        if not text_hidden:
            self.text_overlay(rows)
        return rows, text_hidden

    def dma_read(self, a):
        a &= 0xFFFF
        if a >= 0xF000:
            return self.hi_tvram[a - 0xF000]
        return self.ram[a]

    def text_overlay(self, rows):
        """テキスト面を重ねる。セミグラフィックだけ描く (文字のフォントは持たない)。

        色 0 のドットは 8 番 (黒) として返す。透明ではない。
        """
        p5 = self.crtc_p5
        mode = (p5 >> 5) & 7
        nattr = 0 if (mode & 1) else min((p5 & 0x1F) + 1, 20)
        color_ok = bool(mode & 2) and not (self.port30 & 0x02)
        w40 = not (self.port30 & 0x01)
        stride = 80 + nattr * 2
        attr = 0xE0
        for r in range(25):
            base = self.dma_addr2 + r * stride
            codes = [self.dma_read(base + i) for i in range(80)]
            pairs = [(self.dma_read(base + 80 + i * 2),
                      self.dma_read(base + 81 + i * 2)) for i in range(nattr)]
            at = {}
            for pos, val in pairs:
                at.setdefault(pos & 0x7F, []).append(val)
            ncol = 40 if w40 else 80
            cw = 16 if w40 else 8
            for c in range(ncol):
                cx = c * 2 if w40 else c
                for val in at.get(cx, ()):
                    if val & 0x08:
                        attr = (attr & 0x0F) | (val & 0xF0)
                code = codes[cx]
                if not (attr & 0x10) or code == 0:
                    continue
                col = (attr >> 5) if color_ok else 7
                pix = col if col else 8
                half = cw // 2
                for l in range(8):
                    br = l // 2
                    left = code & (1 << br)
                    right = code & (1 << (br + 4))
                    if not (left or right):
                        continue
                    row = rows[r * 8 + l]
                    x0 = c * cw
                    if left:
                        for x in range(x0, x0 + half):
                            row[x] = pix
                    if right:
                        for x in range(x0 + half, x0 + cw):
                            row[x] = pix

    def save_png(self, path, scale=1):
        rows, _ = self.render()
        pal = [tuple(min(255, c * 36) for c in self.palram[i])
               for i in range(8)] + [(0, 0, 0)]
        w, h = 640, 200 * 2        # 縦 2 倍にして実機の見た目に近づける
        raw = bytearray()
        for y in range(200):
            line = bytearray()
            for c in rows[y]:
                r, g, b = pal[c]
                line += bytes((r, g, b))
            for _ in range(2):
                raw += b'\x00' + line
        png = png_bytes(w, h, bytes(raw))
        with open(path, 'wb') as f:
            f.write(png)

    def dump_text(self):
        """GVRAM を 2x4 ドットの文字で粗く表示する (端末確認用)。"""
        rows, _ = self.render()
        out = []
        for y in range(0, 200, 4):
            line = []
            for x in range(0, 640, 4):
                best = 0
                for dy in range(4):
                    for dx in range(4):
                        c = rows[y + dy][x + dx]
                        if c:
                            best = c
                line.append('.123456789'[best] if best else '.')
            out.append(''.join(line))
        return '\n'.join(out)


def png_bytes(w, h, raw_rgb_with_filter):
    def chunk(tag, data):
        c = tag + data
        return (len(data).to_bytes(4, 'big') + c
                + (zlib.crc32(c) & 0xFFFFFFFF).to_bytes(4, 'big'))
    hdr = (w.to_bytes(4, 'big') + h.to_bytes(4, 'big')
           + bytes((8, 2, 0, 0, 0)))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', hdr)
            + chunk(b'IDAT', zlib.compress(raw_rgb_with_filter, 6))
            + chunk(b'IEND', b''))


# ==========================================================================

def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('disk', nargs='?', help='D88 イメージ')
    ap.add_argument('--romdir', default=ROMDIR_DEFAULT)
    ap.add_argument('--frames', type=int, default=180)
    ap.add_argument('--png')
    ap.add_argument('--text', action='store_true', help='画面を端末に粗く表示')
    ap.add_argument('--boot', choices=('rom', 'direct'), default='rom')
    ap.add_argument('--bin', help='direct ブート時に読み込むバイナリ')
    ap.add_argument('--load', default='0x0000', help='direct ブートの読み込み先')
    ap.add_argument('--entry', default='0x0000', help='direct ブートの開始番地')
    ap.add_argument('--verbose', '-v', action='count', default=0)
    ap.add_argument('--trace', type=int, default=0, help='先頭 N 命令をトレース')
    ap.add_argument('--trace-fdd', type=int, default=0, help='8255 のやり取りを N 行表示')
    args = ap.parse_args(argv)

    disk = d88mod.Disk.load(args.disk) if args.disk else d88mod.blank_2d()
    m = PC88(romdir=args.romdir, disk=disk, verbose=args.verbose)

    if args.boot == 'direct':
        if not args.bin:
            raise SystemExit("--boot direct には --bin が必要です")
        with open(args.bin, 'rb') as f:
            data = f.read()
        base = int(args.load, 0)
        m.ram[base:base + len(data)] = data
        m.port31 = 0x02 | 0x08 | 0x10 | 0x01   # 64K RAM / 画面表示 / カラー / 200 行
        m.port32 = 0x10                        # F000-FFFF はメイン RAM
        m.cpu.pc = int(args.entry, 0)
        m.cpu.sp = 0xBFF0
    else:
        m.cpu.reset()
        m.cpu.pc = 0x0000

    if args.trace_fdd:
        m.trace_fdd = []
    if args.trace:
        for i in range(args.trace):
            print("%6d %s  op=%02X" % (i, m.cpu.state(), m.rb(m.cpu.pc)))
            m.cpu.step()

    try:
        m.run_frames(args.frames)
    except KeyboardInterrupt:
        pass

    print("フレーム=%d サイクル=%d %s" % (m.frame, m.cpu.cycles, m.cpu.state()))
    print("port31=%02X port53=%02X vram_sel=%d" % (m.port31, m.port53, m.vram_sel))
    if m.fdd.log:
        print("FDD ログ (最後の 12 件):")
        for s in m.fdd.log[-12:]:
            print("   " + s)
    if args.trace_fdd and m.trace_fdd:
        print("8255 トレース (先頭 %d 行):" % args.trace_fdd)
        for ln in m.trace_fdd[:args.trace_fdd]:
            print("   " + ln)
    if m.io_unknown:
        print("未対応 I/O:", {("%s %02X" % k): v for k, v in m.io_unknown.items()})
    if args.png:
        m.save_png(args.png)
        print("画面を書き出しました:", args.png)
    if args.text:
        print(m.dump_text())
    return 0


if __name__ == '__main__':
    sys.exit(main())
