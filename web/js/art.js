"use strict";
// 全スプライト。起動時に SpriteData から生成する (PC版 Art.cs と同じ)。

const Art = {
  /** [犬種][0:正面 1:正面歩き 2:後ろ 3:後ろ歩き 4:右向き 5:右向き歩き 6:おしっこ(電柱が右) 7:おしっこ(上) 8:おしっこ(下)] */
  Dogs: [],
  Pole: null, PeeMark: null, PoleBand: null, Grass0: null, Grass1: null, RoadTop: null, RoadBottom: null, Paw: null,
  Items: [],
  Icons: {},
  Cars: [],

  load() {
    const D = SpriteData;
    const join = (a, b) => [...rows(a), ...rows(b)];
    // rows の startRow 行目から patch を重ねる。patch の '_' は元の絵を残す
    const overlay = (r, startRow, patch) => {
      for (let y = 0; y < patch.length; y++) {
        const line = r[startRow + y].split("");
        for (let x = 0; x < line.length && x < patch[y].length; x++)
          if (patch[y][x] !== "_") line[x] = patch[y][x];
        r[startRow + y] = line.join("");
      }
      return r;
    };

    this.Dogs = Breeds.map(b => {
      const pal = buildPalette(b);
      const [fh, bh, st] =
        b.ear === Ear.Big ? [D.FrontHeadBig, D.BackHeadBig, D.SideTopBig]
        : b.ear === Ear.Floppy ? [D.FrontHeadFloppy, D.BackHeadFloppy, D.SideTopFloppy]
        : [D.FrontHeadPointy, D.BackHeadPointy, D.SideTopPointy];
      return [
        Gfx.makeSprite(join(fh, D.FrontBodyStand), pal),
        Gfx.makeSprite(join(fh, D.FrontBodyStride), pal),
        Gfx.makeSprite(join(bh, D.BackBodyStand), pal),
        Gfx.makeSprite(join(bh, D.BackBodyStride), pal),
        Gfx.makeSprite(join(st, D.SideLegsStand), pal),
        Gfx.makeSprite(join(st, D.SideLegsStride), pal),
        Gfx.makeSprite(overlay(join(bh, D.BackBodyPee), 6, rows(D.BackPeeTail)), pal),
        Gfx.makeSprite([...rows(st).slice(0, 11), ...rows(D.SideBottomPeeFar)], pal),
        Gfx.makeSprite([...rows(st).slice(0, 12), ...rows(D.SideBottomPeeNear)], pal),
      ];
    });

    const white = { W: 0xFFFFFF, O: 0x202020 };
    const misc = { O: 0x20242C, G: 0xB8BCC4, g: 0x8A8E98, W: 0x6A4A2A, I: 0xE8E8F0 };
    this.Pole = Gfx.makeSprite(rows(D.Pole), misc);
    this.PeeMark = Gfx.makeSprite(rows(D.PeeMark), white);
    this.PoleBand = Gfx.makeSprite(rows(D.PoleBand), white);
    this.Paw = Gfx.makeSprite(rows(D.Paw), white);
    const itemPal = { O: 0x30241C, W: 0xFFFFFF, w: 0xD8D0C0, P: 0x7A48C8, R: 0xE83838, y: 0xF0C040 };
    this.Items = [Gfx.makeSprite(rows(D.Bone), itemPal), Gfx.makeSprite(rows(D.Scroll), itemPal)];

    const iconPal = {
      O: 0x20242C, Y: 0xFFD840, y: 0xC89A20, W: 0xFFFFFF, w: 0xC8CCD8,
      R: 0xE84848, r: 0xA82828, B: 0x58A8F0, b: 0x2F6FB8, M: 0xFFF0A0,
    };
    this.Icons = {
      Flag: Gfx.makeSprite(rows(D.IconFlag), iconPal),
      Moon: Gfx.makeSprite(rows(D.IconMoon), iconPal),
      Star: Gfx.makeSprite(rows(D.IconStar), iconPal),
      Trophy: Gfx.makeSprite(rows(D.IconTrophy), iconPal),
      Crown: Gfx.makeSprite(rows(D.IconCrown), iconPal),
      Drop: Gfx.makeSprite(rows(D.IconDrop), iconPal),
      Heart: Gfx.makeSprite(rows(D.IconHeart), iconPal),
      Bolt: Gfx.makeSprite(rows(D.IconBolt), iconPal),
    };

    const grass = { g: 0x5AA843, G: 0x4C963A, d: 0x6DB84F, f: 0xFFFFFF, y: 0xFFE040 };
    this.Grass0 = Gfx.makeSprite(rows(D.Grass0), grass);
    this.Grass1 = Gfx.makeSprite(rows(D.Grass1), grass);
    const road = { r: 0x5C5E68, w: 0xD8D8D0, e: 0x8C8C84 };
    this.RoadTop = Gfx.makeSprite(rows(D.RoadTop), road);
    this.RoadBottom = Gfx.makeSprite(rows(D.RoadBottom), road);

    const body = [0xE8483A, 0x3A7BE8, 0xF0C020, 0xF0F0F0];
    this.Cars = body.map(c => Gfx.makeSprite(rows(D.Car), {
      O: 0x20242C, A: c, a: Gfx.shade(c, 0.75), G: 0xBFE4F5, K: 0x18181C, S: 0xA0A4AC, Y: 0xFFE66A, R: 0xFF3030,
    }));
  },
};
