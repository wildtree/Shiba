#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sndscene.py - 場面ごとに OPN への書き込みを拾って、音の出方を確かめる

    python tools/sndscene.py

  1. おしっこ: しずくの音がすぐ鳴り始めて 4 ティックごとに続き、最後に印の音
  2. ステージクリア: 効果音の途中でクリアしても音が残らず、ジングルが鳴って止まる
  3. 1UP: 20000 点で残機が増えてファンファーレ
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import d88        # noqa: E402
import pc88emu    # noqa: E402
import z80asm     # noqa: E402
import featuretest  # noqa: E402
import sndtest    # noqa: E402

F = pc88emu.FRAME_CYCLES
SSG_HZ = 3993600 / 64.0


def ssg_events(log, t0):
    """SSG チャンネル A の「鳴り始め / 止まり」を (フレーム, 内容) で返す。"""
    tp = [0, 0]
    out = []
    vol = 0
    for cyc, r, v in log:
        fr = (cyc - t0) / F
        if r == 0:
            tp[0] = v
        elif r == 1:
            tp[1] = v
        elif r == 8:
            per = (tp[1] << 8) | tp[0]
            if v & 0x0F and not vol:
                out.append((fr, '鳴る %4.0fHz 音量%d' % (SSG_HZ / max(per, 1), v & 15)))
            elif not (v & 0x0F) and vol:
                out.append((fr, '止まる'))
            elif v & 0x0F:
                out.append((fr, '変わる %4.0fHz 音量%d' % (SSG_HZ / max(per, 1), v & 15)))
            vol = v & 0x0F
    return out, vol


def fm_events(log, t0):
    out = []
    for e in sndtest.decode(log, None):
        fr = (e[1] - t0) / F
        if e[0] == 'on':
            out.append((fr, 'FM%d %s' % (e[2], sndtest.hz_name(e[5]).split(' ')[0])))
        elif e[0] == 'off':
            out.append((fr, 'FM%d 止め' % e[2]))
    return out


def run_ticks(m, sym, n):
    top = sym['PLAYSTAGE.loop']
    t = 0
    while t < n:
        m.cpu.step()
        if m.cpu.pc == top:
            t += 1


def scene_pee(sym):
    print('■ 1. おしっこ')
    m = featuretest.boot(sym, stage=1, demo=0)
    run_ticks(m, sym, 5)
    # 柴犬を電柱のとなりに置く
    P = sym['POLES']
    d0 = sym['DOGS']
    placed = None
    for i in range(m.ram[sym['NPOLES']]):
        px, py = m.ram[P + i * 4], m.ram[P + i * 4 + 1]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x, y = px + dx, py + dy
            if not (0 <= x < 30 and 0 <= y < 25):
                continue
            if m.ram[sym['ARR_POLEAT'] + y * 32 + x] != 0xFF:
                continue
            if m.ram[sym['LANEOF'] + y]:
                continue
            placed = (x, y, px, py)
            break
        if placed:
            break
    x, y, px, py = placed
    m.ram[d0], m.ram[d0 + 1] = x, y
    m.opn_log = []
    t0 = m.cpu.cycles
    m.key_down(0x09, 6)          # スペース
    run_ticks(m, sym, 3)
    m.key_up(0x09, 6)
    run_ticks(m, sym, 110)       # 3 秒 + 少し
    ev, _ = ssg_events(m.opn_log, t0)
    starts = [fr for fr, s in ev if s.startswith('鳴る')]
    print('   柴犬 (%d,%d) / 電柱 (%d,%d)  持ち主=%d'
          % (x, y, px, py, m.ram[P + [i for i in range(m.ram[sym['NPOLES']])
                                       if m.ram[P + i * 4] == px and m.ram[P + i * 4 + 1] == py][0] * 4 + 2]))
    print('   SSG が鳴り始めた回数: %d' % len(starts))
    if len(starts) >= 3:
        gaps = [round(b - a) for a, b in zip(starts, starts[1:])]
        print('   最初の音: スペースから %.0f フレーム後' % starts[0])
        print('   間隔 (フレーム): %s' % gaps[:12])
    print('   最後の 3 つ:', [s for _, s in ev[-3:]])
    return len(starts) >= 10


