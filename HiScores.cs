using System.Text.Json;

namespace ShibaJintori;

public readonly record struct HiScore(string Name, int Score, int Stage);

/// <summary>
/// ハイスコア上位10件。hiscores.json に保存する。
/// 以前の形式の hiscores.txt があれば読み込んで JSON に移し、txt は消す。
/// </summary>
/// <remarks>
/// hiscores.json の形:
/// { "version": 1, "scores": [ { "name": "SHB", "score": 10000, "stage": 1 }, ... ] }
/// </remarks>
public sealed class HiScoreTable
{
    public const int Max = 10;
    public readonly List<HiScore> Entries = new();
    readonly string _path = SaveData.PathOf("hiscores.json");
    readonly string _oldPath = SaveData.PathOf("hiscores.txt");

    public HiScoreTable() => Load();

    public int Top => Entries.Count > 0 ? Entries[0].Score : 0;

    static string FixName(string name) => name.PadRight(3)[..3];

    void Load()
    {
        using (var doc = SaveData.ReadJson(_path))
        {
            if (doc != null && doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("scores", out var scores) && scores.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in scores.EnumerateArray())
                {
                    var h = new HiScore(FixName(SaveData.GetString(e, "name", "???")),
                                        SaveData.GetInt(e, "score", 0),
                                        Math.Max(1, SaveData.GetInt(e, "stage", 1)));
                    if (!Entries.Contains(h)) Entries.Add(h);
                }
            }
        }

        // 以前の形式 (1行 = 名前<TAB>スコア<TAB>ステージ)。JSON と両方あれば合わせる
        bool migrate = File.Exists(_oldPath);
        if (migrate)
        {
            try
            {
                foreach (var line in File.ReadAllLines(_oldPath))
                {
                    var p = line.Split('\t');
                    if (p.Length < 3 || !int.TryParse(p[1], out int score) || !int.TryParse(p[2], out int stage)) continue;
                    var h = new HiScore(FixName(p[0]), score, Math.Max(1, stage));
                    if (!Entries.Contains(h)) Entries.Add(h);
                }
            }
            catch (Exception e)
            {
                // 読めなかった txt は消さずに残しておく
                Console.Error.WriteLine("hiscores.txt could not be read: " + e.Message);
                migrate = false;
            }
        }

        string[] names = ["SHB", "KRO", "SRO", "CRG", "CHW", "SLT", "HSK", "PUG", "DAL", "BGL"];
        for (int i = Entries.Count; i < Max; i++) Entries.Add(new HiScore(names[i], (Max - i) * 1000, 1));
        Sort();

        // JSON に書けたときだけ txt を消す
        if (migrate && Save()) SaveData.DeleteOld(_oldPath);
    }

    void Sort()
    {
        Entries.Sort((a, b) => b.Score.CompareTo(a.Score));
        if (Entries.Count > Max) Entries.RemoveRange(Max, Entries.Count - Max);
    }

    public bool Qualifies(int score) => score > 0 && (Entries.Count < Max || score > Entries[^1].Score);

    /// <summary>登録して順位(0始まり)を返す。</summary>
    public int Add(string name, int score, int stage)
    {
        var e = new HiScore(name, score, stage);
        int rank = 0;
        while (rank < Entries.Count && Entries[rank].Score >= score) rank++;
        Entries.Insert(rank, e);
        if (Entries.Count > Max) Entries.RemoveRange(Max, Entries.Count - Max);
        Save();
        return rank;
    }

    bool Save() => SaveData.WriteJson(_path, w =>
    {
        w.WriteStartObject();
        w.WriteNumber("version", 1);
        w.WriteStartArray("scores");
        foreach (var e in Entries)
        {
            w.WriteStartObject();
            w.WriteString("name", e.Name);
            w.WriteNumber("score", e.Score);
            w.WriteNumber("stage", e.Stage);
            w.WriteEndObject();
        }
        w.WriteEndArray();
        w.WriteEndObject();
    });
}
