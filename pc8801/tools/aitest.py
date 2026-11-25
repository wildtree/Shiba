#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
aitest.py - 敵の AI がちゃんと印をつけてなわばりを作るか見る

    python tools/aitest.py [--stage N] [--secs N] [--png out.png]
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


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--stage', type=int, default=4)
    ap.add_argument('--secs', type=int, default=60, help='ゲーム内の秒数')
    ap.add_argument('--png')
    args = ap.parse_args(argv)

    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    m = pc88emu.PC88(disk=d88.Disk.load(args.disk))
    m.cpu.reset()
    m.cpu.pc = 0
    while m.cpu.pc != sym['TITLESCREEN.loop'] or m.cpu.sp >= 0xC000:   # 起動中の ROM と番地が重なることがある
        m.cpu.step()
    # スペースを押して PLAYSTAGE に入った瞬間を捕まえる
    m.key_down(0x09, 6)
    for _ in range(2000000):
        m.cpu.step()
        if m.cpu.pc == sym['PLAYSTAGE']:
            break
    m.key_up(0x09, 6)
    m.ram[sym['STAGE']] = args.stage
    m.ram[sym['DEMOMODE']] = 1          # 柴犬も AI にまかせる
    top = sym['PLAYSTAGE.loop']
    n = 0
    while m.cpu.pc != top and n < 8000000:
        m.cpu.step()
        n += 1

    def g(name):
        return m.ram[sym[name]]

    print("開始: ステージ%d 犬%d匹 電柱%d本"
          % (g('STAGE'), g('NDOGS'), g('NPOLES')), flush=True)
    start = g('SECLEFT')
    last = start
    while True:
        sec = g('SECLEFT')
        if start - sec >= args.secs or g('FINISHED') or g('GAMEOVER'):
            break
        if m.cpu.pc < 0x100 or m.cpu.pc >= sym['GAME_END'] and not (sym['HIGH_START'] <= m.cpu.pc < sym['HIGH_END']):
            print("暴走 PC=%04X" % m.cpu.pc, flush=True)
            break
        if sec != last and (start - sec) % 10 == 0:
            last = sec
            T = sym['ARR_TERR']
            terr = Counter(m.ram[T + y * 32 + x]
                           for y in range(25) for x in range(30))
            P = sym['POLES']
            owners = Counter(m.ram[P + i * 4 + 2] for i in range(g('NPOLES')))
            chains = [m.ram[sym['DOGS'] + i * 32 + 16] for i in range(g('NDOGS'))]
            sc = sym['SCORE']
            print("経過%3d秒 なわばり=%s 印=%s chain=%s score=%d"
                  % (start - sec, dict(terr), dict(owners), chains,
                     m.ram[sc] | (m.ram[sc + 1] << 8) | (m.ram[sc + 2] << 16)),
                  flush=True)
        m.run_frames(10)
    if args.png:
        m.save_png(args.png)
        print("画面:", args.png, flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
