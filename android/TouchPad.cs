using Android.Graphics;
using SDL3;
using Path = Android.Graphics.Path;   // System.IO.Path と名前がぶつかるため

namespace ShibaJintori;

/// <summary>
/// ステータス領域に重ねる半透明の操作パッド。
/// 左に十字キー、右におしっこ(トリガー)とギブアップ、中央に SELECT と START、左上に音の切り替え。
/// 動かない部分 (枠や光り) は一度だけ1枚の絵に描きためておき、毎フレームは
/// その絵と「押されているボタンの光り」だけを描く (そのほうが軽い)。
/// 押されたボタンは、PC版のゲームパッドと同じ道 (Input.PadButton) に流し込む。
/// </summary>
public sealed class TouchPad
{
    public enum Btn { None = 0, Up, Down, Left, Right, Trigger, Start, Select, GiveUp, Sound }
    const int BtnCount = 10;

    // 色 (ネオン風)
    const uint Cyan = 0x4FD2FF, Orange = 0xFFA040, Red = 0xFF5A5A, Gray = 0xA8B4D8;

    readonly RectF _area = new();
    float _q;                                   // 設計の基準寸法 (画面幅、または入る高さから決める)
    float _dcx, _dcy, _dsize, _dthick;          // 十字キー
    float _tcx, _tcy, _trad;                    // トリガー
    readonly RectF _start = new(), _select = new(), _giveUp = new(), _sound = new();
    readonly RectF[] _arms = [new(), new(), new(), new()];   // Dir の順 (Down, Left, Right, Up)
    static readonly Btn[] DirBtn = [Btn.Down, Btn.Left, Btn.Right, Btn.Up];

    Bitmap? _art;
    readonly Dictionary<int, Btn> _touch = new();
    readonly bool[] _state = new bool[BtnCount];
    float _armT;        // ギブアップの確認待ち (秒)
    float _flashT;      // BGM を切り替えた直後の表示

    /// <summary>操作パッドを置く場所を決める (画面の大きさが変わったときに呼ぶ)。</summary>
    public void Layout(RectF area)
    {
        _area.Set(area);
        float w = area.Width(), h = area.Height();
        // 高さが足りない端末では、入る大きさまで縮める
        _q = MathF.Min(w, h / 0.64f);
        float left = area.Left + (w - _q) / 2f;
        float bottom = area.Bottom - 0.04f * _q;
        float top = bottom - 0.60f * _q;

        _dsize = 0.38f * _q;
        _dthick = _dsize * 0.40f;
        _dcx = left + 0.245f * _q;
        _dcy = bottom - 0.21f * _q;
        float half = _dsize / 2f, t2 = _dthick / 2f;
        _arms[(int)Dir.Up].Set(_dcx - t2, _dcy - half, _dcx + t2, _dcy - t2);
        _arms[(int)Dir.Down].Set(_dcx - t2, _dcy + t2, _dcx + t2, _dcy + half);
        _arms[(int)Dir.Left].Set(_dcx - half, _dcy - t2, _dcx - t2, _dcy + t2);
        _arms[(int)Dir.Right].Set(_dcx + t2, _dcy - t2, _dcx + half, _dcy + t2);

        _trad = 0.125f * _q;
        _tcx = left + 0.775f * _q;
        _tcy = bottom - 0.225f * _q;

        float pw = 0.185f * _q, ph = 0.082f * _q, mid = left + 0.53f * _q;
        _start.Set(mid - pw / 2, bottom - 0.40f * _q, mid + pw / 2, bottom - 0.40f * _q + ph);
        _select.Set(mid - pw / 2, bottom - 0.22f * _q, mid + pw / 2, bottom - 0.22f * _q + ph);

        float gw = 0.30f * _q, gh = 0.095f * _q, gcx = left + 0.78f * _q;
        _giveUp.Set(gcx - gw / 2, top, gcx + gw / 2, top + gh);
        float bw = 0.23f * _q;
        _sound.Set(left + 0.03f * _q, top, left + 0.03f * _q + bw, top + gh);

        _art?.Dispose();
        _art = null;
    }

