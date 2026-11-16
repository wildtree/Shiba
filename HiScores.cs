namespace ShibaJintori;

public readonly record struct HiScore(string Name, int Score, int Stage);

/// <summary>ハイスコア上位10件。ユーザーの設定フォルダにテキストで保存する。</summary>
public sealed class HiScoreTable
{
    public const int Max = 10;
    public readonly List<HiScore> Entries = new();
    readonly string _path;

    public HiScoreTable()
    {
        string dir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(dir)) dir = AppContext.BaseDirectory;
        _path = Path.Combine(dir, "ShibaJintori", "hiscores.txt");
        Load();
    }

    public int Top => Entries.Count > 0 ? Entries[0].Score : 0;

    void Load()
    {
        try
        {
            if (File.Exists(_path))
                foreach (var line in File.ReadAllLines(_path))
                {
                    var p = line.Split('\t');
                    if (p.Length >= 3 && int.TryParse(p[1], out int score) && int.TryParse(p[2], out int stage))
                        Entries.Add(new HiScore(p[0].PadRight(3)[..3], score, stage));
                }
        }
        catch (Exception e) { Console.Error.WriteLine("hiscore load failed: " + e.Message); }

        string[] names = ["SHB", "KRO", "SRO", "CRG", "CHW", "SLT", "HSK", "PUG", "DAL", "BGL"];
        for (int i = Entries.Count; i < Max; i++) Entries.Add(new HiScore(names[i], (Max - i) * 1000, 1));
        Sort();
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

    void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var lines = new List<string>();
            foreach (var e in Entries) lines.Add($"{e.Name}\t{e.Score}\t{e.Stage}");
            File.WriteAllLines(_path, lines);
        }
        catch (Exception e) { Console.Error.WriteLine("hiscore save failed: " + e.Message); }
    }
}
