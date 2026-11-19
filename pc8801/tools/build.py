#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build.py - 柴犬陣取り PC-8801 版をアセンブルして起動可能な .D88 を作る

    python tools/build.py [-o SHIBA88.D88] [--run N]

手順
  1. tools/art.py でドット絵とフォントのデータ (src/gen_art.asm) を作る
  2. src/game.asm をアセンブルして本体のバイナリを得る
  3. 本体の大きさから src/gen_size.asm を作る
  4. src/boot.asm をアセンブルして 256 バイトの起動セクタを得る
  5. 2D の D88 を組み立てる
       トラック0 セクタ1      : 起動セクタ
       トラック0 セクタ2 以降 : 本体
       トラック78 セクタ1     : ハイスコア
"""

import argparse
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, 'src')
sys.path.insert(0, HERE)

import art      # noqa: E402
import d88      # noqa: E402
import z80asm   # noqa: E402

SECTOR = 256


def say(msg):
    print(msg)


def gen_art():
    out = os.path.join(SRC, 'gen_art.asm')
    with open(out, 'w', encoding='utf-8') as f:
        f.write(art.emit_asm())
    total = sum(len(d) for _, d in art.collect())
    say("ドット絵を生成: %s (%d バイト)" % (os.path.relpath(out, ROOT), total))


def assemble(path):
    try:
        return z80asm.assemble(path)
    except z80asm.AsmError as e:
        print("アセンブルエラー (%s):" % os.path.basename(path))
        print(str(e))
        raise SystemExit(1)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', default=os.path.join(ROOT, 'SHIBA88.D88'))
    ap.add_argument('--run', type=int, default=0,
                    help='作ったあとエミュレータで N フレーム動かす')
    ap.add_argument('--png', help='--run のあと画面を PNG に書き出す')
    ap.add_argument('--no-art', action='store_true')
    args = ap.parse_args(argv)

    if not args.no_art:
        gen_art()

    # --- 本体 ---
    img, written, syms = assemble(os.path.join(SRC, 'game.asm'))
    org = syms['GAME_ENTRY']
    end = syms['GAME_END']
    body = bytes(img[org:end])
    nsec = (len(body) + SECTOR - 1) // SECTOR
    say("本体: %04Xh - %04Xh  %d バイト (%d セクタ)" % (org, end, len(body), nsec))
    if nsec > 16 * 2 * 38:
        raise SystemExit("本体がディスクに収まりません")
    # 変数領域の位置を確認
    say("変数: %04Xh - %04Xh" % (syms['VARS'], syms['VARS_END']))

    # --- 起動セクタ ---
    with open(os.path.join(SRC, 'gen_size.asm'), 'w', encoding='utf-8') as f:
        f.write("; build.py が生成しています。直接編集しないこと。\n")
        f.write("GAME_SECTORS    EQU %d\n" % nsec)
        f.write("GAME_ENTRY      EQU 0x%04X\n" % org)
    bimg, bwritten, bsyms = assemble(os.path.join(SRC, 'boot.asm'))
    boot = bytes(bimg[0xC000:0xC100])
    used = bsyms['BOOTEND'] - 0xC000
    say("起動セクタ: %d / 256 バイト" % used)

    # --- D88 ---
    disk = d88.blank_2d('SHIBA88')
    disk.put(0, 1, boot)
    pad = body + bytes((-len(body)) % SECTOR)
    disk.write_linear(0, 2, pad)
    # ハイスコアのセクタ (まだ目印なし = 初期値)
    disk.put(78, 1, bytes(256))
    disk.save(args.out)
    say("書き出しました: %s (%d バイト)" % (args.out, os.path.getsize(args.out)))

    if args.run:
        import pc88emu
        say("--- エミュレータで %d フレーム動かします ---" % args.run)
        m = pc88emu.PC88(disk=d88.Disk.load(args.out))
        m.cpu.reset()
        m.cpu.pc = 0
        m.run_frames(args.run)
        print("PC=%04X halted=%s port31=%02X port53=%02X"
              % (m.cpu.pc, m.cpu.halted, m.port31, m.port53))
        if m.fdd.log:
            print("FDD:", [x for x in m.fdd.log if x.startswith('cmd')][:12])
        if m.io_unknown:
            print("未対応 I/O:", {("%s %02X" % k): v
                                  for k, v in m.io_unknown.items()})
        if args.png:
            m.save_png(args.png)
            say("画面: " + args.png)
    return 0


if __name__ == '__main__':
    sys.exit(main())
