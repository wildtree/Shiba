using System.Globalization;
using System.Text.Json;

namespace ShibaJintori;

/// <summary>
/// 実績。解除した実績はユーザーの設定フォルダ (ハイスコアと同じ場所) の achievements.json に保存する。
/// 名前と解除条件は、解除されるまで画面に出さない。
/// </summary>
public static class Achievements
{
    public sealed record Def(string Id, string Name, string Desc);

    /// <summary>実績画面では 8列 x 3行 でこの順に並ぶ。</summary>
    public static readonly Def[] All =
    [
        new("FIRST_TURF", "MY FIRST TURF", "CLAIM YOUR FIRST TERRITORY."),
        new("BIG_TURF", "BIG TURF", "CLAIM 100 OR MORE TILES AT ONCE."),
        new("HALF", "HALF THE TOWN", "OWN HALF OF THE FIELD IN ONE STAGE."),
        new("CATCH_DOG", "GOTCHA!", "SURROUND ANOTHER DOG WITH YOUR TERRITORY."),
        new("DOUBLE_CATCH", "DOUBLE CATCH", "SURROUND TWO OR MORE DOGS AT ONCE."),
        new("BOSS_DOWN", "GIANT SLAYER", "SURROUND THE BOSS DOG."),
        new("GOT_CAUGHT", "SURROUNDED...", "GET SURROUNDED BY ANOTHER DOG'S TERRITORY."),
        new("CAR_HIT", "WATCH THE ROAD", "GET HIT BY A CAR."),

        new("OVERWRITE", "MY POLE NOW", "PEE OVER ANOTHER DOG'S MARK."),
        new("WASHED", "WASHED AWAY", "HAVE YOUR MARKS WASHED AWAY BY THE RAIN."),
        new("BONE", "GOOD BOY", "PICK UP A BONE."),
        new("NINJA", "NINJA DOG", "WALK THROUGH ANOTHER DOG'S TERRITORY."),
        new("GIVE_UP", "I GIVE UP", "GIVE UP A STAGE FROM THE PAUSE MENU."),
        new("ONE_UP", "ONE MORE LIFE", "EARN AN EXTRA LIFE."),
        new("NO_MISS", "FLAWLESS", "CLEAR A STAGE WITHOUT A SINGLE MISS."),
        new("SPEEDY", "SPEED RUN", "CLEAR A STAGE WITHIN 2 MINUTES."),

        new("STAGE4", "STAGE 4 CLEAR", "CLEAR STAGE 4."),
        new("STAGE8", "STAGE 8 CLEAR", "CLEAR STAGE 8."),
        new("STAGE16", "STAGE 16 CLEAR", "CLEAR STAGE 16."),
        new("BONUS_CLEAR", "NIGHT WALK", "FINISH A BONUS STAGE."),
        new("BONUS_PERFECT", "SWEET DREAMS", "SURROUND ALL THE SLEEPING DOGS IN A BONUS STAGE."),
        new("SCORE_100K", "BIG SCORE", "SCORE 100,000 POINTS IN ONE GAME."),
        new("ALL_SHIBA", "SHIBA TRIO", "CLEAR A STAGE WITH ALL THREE SHIBA COLORS."),
        new("HIGH_SCORE", "HALL OF FAME", "ENTER YOUR NAME IN THE HIGH SCORE TABLE."),
    ];

    public const int Columns = 8;
    public const float ToastTime = 3.5f;

    // ID → 解除した日時 (UNIX秒)。"_" で始まるIDは画面に出さない途中経過 (柴犬の色ごとのクリアなど)
    static readonly Dictionary<string, long> _got = new();
    static readonly Queue<int> _toasts = new();
    static float _toastT;
    static bool _loaded;
    static string _path = "";

    public static int Unlocked
    {
        get
        {
            Load();
            int n = 0;
            foreach (var d in All) if (_got.ContainsKey(d.Id)) n++;
            return n;
        }
    }

    public static bool Has(string id)
    {
        Load();
        return _got.ContainsKey(id);
    }

    public static DateTimeOffset? When(string id)
    {
        Load();
        return _got.TryGetValue(id, out long t) ? DateTimeOffset.FromUnixTimeSeconds(t).ToLocalTime() : null;
    }

    /// <summary>実績を解除する。初めてなら保存して、画面上部に通知を出す。</summary>
    public static void Unlock(string id)
    {
        Load();
        if (_got.ContainsKey(id)) return;
        int index = Array.FindIndex(All, d => d.Id == id);
        if (index < 0) return;
        _got[id] = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        Save();
        _toasts.Enqueue(index);
        if (_toasts.Count == 1) _toastT = 0;
        Audio.Play(Sfx.Achievement);
    }

