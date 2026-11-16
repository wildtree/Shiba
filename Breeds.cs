namespace ShibaJintori;

public enum Ear { Pointy, Big, Floppy }

/// <summary>
/// 犬種の定義。Palette は "文字=RRGGBB" または "文字=別の文字"(同じ色を使う) を空白区切りで並べる。
/// 文字の意味は SpriteData.cs の先頭コメントを参照。
/// </summary>
public sealed record Breed(string Name, string Display, Ear Ear, uint TerritoryColor, string Palette)
{
    /// <summary>0-2: 柴犬(茶/黒/白)、3以降: 敵の犬種</summary>
    public static readonly Breed[] All =
    [
        new("ShibaRed", "SHIBA", Ear.Pointy, 0xFF8C1A,
            "O=5A3214 E=D9822E P=F7B9A6 F=E8973C Y=F F=E8973C Z=F d=F K=2A1A10 H=FFFFFF C=FFF3DC N=2A1A10 M=F0707F B=F S=D9822E R=FFF3DC L=FFF3DC T=FFF3DC D=B"),
        new("ShibaBlack", "SHIBA", Ear.Pointy, 0xFF8C1A,
            "O=0C0C10 E=2E2E38 P=C98A80 F=3A3A46 Y=E0A050 Z=F d=F K=0C0C10 H=FFFFFF C=F6EAD0 N=0C0C10 M=F0707F B=F S=2E2E38 R=F6EAD0 L=E0A050 T=F6EAD0 D=B"),
        new("ShibaWhite", "SHIBA", Ear.Pointy, 0xFF8C1A,
            "O=8C7A66 E=F6ECD8 P=F7B9A6 F=FFFDF6 Y=F Z=F d=F K=2A1A10 H=FFFFFF C=FFFFFF N=2A1A10 M=F0707F B=F S=F1E6D0 R=FFFFFF L=FFFFFF T=F1E6D0 D=B"),

        new("Corgi", "CORGI", Ear.Big, 0xFFE02E,
            "O=5C3410 E=E89030 P=F7B9A6 F=F2A444 Y=F Z=FFFFFF d=F K=2A1A10 H=FFFFFF C=FFFFFF N=2A1A10 M=F0707F B=F S=E89030 R=FFFFFF L=FFFFFF T=FFFFFF D=B"),
        new("Chihuahua", "CHIHUAHUA", Ear.Big, 0xFF7EB6,
            "O=7A5630 E=EBC98A P=FFC8C0 F=F7E0AE Y=F Z=F d=F K=1A1010 H=FFFFFF C=FFF8E6 N=4A2A20 M=F0707F B=F S=EBC98A R=FFF8E6 L=FFF8E6 T=EBC98A D=B"),
        new("Sheltie", "SHELTIE", Ear.Pointy, 0xB86CFF,
            "O=3A2414 E=7A4A22 P=E0A090 F=B8742E Y=F Z=FFFFFF d=F K=1A1010 H=FFFFFF C=FFFFFF N=1A1010 M=F0707F B=F S=7A4A22 R=FFFFFF L=FFFFFF T=7A4A22 D=B"),
        new("Husky", "HUSKY", Ear.Pointy, 0x38B6FF,
            "O=1E222A E=59636F P=E8B0A8 F=7C8794 Y=FFFFFF Z=FFFFFF d=F K=2E9BE8 H=FFFFFF C=FFFFFF N=1E222A M=F0707F B=F S=59636F R=FFFFFF L=FFFFFF T=FFFFFF D=B"),
        new("Pug", "PUG", Ear.Floppy, 0xA8845C,
            "O=3A2A1A E=2A2220 P=E F=EBCB92 Y=F Z=F d=F K=000000 H=FFFFFF C=5E4C40 N=000000 M=F0707F B=F S=DDB878 R=F4DEB0 L=F T=DDB878 D=B"),
        new("Dalmatian", "DALMATIAN", Ear.Floppy, 0xE8E8F0,
            "O=3A3A40 E=26262C P=E F=FFFFFF Y=F Z=F d=26262C K=101014 H=FFFFFF C=FFFFFF N=101014 M=F0707F B=F S=F R=F L=F T=F D=26262C"),
        new("Poodle", "POODLE", Ear.Floppy, 0xFF5A4A,
            "O=6A3A20 E=B06A34 P=E F=CC8A4E Y=F Z=F d=DDA066 K=1A1010 H=FFFFFF C=DDA066 N=1A1010 M=F0707F B=F S=B06A34 R=DDA066 L=F T=B06A34 D=DDA066"),
        new("Beagle", "BEAGLE", Ear.Floppy, 0x3AD6A0,
            "O=3A2010 E=8A4A1A P=E F=B86A2A Y=F Z=FFFFFF d=F K=1A1010 H=FFFFFF C=FFFFFF N=1A1010 M=F0707F B=FFFFFF S=2A2A2E R=FFFFFF L=FFFFFF T=FFFFFF D=B86A2A"),
    ];

