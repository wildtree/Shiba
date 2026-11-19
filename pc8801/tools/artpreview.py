#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
artpreview.py - ドット絵を PNG にして確認する

    python tools/artpreview.py preview.png

16x8 のスプライトを縦 2 倍 (実機の見た目) にして並べる。
体の色はその絵らしい色を割り当てる。
"""

import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art        # noqa: E402
import pc88emu    # noqa: E402

SCALE = 3
CELLW, CELLH = 16, 8
COLS = 8


def pen_rgb(i):
    r, g, b = art.PALETTE[i]
    return (min(255, r * 36), min(255, g * 36), min(255, b * 36))


def render_sprite(data, body):
    """48 バイトのスプライトを (16,8) の色番号にする。"""
    out = [[0] * 16 for _ in range(8)]
    for k in range(16):
        mask, bodyb, white = data[k * 3], data[k * 3 + 1], data[k * 3 + 2]
        row = k // 2
        half = k % 2
        for bit in range(8):
            m = 0x80 >> bit
            if not (mask & m):
                continue
            x = half * 8 + bit
            if white & m:
                out[row][x] = art.C_WHITE
            elif bodyb & m:
                out[row][x] = body
            else:
                out[row][x] = art.C_DARK
    return out


BODY_FOR = {
    'DOG_POINTY': art.C_ORANGE, 'DOG_BIG': art.C_YELLOW, 'DOG_FLOPPY': art.C_RED,
    'PEE_POINTY': art.C_ORANGE, 'PEE_BIG': art.C_YELLOW, 'PEE_FLOPPY': art.C_RED,
    'BOSS': art.C_RED, 'BIG': art.C_ORANGE, 'CARR': art.C_RED, 'CARL': art.C_BLUE,
    'PEEMARK': art.C_ORANGE, 'POLEBAND': art.C_BLUE, 'SCROLL': art.C_BLUE,
}


def body_of(name):
    for k, v in BODY_FOR.items():
        if name.startswith('SPR_' + k):
            return v
    return art.C_WHITE


def main(argv=None):
    out = (argv or sys.argv[1:] or ['artpreview.png'])[0]
    items = [(n, d) for (n, d) in art.collect()
             if n.startswith('SPR_') and len(d) == 48]
    rows = (len(items) + COLS - 1) // COLS
    W = COLS * (CELLW + 2) * SCALE
    H = rows * (CELLH * 2 + 10) * SCALE
    img = [[(24, 24, 32)] * W for _ in range(H)]

    for idx, (name, data) in enumerate(items):
        cx = (idx % COLS) * (CELLW + 2) * SCALE
        cy = (idx // COLS) * (CELLH * 2 + 10) * SCALE
        pix = render_sprite(data, body_of(name))
        for y in range(8):
            for x in range(16):
                c = pix[y][x]
                col = pen_rgb(c) if c else (40, 40, 48)
                for sy in range(SCALE * 2):
                    for sx in range(SCALE):
                        yy = cy + y * SCALE * 2 + sy
                        xx = cx + x * SCALE + sx
                        if 0 <= yy < H and 0 <= xx < W:
                            img[yy][xx] = col

    raw = bytearray()
    for y in range(H):
        raw.append(0)
        for (r, g, b) in img[y]:
            raw += bytes((r, g, b))
    with open(out, 'wb') as f:
        f.write(pc88emu.png_bytes(W, H, bytes(raw)))
    print("書き出しました: %s (%d 枚)" % (out, len(items)))
    for i, (n, _) in enumerate(items):
        if i % COLS == 0:
            print()
        print("%-18s" % n[4:], end='')
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
