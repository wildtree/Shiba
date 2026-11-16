using SDL3;

namespace ShibaJintori;

public readonly record struct Sprite(IntPtr Tex, int W, int H);

/// <summary>SDL3 の描画まわりをまとめた薄いラッパー。SDL の呼び出しはこのファイルと Audio.cs / App.cs だけ。</summary>
public static class Gfx
{
    public const int W = 640, H = 400;
    public static IntPtr Window, Renderer;
    static bool _fullscreen;

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

/// <summary>全スプライト。起動時に SpriteData から生成する。</summary>
public static class Art
{
    /// <summary>
    /// [犬種][0:正面 1:正面歩き 2:後ろ 3:後ろ歩き 4:右向き 5:右向き歩き
    ///        6:おしっこ(電柱が右。左は反転) 7:おしっこ(電柱が上) 8:おしっこ(電柱が下)]
    /// </summary>
    public static Sprite[][] Dogs = [];
    public static Sprite Pole, PeeMark, PoleBand, Grass0, Grass1, RoadTop, RoadBottom, Paw;
    /// <summary>[0:骨 1:巻物]</summary>
    public static Sprite[] Items = [];
    public static Sprite[] Cars = [];

    public static void Load()
    {
        static string[] Join(string a, string b) => [.. Gfx.Rows(a), .. Gfx.Rows(b)];

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
                Gfx.MakeSprite(Join(fh, SpriteData.FrontBodyPee), pal),
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

/// <summary>キーボード入力。</summary>
public static class Input
{
    static readonly HashSet<SDL.Scancode> _down = new();
    static readonly List<SDL.Scancode> _pressed = new();
    static readonly List<Dir> _dirs = new();

    public static IReadOnlyList<SDL.Scancode> PressedKeys => _pressed;
    public static bool AnyPressed => _pressed.Count > 0;

    static Dir? ToDir(SDL.Scancode s) => s switch
    {
        SDL.Scancode.Left or SDL.Scancode.A => Dir.Left,
        SDL.Scancode.Right or SDL.Scancode.D => Dir.Right,
        SDL.Scancode.Up or SDL.Scancode.W => Dir.Up,
        SDL.Scancode.Down or SDL.Scancode.S => Dir.Down,
        _ => null,
    };

    public static void KeyDown(SDL.Scancode s)
    {
        _down.Add(s);
        _pressed.Add(s);
        if (ToDir(s) is Dir d) { _dirs.Remove(d); _dirs.Add(d); }
    }

    public static void KeyUp(SDL.Scancode s)
    {
        _down.Remove(s);
        if (ToDir(s) is Dir d)
        {
            // 矢印キーとWASDの両方を押している場合に備えて、まだ押されているか確かめる
            bool still = false;
            foreach (var k in _down) if (ToDir(k) == d) still = true;
            if (!still) _dirs.Remove(d);
        }
    }

    public static void Reset()
    {
        _down.Clear(); _dirs.Clear();
        Array.Clear(_padDpad); Array.Clear(_padStick); Array.Clear(_padDir);
        _stickX = _stickY = 0;
    }

    // ---------------- ゲームパッド ----------------
    // 方向(Dパッド/左スティック)は矢印キー、A/B/X/Y はスペース、START は Enter、BACK は Esc
    // を押したのと同じ扱いにする。こうしておくと画面側はキーボードだけ見ればよい。

    static readonly SDL.Scancode[] DirKey = [SDL.Scancode.Down, SDL.Scancode.Left, SDL.Scancode.Right, SDL.Scancode.Up];
    static readonly bool[] _padDpad = new bool[4], _padStick = new bool[4], _padDir = new bool[4];
    static int _stickX, _stickY;
    static bool _padPause;

    /// <summary>ゲームパッドの START が押された(ポーズ用)。</summary>
    public static bool PadPause => _padPause;

    static void SyncPadDirs()
    {
        for (int i = 0; i < 4; i++)
        {
            bool now = _padDpad[i] || _padStick[i];
            if (now == _padDir[i]) continue;
            _padDir[i] = now;
            if (now) KeyDown(DirKey[i]); else KeyUp(DirKey[i]);
        }
    }

    static void PadKey(SDL.Scancode s, bool down)
    {
        if (down) KeyDown(s); else KeyUp(s);
    }

    public static void PadButton(byte button, bool down)
    {
        switch ((SDL.GamepadButton)button)
        {
            case SDL.GamepadButton.DPadDown: _padDpad[(int)Dir.Down] = down; SyncPadDirs(); break;
            case SDL.GamepadButton.DPadLeft: _padDpad[(int)Dir.Left] = down; SyncPadDirs(); break;
            case SDL.GamepadButton.DPadRight: _padDpad[(int)Dir.Right] = down; SyncPadDirs(); break;
            case SDL.GamepadButton.DPadUp: _padDpad[(int)Dir.Up] = down; SyncPadDirs(); break;
            case SDL.GamepadButton.South:
            case SDL.GamepadButton.East:
            case SDL.GamepadButton.West:
            case SDL.GamepadButton.North:
                PadKey(SDL.Scancode.Space, down); break;
            case SDL.GamepadButton.Start:
                PadKey(SDL.Scancode.Return, down);
                if (down) _padPause = true;
                break;
            case SDL.GamepadButton.Back:
                PadKey(SDL.Scancode.Escape, down); break;
        }
    }

    public static void PadAxis(byte axis, short value)
    {
        if ((SDL.GamepadAxis)axis == SDL.GamepadAxis.LeftX) _stickX = value;
        else if ((SDL.GamepadAxis)axis == SDL.GamepadAxis.LeftY) _stickY = value;
        else return;

        // 倒れている量が大きい軸だけを採用する(斜め入力で向きがばたつかないように)。
        // 入るしきい値より戻るしきい値を低くして、境目での細かいオン/オフを防ぐ
        bool active = _padStick[0] || _padStick[1] || _padStick[2] || _padStick[3];
        int threshold = active ? 10000 : 16000;
        int ax = Math.Abs(_stickX), ay = Math.Abs(_stickY);
        int dir = -1;
        if (Math.Max(ax, ay) >= threshold)
        {
            bool horizontal = ax > ay;
            // 今の向きの軸を少し優遇して、ほぼ45度のときに切り替わり続けないようにする
            if (_padStick[(int)Dir.Left] || _padStick[(int)Dir.Right]) horizontal = ax * 5 > ay * 4;
            else if (_padStick[(int)Dir.Up] || _padStick[(int)Dir.Down]) horizontal = ax * 4 > ay * 5;
            dir = horizontal ? (int)(_stickX < 0 ? Dir.Left : Dir.Right) : (int)(_stickY < 0 ? Dir.Up : Dir.Down);
        }
        for (int i = 0; i < 4; i++) _padStick[i] = i == dir;
        SyncPadDirs();
    }
    public static void EndFrame() { _pressed.Clear(); _padPause = false; }

    public static bool Pressed(SDL.Scancode s) => _pressed.Contains(s);

    /// <summary>最後に押された方向キー。</summary>
    public static Dir? Held => _dirs.Count > 0 ? _dirs[^1] : null;

    public static Dir? PressedDir
    {
        get
        {
            foreach (var s in _pressed) if (ToDir(s) is Dir d) return d;
            return null;
        }
    }

    public static bool Action => Pressed(SDL.Scancode.Space) || Pressed(SDL.Scancode.Z) || Pressed(SDL.Scancode.X);
    public static bool Confirm => Action || Pressed(SDL.Scancode.Return) || Pressed(SDL.Scancode.KpEnter);
    public static bool Back => Pressed(SDL.Scancode.Escape);
}
