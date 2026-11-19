#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sndtest.py - YM2203 (OPN) への書き込みを拾って、BGM と効果音を確かめる

    python tools/sndtest.py [--secs N]

タイトル画面とゲーム中で実際に出ているレジスタ書き込みを読み、
音色の読み込み / キーオン / 音の高さ / SSG の効果音を日本語で並べる。
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402

OPNCLK = 3993600.0
NAMES = ['ド', 'ド#', 'レ', 'レ#', 'ミ', 'ファ', 'ファ#', 'ソ', 'ソ#', 'ラ', 'ラ#', 'シ']


def fnum_hz(block, fnum):
    if fnum == 0:
        return 0.0
    return fnum * OPNCLK / (72.0 * (2 ** (21 - block)))


def hz_name(hz):
    """周波数を音名に直す (A4 = 440Hz)。"""
    if hz <= 0:
        return '-'
    n = 12 * math.log2(hz / 440.0) + 69      # MIDI 番号
    i = int(round(n))
    cent = (n - i) * 100
    return '%s%d (%+.0fcent)' % (NAMES[i % 12], i // 12 - 1, cent)


def decode(log, sym_names):
    """書き込みの列を読みやすい行にする。"""
    fh = {}
    fl = {}
    out = []
    ssg = {}
    for cyc, r, v in log:
        if r == 0x28:
            ch = v & 3
            if v & 0xF0:
                hi = fh.get(ch, 0)
                lo = fl.get(ch, 0)
                blk = (hi >> 3) & 7
                fn = ((hi & 7) << 8) | lo
                hz = fnum_hz(blk, fn)
                out.append(('on', cyc, ch, blk, fn, hz))
            else:
                out.append(('off', cyc, ch, 0, 0, 0.0))
        elif 0xA4 <= r <= 0xA6:
            fh[r - 0xA4] = v
        elif 0xA0 <= r <= 0xA2:
            fl[r - 0xA0] = v
        elif r <= 0x0D:
            ssg[r] = v
            out.append(('ssg', cyc, r, v, 0, 0.0))
        elif 0x30 <= r <= 0x8F:
            out.append(('op', cyc, r, v, 0, 0.0))
        elif 0xB0 <= r <= 0xB2:
            out.append(('alg', cyc, r - 0xB0, v, 0, 0.0))
    return out


SSGNAME = {0: 'Aの音程(下)', 1: 'Aの音程(上)', 2: 'Bの音程(下)', 3: 'Bの音程(上)',
           4: 'Cの音程(下)', 5: 'Cの音程(上)', 6: 'ノイズ', 7: 'ミキサー',
           8: 'Aの音量', 9: 'Bの音量', 10: 'Cの音量',
           11: 'エンベロープ(下)', 12: 'エンベロープ(上)', 13: 'エンベロープ形'}


def show(title, log, limit=40):
    ev = decode(log, None)
    print('\n--- %s (書き込み %d 回) ---' % (title, len(log)))
    nop = sum(1 for e in ev if e[0] == 'op')
    nalg = sum(1 for e in ev if e[0] == 'alg')
    non = sum(1 for e in ev if e[0] == 'on')
    noff = sum(1 for e in ev if e[0] == 'off')
    nssg = sum(1 for e in ev if e[0] == 'ssg')
    print('音色パラメータ %d / アルゴリズム %d / キーオン %d / キーオフ %d / SSG %d'
          % (nop, nalg, non, noff, nssg))
    shown = 0
    for e in ev:
        if e[0] == 'on':
            print('   FM%d キーオン  ブロック%d F-Num%4d  %8.2fHz  %s'
                  % (e[2], e[3], e[4], e[5], hz_name(e[5])))
            shown += 1
        elif e[0] == 'ssg':
            print('   SSG %-14s = %02X' % (SSGNAME.get(e[2], 'reg%d' % e[2]), e[3]))
            shown += 1
        if shown >= limit:
            print('   ...')
            break


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--frames', type=int, default=240)
    args = ap.parse_args(argv)

    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    m = pc88emu.PC88(disk=d88.Disk.load(args.disk))
    m.cpu.reset()
    m.cpu.pc = 0
    m.opn_log = []
    while m.cpu.pc != sym['TITLESCREEN.loop'] or m.cpu.sp >= 0xC000:   # 起動中の ROM と番地が重なることがある
        m.cpu.step()
    boot = m.opn_log
    show('起動時の初期化と音色の読み込み', boot, limit=0)
    # 音色が 3 つぶん (4 オペレータ x 6 パラメータ) 入っているか
    nop = sum(1 for _, r, _ in boot if 0x30 <= r <= 0x8F)
    print('   -> オペレータ設定 %d 個 (音色3種 x 4op x 6項目 = 72 なら正しい)' % nop)
    alg = [(r - 0xB0, v) for _, r, v in boot if 0xB0 <= r <= 0xB2]
    print('   -> FB|ALG:', ['ch%d=%02X' % (c, v) for c, v in alg])

    m.opn_log = []
    m.run_frames(args.frames)
    show('タイトルの BGM (%d フレーム)' % args.frames, m.opn_log)

    # ゲームに入る
    m.key_down(0x09, 6)
    for _ in range(2000000):
        m.cpu.step()
        if m.cpu.pc == sym['PLAYSTAGE']:
            break
    m.key_up(0x09, 6)
    while m.cpu.pc != sym['PLAYSTAGE.loop']:
        m.cpu.step()
    m.opn_log = []
    m.run_frames(args.frames)
    show('ゲーム中の BGM と効果音 (%d フレーム)' % args.frames, m.opn_log)
    return 0


if __name__ == '__main__':
    sys.exit(main())