    /// <summary>パッドのいちばん上 (この上はステータスの表示に使える)。</summary>
    public float ContentTop => _giveUp.Top;

    public void Update(float dt)
    {
        if (_armT > 0) _armT = MathF.Max(0, _armT - dt);
        if (_flashT > 0) _flashT = MathF.Max(0, _flashT - dt);
    }

    // ------------------------------------------------------------ 指の扱い

    /// <summary>指が触れた/動いた/離れた。描画と同じスレッドから呼ぶ。</summary>
    public void Pointer(int id, float x, float y, bool down, App app)
    {
        if (!down) _touch.Remove(id);
        else
        {
            var hit = HitTest(x, y);
            if (hit == Btn.None) _touch.Remove(id);
            else _touch[id] = hit;
        }
        Sync(app);
    }

    public void ReleaseAll(App app)
    {
        _touch.Clear();
        Sync(app);
    }

    Btn HitTest(float x, float y)
    {
        // 小さいボタンから先に調べる (十字キーとトリガーは判定を広めに取ってあるため)
        if (Near(_start, x, y)) return Btn.Start;
        if (Near(_select, x, y)) return Btn.Select;
        if (Near(_giveUp, x, y)) return Btn.GiveUp;
        if (Near(_sound, x, y)) return Btn.Sound;

        if (Dist(x, y, _tcx, _tcy) <= _trad * 1.25f) return Btn.Trigger;

        float half = _dsize / 2f * 1.12f;
        float dx = x - _dcx, dy = y - _dcy;
        if (MathF.Abs(dx) <= half && MathF.Abs(dy) <= half)
        {
            float dead = _dsize * 0.09f;
            if (MathF.Abs(dx) < dead && MathF.Abs(dy) < dead) return Btn.None;
            return MathF.Abs(dx) > MathF.Abs(dy) ? (dx < 0 ? Btn.Left : Btn.Right) : (dy < 0 ? Btn.Up : Btn.Down);
        }
        return Btn.None;
    }

    bool Near(RectF r, float x, float y)
    {
        float m = 0.012f * _q;
        return x >= r.Left - m && x <= r.Right + m && y >= r.Top - m && y <= r.Bottom + m;
    }

