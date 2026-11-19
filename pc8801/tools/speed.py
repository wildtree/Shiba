#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
speed.py - ステージごとの実測の速さ (1 ティックに何フレームかかるか)

    python tools/speed.py [--stages 1,2,4,6,8] [--ticks 30] [--warm 900]
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402

F = pc88emu.FRAME_CYCLES


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--stages', default='1,2,4,6,8')
    ap.add_argument('--ticks', type=int, default=30)
    ap.add_argument('--warm', type=int, default=900)
    args = ap.parse_args(argv)
    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    top = sym['PLAYSTAGE.loop']
    print('ステージ  犬  1ティックのフレーム数  実際の速さ  1ティック最悪')
    for st in [int(x) for x in args.stages.split(',')]:
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
        m.ram[sym['STAGE']] = st
        m.ram[sym['DEMOMODE']] = 1
        while m.cpu.pc != top:
            m.cpu.step()
        m.run_frames(args.warm)
        while m.cpu.pc != top:
            m.cpu.step()
        t0 = m.cpu.cycles
        last = t0
        worst = 0
        n = 0
        while n < args.ticks:
            m.cpu.step()
            if m.cpu.pc == top:
                n += 1
                d = m.cpu.cycles - last
                last = m.cpu.cycles
                if d > worst:
                    worst = d
        avg = (m.cpu.cycles - t0) / args.ticks
        print('   %d     %d          %.2f              %.1f Hz      %.2f フレーム'
              % (st, m.ram[sym['NDOGS']], avg / F, 60.0 / (avg / F), worst / F))
    return 0


if __name__ == '__main__':
    sys.exit(main())
