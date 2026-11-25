#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build.py - 柴犬陣取り PC-8801 版をアセンブルして起動可能な .D88 を作る

    python tools/build.py [-o SHIBA88.D88] [--keep-records [D88]] [--run N]

手順
  1. tools/art.py でドット絵とフォントのデータ (src/gen_art.asm) を作る
  2. src/game.asm をアセンブルして本体のバイナリを得る
  3. 本体の大きさから src/gen_size.asm を作る
  4. src/boot.asm をアセンブルして 256 バイトの起動セクタを得る
  5. 2D の D88 を組み立てる
       トラック0 セクタ1      : 起動セクタ
       トラック0 セクタ2 以降 : 本体
       トラック78 セクタ1     : ハイスコアと実績 (tools/records.py)

--keep-records を付けると、今あるディスク (D88 を省くと -o のファイル) が
柴犬陣取りのディスクなら、そこからハイスコアと実績を引き継ぐ。
古い版の形の記録は今の版の形に変換して書く。
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
import records  # noqa: E402
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


def read_kept(path):
    """引き継ぐ記録を読む。引き継ぐものがなければ None。"""
    if not os.path.exists(path):
        say("記録の引き継ぎ: %s がないので、まっさらな記録で作ります" % path)
        return None
    try:
        rec = records.read_disk(d88.Disk.load(path))
    except (records.RecordError, ValueError) as e:
        raise SystemExit("記録を引き継げません (%s): %s\n"
                         "上書きしてよければ --keep-records を外してください" % (path, e))
    if rec is None:
        say("記録の引き継ぎ: %s にはまだ記録がありません" % path)
    return rec


def check_record_format(syms):
    """src/disk.asm と tools/records.py で記録の形が食い違っていないか。"""
    want = {'HS_MAGIC2': records.CURRENT_MAGIC, 'HS_TRACK': records.HS_TRACK,
            'HS_SECTOR': records.HS_SECTOR, 'ACH_N': records.ACH_N}
    bad = ["%s = %02Xh (records.py は %02Xh)" % (k, syms[k], v)
           for k, v in want.items() if syms.get(k) != v]
    if bad:
        raise SystemExit("記録の形が tools/records.py と合いません: " + ", ".join(bad) +
                         "\n新しい形の読み書きを tools/records.py に足してください")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', default=os.path.join(ROOT, 'SHIBA88.D88'))
    ap.add_argument('--run', type=int, default=0,
                    help='作ったあとエミュレータで N フレーム動かす')
    ap.add_argument('--png', help='--run のあと画面を PNG に書き出す')
    ap.add_argument('--no-art', action='store_true')
    ap.add_argument('--keep-records', nargs='?', const='', metavar='D88',
                    help='今あるディスクのハイスコアと実績を引き継ぐ '
                         '(D88 を省くと -o のファイル)')
    args = ap.parse_args(argv)

    # 引き継ぐ記録は、ファイルを書き換える前に読んでおく
    kept = None
    keep_from = None
    if args.keep_records is not None:
        keep_from = args.keep_records or args.out
        kept = read_kept(keep_from)

    if not args.no_art:
        gen_art()

    # --- 本体 ---
    img, written, syms = assemble(os.path.join(SRC, 'game.asm'))
    org = syms['GAME_ENTRY']
    end = syms['GAME_END']
    # GVRAM の裏で動く部分 (C000h-) は本体のすぐうしろに続けて置く
    hs, he = syms['HIGH_START'], syms['HIGH_END']
    body = bytes(img[org:end]) + bytes(img[hs:he])
    say("裏の部分: %04Xh - %04Xh  %d バイト (読み込み先 %04Xh)" % (hs, he, he - hs, end))
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
    try:
        boot = records.stamp_boot(boot)
    except records.RecordError as e:
        raise SystemExit(str(e))

    # --- 記録の形式が tools/records.py と合っているか ---
    check_record_format(syms)

    # --- D88 ---
    disk = d88.blank_2d('SHIBA88')
    disk.put(0, 1, boot)
    pad = body + bytes((-len(body)) % SECTOR)
    disk.write_linear(0, 2, pad)
    # ハイスコアと実績のセクタ
    if kept is None:
        disk.put(records.HS_TRACK, records.HS_SECTOR, bytes(256))   # まだ記録なし
    else:
        defaults = records.defaults_from_image(img, syms)
        disk.put(records.HS_TRACK, records.HS_SECTOR, records.write(kept, defaults))
        say("記録を引き継ぎました: %s%s" % (
            keep_from, '' if kept.magic == records.CURRENT_MAGIC
            else " (目印 %02Xh の形から変換)" % kept.magic))
        for line in records.describe(records.parse(disk.get(records.HS_TRACK, records.HS_SECTOR))):
            say("  " + line)
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
