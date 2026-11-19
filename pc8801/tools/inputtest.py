#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
inputtest.py - 方向キーを重ねて押したときに、ちゃんと新しいキーに従うか

    python tools/inputtest.py

前のキーが離れきらないうちに次のキーを押す (QUASI88 でキーが残って見える状況)
を再現して、犬の動いた向きを調べる。
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402
import featuretest  # noqa: E402

KEY = {'↓': (0x0A, 1), '←': (0x0A, 2), '→': (0x08, 2), '↑': (0x08, 1)}
NAME = {0: '↓', 1: '←', 2: '→', 3: '↑', 0xFF: 'なし'}


def run(sym, steps):
    """steps = [(フレーム数, 押しているキーの集合), ...]。各区間の移動量を返す。"""
    m = featuretest.boot(sym, stage=1, demo=0)
    d0 = sym['DOGS']
    # 柴犬を広い場所の真ん中に置く (道路や電柱に当たらないように)
    m.run_frames(20)
    out = []
    held = set()
    for frames, keys in steps:
        for k in held - keys:
            m.key_up(*KEY[k])
        for k in keys - held:
            m.key_down(*KEY[k])
        held = set(keys)
        x0, y0 = m.ram[d0], m.ram[d0 + 1]
        m.run_frames(frames)
        x1, y1 = m.ram[d0], m.ram[d0 + 1]
        out.append((frames, ''.join(sorted(keys)) or '-', x1 - x0, y1 - y0,
                    NAME.get(m.ram[sym['HELDDIR']], '?')))
    return out


def show(title, res, expect):
    print('■ ' + title)
    ok = True
    for (frames, keys, dx, dy, hd), want in zip(res, expect):
        if dx > 0:
            went = '→'
        elif dx < 0:
            went = '←'
        elif dy > 0:
            went = '↓'
        elif dy < 0:
            went = '↑'
        else:
            went = '止まる'
        mark = 'OK' if (want is None or went == want) else 'だめ'
        if mark == 'だめ':
            ok = False
        print('   %3d フレーム 押しているキー=%-4s 動いた向き=%-4s (dx=%+d dy=%+d) 期待=%-4s %s'
              % (frames, keys, went, dx, dy, want or '-', mark))
    return ok


def main():
    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    allok = True
    # 1. ↓ を押したまま → を足す。前の作りでは ↓ が優先されて → が無視された
    allok &= show('↓ を押しっぱなしのまま → を押す',
                  run(sym, [(20, {'↓'}), (30, {'↓', '→'})]),
                  ['↓', '→'])
    # 2. → を離しきらないうちに ↑ を押す (QUASI88 でキーが残る状況)
    allok &= show('→ が残っているうちに ↑ に切り替える',
                  run(sym, [(20, {'→'}), (10, {'→', '↑'}), (20, {'↑'})]),
                  ['→', '↑', '↑'])
    # 3. 新しいほうを離すと、まだ押している古いほうに戻る (元の版と同じ)
    allok &= show('→ を押したまま ↑ を押して離す',
                  run(sym, [(20, {'→'}), (20, {'→', '↑'}), (20, {'→'})]),
                  ['→', '↑', '→'])
    # 4. 全部離すと止まる
    allok &= show('離すと止まる',
                  run(sym, [(20, {'→'}), (30, set())]),
                  ['→', None])
    print('\n結果:', 'すべて期待どおり' if allok else '期待と違うところがある')
    return 0 if allok else 1


if __name__ == '__main__':
    sys.exit(main())
