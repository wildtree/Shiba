#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
featuretest.py - アイテム / 雨 / ボス犬 / 夜のボーナス面がちゃんと動くか見る

    python tools/featuretest.py [--png-dir DIR]
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

D_BONET = 24
D_PASST = 26

DISK = os.path.join(os.path.dirname(HERE), 'SHIBA88.D88')


def boot(sym, stage=1, bonus=0, demo=1):
    """タイトルからゲーム本体に入ったところまで進める。"""
    m = pc88emu.PC88(disk=d88.Disk.load(DISK))
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
    m.ram[sym['STAGE']] = stage
    m.ram[sym['BONUSMODE']] = bonus
    m.ram[sym['DEMOMODE']] = demo
    while m.cpu.pc != sym['PLAYSTAGE.loop']:
        m.cpu.step()
    return m


def items_report(m, sym):
    out = []
    for i in range(m.ram[sym['NITEM']] if 'NITEM' in sym else 2):
        b = sym['ITEMS'] + i * 6
        if m.ram[b]:
            out.append('%s(%d,%d)' % ('骨' if m.ram[b + 3] == 0 else '巻物',
                                      m.ram[b + 1], m.ram[b + 2]))
    return out


def dogs_report(m, sym):
    out = []
    for i in range(m.ram[sym['NDOGS']]):
        b = sym['DOGS'] + i * 32
        f = m.ram[b + 20] if False else m.ram[b + 18]
        out.append((i, m.ram[b + 17], m.ram[b], m.ram[b + 1]))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--png-dir')
    args = ap.parse_args(argv)
    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))

    def png(m, name):
        if args.png_dir:
            p = os.path.join(args.png_dir, name)
            m.save_png(p)
            print('   画面:', p)

    # ---------------- 1. アイテム ----------------
    print('■ アイテム (骨と巻物)')
    m = boot(sym, stage=6)       # アイテムは 5 面から出る
    seen = Counter()
    picked = 0
    prev = [m.ram[sym['ITEMS'] + i * 6] for i in range(2)]
    for _ in range(90):
        m.run_frames(10)
        for i in range(2):
            b = sym['ITEMS'] + i * 6
            a = m.ram[b]
            if a and not prev[i]:
                seen[m.ram[b + 3]] += 1
            if prev[i] and not a:
                picked += 1
            prev[i] = a
    # 拾ったあとの効果 (骨 = 速くなる / 巻物 = 通行証) が付いた犬を数える
    eff = 0
    for _ in range(120):
        m.run_frames(10)
        for i in range(m.ram[sym['NDOGS']]):
            b0 = sym['DOGS'] + i * 32
            bone = m.ram[b0 + D_BONET] | (m.ram[b0 + D_BONET + 1] << 8)
            pas = m.ram[b0 + D_PASST] | (m.ram[b0 + D_PASST + 1] << 8)
            if bone or pas:
                eff += 1
        for i in range(2):
            bb = sym['ITEMS'] + i * 6
            a0 = m.ram[bb]
            if a0 and not prev[i]:
                seen[m.ram[bb + 3]] += 1
            if prev[i] and not a0:
                picked += 1
            prev[i] = a0
    print('   出たアイテム: 骨 %d 個 / 巻物 %d 個 / 消えた(拾われた) %d 回'
          % (seen[0], seen[1], picked))
    print('   効果が付いていた回数 (骨/巻物の持続):', eff)

    # ---------------- 2. 雨 ----------------
    print('■ 雨')
    m = boot(sym, stage=3)
    # 予告をすぐ始まるようにする
    m.ram[sym['RAINWARN']] = 30
    m.ram[sym['RAINWARN'] + 1] = 0
    marks0 = Counter(m.ram[sym['POLES'] + i * 4 + 2]
                     for i in range(m.ram[sym['NPOLES']]))
    rained = False
    for _ in range(120):
        m.run_frames(10)
        t = m.ram[sym['RAINT']] | (m.ram[sym['RAINT'] + 1] << 8)
        if t:
            rained = True
            break
    print('   雨が降りだした:', 'はい' if rained else 'いいえ')
    if rained:
        png(m, 'rain.png')
        for _ in range(60):
            m.run_frames(10)
        marks1 = Counter(m.ram[sym['POLES'] + i * 4 + 2]
                         for i in range(m.ram[sym['NPOLES']]))
        print('   雨の前の印:', dict(marks0))
        print('   雨のあとの印:', dict(marks1))

    # ---------------- 3. ボス犬 ----------------
    print('■ ボス犬 (8 ステージごと)')
    m = pc88emu.PC88(disk=d88.Disk.load(DISK))
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
    m.ram[sym['STAGE']] = 8
    m.ram[sym['DEMOMODE']] = 1
    while m.cpu.pc != sym['PLAYSTAGE.loop']:
        m.cpu.step()
    print('   HASBOSS =', m.ram[sym['HASBOSS']])
    bosses = []
    for i in range(m.ram[sym['NDOGS']]):
        b = sym['DOGS'] + i * 32
        fl = m.ram[b + 5]        # D_FLAGS
        if fl & 0x08:
            bosses.append('犬%d 犬種%d (%d,%d)' % (i, m.ram[b + 17], m.ram[b], m.ram[b + 1]))
    print('   ボスの犬:', bosses if bosses else 'いない')
    m.run_frames(300)
    png(m, 'boss.png')

    # ---------------- 4. 夜のボーナス面 ----------------
    print('■ 夜のボーナス面')
    m = boot(sym, stage=5, bonus=1)
    print('   BONUSMODE =', m.ram[sym['BONUSMODE']],
          '/ 犬 =', m.ram[sym['NDOGS']],
          '/ 電柱 =', m.ram[sym['NPOLES']],
          '/ 残り秒 =', m.ram[sym['SECLEFT']])
    m.run_frames(600)
    print('   10 秒後: つかまえた =', m.ram[sym['BONUSCAUGHT']],
          '/ 残り秒 =', m.ram[sym['SECLEFT']])
    png(m, 'bonus.png')
    return 0


if __name__ == '__main__':
    sys.exit(main())
