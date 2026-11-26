using Android.Graphics;

namespace ShibaJintori;

/// <summary>スプライト1枚の中身。色かけ(Tint)は PC版の SDL と同じく絵のほうに覚えさせる。</summary>
public sealed class SpriteTex
{
    public Bitmap Bmp = null!;
    public int W, H;
    public uint TintColor = 0xFFFFFF;
    public byte Alpha = 255;
}

public readonly record struct Sprite(SpriteTex Tex, int W, int H);

/// <summary>
/// Android版の描画。PC版の Gfx (SDL3) と同じ使い方ができるように作ってあるので、
/// 画面を描くコード (App.cs / Art.cs / Achievements.cs) は PC版と同じものが動く。
/// 中身は 480x400 などの小さなビットマップにドット単位で描き、
/// 最後に画面いっぱいへ拡大して出す(ドットのにじまないレトロな見た目になる)。
/// </summary>
public static class Gfx
{
    /// <summary>タイトルなどメニュー画面の論理解像度 (PC版と同じ)。</summary>
    public const int W = 640, H = 400;

    /// <summary>Android は常に全画面。PC版と同じ App.cs を通すために用意している</summary>
    public static bool IsFullscreen => true;

    static Canvas? _c;
    static int _clipDepth;

    static readonly Paint _fill = new() { AntiAlias = false, Dither = false };
    static readonly Paint _blit = new() { AntiAlias = false, FilterBitmap = false, Dither = false };
    static readonly Paint _label = new() { AntiAlias = false, FilterBitmap = false, Dither = false };
    static readonly RectF _dst = new();
    static readonly Rect _src = new();
    static readonly Dictionary<uint, ColorFilter> _filters = new();
    static Bitmap? _font;

    /// <summary>これから描き込む先を決める。null で描画を止める。</summary>
    public static void Target(Canvas? c)
    {
        _c = c;
        _clipDepth = 0;
    }

    static Color Col(uint rgb, int a) =>
        Color.Argb(a, (int)((rgb >> 16) & 255), (int)((rgb >> 8) & 255), (int)(rgb & 255));

    static ColorFilter? FilterFor(uint rgb)
    {
        if (rgb == 0xFFFFFF) return null;
        if (!_filters.TryGetValue(rgb, out var f))
            _filters[rgb] = f = new PorterDuffColorFilter(Col(rgb, 255), PorterDuff.Mode.Multiply!);
        return f;
    }

    public static string[] Rows(string art)
    {
        var list = new List<string>();
        foreach (var line in art.Split('\n'))
        {
            var t = line.Trim();
            if (t.Length > 0) list.Add(t);
        }
        return list.ToArray();
    }

    /// <summary>文字で描いたドット絵からビットマップを作る。パレットにない文字は透明。</summary>
    public static Sprite MakeSprite(string[] rows, IReadOnlyDictionary<char, uint> palette)
    {
        int w = rows[0].Length, h = rows.Length;
        var px = new int[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w && x < rows[y].Length; x++)
            {
                if (!palette.TryGetValue(rows[y][x], out uint rgb)) continue;
                px[y * w + x] = unchecked((int)(0xFF000000u | rgb));
            }
        var bmp = Bitmap.CreateBitmap(px, w, h, Bitmap.Config.Argb8888!)!;
        return new Sprite(new SpriteTex { Bmp = bmp, W = w, H = h }, w, h);
    }

    public static void Clear(uint rgb) => _c?.DrawColor(Col(rgb, 255), PorterDuff.Mode.Src!);

    /// <summary>PC版との互換のためにあるだけ (Android版は GameView が画面に出す)。</summary>
    public static void Present() { }

    public static void Draw(Sprite s, float x, float y, bool flip = false, int scale = 1)
    {
        if (_c == null || s.Tex == null) return;
        var t = s.Tex;
        _blit.Alpha = t.Alpha;
        _blit.SetColorFilter(FilterFor(t.TintColor));
        float px = MathF.Floor(x), py = MathF.Floor(y), w = s.W * scale, h = s.H * scale;
        if (flip)
        {
            _c.Save();
            _c.Scale(-1f, 1f, px + w / 2f, py + h / 2f);
        }
        _dst.Set(px, py, px + w, py + h);
        _c.DrawBitmap(t.Bmp, null, _dst, _blit);
        if (flip) _c.Restore();
    }

    public static void Tint(Sprite s, uint rgb, byte alpha = 255)
    {
        if (s.Tex == null) return;
        s.Tex.TintColor = rgb;
        s.Tex.Alpha = alpha;
    }

    public static void Fill(float x, float y, float w, float h, uint rgb, byte a = 255)
    {
        if (_c == null || w <= 0 || h <= 0 || a == 0) return;
        _fill.Color = Col(rgb, a);
        _c.DrawRect(x, y, x + w, y + h, _fill);
    }

    public static void Frame(float x, float y, float w, float h, uint rgb)
    {
        Fill(x, y, w, 1, rgb); Fill(x, y + h - 1, w, 1, rgb);
        Fill(x, y, 1, h, rgb); Fill(x + w - 1, y, 1, h, rgb);
    }

