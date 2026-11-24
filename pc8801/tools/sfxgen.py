#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sfxgen.py - 効果音 (SSG) とジングル (FM) のデータを作る

    python tools/sfxgen.py            # 作ったデータを表示する
    python tools/sfxgen.py --write    # src/sound.asm の自動生成の区間を書き換える
    python tools/sfxgen.py --check    # 音程の一覧を出す

元の版 (Audio.cs) の音の指定を、PC-8801 の YM2203 用のデータに直す。
src/sound.asm の「sfxgen.py ここから / ここまで」の間はこのスクリプトが
書き換えるので、直接編集しないこと。

■ SSG の音程について
  YM2203 はリセット直後のプリスケーラが FM 1/6・SSG 1/4 で、
  SSG のトーン周波数は  f = φM / (64 × TP)  になる。
  PC-8801 の φM = 3.9936MHz なので  TP = 62400 / f。
  (最初の版は φM / (16 × TP) で計算していて、全部 2 オクターブ低かった)
"""

import argparse
import sys

CLOCK = 3993600
SSG_DIV = 64            # φM / (64 × TP)
TICK = 30               # ゲームは 30 ティック/秒

NOTE_SEMI = {'c': 0, 'c#': 1, 'd': 2, 'd#': 3, 'e': 4, 'f': 5, 'f#': 6,
             'g': 7, 'g#': 8, 'a': 9, 'a#': 10, 'b': 11}


def parse_note(name):
    """'c5' / 'a#3' -> (半音, オクターブ)。"""
    name = name.lower()
    octv = int(name[-1])
    return NOTE_SEMI[name[:-1]], octv


def note_hz(name):
    semi, octv = parse_note(name)
    midi = (octv + 1) * 12 + semi
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def fm_note(name):
    """FMKEY の音番号 (C2 = 1, 半音ごとに 1)。"""
    semi, octv = parse_note(name)
    n = (octv - 2) * 12 + semi + 1
    assert 1 <= n <= 72, (name, n)
    return n


def tp_of(hz):
    tp = int(round(CLOCK / SSG_DIV / hz))
    return max(1, min(0xFFF, tp))


# =====================================================================
# 効果音 (SSG チャンネル A)
#   ('t', 周波数Hz または音名, 音量0-15, ティック)   トーン
#   ('n', ノイズ周期0-31,       音量0-15, ティック)   ノイズ
#   ('r', 0,                     0,        ティック)   休み
# 元の版の Notes() の 1 音 = 約 0.05〜0.07 秒 = 2 ティックにしてある。
# =====================================================================

def notes(seq, vol, unit=2):
    """'c5 e5 g5 c6:3' を音の並びにする。"""
    out = []
    for tok in seq.split():
        if ':' in tok:
            nm, k = tok.split(':')
            k = int(k)
        else:
            nm, k = tok, 1
        out.append(('t', nm, vol, unit * k))
    return out


SFX = [
    # 名前, 優先度, 中身                               元の版の指定
    ('STEP', 1, [('t', 550, 8, 1)]),                  # V(1, 480→620, 0.035)
    ('MARK', 5, notes('e6 a6:2', 12)),                # Notes "e6 a6:2"
    ('INVALID', 5, [('t', 120, 12, 3), ('t', 104, 11, 3)]),   # V(0, 120→100, 0.18)
    ('OVERWRITE', 6, notes('a5 e5 a5 e6', 12)),       # Notes "a5 e5 a5 e6"
    ('TERRITORY', 7, notes('c5 e5 g5 c6 e6 g6 c7:3', 13)),    # Notes "... c7:4"
    ('ENEMYTERR', 2, notes('g3 a#3 d4 g4:3', 9)),     # Notes "g3 a#3 d4 g4:3"
    ('ENEMYOUT', 6, [('t', 700, 12, 1), ('t', 1200, 12, 1), ('t', 1700, 12, 1)]
     + notes('g5 c6 e6 g6:3', 12)),                   # V(700→1700) + Notes
    ('MISS', 8, [('t', 900, 13, 3), ('t', 650, 12, 3), ('t', 450, 11, 3),
                 ('t', 320, 10, 3), ('t', 230, 9, 3), ('t', 160, 8, 3),
                 ('t', 110, 7, 4)]),                  # V(0, 900→110, 0.7)
    ('CARHIT', 8, [('n', 3, 15, 2), ('n', 8, 14, 2), ('n', 14, 12, 2),
                   ('n', 22, 10, 2), ('n', 31, 8, 3)]),        # V(3, 5000→600, 0.3)
    ('ITEM', 6, notes('e6 g6 e6 c7:3', 12)),          # Notes "e6 g6 e6 c7:3"
    ('RAIN', 5, [('n', 1, 9, 6), ('n', 2, 7, 6), ('n', 3, 5, 8)]),   # V(3, 7000→5500)
    ('THUNDER', 7, [('n', 6, 15, 3), ('n', 12, 14, 4), ('n', 18, 12, 5),
                    ('n', 24, 10, 6), ('n', 31, 8, 8)]),       # V(3, 900→120, 1.1)
    ('KICKED', 5, notes('c6 g5 e5 c5', 12)),          # Notes "c6 g5 e5 c5"
    ('BARK', 4, [('t', 520, 13, 1), ('t', 900, 13, 2), ('r', 0, 0, 2),
                 ('t', 540, 13, 1), ('t', 950, 13, 2)]),       # V(1, 500→900) x2
    # おしっこのしずく: 高い「ピッ」を 0.13 秒ごとに (tick.asm が 4 ティックごとに鳴らす)
    ('PEEDRIP', 3, [('t', 1900, 11, 1), ('t', 1250, 9, 1)]),   # V(2, 1500..2400→1000..1500, 0.06)
    ('SELECT', 3, [('t', 880, 11, 2)]),               # V(1, 880, 0.04)
    ('START', 9, notes('c5 e5 g5 c6:3', 13)),         # Notes "c5 e5 g5 c6:3"
    ('EXTEND', 9, notes('e6 g6 e7 c7 d7 g7:4', 13)),  # Notes "e6 g6 e7 c7 d7 g7:4"
    ('ACHIEVE', 9, notes('g5 c6 e6 g6 e6 g6 c7:4', 13)),   # Achievement: Notes "g5 c6 e6 g6 e6 g6 c7:4"
    ('NAMEOK', 9, notes('g5 c6 e6 c6 e6 g6:4', 13)),       # NameOk: Notes "g5 c6 e6 c6 e6 g6:4"
]


def sfx_rows(steps):
    rows = []
    for kind, val, vol, ticks in steps:
        assert ticks >= 1, '長さ 0 の行があると効果音が止まらなくなる'
        if kind == 't':
            hz = note_hz(val) if isinstance(val, str) else float(val)
            tp = tp_of(hz)
            rows.append(((tp >> 8) & 0x0F, tp & 0xFF, vol & 0x0F, ticks,
                         '%s %.0fHz' % (val if isinstance(val, str) else '', CLOCK / SSG_DIV / tp)))
        elif kind == 'n':
            rows.append((0, val & 0x1F, 0x80 | (vol & 0x0F), ticks, 'ノイズ周期 %d' % val))
        else:
            rows.append((0, 0, 0, ticks, '休み'))
    return rows


def emit_sfx():
    L = ['; ==== sfxgen.py ここから (効果音) — 直接編集しないこと ====',
         '; 優先度 (大きいほど強い。鳴っている音以下の優先度の音は鳴らない)',
         'SFXPRIO:']
    for name, prio, _ in SFX:
        L.append('        DB      %-3d     ; %s' % (prio, name))
    L.append('')
    L.append('SFXTBL:')
    names = ['SFX_D_' + n for n, _, _ in SFX]
    for i in range(0, len(names), 4):
        L.append('        DW      ' + ', '.join(names[i:i + 4]))
    L.append('')
    L.append('; 周期上位, 周期下位 (ノイズのときはノイズ周期), 音量 (bit7 でノイズ), 長さ (ティック)')
    for name, _, steps in SFX:
        L.append('SFX_D_%s:' % name)
        for hi, lo, vol, ticks, note in sfx_rows(steps):
            L.append('        DB      0x%02X,0x%02X,0x%02X,%-3d  ; %s' % (hi, lo, vol, ticks, note.strip()))
        L.append('        DB      0xFF')
    L.append('; ==== sfxgen.py ここまで (効果音) ====')
    return '\n'.join(L)


def emit_sfx_equ():
    L = ['; ==== sfxgen.py ここから (効果音の番号) ====']
    for i, (name, _, _) in enumerate(SFX):
        L.append('SFX_%-11s EQU %d' % (name, i))
    L.append('SFX_NSFX        EQU %d' % len(SFX))
    L.append('; ==== sfxgen.py ここまで (効果音の番号) ====')
    return '\n'.join(L)


# =====================================================================
# ジングル (FM 3 声)。1 拍 = unit ティック
#   ch0 主旋律 / ch1 主旋律の 1 オクターブ下 / ch2 ベース
# =====================================================================

def voice(seq, shift=0):
    out = []
    for tok in seq.split():
        if ':' in tok:
            nm, k = tok.split(':')
            k = int(k)
        else:
            nm, k = tok, 1
        if nm == '-':
            out.append((None, k))
        else:
            semi, octv = parse_note(nm)
            out.append(('%s%d' % (nm[:-1], octv + shift), k))
    return out


def merge(voices, unit):
    """3 声を「行 = 3 声の音 + 長さ」の並びにする。"""
    events = []
    for v in voices:
        t = 0
        ev = {}
        for nm, k in v:
            ev[t] = nm
            t += k
        events.append((ev, t))
    ends = sorted(set([0] + [t for ev, end in events for t in ev] + [end for _, end in events]))
    total = max(end for _, end in events)
    rows = []
    off = [False] * len(voices)
    for i, t in enumerate(ends):
        if t >= total:
            break
        t2 = ends[i + 1]
        cells = []
        for vi, (ev, end) in enumerate(events):
            if t in ev:
                nm = ev[t]
                cells.append(0 if nm is None else fm_note(nm))
            elif t >= end and not off[vi]:
                cells.append(0)
                off[vi] = True
            else:
                cells.append(0xFE)
        ticks = (t2 - t) * unit
        assert 1 <= ticks <= 256
        rows.append(cells + [ticks - 1])     # BGMTICK は「長さ + 1」ティック鳴らす
    return rows


JINGLES = [
    # ステージクリア (元の版の Sfx.StageClear)
    ('CLEAR', 3,
     'c5 c5 c5 e5:2 g5:2 e5 g5 c6:6',
     'c4:3 g4:2 c4:2 e4 g4 c5:6'),
    # ステージ失敗 (元の版の Sfx.StageFail)
    ('FAIL', 4,
     'e4:2 d#4:2 d4:2 c#4:6',
     'e2:2 d#2:2 d2:2 c#2:6'),
    # ゲームオーバー (元の版の Sfx.GameOver)
    ('OVER', 4,
     'c5:2 g4:2 e4:2 a4 b4 a4 g#4:2 g4:6',
     'c3:6 f3:5 c3:8'),
]


def emit_jingles():
    L = ['; ==== sfxgen.py ここから (ジングル) — 直接編集しないこと ====',
         '; 主旋律, 主旋律の 1 オクターブ下, ベース, 長さ-1   (0xFD で止まる)']
    for name, unit, mel, bass in JINGLES:
        rows = merge([voice(mel), voice(mel, -1), voice(bass)], unit)
        L.append('BGM_D_%s:' % name)
        for r in rows:
            L.append('        DB      %s' % ', '.join(
                ('HOLD' if c == 0xFE else str(c)) for c in r))
        L.append('        DB      0xFD')
    L.append('; ==== sfxgen.py ここまで (ジングル) ====')
    return '\n'.join(L)


# =====================================================================
# BGM (元の版の Audio.RenderTune)。1 曲を、タイトルとステージでテンポと
# 主旋律の音色を変えて使う (sound.asm の BGMTEMPOS / BGMLEADS)。
#   ch0 主旋律 / ch1 裏拍の和音 (3 度) / ch2 ベース (根音と 5 度)
#   1 行 = 1 ステップ以上。長さは「ステップ数 - 1」で、BGMTICK が
#   (長さ + 1) x テンポ ティック鳴らす。
# =====================================================================

BGM_MELODY = (
    "e5 e5 g5 e5 c6:2 g5:2  d5 d5 g5 d5 b5:2 g5:2  c5 c5 e5 c5 a5:2 e5:2  f5 g5 a5 g5 f5:2 r:2 "
    "e5 e5 g5 e5 c6:2 e6:2  d6 c6 b5 a5 g5:2 b5:2  a5 f5 a5 c6 b5 g5 b5 d6  c6:4 r:2 g5:2 "
    "a5:2 c6 a5 f5:2 a5:2  g5:2 c6 g5 e5:2 g5:2  a5:2 c6 a5 f5:2 c6:2  b5 a5 g5 a5 b5:2 d6:2 "
    "c6:2 a5 e5 a5:2 c6:2  b5:2 g5 e5 g5:2 b5:2  a5 f5 a5 c6 d6 b5 g5 b5  c6:4 r:4")

# 半小節ごとのコード
BGM_CHORDS = [
    "C", "C", "G", "G", "Am", "Am", "F", "F", "C", "C", "G", "G", "F", "G", "C", "C",
    "F", "F", "C", "C", "F", "F", "G", "G", "Am", "Am", "Em", "Em", "F", "G", "C", "C",
]
BGM_CHORD_NOTES = {   # (根音, 5 度, 裏拍で鳴らす音)
    "G": ("g2", "d3", "b4"), "Am": ("a2", "e3", "c5"), "F": ("f2", "c3", "a4"),
    "Em": ("e2", "b2", "g4"), "C": ("c3", "g2", "e4"),
}


def bgm_rows():
    mel = BGM_MELODY.replace('r:', '-:').replace(' r ', ' - ')
    bass, chop = [], []
    for c in BGM_CHORDS:
        root, fifth, third = BGM_CHORD_NOTES[c]
        bass += ['%s:2' % root, '%s:2' % fifth]
        chop += ['-', third, '-', third]
    rows = merge([voice(mel), voice(' '.join(chop)), voice(' '.join(bass))], 1)
    assert sum(r[3] + 1 for r in rows) == 128, sum(r[3] + 1 for r in rows)
    return rows


def emit_bgm():
    L = ['; ==== sfxgen.py ここから (BGM) — 直接編集しないこと ====',
         '; 元の版の BGM (16 小節 = 128 ステップでくり返す)',
         '; 主旋律, 和音, ベース, ステップ数-1   (0xFF で最初に戻る)',
         'BGM_D_MAIN:']
    for r in bgm_rows():
        L.append('        DB      %s' % ', '.join(
            ('HOLD' if c == 0xFE else str(c)) for c in r))
    L.append('        DB      0xFF')
    L.append('; ==== sfxgen.py ここまで (BGM) ====')
    return '\n'.join(L)


def write_sound_asm(blocks):
    """sound.asm の「sfxgen.py ここから (名前) 〜 ここまで (名前)」を置き換える。"""
    import io
    import os
    import re
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'sound.asm')
    text = io.open(path, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(eol)
    for blk in blocks:
        tag = re.search(r'ここから (\(.*?\))', blk.split('\n')[0]).group(1)
        start = [i for i, l in enumerate(lines) if ('sfxgen.py ここから ' + tag) in l]
        end = [i for i, l in enumerate(lines) if ('sfxgen.py ここまで ' + tag) in l]
        assert len(start) == 1 and len(end) == 1, ('区間が見つからない', tag)
        lines[start[0]:end[0] + 1] = blk.split('\n')
    io.open(path, 'w', encoding='utf-8', newline='').write(eol.join(lines))
    print('書き換えました:', os.path.normpath(path))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--write', action='store_true')
    args = ap.parse_args(argv)
    if args.check:
        print('SSG の音程: f = %d / TP' % (CLOCK // SSG_DIV))
        for name, prio, steps in SFX:
            rows = sfx_rows(steps)
            print('%-10s 優先度%d  %2d ティック  %s' % (
                name, prio, sum(r[3] for r in rows),
                ' '.join(r[4].strip() for r in rows)))
        return 0
    blocks = [emit_sfx_equ(), emit_sfx(), emit_jingles(), emit_bgm()]
    if args.write:
        write_sound_asm(blocks)
        return 0
    for b in blocks:
        print(b)
    return 0


if __name__ == '__main__':
    sys.exit(main())
