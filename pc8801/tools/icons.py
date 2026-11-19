#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
icons.py - 実績アイコン (24 個) を作る

元の版は 16x16 の絵を 2 倍にして 32x32 の台座に描いている。
640x200 ではドットが縦長なので、横 2 倍・縦 1 倍の 32x16 にすると同じ形になる。

データは「色ごとの 1 ビットの絵」を並べたもの:
    見出し 1 バイト: 下位 3 ビット = 色, bit4 = 32 ドット幅のまま (0 なら 16 ドット幅を横 2 倍)
    続いて 16 行 x (2 または 4) バイト
    0xFF で終わり
ふつうのアイコンは 16x16 の元絵を横に広げるだけなので 1 色 32 バイトで済む。
小さい絵を並べたものや文字の入ったものだけ 32 ドット幅のまま持つ。
"""

import icons_src as S

# メニュー画面の色 (タイトルと同じパレット)。0 と 5 は草なので自動では選ばない
MENUPAL = {1: (1, 1, 2), 2: (7, 1, 1), 3: (7, 4, 0), 4: (2, 5, 7), 6: (7, 7, 2), 7: (7, 7, 7)}
W, H = 32, 16


def near(rgb):
    r, g, b = ((rgb >> 16) & 255) * 7 / 255, ((rgb >> 8) & 255) * 7 / 255, (rgb & 255) * 7 / 255
    return min(MENUPAL, key=lambda k: (MENUPAL[k][0] - r) ** 2 + (MENUPAL[k][1] - g) ** 2
               + (MENUPAL[k][2] - b) ** 2)


def palmap(d):
    """{文字: 0xRRGGBB} -> {文字: 色番号}"""
    return {k: near(v) for k, v in d.items()}


ICONPAL = palmap({'O': 0x20242C, 'Y': 0xFFD840, 'y': 0xC89A20, 'W': 0xFFFFFF, 'w': 0xC8CCD8,
                  'R': 0xE84848, 'r': 0xA82828, 'B': 0x58A8F0, 'b': 0x2F6FB8, 'M': 0xFFF0A0})
ICONPAL['w'] = 7
ICONPAL['M'] = 6                # 月は淡い黄色
ITEMPAL = palmap({'O': 0x30241C, 'W': 0xFFFFFF, 'w': 0xD8D0C0, 'P': 0x7A48C8, 'R': 0xE83838,
                  'y': 0xF0C040})
ITEMPAL['P'] = 4                # 紫はないので青
MISCPAL = {'O': 1, 'G': 7, 'g': 4, 'W': 3, 'I': 7}


def dog_rows(ear):
    head = {'Pointy': S.FrontHeadPointy, 'Big': S.FrontHeadBig, 'Floppy': S.FrontHeadFloppy}[ear]
    return list(head) + list(S.FrontBodyStand)


def breed(i):
    name, ear, pal = S.BREEDS[i]
    return dog_rows(ear), palmap(pal)


def blank():
    return [[None] * W for _ in range(H)]


def put(cv, rows, pal, x=0, y=0, sx=2):
    """元絵を横 sx 倍・縦 1 倍で置く"""
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            col = pal.get(ch) if ch != '.' else None
            if col is None:
                continue
            for k in range(sx):
                xx, yy = x + c * sx + k, y + r
                if 0 <= xx < W and 0 <= yy < H:
                    cv[yy][xx] = col


def put_small(cv, rows, pal, x, y):
    """16x16 の元絵を 16x8 に (元の版の scale 1 にあたる)。偶数行を取り、透明なら次の行"""
    small = []
    for k in range(len(rows) // 2):
        a, b = rows[2 * k], rows[2 * k + 1]
        small.append(''.join(p if p != '.' else q for p, q in zip(a, b)))
    put(cv, small, pal, x, y, sx=1)


def text(cv, s, x, y, col):
    import art
    for i, ch in enumerate(s):
        for r, row in enumerate(art.FONT[ch]):
            for c, p in enumerate(row):
                if p != '.':
                    xx, yy = x + i * 8 + c, y + r
                    if 0 <= xx < W and 0 <= yy < H:
                        cv[yy][xx] = col


def tint(pal, light, dark):
    """明るい色を light、暗い色を dark に (つかまった柴犬の青ざめた顔)"""
    return {k: (light if v in (3, 6, 7, 4) else dark) for k, v in pal.items()}


# ---------------------------------------------------------------------
# 24 個 (Achievements.cs の DrawIcon と同じ順・同じ絵)
# ---------------------------------------------------------------------

def make_icons():
    out = []
    shiba, shibapal = breed(0)

    def new():
        cv = blank()
        out.append(cv)
        return cv

    # FIRST_TURF: 印 + 電柱 + 色帯 (柴犬の色)
    cv = new()
    put(cv, S.PeeMark, {'W': 3})
    put(cv, S.Pole, MISCPAL)
    put(cv, S.PoleBand, {'W': 3, 'O': 1})
    # BIG_TURF: 肉球
    put(new(), S.Paw, {'W': 3})
    # HALF: 草の左半分が柴犬の色
    cv = new()
    put(cv, S.Grass0, {'g': 0, 'G': 5, 'd': 5})
    for y in range(H):
        for x in range(16):
            cv[y][x] = 3
        cv[y][14] = cv[y][15] = 1
    # CATCH_DOG: コーギー
    rows, pal = breed(3)
    put(new(), rows, pal)
    # DOUBLE_CATCH: チワワとコーギーを小さく + x2 (元の版はパグ。小さくすると顔が紺に溶けるので)
    cv = new()
    rows, pal = breed(4)
    put_small(cv, rows, pal, 0, 0)
    rows, pal = breed(3)
    put_small(cv, rows, pal, 16, 0)
    text(cv, 'x2', 8, 8, 6)
    # BOSS_DOWN: セントバーナード
    rows, pal = breed(11)
    put(new(), rows, pal)
    # GOT_CAUGHT: 青ざめた柴犬 + 赤い !
    cv = new()
    put(cv, shiba, tint(shibapal, 4, 1))
    for y in range(0, 9):
        if y != 7:
            cv[y][27] = cv[y][28] = 2
    # CAR_HIT: 車 (32x16 を 32x8 に)
    cv = new()
    carpal = {'O': 1, 'A': 2, 'a': 2, 'G': 4, 'K': 1, 'S': 7, 'Y': 6, 'R': 2}
    small = []
    for k in range(8):
        a, b = S.Car[2 * k], S.Car[2 * k + 1]
        small.append(''.join(p if p != '.' else q for p, q in zip(b, a)))
    put(cv, small, carpal, 0, 4, sx=1)
    # OVERWRITE: 柴犬が電柱 (手前) におしっこ
    put(new(), list(S.SideTopPointy[:12]) + list(S.SideBottomPeeNear), shibapal)
    # WASHED: しずく / BONE: 骨 / NINJA: 巻物 / GIVE_UP: 旗
    put(new(), S.IconDrop, ICONPAL)
    put(new(), S.Bone, ITEMPAL)
    put(new(), S.Scroll, ITEMPAL)
    put(new(), S.IconFlag, ICONPAL)
    # ONE_UP: 柴犬 + 1UP
    cv = new()
    put(cv, shiba, shibapal)
    text(cv, '1UP', 4, 8, 2)
    # NO_MISS: ハート / SPEEDY: いなずま
    put(new(), S.IconHeart, ICONPAL)
    put(new(), S.IconBolt, ICONPAL)
    # STAGE4 / 8 / 16: トロフィー + 数字
    for num in ('4', '8', '16'):
        cv = new()
        put(cv, S.IconTrophy, ICONPAL)
        text(cv, num, 16 - len(num) * 4, 2, 3)
    # BONUS_CLEAR: 月 / BONUS_PERFECT: 月 + 星
    put(new(), S.IconMoon, ICONPAL)
    cv = new()
    put(cv, S.IconMoon, ICONPAL)
    put_small(cv, S.IconStar, ICONPAL, 16, 8)
    # SCORE_100K: 星
    put(new(), S.IconStar, ICONPAL)
    # ALL_SHIBA: 3 匹
    cv = new()
    for i, (x, y) in ((1, (8, 1)), (0, (0, 7)), (2, (16, 7))):
        rows, pal = breed(i)
        put_small(cv, rows, pal, x, y)
    # HIGH_SCORE: 王冠
    put(new(), S.IconCrown, ICONPAL)
    assert len(out) == 24
    return out


def encode(cv):
    wide_ok = all((row[2 * k] or 1) == (row[2 * k + 1] or 1) for row in cv for k in range(W // 2))
    data = bytearray()
    # 色 1 (紺) は台座の地の色と同じなので描かない
    for col in sorted({c for row in cv for c in row if c not in (None, 1)}):
        if wide_ok:
            data.append(col)
            for row in cv:
                for b in range(2):
                    v = 0
                    for i in range(8):
                        if row[(b * 8 + i) * 2] == col:
                            v |= 0x80 >> i
                    data.append(v)
        else:
            data.append(col | 0x10)
            for row in cv:
                for b in range(4):
                    v = 0
                    for i in range(8):
                        if row[b * 8 + i] == col:
                            v |= 0x80 >> i
                    data.append(v)
    data.append(0xFF)
    return bytes(data)


def emit_lines():
    lines = ['; ---- 実績アイコン (tools/icons.py) ----']
    icons = make_icons()
    lines.append('ICONTBL:')
    for i in range(0, 24, 6):
        lines.append('        DW      ' + ', '.join('ICON_%d' % k for k in range(i, i + 6)))
    total = 0
    for i, cv in enumerate(icons):
        d = encode(cv)
        total += len(d)
        lines.append('ICON_%d:' % i)
        for k in range(0, len(d), 16):
            lines.append('        DB      ' + ','.join('0x%02X' % b for b in d[k:k + 16]))
    lines.append('; アイコンのデータ: %d バイト' % total)
    lines.append('')
    return lines


if __name__ == '__main__':
    # 文字で確かめる
    for i, cv in enumerate(make_icons()):
        print(i, len(encode(cv)))
        for row in cv:
            print(''.join('.' if c is None else str(c) for c in row))