    /// <summary>動く点線。</summary>
    public static void Dotted(float x1, float y1, float x2, float y2, uint rgb, float phase, byte a = 255)
    {
        float dx = x2 - x1, dy = y2 - y1;
        float len = MathF.Sqrt(dx * dx + dy * dy);
        if (len < 1) return;
        for (float t = phase % 6f; t < len; t += 6f)
            Fill(MathF.Floor(x1 + dx * t / len) - 1, MathF.Floor(y1 + dy * t / len) - 1, 2, 2, rgb, a);
    }

    /// <summary>8x8 のドット文字 (PC版の SDL 内蔵フォントと同じ絵柄)。英数字のみ。</summary>
    public static void Text(string s, float x, float y, uint rgb = 0xFFFFFF, int scale = 1, bool shadow = true)
    {
        if (_c == null || s.Length == 0) return;
        // PC版は文字の影を「拡大率ぶん」ずらして描いているので、そこも合わせる
        if (shadow) Glyphs(s, x + scale, y + scale, 0x000000, 200, scale);
        Glyphs(s, x, y, rgb, 255, scale);
    }

    static void Glyphs(string s, float x, float y, uint rgb, byte a, int scale)
    {
        _font ??= BuildFont();
        _blit.Alpha = a;
        _blit.SetColorFilter(FilterFor(rgb));
        int cell = 8 * scale;
        float px = MathF.Floor(x), py = MathF.Floor(y);
        for (int i = 0; i < s.Length; i++)
        {
            char ch = s[i];
            if (ch == ' ') continue;
            int gi = ch - FontData.First;
            if (gi < 0 || gi >= FontData.Count) gi = '?' - FontData.First;
            int gx = gi % 16 * 8, gy = gi / 16 * 8;
            _src.Set(gx, gy, gx + 8, gy + 8);
            _dst.Set(px + i * cell, py, px + i * cell + cell, py + cell);
            _c!.DrawBitmap(_font, _src, _dst, _blit);
        }
    }

    /// <summary>フォントの絵を1枚のビットマップ(16文字 x 6行)にまとめておく。</summary>
    static Bitmap BuildFont()
    {
        const int cols = 16;
        int rows = FontData.Count / cols, w = cols * FontData.Size, h = rows * FontData.Size;
        var px = new int[w * h];
        for (int i = 0; i < FontData.Count; i++)
        {
            int ox = i % cols * FontData.Size, oy = i / cols * FontData.Size;
            for (int y = 0; y < FontData.Size; y++)
            {
                int bits = FontData.Glyphs[i * FontData.Size + y];
                for (int x = 0; x < FontData.Size; x++)
                    if ((bits & (0x80 >> x)) != 0) px[(oy + y) * w + ox + x] = unchecked((int)0xFFFFFFFF);
            }
        }
        return Bitmap.CreateBitmap(px, w, h, Bitmap.Config.Argb8888!)!;
    }

    /// <summary>
    /// ビットマップを経由せず、画面に直接ドット文字を描く (操作パッドのラベル用)。
    /// 1文字の大きさを好きな実数で指定できる。
    /// </summary>
    public static void TextOn(Canvas c, string s, float x, float y, float cell, uint rgb, byte a = 255)
    {
        _font ??= BuildFont();
        _label.Alpha = a;
        _label.SetColorFilter(FilterFor(rgb));
        for (int i = 0; i < s.Length; i++)
        {
            char ch = s[i];
            if (ch == ' ') continue;
            int gi = ch - FontData.First;
            if (gi < 0 || gi >= FontData.Count) gi = '?' - FontData.First;
            int gx = gi % 16 * 8, gy = gi / 16 * 8;
            _src.Set(gx, gy, gx + 8, gy + 8);
            _dst.Set(x + i * cell, y, x + i * cell + cell, y + cell);
            c.DrawBitmap(_font, _src, _dst, _label);
        }
    }

    /// <summary>TextOn で描いたときの横幅。</summary>
    public static float TextWidth(string s, float cell) => s.Length * cell;

    public static void TextCenter(string s, float cx, float y, uint rgb = 0xFFFFFF, int scale = 1) =>
        Text(s, MathF.Floor(cx - s.Length * 4 * scale), y, rgb, scale);

    public static void Clip(int x, int y, int w, int h)
    {
        if (_c == null) return;
        _c.Save();
        _clipDepth++;
        _c.ClipRect(x, y, x + w, y + h);
    }

    public static void Unclip()
    {
        if (_c == null || _clipDepth <= 0) return;
        _clipDepth--;
        _c.Restore();
    }

    public static uint Shade(uint rgb, float f)
    {
        uint r = (uint)Math.Clamp(((rgb >> 16) & 255) * f, 0, 255);
        uint g = (uint)Math.Clamp(((rgb >> 8) & 255) * f, 0, 255);
        uint b = (uint)Math.Clamp((rgb & 255) * f, 0, 255);
        return r << 16 | g << 8 | b;
    }
}
