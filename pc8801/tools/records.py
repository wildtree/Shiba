#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
records.py - 柴犬陣取り PC-8801 版の記録 (ハイスコアと実績) をディスクから読み書きする

    python tools/records.py SHIBA88.D88      # 記録を表示する

記録はトラック 78 / セクタ 1 の 256 バイト (src/disk.asm)。先頭の 1 バイトが
形式の目印で、版ごとに読み方が違う。

  目印 00h  まだ記録なし (ゲームは最初の表で始める)
  目印 8Ah  最初の版: +1..3 = 1 位の点だけ
  目印 8Bh  今の版:   +1..80 = 10 件 x 8 バイト (点 3 / 名前 3 / ステージ 1 / 予備 1)
                      +81..83 = 実績のビット (実績 i は バイト i/8 の bit i%8)
                      +84     = 3 色の柴犬それぞれでクリアしたか (bit0..2)

読むときはどの版でも Records (版に依らない形) にし、書くときは今の版の形で書く。
だから「古い版の記録 -> 今の版の形」の変換は 読む + 書く でできる。

記録の形を変えたら:
  1. src/disk.asm の目印 (HS_MAGIC2 など) を新しい値にする
  2. ここに新しい目印の読み方 (parse_vN) を足して PARSERS に登録する
  3. CURRENT_MAGIC と write() を新しい形にする
  古い版の parse_* は消さずに残しておく (古いディスクを変換するため)。
