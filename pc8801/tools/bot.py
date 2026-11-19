#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bot.py - エミュレータの中でキーを押して柴犬を動かし、ルールが動くか確かめる

RAM から犬と電柱の位置を読んで、いちばん近い未処理の電柱へ歩き、
隣に着いたらスペースを押す、を繰り返す。
なわばりができればスコアと ARR_TERR が増える。

    python tools/bot.py [--stage N] [--frames N] [--png out.png]
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

DIRKEY = {0: (0x0A, 1), 1: (0x0A, 2), 2: (0x08, 2), 3: (0x08, 1)}  # 下 左 右 上
SPACE = (0x09, 6)
FW, FH, STRIDE = 30, 25, 32


class Game:
    def __init__(self, disk_path, sym):
        self.sym = sym
        self.m = pc88emu.PC88(disk=d88.Disk.load(disk_path))
        self.m.cpu.reset()
        self.m.cpu.pc = 0

    def b(self, name, off=0):
        return self.m.ram[self.sym[name] + off]

    def w(self, name, off=0):
        a = self.sym[name] + off
        return self.m.ram[a] | (self.m.ram[a + 1] << 8)

    def dog(self, i):
        a = self.sym['DOGS'] + i * 32
        r = self.m.ram[a:a + 32]
        return dict(x=r[0], y=r[1], dir=r[4], flags=r[5], peet=r[8] | (r[9] << 8),
                    chainn=r[16], breed=r[17], area=r[19] | (r[20] << 8))

    def poles(self):
        out = []
        n = self.b('NPOLES')
        for i in range(n):
            a = self.sym['POLES'] + i * 4
            r = self.m.ram[a:a + 4]
            out.append(dict(i=i, x=r[0], y=r[1], owner=r[2], locked=r[3]))
        return out

    def terr(self, x, y):
        return self.m.ram[self.sym['ARR_TERR'] + y * STRIDE + x]

    def poleat(self, x, y):
        return self.m.ram[self.sym['ARR_POLEAT'] + y * STRIDE + x]

    def lane(self, y):
        return self.m.ram[self.sym['LANEOF'] + y]

    def score(self):
        a = self.sym['SCORE']
        return self.m.ram[a] | (self.m.ram[a + 1] << 8) | (self.m.ram[a + 2] << 16)

    def run(self, n):
        self.m.run_frames(n)

    def press(self, key, frames=2):
        p, bit = key
        self.m.key_down(p, bit)
        self.m.run_frames(frames)
        self.m.key_up(p, bit)
        self.m.run_frames(1)


def walkable(g, x, y, me=0):
    if not (0 <= x < FW and 0 <= y < FH):
        return False
    if g.poleat(x, y) != 0xFF:
        return False
    t = g.terr(x, y)
    return t == 0xFF or t == me