    /// <summary>画面に出さない途中経過を記録する。</summary>
    public static void Mark(string key)
    {
        Load();
        if (_got.ContainsKey(key)) return;
        _got[key] = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        Save();
    }

    /// <remarks>
    /// achievements.json の形 (日時は UTC の ISO 8601):
    /// { "version": 1,
    ///   "unlocked": { "FIRST_TURF": "2026-11-17T09:20:00.0000000+00:00", ... },
    ///   "progress": { "_SHIBA0": "...", ... } }
    /// 以前の形式の achievements.txt があれば読み込んで JSON に移し、txt は消す。
    /// </remarks>
    static void Load()
    {
        if (_loaded) return;
        _loaded = true;
        _path = SaveData.PathOf("achievements.json");
        string oldPath = SaveData.PathOf("achievements.txt");

        using (var doc = SaveData.ReadJson(_path))
        {
            if (doc != null && doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                ReadSection(doc.RootElement, "unlocked");
                ReadSection(doc.RootElement, "progress");
            }
        }

        // 以前の形式 (1行 = ID<TAB>UNIX秒)。JSON と両方あれば合わせる
        bool migrate = File.Exists(oldPath);
        if (migrate)
        {
            try
            {
                foreach (var line in File.ReadAllLines(oldPath))
                {
                    var p = line.Split('\t');
                    if (p.Length >= 2 && long.TryParse(p[1], out long t)) _got.TryAdd(p[0], t);
                }
            }
            catch (Exception e)
            {
                // 読めなかった txt は消さずに残しておく
                Console.Error.WriteLine("achievements.txt could not be read: " + e.Message);
                migrate = false;
            }
        }

        // JSON に書けたときだけ txt を消す
        if (migrate && Save()) SaveData.DeleteOld(oldPath);
    }