build.py は src/disk.asm の目印と CURRENT_MAGIC が違うと止まるので、
2 と 3 を忘れたまま記録を引き継ぐことはない。
"""

import sys
from dataclasses import dataclass, field

HS_TRACK = 78
HS_SECTOR = 1
SECTOR = 256

MAGIC_BLANK = 0x00
MAGIC_V1 = 0x8A
MAGIC_V2 = 0x8B
CURRENT_MAGIC = MAGIC_V2

NSCORES = 10
ACH_N = 24

# 起動セクタのうしろに置く「柴犬陣取りのディスク」の目印 (build.py が書く)。
# 起動のコードは 0F0h より前に収まっている。
DISK_ID_OFS = 0xF0
DISK_ID = b'SHIBAJNT'
DISK_LAYOUT = 1                 # 記録セクタの場所が変わったら増やす
D88_NAME = 'SHIBA88'            # 目印のない古いディスクはヘッダの名前で見分ける


class RecordError(Exception):
    pass


@dataclass
class Score:
    score: int
    name: str
    stage: int


@dataclass
class Records:
    """版に依らない記録。"""
    scores: list = field(default_factory=list)   # Score の並び (多い順)
    complete: bool = True       # False = 表の一部だけ (最初の表に混ぜて使う)
    ach: set = field(default_factory=set)        # 取った実績の番号
    shiba_colors: int = 0       # 3 色の柴犬でのクリア (bit0..2)
    magic: int = CURRENT_MAGIC  # 読んだときの形式


# ---------------------------------------------------------------------------
# 読む
# ---------------------------------------------------------------------------

def _score_at(b, ofs):
    return Score(score=b[ofs] | b[ofs + 1] << 8 | b[ofs + 2] << 16,
                 name=bytes(b[ofs + 3:ofs + 6]).decode('ascii', 'replace'),
                 stage=b[ofs + 6])


def parse_v1(b):
    """最初の版: 1 位の点だけ。ゲームと同じく名前 "---"、ステージ 1 として扱う。"""
    top = b[1] | b[2] << 8 | b[3] << 16
    return Records(scores=[Score(top, '---', 1)], complete=False, magic=MAGIC_V1)


def parse_v2(b):
    scores = [_score_at(b, 1 + i * 8) for i in range(NSCORES)]
    ach = {i for i in range(ACH_N) if b[81 + (i >> 3)] >> (i & 7) & 1}
    return Records(scores=scores, complete=True, ach=ach,
                   shiba_colors=b[84] & 7, magic=MAGIC_V2)


PARSERS = {
    MAGIC_V1: parse_v1,
    MAGIC_V2: parse_v2,
}


def parse(sector):
    """記録セクタ -> Records。まだ記録がなければ None。知らない形なら RecordError。"""
    magic = sector[0]
    if magic == MAGIC_BLANK:
        return None
    if magic not in PARSERS:
        raise RecordError("記録の形式 (目印 %02Xh) を知りません" % magic)
    return PARSERS[magic](sector)


# ---------------------------------------------------------------------------
# 書く (今の版の形)
# ---------------------------------------------------------------------------

def merged_scores(rec, defaults):
    """表の一部だけの記録は、最初の表に入れて上位 10 件にする (ゲームの HSINSERT と同じ)。"""
    if rec.complete:
        return list(rec.scores[:NSCORES])
    table = list(defaults)
    for s in rec.scores:
        if s.score <= table[-1].score:
            continue
        pos = next(i for i, t in enumerate(table) if s.score > t.score)
        table.insert(pos, s)
        del table[NSCORES:]
    return table


def write(rec, defaults):
    """Records -> 今の版の記録セクタ (256 バイト)。"""
    scores = merged_scores(rec, defaults)
    if len(scores) != NSCORES:
        raise RecordError("ハイスコアが %d 件しかありません" % len(scores))
    b = bytearray(SECTOR)
    b[0] = CURRENT_MAGIC
    for i, s in enumerate(scores):
        o = 1 + i * 8
        v = max(0, min(s.score, 0xFFFFFF))
        b[o:o + 3] = bytes((v & 0xFF, v >> 8 & 0xFF, v >> 16))
        b[o + 3:o + 6] = s.name.encode('ascii', 'replace')[:3].ljust(3, b' ')
        b[o + 6] = max(1, min(s.stage, 255))
    for i in rec.ach:
        if 0 <= i < ACH_N:
            b[81 + (i >> 3)] |= 1 << (i & 7)
    b[84] = rec.shiba_colors & 7
    return bytes(b)


def defaults_from_image(img, syms):
    """アセンブルした本体の HSDEFAULT (最初の 10 件) を読む。"""
    a = syms['HSDEFAULT']
    return [_score_at(img, a + i * 8) for i in range(NSCORES)]


# ---------------------------------------------------------------------------
# ディスク
# ---------------------------------------------------------------------------

def stamp_boot(boot):
    """起動セクタのうしろに柴犬陣取りのディスクの目印を入れる。"""
    b = bytearray(boot.ljust(SECTOR, b'\0'))
    if any(b[DISK_ID_OFS:]):
        raise RecordError("起動セクタが目印の場所 (%02Xh-) まで使っています" % DISK_ID_OFS)
    b[DISK_ID_OFS:DISK_ID_OFS + len(DISK_ID)] = DISK_ID
    b[DISK_ID_OFS + len(DISK_ID)] = DISK_LAYOUT
    return bytes(b)


def identify(disk):
    """柴犬陣取りのディスクなら記録セクタの場所 (トラック, セクタ) を返す。違えば RecordError。"""
    boot = disk.get(0, 1)
    if boot is not None and bytes(boot[DISK_ID_OFS:DISK_ID_OFS + len(DISK_ID)]) == DISK_ID:
        layout = boot[DISK_ID_OFS + len(DISK_ID)]
        if layout == 1:
            return HS_TRACK, HS_SECTOR
        raise RecordError("ディスクの作りの版 %d を知りません" % layout)
    # 目印を入れる前の版: D88 の名前と記録セクタの目印で見分ける
    if disk.name != D88_NAME:
        raise RecordError("柴犬陣取りのディスクではありません (名前 %r)" % disk.name)
    sec = disk.get(HS_TRACK, HS_SECTOR)
    if sec is None:
        raise RecordError("記録のセクタがありません")
    if sec[0] != MAGIC_BLANK and sec[0] not in PARSERS:
        raise RecordError("柴犬陣取りのディスクではないようです (記録の目印 %02Xh)" % sec[0])
    return HS_TRACK, HS_SECTOR


def read_disk(disk):
    """ディスクから Records を読む。記録がまだなければ None。"""
    t, s = identify(disk)
    return parse(disk.get(t, s))


# ---------------------------------------------------------------------------
# 表示
# ---------------------------------------------------------------------------

def describe(rec):
    lines = []
    if rec is None:
        return ["記録はまだありません"]
    lines.append("形式: 目印 %02Xh%s" % (rec.magic, '' if rec.magic == CURRENT_MAGIC else ' (古い版)'))
    for i, s in enumerate(rec.scores):
        lines.append("  %2d. %-3s %8d  ステージ %d" % (i + 1, s.name, s.score, s.stage))
    if not rec.complete:
        lines.append("  (1 位の点だけ。ほかは最初の表で埋めます)")
    lines.append("実績: %d / %d  %s" % (len(rec.ach), ACH_N, sorted(rec.ach)))
    lines.append("3 色の柴犬でのクリア: %s" % format(rec.shiba_colors, '03b'))
    return lines


def main(argv=None):
    import d88
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    try:
        rec = read_disk(d88.Disk.load(argv[0]))
    except (RecordError, ValueError, OSError) as e:
        print("読めません: %s" % e)
        return 1
    print("\n".join(describe(rec)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