def step_toward(g, sx, sy, tx, ty):
    """幅優先で 1 歩だけ方向を返す (0 下 / 1 左 / 2 右 / 3 上)。"""
    from collections import deque
    dx = [0, -1, 1, 0]
    dy = [1, 0, 0, -1]
    prev = {}
    q = deque([(sx, sy)])
    seen = {(sx, sy)}
    goal = None
    while q:
        cx, cy = q.popleft()
        if abs(cx - tx) + abs(cy - ty) == 1:
            goal = (cx, cy)
            break
        for k in range(4):
            nx, ny = cx + dx[k], cy + dy[k]
            if (nx, ny) in seen or not walkable(g, nx, ny):
                continue
            seen.add((nx, ny))
            prev[(nx, ny)] = (cx, cy, k)
            q.append((nx, ny))
    if goal is None:
        return None
    cur = goal
    first = None
    while cur != (sx, sy):
        px, py, k = prev[cur]
        first = k
        cur = (px, py)
    if first is None:
        # もう隣にいる
        for k in range(4):
            if (sx + dx[k], sy + dy[k]) == (tx, ty):
                return ('pee', k)
        return None
    return ('move', first)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--disk', default=os.path.join(os.path.dirname(HERE), 'SHIBA88.D88'))
    ap.add_argument('--stage', type=int, default=0, help='この値でステージを上書きする')
    ap.add_argument('--bonus', action='store_true')
    ap.add_argument('--frames', type=int, default=6000)
    ap.add_argument('--png')
    args = ap.parse_args(argv)

    img, wr, sym = z80asm.assemble(os.path.join(os.path.dirname(HERE), 'src', 'game.asm'))
    g = Game(args.disk, sym)

    # タイトルまで進めてスペースで開始
    while g.m.cpu.pc != sym['TITLESCREEN.loop'] or g.m.cpu.sp >= 0xC000:
        g.m.cpu.step()
    g.press(SPACE, 4)

    # NEWGAME が STAGE を 1 にした直後に上書きする
    if args.stage or args.bonus:
        while g.m.cpu.pc != sym['PLAYSTAGE']:
            g.m.cpu.step()
        if args.stage:
            g.m.ram[sym['STAGE']] = args.stage
        if args.bonus:
            g.m.ram[sym['BONUSMODE']] = 1
        print("ステージを %d / BONUS=%d にしました" % (g.b('STAGE'), g.b('BONUSMODE')))

    # ゲーム本体のループに入るまで待つ
    n = 0
    while g.m.cpu.pc != sym['PLAYSTAGE.running'] and n < 3000000:
        g.m.cpu.step()
        n += 1

    print("開始: STAGE=%d NDOGS=%d NPOLES=%d" % (g.b('STAGE'), g.b('NDOGS'), g.b('NPOLES')))
    frames = 0
    peed = 0
    last_report = 0
    while frames < args.frames:
        if g.m.cpu.pc < 0x100 or g.m.cpu.pc >= sym['GAME_END']:
            print("暴走 PC=%04X (frame %d)" % (g.m.cpu.pc, frames))
            break
        if g.b('FINISHED') or g.b('GAMEOVER'):
            print("ステージ終了 FINISHED=%d GAMEOVER=%d CLEARED=%d"
                  % (g.b('FINISHED'), g.b('GAMEOVER'), g.b('CLEARED')))
            break
        d = g.dog(0)
        if d['peet'] or (d['flags'] & 0x02):
            g.run(2)
            frames += 2
            continue
        # 目標の電柱: chain に入っていない、ロックされていないもののうち近いもの
        chain = [g.m.ram[g.sym['DOGS'] + 13 + k] for k in range(d['chainn'])]
        cands = [p for p in g.poles() if p['i'] not in chain]
        if not cands:
            break
        cands.sort(key=lambda p: abs(p['x'] - d['x']) + abs(p['y'] - d['y']))
        act = None
        for p in cands[:6]:
            act = step_toward(g, d['x'], d['y'], p['x'], p['y'])
            if act:
                break
        if act is None:
            g.press(DIRKEY[frames % 4], 2)
            frames += 4
            continue
        kind, k = act
        if kind == 'pee':
            # 向きを合わせてからスペース
            g.press(DIRKEY[k], 2)
            g.press(SPACE, 3)
            peed += 1
            frames += 8
        else:
            g.press(DIRKEY[k], 3)
            frames += 5
        if frames - last_report > 800:
            last_report = frames
            print("  f=%5d score=%6d area=%3d chain=%d 印=%d なわばり=%d"
                  % (frames, g.score(), g.dog(0)['area'], g.dog(0)['chainn'], peed,
                     sum(1 for y in range(FH) for x in range(FW) if g.terr(x, y) != 0xFF)))

    print("結果: score=%d area=%d おしっこ=%d" % (g.score(), g.dog(0)['area'], peed))
    c = Counter(g.terr(x, y) for y in range(FH) for x in range(FW))
    print("なわばりの内訳:", dict(c))
    if args.png:
        g.m.save_png(args.png)
        print("画面:", args.png)
    return 0


if __name__ == '__main__':
    sys.exit(main())
