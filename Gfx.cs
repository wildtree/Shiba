using SDL3;

namespace ShibaJintori;

public readonly record struct Sprite(IntPtr Tex, int W, int H);

/// <summary>
/// SDL3 の描画まわりをまとめた薄いラッパー (PC版のみ)。
/// Android版では同じ使い方ができる別の Gfx (android/GfxAndroid.cs) に置き換わる。
/// </summary>
public static class Gfx
{
    public const int W = 640, H = 400;
    public static IntPtr Window, Renderer;
    static bool _fullscreen;

    /// <summary>今フルスクリーンかどうか。操作説明の文言を切り替えるのに使う</summary>
    public static bool IsFullscreen => _fullscreen;

    public static bool Init()
    {
        if (!SDL.CreateWindowAndRenderer("Shiba Jintori", W * 2, H * 2, SDL.WindowFlags.Resizable, out Window, out Renderer))
            return false;
        SDL.SetWindowMinimumSize(Window, W, H);
        // 640x400 の論理解像度。ウィンドウを伸縮しても縦横比は維持(余白は黒帯)
        SDL.SetRenderLogicalPresentation(Renderer, W, H, SDL.RendererLogicalPresentation.Letterbox);
        SDL.SetRenderVSync(Renderer, 1);
        SDL.SetRenderDrawBlendMode(Renderer, SDL.BlendMode.Blend);
        return true;
    }

    /// <summary>
    /// ウィンドウのアイコン(タイトルバーやタスクバーに出る絵)を柴犬のドット絵から作って設定する。
    /// packaging/icons のアイコンファイルと同じ絵柄。
    /// </summary>
    public static void SetWindowIcon()
    {
        const int S = 16, K = 4, N = S * K;
        string[] dog = [.. Rows(SpriteData.FrontHeadPointy), .. Rows(SpriteData.FrontBodyStand)];
        var pal = Breed.All[0].BuildPalette();
        var px = new byte[N * N * 4];
        for (int y = 0; y < N; y++)
            for (int x = 0; x < N; x++)
            {
                int sx = x / K, sy = y / K;
                bool corner = (sx == 0 || sx == S - 1) && (sy == 0 || sy == S - 1);
                bool border = sx == 0 || sx == S - 1 || sy == 0 || sy == S - 1
                              || ((sx == 1 || sx == S - 2) && (sy == 1 || sy == S - 2));
                uint rgb;
                if (!pal.TryGetValue(dog[sy][sx], out rgb))
                {
                    if (corner) continue;               // 角は透明
                    rgb = border ? 0x3A782Cu : 0x5AA843u; // 草色の角丸の背景
                }
                int i = (y * N + x) * 4;
                px[i] = (byte)(rgb >> 16); px[i + 1] = (byte)(rgb >> 8); px[i + 2] = (byte)rgb; px[i + 3] = 255;
            }

        var handle = System.Runtime.InteropServices.GCHandle.Alloc(px, System.Runtime.InteropServices.GCHandleType.Pinned);
        try
        {
            IntPtr surface = SDL.CreateSurfaceFrom(N, N, SDL.PixelFormat.ABGR8888, handle.AddrOfPinnedObject(), N * 4);
            if (surface == IntPtr.Zero) return;
            SDL.SetWindowIcon(Window, surface);
            SDL.DestroySurface(surface);
        }
        finally
        {
            handle.Free();
        }
    }

    public static void ToggleFullscreen()
    {
        _fullscreen = !_fullscreen;
        SDL.SetWindowFullscreen(Window, _fullscreen);
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

    /// <summary>文字で描いたドット絵からテクスチャを作る。パレットにない文字は透明。</summary>
    public static Sprite MakeSprite(string[] rows, IReadOnlyDictionary<char, uint> palette)
    {
        int w = rows[0].Length, h = rows.Length;
        var px = new byte[w * h * 4];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w && x < rows[y].Length; x++)
            {
                if (!palette.TryGetValue(rows[y][x], out uint rgb)) continue;
                int i = (y * w + x) * 4;
                px[i] = (byte)(rgb >> 16); px[i + 1] = (byte)(rgb >> 8); px[i + 2] = (byte)rgb; px[i + 3] = 255;
            }
        IntPtr tex = SDL.CreateTexture(Renderer, SDL.PixelFormat.ABGR8888, SDL.TextureAccess.Static, w, h);
        SDL.UpdateTexture(tex, IntPtr.Zero, px, w * 4);
        SDL.SetTextureBlendMode(tex, SDL.BlendMode.Blend);
        SDL.SetTextureScaleMode(tex, SDL.ScaleMode.Nearest);
        return new Sprite(tex, w, h);
    }

    public static void Clear(uint rgb)
    {
        SDL.SetRenderDrawColor(Renderer, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb, 255);
        SDL.RenderClear(Renderer);
    }

    public static void Present() => SDL.RenderPresent(Renderer);

    public static void Draw(Sprite s, float x, float y, bool flip = false, int scale = 1)
    {
        var dst = new SDL.FRect { X = MathF.Floor(x), Y = MathF.Floor(y), W = s.W * scale, H = s.H * scale };
        if (flip) SDL.RenderTextureRotated(Renderer, s.Tex, IntPtr.Zero, dst, 0, IntPtr.Zero, SDL.FlipMode.Horizontal);
        else SDL.RenderTexture(Renderer, s.Tex, IntPtr.Zero, dst);
    }

    public static void Tint(Sprite s, uint rgb, byte alpha = 255)
    {
        SDL.SetTextureColorMod(s.Tex, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        SDL.SetTextureAlphaMod(s.Tex, alpha);
    }

    public static void Fill(float x, float y, float w, float h, uint rgb, byte a = 255)
    {
        SDL.SetRenderDrawColor(Renderer, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb, a);
        var r = new SDL.FRect { X = x, Y = y, W = w, H = h };
        SDL.RenderFillRect(Renderer, r);
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

    /// <summary>SDL内蔵の8x8フォントで文字を描く(英数字のみ)。</summary>
    public static void Text(string s, float x, float y, uint rgb = 0xFFFFFF, int scale = 1, bool shadow = true)
    {
        if (scale != 1) SDL.SetRenderScale(Renderer, scale, scale);
        if (shadow)
        {
            SDL.SetRenderDrawColor(Renderer, 0, 0, 0, 200);
            SDL.RenderDebugText(Renderer, x / scale + 1, y / scale + 1, s);
        }
        SDL.SetRenderDrawColor(Renderer, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb, 255);
        SDL.RenderDebugText(Renderer, x / scale, y / scale, s);
        if (scale != 1) SDL.SetRenderScale(Renderer, 1, 1);
    }

    public static void TextCenter(string s, float cx, float y, uint rgb = 0xFFFFFF, int scale = 1) =>
        Text(s, MathF.Floor(cx - s.Length * 4 * scale), y, rgb, scale);

    public static void Clip(int x, int y, int w, int h)
    {
        var r = new SDL.Rect { X = x, Y = y, W = w, H = h };
        SDL.SetRenderClipRect(Renderer, r);
    }

    public static void Unclip() => SDL.SetRenderClipRect(Renderer, IntPtr.Zero);

    public static uint Shade(uint rgb, float f)
    {
        uint r = (uint)Math.Clamp(((rgb >> 16) & 255) * f, 0, 255);
        uint g = (uint)Math.Clamp(((rgb >> 8) & 255) * f, 0, 255);
        uint b = (uint)Math.Clamp((rgb & 255) * f, 0, 255);
        return r << 16 | g << 8 | b;
    }
}
