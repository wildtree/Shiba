#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
d88.py - D88 ディスクイメージの読み書き

2D フォーマット: 40 シリンダ x 2 面 x 16 セクタ x 256 バイト = 320KB
コマンド上の「トラック番号」は論理トラック = シリンダ*2 + 面 (0..79)。
"""

import struct

HEADER_SIZE = 0x2B0
TRACK_TABLE = 164

MEDIA_2D = 0x00
MEDIA_2DD = 0x10
MEDIA_2HD = 0x20


class Disk:
    """論理トラック(0..79) x セクタ(1..16) の 256 バイトセクタの集まり。"""

    def __init__(self, name='', media=MEDIA_2D, cylinders=40, heads=2,
                 sectors=16, secsize=256):
        self.name = name
        self.media = media
        self.cylinders = cylinders
        self.heads = heads
        self.sectors = sectors
        self.secsize = secsize
        # (logical_track, sector) -> bytearray
        self.data = {}
        for t in range(cylinders * heads):
            for s in range(1, sectors + 1):
                self.data[(t, s)] = bytearray(secsize)

    # ------------------------------------------------------------------ 読み書き

    def put(self, track, sector, payload):
        if (track, sector) not in self.data:
            raise ValueError("トラック %d セクタ %d は存在しません" % (track, sector))
        buf = bytearray(self.secsize)
        buf[:len(payload)] = payload[:self.secsize]
        self.data[(track, sector)] = buf

    def get(self, track, sector):
        return self.data.get((track, sector))

    def write_linear(self, start_track, start_sector, payload):
        """指定位置から連続セクタに書く。使ったセクタ数を返す。"""
        t, s = start_track, start_sector
        n = 0
        for off in range(0, len(payload), self.secsize):
            self.put(t, s, payload[off:off + self.secsize])
            n += 1
            s += 1
            if s > self.sectors:
                s = 1
                t += 1
                if t >= self.cylinders * self.heads:
                    raise ValueError("ディスクの容量を超えました")
        return n

    def read_linear(self, start_track, start_sector, nbytes):
        out = bytearray()
        t, s = start_track, start_sector
        while len(out) < nbytes:
            out += self.get(t, s)
            s += 1
            if s > self.sectors:
                s = 1
                t += 1
        return bytes(out[:nbytes])

    # ------------------------------------------------------------------ D88

    def to_bytes(self):
        n_tracks = self.cylinders * self.heads
        sector_blocks = []
        offsets = [0] * TRACK_TABLE
        pos = HEADER_SIZE
        for t in range(n_tracks):
            offsets[t] = pos
            cyl, head = divmod(t, self.heads)
            for s in range(1, self.sectors + 1):
                payload = self.data[(t, s)]
                n_code = {128: 0, 256: 1, 512: 2, 1024: 3}[self.secsize]
                hdr = struct.pack('<BBBBHBBB5sH',
                                  cyl, head, s, n_code,
                                  self.sectors,
                                  0x00,            # 倍密度
                                  0x00,            # 削除データでない
                                  0x00,            # FDC ステータス正常
                                  b'\0' * 5,
                                  len(payload))
                assert len(hdr) == 16, len(hdr)
                sector_blocks.append(hdr + bytes(payload))
                pos += 16 + len(payload)

        total = pos
        head = bytearray(HEADER_SIZE)
        nm = self.name.encode('ascii', 'replace')[:16]
        head[0:len(nm)] = nm
        head[0x10] = 0
        head[0x1A] = 0x00           # 書き込み可
        head[0x1B] = self.media
        struct.pack_into('<I', head, 0x1C, total)
        for i, off in enumerate(offsets):
            struct.pack_into('<I', head, 0x20 + i * 4, off)
        return bytes(head) + b''.join(sector_blocks)

    def save(self, path):
        with open(path, 'wb') as f:
            f.write(self.to_bytes())

    # ------------------------------------------------------------------ 読み込み

    @classmethod
    def load(cls, path):
        with open(path, 'rb') as f:
            raw = f.read()
        return cls.from_bytes(raw)

    @classmethod
    def from_bytes(cls, raw):
        if len(raw) < HEADER_SIZE:
            raise ValueError("D88 ヘッダが短すぎます")
        media = raw[0x1B]
        name = raw[0:16].split(b'\0')[0].decode('ascii', 'replace')
        offsets = [struct.unpack_from('<I', raw, 0x20 + i * 4)[0]
                   for i in range(TRACK_TABLE)]
        d = cls(name=name, media=media)
        d.data = {}
        max_track = -1
        for t, off in enumerate(offsets):
            if off == 0 or off >= len(raw):
                continue
            # そのトラックのセクタ数はセクタヘッダから取る
            p = off
            c, h, r, n = raw[p], raw[p + 1], raw[p + 2], raw[p + 3]
            nsec = struct.unpack_from('<H', raw, p + 4)[0]
            if nsec == 0 or nsec > 64:
                continue
            for _ in range(nsec):
                if p + 16 > len(raw):
                    break
                c, h, r, n = raw[p], raw[p + 1], raw[p + 2], raw[p + 3]
                size = 128 << n
                dlen = struct.unpack_from('<H', raw, p + 14)[0]
                if dlen == 0 or dlen > size:
                    dlen = size
                body = bytearray(size)
                body[:dlen] = raw[p + 16:p + 16 + dlen]
                d.data[(t, r)] = body
                p += 16 + dlen
            max_track = max(max_track, t)
        d.cylinders = (max_track // 2) + 1 if max_track >= 0 else 0
        d.heads = 2
        return d


def blank_2d(name='SHIBA88'):
    return Disk(name=name, media=MEDIA_2D, cylinders=40, heads=2,
                sectors=16, secsize=256)


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1:
        d = Disk.load(sys.argv[1])
        print("名前=%r メディア=%02Xh シリンダ=%d" % (d.name, d.media, d.cylinders))
        print("セクタ数 =", len(d.data))
        s = d.get(0, 1)
        print("トラック0 セクタ1 先頭 32 バイト:", s[:32].hex())
