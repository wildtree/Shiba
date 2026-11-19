#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
play.py - エミュレータでゲームを動かして画面を書き出す検査用ツール

    python tools/play.py --frames 600 --png shot.png
    python tools/play.py --script "wait 200; key space 5; wait 400" --png shot.png

script の書き方 (; 区切り):
    wait N          N フレーム待つ
    key NAME N      キー NAME を N フレーム押す
    hold NAME       押しっぱなしにする
    release NAME    離す
    shot FILE       そのときの画面を書き出す
    dump            端末に粗く表示する
"""

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402

KEYS = {
    'up': (0x08, 1), 'right': (0x08, 2), 'down': (0x0A, 1), 'left': (0x0A, 2),
    'space': (0x09, 6), 'z': (0x05, 2), 'x': (0x05, 0),
    'p': (0x04, 0), 'r': (0x04, 2), 'm': (0x03, 5), 'esc': (0x09, 7),
    'ret': (0x01, 7),
}


def run(m, n, label=''):
    t0 = time.time()
    m.run_frames(n)
    dt = time.time() - t0
    if label:
        print("  %s: %d フレーム (%.1f 秒, %.1f fps)" % (label, n, dt, n / max(dt, 1e-6)))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--frames', type=int, default=400)
    ap.add_argument('--png')
    ap.add_argument('--script')
    ap.add_argument('--dump', action='store_true')
    ap.add_argument('--sym', action='store_true', help='主な変数の値を表示')
    args = ap.parse_args(argv)

    disk = d88.Disk.load(args.disk)
    m = pc88emu.PC88(disk=disk)
    m.cpu.reset()
    m.cpu.pc = 0

    if args.script:
        for step in args.script.split(';'):
            step = step.strip()
            if not step:
                continue
            parts = step.split()
            cmd = parts[0]
            if cmd == 'wait':
                run(m, int(parts[1]), 'wait')
            elif cmd == 'key':
                p, b = KEYS[parts[1]]
                m.key_down(p, b)
                run(m, int(parts[2]), 'key ' + parts[1])
                m.key_up(p, b)
                run(m, 2)
            elif cmd == 'hold':
                p, b = KEYS[parts[1]]
                m.key_down(p, b)
            elif cmd == 'release':
                p, b = KEYS[parts[1]]
                m.key_up(p, b)
            elif cmd == 'shot':
                # 描画が終わった時点 (垂直帰線待ち) で撮る
                try:
                    import z80asm as _z
                    _i, _w, _s = _z.assemble(os.path.join(os.path.dirname(HERE),
                                                          'src', 'game.asm'))
                    tgt = _s.get('WAITVSYNC.w1')
                    if tgt:
                        for _ in range(2000000):
                            if m.cpu.pc == tgt:
                                break
                            m.cpu.step()
                except Exception as e:
                    print("  (同期できず: %s)" % e)
                m.save_png(parts[1])
                print("  画面: " + parts[1])
            elif cmd == 'dump':
                print(m.dump_text())
            else:
                raise SystemExit("不明なコマンド: " + step)
    else:
        run(m, args.frames, 'run')

    print("PC=%04X halted=%s port31=%02X port53=%02X"
          % (m.cpu.pc, m.cpu.halted, m.port31, m.port53))
    if m.io_unknown:
        print("未対応 I/O:", {("%s %02X" % k): v for k, v in m.io_unknown.items()})
    if args.sym:
        img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                    'src', 'game.asm'))
        for name in ('STAGE', 'LIVES', 'NPOLES', 'NDOGS', 'SECLEFT',
                     'CLAIMED', 'FINISHED', 'GAMEOVER', 'PAUSED',
                     'DEMOMODE', 'BONUSMODE', 'SPRCOUNT'):
            a = sym[name]
            print("  %-10s = %d" % (name, m.ram[a]))
        a = sym['SCORE']
        print("  SCORE      = %d" % (m.ram[a] | (m.ram[a + 1] << 8) | (m.ram[a + 2] << 16)))
        a = sym['CLAIMED']
        print("  CLAIMED    = %d" % (m.ram[a] | (m.ram[a + 1] << 8)))
    if args.dump:
        print(m.dump_text())
    if args.png:
        m.save_png(args.png)
        print("画面: " + args.png)
    return 0


if __name__ == '__main__':
    sys.exit(main())
