#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prof.py - ゲーム中の処理時間をルーチンごとに測る

    python tools/prof.py [--stage N] [--ticks N]

1 ティック (メインループ 1 周) あたりの CPU サイクル数と、
どのルーチンで使っているかを出す。4MHz の 1 フレームは 66560 サイクル。
"""

import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402

FRAME = pc88emu.FRAME_CYCLES


def build_map(sym, lo, hi):
    """アドレス -> ルーチン名 (グローバルラベルだけ) の表を作る。"""
    globals_ = sorted((v, k) for k, v in sym.items()
                      if lo <= v < hi and '.' not in k)
    table = [''] * (hi - lo)
    cur = '?'
    gi = 0
    for a in range(lo, hi):
        while gi < len(globals_) and globals_[gi][0] <= a:
            cur = globals_[gi][1]
            gi += 1
        table[a - lo] = cur
    return table


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--stage', type=int, default=0)
    ap.add_argument('--ticks', type=int, default=120)
    ap.add_argument('--warm', type=int, default=0, help='測る前に動かすフレーム数')
    args = ap.parse_args(argv)

    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    lo, hi = sym['GAME_ENTRY'], sym['GAME_END']
    amap = build_map(sym, lo, hi)

    m = pc88emu.PC88(disk=d88.Disk.load(args.disk))
    m.cpu.reset()
    m.cpu.pc = 0
    while m.cpu.pc != sym['TITLESCREEN.loop'] or m.cpu.sp >= 0xC000:   # 起動中の ROM と番地が重なることがある
        m.cpu.step()
    m.key_down(0x09, 6)
    for _ in range(2000000):
        m.cpu.step()
        if m.cpu.pc == sym['PLAYSTAGE']:
            break
    m.key_up(0x09, 6)

    if args.stage:
        m.ram[sym['STAGE']] = args.stage

    top = sym['PLAYSTAGE.loop']
    n = 0
    while m.cpu.pc != top and n < 6000000:
        m.cpu.step()
        n += 1
    if args.warm:
        m.run_frames(args.warm)
        while m.cpu.pc != top:
            m.cpu.step()
    print("ステージ %d / 犬 %d 匹 / 電柱 %d 本"
          % (m.ram[sym['STAGE']], m.ram[sym['NDOGS']], m.ram[sym['NPOLES']]))

    cyc = Counter()
    ticks = 0
    start_cycles = m.cpu.cycles
    wait_cycles = 0
    while ticks < args.ticks:
        pc = m.cpu.pc
        if pc < lo or pc >= hi:
            print("暴走 PC=%04X" % pc)
            break
        name = amap[pc - lo]
        c0 = m.cpu.cycles
        m.cpu.step()
        d = m.cpu.cycles - c0
        cyc[name] += d
        if name in ('WAITVSYNC', 'VBPOLL'):
            wait_cycles += d
        if m.cpu.pc == top:
            ticks += 1

    total = m.cpu.cycles - start_cycles
    work = total - wait_cycles
    print("ティック数 = %d" % ticks)
    print("1 ティックあたり: 合計 %d サイクル (うち待ち %d / 実処理 %d)"
          % (total // max(ticks, 1), wait_cycles // max(ticks, 1),
             work // max(ticks, 1)))
    print("1 フレーム (60Hz) = %d サイクル なので %.2f フレーム分"
          % (FRAME, (work / max(ticks, 1)) / FRAME))
    print("\n処理の内訳 (1 ティックあたりのサイクル数):")
    for k, v in cyc.most_common(28):
        if k == 'WAITVSYNC':
            continue
        print("   %-20s %7d  %5.1f%%" % (k, v // max(ticks, 1), 100.0 * v / max(work, 1)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