def scene_clear(sym):
    print('■ 2. ステージクリア (なわばりの音が鳴っている途中でクリア)')
    m = featuretest.boot(sym, stage=1, demo=1)
    run_ticks(m, sym, 30)
    # なわばりの効果音を鳴らした直後にクリアさせる
    m.opn_log = []
    t0 = m.cpu.cycles
    sp = sym['SFXPLAY']
    # SFXPLAY を直接呼ぶ: A = SFX_TERRITORY
    ret = m.cpu.pc
    m.cpu.sp -= 2
    m.ram[m.cpu.sp] = ret & 0xFF
    m.ram[m.cpu.sp + 1] = ret >> 8
    m.cpu.a = sym['SFX_TERRITORY']
    m.cpu.pc = sp
    while m.cpu.pc != ret:
        m.cpu.step()
    m.ram[sym['CLEARED']] = 1
    m.ram[sym['FINISHED']] = 1
    # PLAYSTAGE を抜けて次のステージの READY が終わるまで
    m.run_frames(60 * 5)
    ev, vol = ssg_events(m.opn_log, t0)
    fm = fm_events(m.opn_log, t0)
    ssg_on = [(fr, s) for fr, s in ev]
    print('   SSG:', ['%.0f:%s' % (fr, s) for fr, s in ssg_on][:8])
    last_ssg_stop = max([fr for fr, s in ev if s == '止まる'] or [0])
    print('   SSG が最後に止まったのは %.0f フレーム目 / 最後の音量 = %d' % (last_ssg_stop, vol))
    ons = [(fr, s) for fr, s in fm if '止め' not in s]
    print('   FM のキーオン (クリアのジングル):')
    row = []
    for fr, s in ons[:24]:
        row.append('%3.0f:%s' % (fr, s))
    for k in range(0, len(row), 6):
        print('      ' + '  '.join(row[k:k + 6]))
    offs = [fr for fr, s in fm if '止め' in s]
    print('   ジングル後の FM 全停止: %s フレーム目' % (
        '%.0f' % offs[-1] if offs else 'なし'))
    return vol == 0


def scene_extend(sym):
    print('■ 3. 1UP')
    m = featuretest.boot(sym, stage=1, demo=1)
    run_ticks(m, sym, 10)
    lives0 = m.ram[sym['LIVES']]
    nx = sym['NEXTEXT']
    print('   次の 1UP: %d 点' % (m.ram[nx] | (m.ram[nx + 1] << 8) | (m.ram[nx + 2] << 16)))
    sc = sym['SCORE']
    v = 20050
    m.ram[sc], m.ram[sc + 1], m.ram[sc + 2] = v & 0xFF, (v >> 8) & 0xFF, v >> 16
    m.opn_log = []
    t0 = m.cpu.cycles
    run_ticks(m, sym, 30)
    ev, _ = ssg_events(m.opn_log, t0)
    lives1 = m.ram[sym['LIVES']]
    nxt = m.ram[nx] | (m.ram[nx + 1] << 8) | (m.ram[nx + 2] << 16)
    print('   残機 %d -> %d / 次の 1UP: %d 点' % (lives0, lives1, nxt))
    print('   SSG:', [s for _, s in ev][:8])
    return lives1 == lives0 + 1 and nxt == 60000


def main():
    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE),
                                                'src', 'game.asm'))
    ok = [scene_pee(sym), scene_clear(sym), scene_extend(sym)]
    print('\n結果:', 'すべて期待どおり' if all(ok) else '期待と違うところがある %s' % ok)
    return 0 if all(ok) else 1


if __name__ == '__main__':
    sys.exit(main())
