namespace ShibaJintori;

/// <summary>全スプライト。起動時に SpriteData から生成する。</summary>
public static class Art
{
    /// <summary>
    /// [犬種][0:正面 1:正面歩き 2:後ろ 3:後ろ歩き 4:右向き 5:右向き歩き
    ///        6:おしっこ(電柱が右。お尻をこちらに向けた絵。左は反転) 7:おしっこ(電柱が上) 8:おしっこ(電柱が下)]
    /// </summary>
    public static Sprite[][] Dogs = [];
    public static Sprite Pole, PeeMark, PoleBand, Grass0, Grass1, RoadTop, RoadBottom, Paw;
    /// <summary>[0:骨 1:巻物]</summary>
    public static Sprite[] Items = [];
    /// <summary>実績アイコン用の絵 (Flag, Moon, Star, Trophy, Crown, Drop, Heart, Bolt)</summary>
    public static Dictionary<string, Sprite> Icons = new();
    public static Sprite[] Cars = [];

    public static void Load()
    {
        static string[] Join(string a, string b) => [.. Gfx.Rows(a), .. Gfx.Rows(b)];

        // rows の startRow 行目から patch を重ねる。patch の '_' は元の絵を残す
        static string[] Overlay(string[] rows, int startRow, string[] patch)
        {
            for (int y = 0; y < patch.Length; y++)
            {
                var line = rows[startRow + y].ToCharArray();
                for (int x = 0; x < line.Length && x < patch[y].Length; x++)
                    if (patch[y][x] != '_') line[x] = patch[y][x];
                rows[startRow + y] = new string(line);
            }
            return rows;
        }

        Dogs = new Sprite[Breed.All.Length][];
        for (int i = 0; i < Breed.All.Length; i++)
        {
            var b = Breed.All[i];
            var pal = b.BuildPalette();
            var (fh, bh, st) = b.Ear switch
            {
                Ear.Big => (SpriteData.FrontHeadBig, SpriteData.BackHeadBig, SpriteData.SideTopBig),
                Ear.Floppy => (SpriteData.FrontHeadFloppy, SpriteData.BackHeadFloppy, SpriteData.SideTopFloppy),
                _ => (SpriteData.FrontHeadPointy, SpriteData.BackHeadPointy, SpriteData.SideTopPointy),
            };
            Dogs[i] =
            [
                Gfx.MakeSprite(Join(fh, SpriteData.FrontBodyStand), pal),
                Gfx.MakeSprite(Join(fh, SpriteData.FrontBodyStride), pal),
                Gfx.MakeSprite(Join(bh, SpriteData.BackBodyStand), pal),
                Gfx.MakeSprite(Join(bh, SpriteData.BackBodyStride), pal),
                Gfx.MakeSprite(Join(st, SpriteData.SideLegsStand), pal),
                Gfx.MakeSprite(Join(st, SpriteData.SideLegsStride), pal),
                Gfx.MakeSprite(Overlay(Join(bh, SpriteData.BackBodyPee), 6, Gfx.Rows(SpriteData.BackPeeTail)), pal),
                Gfx.MakeSprite([.. Gfx.Rows(st)[..11], .. Gfx.Rows(SpriteData.SideBottomPeeFar)], pal),
                Gfx.MakeSprite([.. Gfx.Rows(st)[..12], .. Gfx.Rows(SpriteData.SideBottomPeeNear)], pal),
            ];
        }

        var white = new Dictionary<char, uint> { ['W'] = 0xFFFFFF, ['O'] = 0x202020 };
        var misc = new Dictionary<char, uint>
        {
            ['O'] = 0x20242C, ['G'] = 0xB8BCC4, ['g'] = 0x8A8E98, ['W'] = 0x6A4A2A, ['I'] = 0xE8E8F0,
        };
        Pole = Gfx.MakeSprite(Gfx.Rows(SpriteData.Pole), misc);
        PeeMark = Gfx.MakeSprite(Gfx.Rows(SpriteData.PeeMark), white);
        PoleBand = Gfx.MakeSprite(Gfx.Rows(SpriteData.PoleBand), white);
        Paw = Gfx.MakeSprite(Gfx.Rows(SpriteData.Paw), white);
        var itemPal = new Dictionary<char, uint>
        {
            ['O'] = 0x30241C, ['W'] = 0xFFFFFF, ['w'] = 0xD8D0C0, ['P'] = 0x7A48C8, ['R'] = 0xE83838, ['y'] = 0xF0C040,
        };
        Items = [Gfx.MakeSprite(Gfx.Rows(SpriteData.Bone), itemPal), Gfx.MakeSprite(Gfx.Rows(SpriteData.Scroll), itemPal)];

        var iconPal = new Dictionary<char, uint>
        {
            ['O'] = 0x20242C, ['Y'] = 0xFFD840, ['y'] = 0xC89A20, ['W'] = 0xFFFFFF, ['w'] = 0xC8CCD8,
            ['R'] = 0xE84848, ['r'] = 0xA82828, ['B'] = 0x58A8F0, ['b'] = 0x2F6FB8, ['M'] = 0xFFF0A0,
        };
        Icons = new Dictionary<string, Sprite>
        {
            ["Flag"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconFlag), iconPal),
            ["Moon"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconMoon), iconPal),
            ["Star"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconStar), iconPal),
            ["Trophy"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconTrophy), iconPal),
            ["Crown"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconCrown), iconPal),
            ["Drop"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconDrop), iconPal),
            ["Heart"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconHeart), iconPal),
            ["Bolt"] = Gfx.MakeSprite(Gfx.Rows(SpriteData.IconBolt), iconPal),
        };

        var grass = new Dictionary<char, uint>
        {
            ['g'] = 0x5AA843, ['G'] = 0x4C963A, ['d'] = 0x6DB84F, ['f'] = 0xFFFFFF, ['y'] = 0xFFE040,
        };
        Grass0 = Gfx.MakeSprite(Gfx.Rows(SpriteData.Grass0), grass);
        Grass1 = Gfx.MakeSprite(Gfx.Rows(SpriteData.Grass1), grass);
        var road = new Dictionary<char, uint> { ['r'] = 0x5C5E68, ['w'] = 0xD8D8D0, ['e'] = 0x8C8C84 };
        RoadTop = Gfx.MakeSprite(Gfx.Rows(SpriteData.RoadTop), road);
        RoadBottom = Gfx.MakeSprite(Gfx.Rows(SpriteData.RoadBottom), road);

        uint[] body = [0xE8483A, 0x3A7BE8, 0xF0C020, 0xF0F0F0];
        Cars = new Sprite[body.Length];
        for (int i = 0; i < body.Length; i++)
        {
            var pal = new Dictionary<char, uint>
            {
                ['O'] = 0x20242C, ['A'] = body[i], ['a'] = Gfx.Shade(body[i], 0.75f), ['G'] = 0xBFE4F5,
                ['K'] = 0x18181C, ['S'] = 0xA0A4AC, ['Y'] = 0xFFE66A, ['R'] = 0xFF3030,
            };
            Cars[i] = Gfx.MakeSprite(Gfx.Rows(SpriteData.Car), pal);
        }
    }
}
