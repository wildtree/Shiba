using System.Text;
using System.Text.Json;

namespace ShibaJintori;

/// <summary>
/// セーブデータ (ハイスコア・実績) の保存場所と、JSON の読み書きの共通処理。
/// 保存場所: Windows は %APPDATA%\ShibaJintori、Linux は ~/.config/ShibaJintori
/// </summary>
public static class SaveData
{
    public static string Folder { get; } = MakeFolder();

    static string MakeFolder()
    {
        string dir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(dir)) dir = AppContext.BaseDirectory;
        return Path.Combine(dir, "ShibaJintori");
    }

    public static string PathOf(string fileName) => Path.Combine(Folder, fileName);

    /// <summary>
    /// JSON を書き出す。いったん .tmp に書いてから置き換えるので、
    /// 書き込み中に落ちても元のファイルは壊れない。成功したら true。
    /// </summary>
    public static bool WriteJson(string path, Action<Utf8JsonWriter> write)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            using var ms = new MemoryStream();
            using (var w = new Utf8JsonWriter(ms, new JsonWriterOptions { Indented = true }))
            {
                write(w);
            }
            string tmp = path + ".tmp";
            File.WriteAllBytes(tmp, ms.ToArray());
            File.Move(tmp, path, overwrite: true);
            return true;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"save failed ({Path.GetFileName(path)}): {e.Message}");
            return false;
        }
    }

    /// <summary>JSON を読む。ファイルがないか壊れていれば null。</summary>
    public static JsonDocument? ReadJson(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            return JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"load failed ({Path.GetFileName(path)}): {e.Message}");
            return null;
        }
    }

    /// <summary>JSON に移し終えた古い txt を消す。</summary>
    public static void DeleteOld(string path)
    {
        try { File.Delete(path); }
        catch (Exception e) { Console.Error.WriteLine($"could not delete {Path.GetFileName(path)}: {e.Message}"); }
    }

    public static string GetString(JsonElement e, string name, string fallback) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() ?? fallback : fallback;

    public static int GetInt(JsonElement e, string name, int fallback) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
        && v.TryGetInt32(out int n) ? n : fallback;
}