    public const int ShibaCount = 3;
    public static int EnemyBreedCount => All.Length - ShibaCount;

    public Dictionary<char, uint> BuildPalette()
    {
        var raw = new Dictionary<char, string>();
        foreach (var kv in Palette.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            raw[kv[0]] = kv[2..];
        var pal = new Dictionary<char, uint>();
        foreach (var k in raw.Keys)
        {
            var v = raw[k];
            for (int guard = 0; v.Length == 1 && guard < 8; guard++) v = raw[v[0]];
            pal[k] = Convert.ToUInt32(v, 16);
        }
        return pal;
    }
}

/// <summary>
/// 敵の犬種ごとの性格。数値を変えると味付けを調整できる。
///  Speed      1歩にかかる時間の倍率 (小さいほど速い)
///  Reach      2本目の電柱を選ぶときの好みの距離 (大きいほど大きななわばりを狙う)
///  SizeWeight 3本目を選ぶときに面積をどれだけ重視するか
///  Aggro      柴犬を囲もうとする強さ
///  Herd       ほかの敵犬を囲もうとする強さ
///  Steal      ほかの犬の印を上書きしたがる強さ
///  Caution    道路を渡るときの用心深さ (1未満だと確認をさぼることがある)
///  Stamina    何歩ごとに休むか (0なら休まない)、RestTime は休む秒数
///  Dither     おしっこの後にぼんやりする時間の倍率
///  Noise      気まぐれさ (大きいほど行き先がでたらめ)
/// </summary>
public sealed record Temper(
    float Speed, int Reach, float SizeWeight, float Aggro, float Herd, float Steal, float Caution,
    int Stamina, float RestTime, float Dither, float Noise, string RestText, string Trait)
{
    public static readonly Temper Default = new(1f, 7, 1f, 1f, 0f, 1f, 1f, 0, 0f, 1f, 1f, "", "");

    public static Temper For(Breed b) => b.Name switch
    {
        // コーギー: 足が短くて少し遅いが、用心深く堅実
        "Corgi" => new(1.08f, 6, 1.0f, 0.8f, 0.5f, 1.0f, 1.6f, 0, 0f, 1.0f, 1.0f, "", "STEADY"),
        // チワワ: すばしこいがスタミナがなく、よく休む。小さななわばりをたくさん作る
        "Chihuahua" => new(0.70f, 3, 0.25f, 0.4f, 0f, 0.5f, 1.2f, 28, 2.4f, 0.5f, 1.2f, "HAH..", "QUICK"),
        // シェルティー: 牧羊犬。かしこく、ほかの犬を囲い込むのが得意
        "Sheltie" => new(0.92f, 8, 1.0f, 1.2f, 2.0f, 1.0f, 1.2f, 0, 0f, 0.7f, 0.6f, "", "HERDER"),
        // ハスキー: 攻撃的。柴犬のそばに陣取り、大きななわばりで囲みに来る。車には無頓着
        "Husky" => new(0.86f, 13, 1.6f, 2.4f, 0.5f, 1.5f, 0.6f, 0, 0f, 0.6f, 0.8f, "", "FIERCE"),
        // パグ: のんびり屋。歩くのが遅く、すぐ昼寝する
        "Pug" => new(1.35f, 5, 0.7f, 0.5f, 0f, 0.5f, 1.5f, 16, 3.2f, 2.0f, 1.0f, "ZZZ", "LAZY"),
        // ダルメシアン: 走るのが大好きで遠くの電柱まで行く。車が好きで道路を気にしない
        "Dalmatian" => new(0.78f, 11, 1.2f, 0.8f, 0f, 1.0f, 0.25f, 0, 0f, 0.8f, 1.5f, "", "RUNNER"),
        // プードル: 頭脳派。迷いがなく、ほかの犬の印をどんどん上書きする
        "Poodle" => new(0.95f, 7, 1.0f, 1.0f, 0.3f, 3.0f, 1.3f, 0, 0f, 0.5f, 0.4f, "", "CLEVER"),
        // ビーグル: においに夢中。ほかの犬の印に引き寄せられ、気まぐれに寄り道する
        "Beagle" => new(1.0f, 7, 0.9f, 0.7f, 0f, 2.0f, 0.8f, 20, 1.2f, 1.2f, 3.0f, "SNIFF", "NOSY"),
        _ => Default,
    };
}