    static void ReadSection(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var section) || section.ValueKind != JsonValueKind.Object) return;
        foreach (var kv in section.EnumerateObject())
        {
            if (kv.Value.ValueKind != JsonValueKind.String) continue;
            if (DateTimeOffset.TryParse(kv.Value.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var when))
                _got.TryAdd(kv.Name, when.ToUnixTimeSeconds());
        }
    }

    static bool Save() => SaveData.WriteJson(_path, w =>
    {
        w.WriteStartObject();
        w.WriteNumber("version", 1);
        // 実績は定義の順、途中経過はその後ろに
        w.WriteStartObject("unlocked");
        foreach (var d in All)
            if (_got.TryGetValue(d.Id, out long t)) w.WriteString(d.Id, Iso(t));
        w.WriteEndObject();
        w.WriteStartObject("progress");
        foreach (var kv in _got)
            if (kv.Key.StartsWith('_')) w.WriteString(kv.Key, Iso(kv.Value));
        w.WriteEndObject();
        w.WriteEndObject();
    });

    static string Iso(long unixSeconds) =>
        DateTimeOffset.FromUnixTimeSeconds(unixSeconds).ToString("o", CultureInfo.InvariantCulture);

    // ------------------------------------------------------------ 通知

    public static void UpdateToast(float dt)
    {
        if (_toasts.Count == 0) return;
        _toastT += dt;
        if (_toastT < ToastTime) return;
        _toasts.Dequeue();
        _toastT = 0;
    }

    /// <summary>解除したときの通知。画面上部に上からすべり込む。</summary>
    public static void DrawToast()
    {
        if (_toasts.Count == 0) return;
        int index = _toasts.Peek();
        const float W = 300, H = 48;
        float slide = Math.Min(Math.Min(_toastT, ToastTime - _toastT) / 0.25f, 1f);
        float x = (Gfx.W - W) / 2, y = -H + (H + 6) * slide;
        Gfx.Fill(x + 3, y + 3, W, H, 0x000000, 120);
        Gfx.Fill(x, y, W, H, 0x1B2033, 240);
        Gfx.Frame(x, y, W, H, 0xFFD840);
        DrawPlate(index, x + 4, y + 4, true);
        Gfx.Text("ACHIEVEMENT UNLOCKED!", x + 50, y + 12, 0xFFD840);
        Gfx.Text(All[index].Name, x + 50, y + 28, 0xFFFFFF);
    }

    // ------------------------------------------------------------ アイコン

    /// <summary>40x40 の台座にアイコンを描く。未解除なら「?」だけ。</summary>
    public static void DrawPlate(int index, float x, float y, bool unlocked)
    {
        if (!unlocked)
        {
            Gfx.Fill(x, y, 40, 40, 0x0C0E18);
            Gfx.Frame(x, y, 40, 40, 0x3A4468);
            Gfx.Text("?", x + 12, y + 12, 0x5A6488, 2, shadow: false);
            return;
        }
        Gfx.Fill(x, y, 40, 40, 0x2C3558);
        Gfx.Frame(x, y, 40, 40, 0xFFD840);
        Gfx.Frame(x + 1, y + 1, 38, 38, 0xC89A20);
        Gfx.Clip((int)x + 2, (int)y + 2, 36, 36);
        DrawIcon(index, x + 4, y + 4);
        Gfx.Unclip();
    }

    /// <summary>32x32 の範囲にアイコンの絵を描く。ゲーム中のドット絵を使い回している。</summary>
    static void DrawIcon(int index, float x, float y)
    {
        var dogs = Art.Dogs;
        switch (All[index].Id)
        {
            case "FIRST_TURF":
                Gfx.Tint(Art.PeeMark, 0xFF8C1A); Gfx.Draw(Art.PeeMark, x, y, scale: 2); Gfx.Tint(Art.PeeMark, 0xFFFFFF);
                Gfx.Draw(Art.Pole, x, y, scale: 2);
                Gfx.Tint(Art.PoleBand, 0xFF8C1A); Gfx.Draw(Art.PoleBand, x, y, scale: 2); Gfx.Tint(Art.PoleBand, 0xFFFFFF);
                break;
            case "BIG_TURF":
                Gfx.Tint(Art.Paw, 0xFF8C1A); Gfx.Draw(Art.Paw, x, y, scale: 2); Gfx.Tint(Art.Paw, 0xFFFFFF);
                break;
            case "HALF":
                Gfx.Draw(Art.Grass0, x, y, scale: 2);
                Gfx.Fill(x, y, 16, 32, 0xFF8C1A, 170);
                Gfx.Fill(x + 15, y, 2, 32, 0x8A4A10);
                break;
            case "CATCH_DOG":
                Gfx.Draw(dogs[Breed.ShibaCount][0], x, y, scale: 2);
                break;
            case "DOUBLE_CATCH":
                Gfx.Draw(dogs[Breed.ShibaCount + 1][0], x, y + 4);
                Gfx.Draw(dogs[Breed.ShibaCount + 4][0], x + 16, y + 4);
                Gfx.Text("x2", x + 8, y + 22, 0xFFD840);
                break;
            case "BOSS_DOWN":
                Gfx.Draw(dogs[Breed.BossIndex][0], x, y, scale: 2);
                break;
            case "GOT_CAUGHT":
                Gfx.Tint(dogs[0][0], 0x8090B0); Gfx.Draw(dogs[0][0], x, y, scale: 2); Gfx.Tint(dogs[0][0], 0xFFFFFF);
                Gfx.Text("!", x + 24, y, 0xFF5050);
                break;
            case "CAR_HIT":
                Gfx.Draw(Art.Cars[0], x, y + 8);
                break;
            case "OVERWRITE":
                Gfx.Draw(dogs[0][8], x, y, scale: 2);
                break;
            case "WASHED":
                Gfx.Draw(Art.Icons["Drop"], x, y, scale: 2);
                break;
            case "BONE":
                Gfx.Draw(Art.Items[0], x, y, scale: 2);
                break;
            case "NINJA":
                Gfx.Draw(Art.Items[1], x, y, scale: 2);
                break;
            case "GIVE_UP":
                Gfx.Draw(Art.Icons["Flag"], x, y, scale: 2);
                break;
            case "ONE_UP":
                Gfx.Draw(dogs[0][0], x, y, scale: 2);
                Gfx.Text("1UP", x + 4, y + 24, 0x60FF90);
                break;
            case "NO_MISS":
                Gfx.Draw(Art.Icons["Heart"], x, y, scale: 2);
                break;
            case "SPEEDY":
                Gfx.Draw(Art.Icons["Bolt"], x, y, scale: 2);
                break;
            case "STAGE4":
            case "STAGE8":
            case "STAGE16":
            {
                Gfx.Draw(Art.Icons["Trophy"], x, y, scale: 2);
                string num = All[index].Id[5..];
                Gfx.Text(num, x + 16 - num.Length * 4, y + 6, 0x8A5A10, shadow: false);
                break;
            }
            case "BONUS_CLEAR":
                Gfx.Draw(Art.Icons["Moon"], x, y, scale: 2);
                break;
            case "BONUS_PERFECT":
                Gfx.Draw(Art.Icons["Moon"], x, y, scale: 2);
                Gfx.Draw(Art.Icons["Star"], x + 16, y + 16);
                break;
            case "SCORE_100K":
                Gfx.Draw(Art.Icons["Star"], x, y, scale: 2);
                break;
            case "ALL_SHIBA":
                Gfx.Draw(dogs[1][0], x + 8, y + 2);
                Gfx.Draw(dogs[0][0], x, y + 14);
                Gfx.Draw(dogs[2][0], x + 16, y + 14);
                break;
            case "HIGH_SCORE":
                Gfx.Draw(Art.Icons["Crown"], x, y, scale: 2);
                break;
        }
    }
}