    static float Dist(float x, float y, float cx, float cy)
    {
        float dx = x - cx, dy = y - cy;
        return MathF.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>今押されているボタンを、ゲーム本体の入力へ反映する。</summary>
    void Sync(App app)
    {
        var want = new bool[BtnCount];
        foreach (var b in _touch.Values) want[(int)b] = true;
        for (int i = 1; i < BtnCount; i++)
        {
            if (want[i] == _state[i]) continue;
            _state[i] = want[i];
            Apply((Btn)i, want[i], app);
        }
    }

    void Apply(Btn b, bool down, App app)
    {
        // 押した瞬間だけ手ごたえを返す (十字キーは軽く、ボタンははっきり)
        if (down)
        {
            if (b is Btn.Up or Btn.Down or Btn.Left or Btn.Right) Haptics.Tick();
            else Haptics.Click();
        }
        switch (b)
        {
            case Btn.Up: Pad(SDL.GamepadButton.DPadUp, down); break;
            case Btn.Down: Pad(SDL.GamepadButton.DPadDown, down); break;
            case Btn.Left: Pad(SDL.GamepadButton.DPadLeft, down); break;
            case Btn.Right: Pad(SDL.GamepadButton.DPadRight, down); break;
            case Btn.Trigger: Pad(SDL.GamepadButton.South, down); break;
            case Btn.Start: Pad(SDL.GamepadButton.Start, down); break;
            case Btn.Select:
                // タイトル画面の SELECT はゲームを終わらせてしまうので、そこだけ無効にする
                if (!app.AtTitle) Pad(SDL.GamepadButton.Back, down);
                break;
            case Btn.GiveUp:
                if (!down) break;
                if (!app.CanGiveUp) { _armT = 0; break; }
                // 誤って押したときのために、2回押しで確定する
                if (_armT > 0) { _armT = 0; app.MobileGiveUp(); }
                else { _armT = 3f; Audio.Play(Sfx.Select); }
                break;
            case Btn.Sound:
                if (!down) break;
                Audio.CycleMode();          // BGMあり → 効果音だけ → マナーモード
                _flashT = 1.2f;
                Audio.Play(Sfx.Select);     // マナーモードでは鳴らない
                break;
        }
    }

    static void Pad(SDL.GamepadButton b, bool down) => Input.PadButton((byte)b, down);

    // ------------------------------------------------------------ 描画

    public void Draw(Canvas c, App app, float clock)
    {
        _art ??= BuildArt();
        c.DrawBitmap(_art, _area.Left, _area.Top, null);

        // 押されている十字キー
        for (int i = 0; i < 4; i++)
        {
            if (!_state[(int)DirBtn[i]]) continue;
            using var p = new Paint { AntiAlias = true };
            p.Color = Argb(Cyan, 150);
            c.DrawRoundRect(_arms[i], _dthick * 0.28f, _dthick * 0.28f, p);
            Arrow(c, (Dir)i, 0xFFFFFF, 255);
        }

        // 押されているトリガー
        if (_state[(int)Btn.Trigger])
        {
            using var p = new Paint { AntiAlias = true };
            p.Color = Argb(0xFFE0B0, 180);
            c.DrawCircle(_tcx, _tcy, _trad * 0.94f, p);
            Label(c, "PEE", _tcx, _tcy, _trad * 1.60f, _trad * 0.44f, 0x201008, 255);
        }

        // 押されている SELECT / START
        if (_state[(int)Btn.Start]) PressPill(c, _start, "START", Cyan);
        if (_state[(int)Btn.Select] && !app.AtTitle) PressPill(c, _select, "SELECT", Cyan);

        // ギブアップ: 1回目は確認待ち (点滅して SURE? になる)
        if (_armT > 0 && app.CanGiveUp)
        {
            bool on = ((int)(clock * 6) & 1) == 0;
            using var p = new Paint { AntiAlias = true };
            p.Color = Argb(Red, on ? (byte)210 : (byte)90);
            float rad = _giveUp.Height() / 2f;
            c.DrawRoundRect(_giveUp, rad, rad, p);
            Label(c, "SURE?", _giveUp.CenterX(), _giveUp.CenterY(), _giveUp.Width(), _giveUp.Height() * 0.44f, 0x201008, 255);
        }
        else if (_state[(int)Btn.GiveUp]) PressPill(c, _giveUp, "GIVE UP", Red);

        // 音の状態 (ここだけ毎フレーム書き換わる)。音の出口を開けなかった端末では NO SOUND と出す
        string label = !Audio.Ok ? "NO SOUND"
                     : Audio.Mode switch { SoundMode.All => "BGM ON", SoundMode.SfxOnly => "BGM OFF", _ => "SILENT" };
        uint col = !Audio.Ok ? 0xE07878u
                 : Audio.Mode switch { SoundMode.All => 0x80E0A0u, SoundMode.SfxOnly => 0xD8D070u, _ => 0x8894B8u };
        if (_state[(int)Btn.Sound] || _flashT > 0) PressPill(c, _sound, label, col);
        else Label(c, label, _sound.CenterX(), _sound.CenterY(), _sound.Width(), _sound.Height() * 0.40f, col, 235);
    }

    void PressPill(Canvas c, RectF r, string text, uint tint)
    {
        using var p = new Paint { AntiAlias = true };
        p.Color = Argb(tint, 170);
        float rad = r.Height() / 2f;
        c.DrawRoundRect(r, rad, rad, p);
        Label(c, text, r.CenterX(), r.CenterY(), r.Width(), r.Height() * 0.42f, 0x101620, 255);
    }

    /// <summary>中央そろえのドット文字 (枠の幅に収まるように字の大きさを決める)。</summary>
    static void Label(Canvas c, string s, float cx, float cy, float maxW, float cell, uint rgb, byte a)
    {
        if (s.Length == 0) return;
        float use = MathF.Min(cell, maxW * 0.84f / s.Length);
        Gfx.TextOn(c, s, cx - Gfx.TextWidth(s, use) / 2f, cy - use / 2f, use, rgb, a);
    }

    void Arrow(Canvas c, Dir d, uint rgb, byte a)
    {
        float s = _dsize * 0.085f, off = _dsize * 0.33f;
        float cx = _dcx + (d == Dir.Left ? -off : d == Dir.Right ? off : 0);
        float cy = _dcy + (d == Dir.Up ? -off : d == Dir.Down ? off : 0);
        using var path = new Path();
        switch (d)
        {
            case Dir.Up:
                path.MoveTo(cx, cy - s); path.LineTo(cx + s, cy + s * 0.8f); path.LineTo(cx - s, cy + s * 0.8f); break;
            case Dir.Down:
                path.MoveTo(cx, cy + s); path.LineTo(cx + s, cy - s * 0.8f); path.LineTo(cx - s, cy - s * 0.8f); break;
            case Dir.Left:
                path.MoveTo(cx - s, cy); path.LineTo(cx + s * 0.8f, cy + s); path.LineTo(cx + s * 0.8f, cy - s); break;
            default:
                path.MoveTo(cx + s, cy); path.LineTo(cx - s * 0.8f, cy + s); path.LineTo(cx - s * 0.8f, cy - s); break;
        }
        path.Close();
        using var p = new Paint { AntiAlias = true };
        p.Color = Argb(rgb, a);
        c.DrawPath(path, p);
    }

    /// <summary>動かない部分 (枠・光り・ラベル) を1枚の絵に描きためる。</summary>
    Bitmap BuildArt()
    {
        int w = Math.Max(1, (int)_area.Width()), h = Math.Max(1, (int)_area.Height());
        var bmp = Bitmap.CreateBitmap(w, h, Bitmap.Config.Argb8888!)!;
        using var c = new Canvas(bmp);
        c.Translate(-_area.Left, -_area.Top);   // 画面と同じ座標で描けるようにする

        // 下へ向かって少し暗くなる下地 (ステータスの文字は透けて見える)
        using (var bg = new Paint())
        {
            bg.SetShader(new LinearGradient(0, _area.Top, 0, _area.Bottom,
                Argb(0x0C1222, 0), Argb(0x05070E, 150), Shader.TileMode.Clamp!));
            c.DrawRect(_area, bg);
        }

        // 十字キー
        using (var plus = Plus(_dcx, _dcy, _dsize, _dthick, _dthick * 0.30f))
        {
            Glow(c, plus, Cyan, _dthick * 0.30f);
            Glass(c, plus, _dcy - _dsize / 2, _dcy + _dsize / 2, 0x2A4A6E, 0x101A2C, 150);
            Edge(c, plus, Cyan, _q * 0.004f, 200);
        }
        for (int i = 0; i < 4; i++) Arrow(c, (Dir)i, 0xDCEAFF, 220);

        // トリガー (おしっこ)
        using (var circle = new Path())
        {
            circle.AddCircle(_tcx, _tcy, _trad, Path.Direction.Cw!);
            Glow(c, circle, Orange, _trad * 0.22f);
            using (var p = new Paint { AntiAlias = true })
            {
                p.SetShader(new RadialGradient(_tcx - _trad * 0.3f, _tcy - _trad * 0.4f, _trad * 1.6f,
                    Argb(0xFFC070, 225), Argb(0xC4521C, 205), Shader.TileMode.Clamp!));
                c.DrawCircle(_tcx, _tcy, _trad, p);
            }
            Edge(c, circle, 0xFFE0B0, _q * 0.005f, 230);
            using (var p = new Paint { AntiAlias = true })
            {
                p.SetStyle(Paint.Style.Stroke);
                p.StrokeWidth = MathF.Max(1f, _q * 0.0025f);
                p.Color = Argb(0xFFFFFF, 60);
                c.DrawCircle(_tcx, _tcy, _trad * 0.84f, p);
            }
        }
        Label(c, "PEE", _tcx, _tcy, _trad * 1.60f, _trad * 0.44f, 0x3A1808, 255);

        // SELECT / START / GIVE UP / BGM
        Pill(c, _start, "START", Cyan);
        Pill(c, _select, "SELECT", Cyan);
        Pill(c, _giveUp, "GIVE UP", Red);
        Pill(c, _sound, "", Gray);   // 中の文字は状態によって変わるので Draw 側で描く

        return bmp;
    }

    void Pill(Canvas c, RectF r, string text, uint tint)
    {
        float rad = r.Height() / 2f;
        using var path = new Path();
        path.AddRoundRect(r, rad, rad, Path.Direction.Cw!);
        Glow(c, path, tint, r.Height() * 0.22f);
        Glass(c, path, r.Top, r.Bottom, 0x24304E, 0x0E1420, 160);
        Edge(c, path, tint, _q * 0.0035f, 190);
        Label(c, text, r.CenterX(), r.CenterY(), r.Width(), r.Height() * 0.42f, 0xE8F0FF, 240);
    }

    /// <summary>外側のぼんやりした光。</summary>
    static void Glow(Canvas c, Path path, uint rgb, float radius)
    {
        using var p = new Paint { AntiAlias = true };
        p.SetStyle(Paint.Style.Stroke);
        p.StrokeWidth = MathF.Max(1f, radius * 0.9f);
        p.Color = Argb(rgb, 70);
        p.SetMaskFilter(new BlurMaskFilter(MathF.Max(1f, radius), BlurMaskFilter.Blur.Normal!));
        c.DrawPath(path, p);
    }

    /// <summary>半透明のガラスっぽい中身 (上が明るい)。</summary>
    static void Glass(Canvas c, Path path, float top, float bottom, uint hi, uint lo, byte alpha)
    {
        byte lowAlpha = (byte)Math.Min(255, alpha + 40);
        using var p = new Paint { AntiAlias = true };
        p.SetShader(new LinearGradient(0, top, 0, bottom, Argb(hi, alpha), Argb(lo, lowAlpha), Shader.TileMode.Clamp!));
        c.DrawPath(path, p);
    }

    static void Edge(Canvas c, Path path, uint rgb, float width, byte alpha)
    {
        using var p = new Paint { AntiAlias = true };
        p.SetStyle(Paint.Style.Stroke);
        p.StrokeWidth = MathF.Max(1.5f, width);
        p.Color = Argb(rgb, alpha);
        c.DrawPath(path, p);
    }

    /// <summary>十字の形。</summary>
    static Path Plus(float cx, float cy, float size, float thick, float round)
    {
        float h = size / 2f, t = thick / 2f;
        var a = new Path();
        a.AddRoundRect(new RectF(cx - h, cy - t, cx + h, cy + t), round, round, Path.Direction.Cw!);
        using var b = new Path();
        b.AddRoundRect(new RectF(cx - t, cy - h, cx + t, cy + h), round, round, Path.Direction.Cw!);
        a.InvokeOp(b, Path.Op.Union!);   // 2つの角丸四角をひとつの十字の形にまとめる
        return a;
    }

    static Color Argb(uint rgb, byte a) =>
        Color.Argb(a, (int)((rgb >> 16) & 255), (int)((rgb >> 8) & 255), (int)(rgb & 255));
}
