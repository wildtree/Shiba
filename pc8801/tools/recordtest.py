#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
recordtest.py - build.py --keep-records (記録の引き継ぎと変換) を確かめる

    python tools/recordtest.py

一時フォルダにディスクを作って、次の場合を試す。
  ・今の形の記録があるディスク -> そのまま引き継ぐ
  ・最初の版の形 (目印 8Ah、ディスクの目印もない古いディスク) -> 今の形に変換
  ・柴犬陣取りでないディスク -> 止まって、ファイルはそのまま
  ・ファイルがない -> まっさらな記録で作る
  ・引き継いだディスクをエミュレータで起動して、ゲームが同じ記録を読むか
記録の形を変えたら、古い形のディスクを作る関数をここにも足すこと。
"""

import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import build    # noqa: E402
import d88      # noqa: E402
import pc88emu  # noqa: E402
import records  # noqa: E402
import z80asm   # noqa: E402

FAILS = []


def check(ok, msg):
    print("  %s %s" % ('OK ' if ok else 'NG ', msg))
    if not ok:
        FAILS.append(msg)


def quiet_build(argv):
    """build.py を動かす。SystemExit のメッセージを返す (正常なら None)。"""
    saved = build.say
    build.say = lambda m: None
    try:
        build.main(argv + ['--no-art'])
        return None
    except SystemExit as e:
        return str(e)
    finally:
        build.say = saved


def old_disk(path, sector, stamp=True):
    """記録セクタだけ差し替えた柴犬陣取りのディスクを作る (stamp=False で目印なしの古い版)。"""
    disk = d88.Disk.load(path)
    if not stamp:
        boot = bytearray(disk.get(0, 1))
        boot[records.DISK_ID_OFS:] = bytes(256 - records.DISK_ID_OFS)
        disk.put(0, 1, bytes(boot))
    disk.put(records.HS_TRACK, records.HS_SECTOR, sector)
    disk.save(path)


def v2_sector():
    b = bytearray(256)
    b[0] = records.MAGIC_V2
    table = [(250000, 'ABC', 17), (99999, 'XYZ', 9)] + [(1000 * (9 - i), 'Q%02d' % i, 1) for i in range(8)]
    for i, (sc, nm, st) in enumerate(table):
        o = 1 + i * 8
        b[o:o + 3] = sc.to_bytes(3, 'little')
        b[o + 3:o + 6] = nm.encode()
        b[o + 6] = st
    for a in (0, 5, 9, 19, 23):
        b[81 + a // 8] |= 1 << (a % 8)
    b[84] = 0b101
    return bytes(b), table


def game_reads(path, sym):
    """ディスクを起動して、タイトルに来たときの HISCORES と ACHBITS を返す。"""
    m = pc88emu.PC88(disk=d88.Disk.load(path))
    m.cpu.reset()
    m.cpu.pc = 0
    for _ in range(30000000):
        m.cpu.step()
        if m.cpu.pc == sym['TITLESCREEN.loop'] and m.cpu.sp < 0xC000:
            break
    hs = bytes(m.ram[sym['HISCORES']:sym['HISCORES'] + 80])
    ach = bytes(m.ram[sym['ACHBITS']:sym['ACHBITS'] + 4])
    return hs, ach


def main():
    img, _, sym = z80asm.assemble(os.path.join(ROOT, 'src', 'game.asm'))
    tmp = tempfile.mkdtemp(prefix='shiba_rec_')
    try:
        disk = os.path.join(tmp, 'S.D88')

        print("■ ファイルがない")
        err = quiet_build(['-o', disk, '--keep-records'])
        check(err is None and os.path.exists(disk), "まっさらな記録で作れた")
        check(records.read_disk(d88.Disk.load(disk)) is None, "記録はまだなし")

        print("■ 今の形の記録を引き継ぐ")
        sec, table = v2_sector()
        old_disk(disk, sec)
        err = quiet_build(['-o', disk, '--keep-records'])
        check(err is None, "ビルドできた")
        out = bytes(d88.Disk.load(disk).get(records.HS_TRACK, records.HS_SECTOR))
        check(out[:85] == sec[:85], "記録セクタが同じ")
        hs, ach = game_reads(disk, sym)
        check(hs == sec[1:81] and ach == sec[81:85], "ゲームが同じ記録を読む")

        print("■ --keep-records なしなら記録は消える (今までどおり)")
        quiet_build(['-o', disk])
        check(records.read_disk(d88.Disk.load(disk)) is None, "記録なしになった")

        print("■ 最初の版の形 (目印 8Ah) を変換する")
        b = bytearray(256)
        b[0] = records.MAGIC_V1
        b[1:4] = (15500).to_bytes(3, 'little')
        old_disk(disk, bytes(b), stamp=False)
        err = quiet_build(['-o', disk, '--keep-records'])
        check(err is None, "ビルドできた")
        rec = records.read_disk(d88.Disk.load(disk))
        check(rec is not None and rec.magic == records.CURRENT_MAGIC, "今の形になった")
        check(rec is not None and [(s.score, s.name) for s in rec.scores[:2]] == [(15500, '---'), (10000, 'SHB')]
              and len(rec.scores) == 10 and rec.scores[-1].score == 2000,
              "1 位に入って最初の表は 1 件ずれた")
        check(records.identify(d88.Disk.load(disk)) == (records.HS_TRACK, records.HS_SECTOR),
              "ディスクの目印が付いた")
        # ゲーム自身の変換と同じ結果か
        b2 = bytearray(256)
        b2[0] = records.MAGIC_V1
        b2[1:4] = (15500).to_bytes(3, 'little')
        old_disk(disk, bytes(b2))
        hs_game, _ = game_reads(disk, sym)
        check(hs_game == records.write(rec, records.defaults_from_image(img, sym))[1:81],
              "ゲームが 8Ah を読んだ結果と同じ表")

        print("■ 柴犬陣取りでないディスク")
        other = d88.blank_2d('OTHERGAME')
        other.put(0, 1, b'\xC3\x00\x01' + bytes(253))
        other.put(records.HS_TRACK, records.HS_SECTOR, b'\x55' * 256)
        other.save(disk)
        before = open(disk, 'rb').read()
        err = quiet_build(['-o', disk, '--keep-records'])
        check(err is not None and '引き継げません' in err, "止まった")
        check(open(disk, 'rb').read() == before, "ファイルはそのまま")

        print("■ 知らない形の記録 (未来の版など)")
        quiet_build(['-o', disk])
        b3 = bytearray(256)
        b3[0] = 0x8C
        old_disk(disk, bytes(b3))
        before = open(disk, 'rb').read()
        err = quiet_build(['-o', disk, '--keep-records'])
        check(err is not None and '8Ch' in err and open(disk, 'rb').read() == before,
              "止まって、ファイルはそのまま")

        print("■ 別のファイルから引き継ぐ")
        src = os.path.join(tmp, 'OLD.D88')
        quiet_build(['-o', src])
        old_disk(src, sec)
        err = quiet_build(['-o', disk, '--keep-records', src])
        out = bytes(d88.Disk.load(disk).get(records.HS_TRACK, records.HS_SECTOR))
        check(err is None and out[:85] == sec[:85], "記録が写った")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print("結果: " + ("すべて期待どおり" if not FAILS else "%d 件 NG" % len(FAILS)))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
