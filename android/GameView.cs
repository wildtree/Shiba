using Android.Content;
using Android.Graphics;
using Android.Views;
using SDL3;

namespace ShibaJintori;

/// <summary>
/// ゲームの表示と操作をまとめた画面。画面の形に合わせて、次の3つの並べ方から選ぶ (Arrangement)。
///   縦  : 上にフィールド (横幅いっぱい)、下にステータスと半透明の操作パッド。スマホの縦向き
///   2段 : 上に PC版と同じ 640x400 の画面 (フィールド + 右のパネル)、下に操作パッド。広げた折りたたみ
///   3列 : 真ん中にフィールド (高さいっぱい)、左右に HUD と操作パッド。スマホやタブレットの横向き
/// どれになるかは機種ではなく画面の縦横の大きさだけで決めるので、分割画面などの半端な大きさでも並ぶ。
/// 描画は専用のスレッドで回し、小さなビットマップに描いてから画面へ拡大する。
/// </summary>
public sealed class GameView : SurfaceView, ISurfaceHolderCallback
{
    /// <summary>並べ方。</summary>
    enum Arrangement { Portrait, Rows, Columns }

    /// <summary>
    /// 操作パッドの基準寸法の上限 (dp)。スマホの縦画面の幅くらい。
    /// これより広い画面ではパッドを大きくせず、十字キーとおしっこを左右の端へ寄せる
    /// (タブレットで十字キーが巨大になったり、親指の届かない真ん中に寄ったりしないように)。
    /// </summary>
    const float PadMaxDp = 420f;

    /// <summary>縦の並びで、ステータスを最低でもフィールドの何倍の拡大率で出すか (小さく潰れないように)。</summary>
    const float PortraitStatusRatio = 0.75f;

    readonly App _app = new();
    readonly TouchPad _pad = new();
    readonly Action _onQuit;
    Arrangement _arr;
    volatile float _dp = 2.625f;   // 1dp が何ドットか (折りたたみを開くと変わることがある)

    Thread? _thread;
    volatile bool _run;
    volatile bool _sleep;          // アプリが裏に回っている間は描かない
    volatile bool _backPressed;
    bool _started;
    // Activity が作り直されると、古い画面の後片付けが新しい画面より後に来ることがある。
    // 音は静的な置き場所にあるので、「音を始めた画面」だけが止められるようにしておく
    static GameView? _audioOwner;
    volatile int _wantW, _wantH;   // 画面の大きさが変わったことの知らせ
    int _haveW, _haveH;
    float _clock;

    // 描画先 (ドット絵の論理サイズ)
    Bitmap? _field, _status, _menu, _hudL, _hudR;
    Canvas? _fieldC, _statusC, _menuC, _hudLC, _hudRC;
    // 画面のどこへ拡大するか
    readonly RectF _fieldDst = new(), _statusDst = new(), _menuDst = new(), _padArea = new();
    readonly RectF _sideL = new(), _sideR = new(), _hudLDst = new(), _hudRDst = new();
    readonly Paint _blit = new() { AntiAlias = false, FilterBitmap = false, Dither = false };
    readonly Paint _panelBg = new() { Color = Color.Argb(255, 0x1B, 0x20, 0x33) };

    readonly object _lock = new();
    readonly List<(int Id, float X, float Y, bool Down)> _events = new();
    bool _cancel;

    // 半開きの折り目 (テーブルトップ)。画面の座標で、ないときは -1。
    // UI スレッドから SetHinge で届き (_lock で守る)、描画スレッドが並べ直すときに _useHinge* へ写す
    int _hingeTop = -1, _hingeBottom = -1;
    bool _hingeDirty;
    int _useHingeTop = -1, _useHingeBottom = -1;

    public GameView(Context context, Action onQuit) : base(context)
    {
        _onQuit = onQuit;
        Holder?.AddCallback(this);
        Focusable = true;
    }

    // ------------------------------------------------------------ 画面の用意

    public void SurfaceCreated(ISurfaceHolder holder)
    {
        _run = true;
        _thread = new Thread(Loop) { IsBackground = true, Name = "shiba-render" };
        _thread.Start();
    }

    public void SurfaceChanged(ISurfaceHolder holder, Format format, int width, int height)
    {
        _dp = Resources?.DisplayMetrics?.Density ?? _dp;
        _wantW = width;
        _wantH = height;
    }

    public void SurfaceDestroyed(ISurfaceHolder holder)
    {
        _run = false;
        _thread?.Join(2000);
        _thread = null;
    }

    /// <summary>画面の大きさが決まった/変わったときに、何をどこへ置くかを決め直す。</summary>
    void Relayout(int vw, int vh)
    {
        bool reshaped = _haveW != 0;    // 最初の1回ではなく、回転・開閉・分割画面などで形が変わった
        _haveW = vw; _haveH = vh;

        // それぞれの並べ方で、フィールドをどこまで大きくできるかを比べて、いちばん大きくなるものにする
        float qMax = PadMaxDp * _dp;
        float qBand = MathF.Min(qMax, vw);            // 帯に置くパッドの基準寸法
        float qCol = MathF.Min(qMax, vh);             // 列に置くパッドの基準寸法 (列の高さに収まるように)
        float colW = 0.56f * qCol;                    // 列に要る幅 (いちばん幅を取るのは「音 + ギブアップ」の並び)
        // 縦: フィールドの下に、ステータス (フィールドの 3/4 以上の大きさ) と操作パッドが縦に積まれる
        float qPortrait = MathF.Min(qMax, vw);
        float sPortrait = MathF.Min(vw / (float)App.FieldPixW,
                                    (vh - 0.64f * qPortrait) / (App.FieldPixH + PortraitStatusRatio * App.StatusH));
        float sRows = MathF.Min(vw / (float)Gfx.W, (vh - 0.64f * qBand) / Gfx.H);
        float sColumns = MathF.Min((vw - 2 * colW) / App.FieldPixW, vh / (float)App.FieldPixH);

        var arr = Arrangement.Portrait;
        float best = sPortrait;
        // 縦と2段でフィールドの大きさがほぼ同じなら、2段にする。縦の並びが高さで頭打ちのときは
        // フィールドの左右が空いてしまうが、2段なら横幅いっぱいに収まり、PC版のパネルも出せる
        // (背の低い外側画面や、縦に持った正方形に近い画面)
        if (sRows >= best * 0.98f) { arr = Arrangement.Rows; best = sRows; }
        if (sColumns > best * 1.02f) { arr = Arrangement.Columns; best = sColumns; }

        // 半開きで机に置いている (横向きの折り目がある) ときは、折り目でちょうど上下に分ける。
        // 折り目が画面の端に寄りすぎている場合は、ふつうの並べ方のままにする
        int ht = _useHingeTop, hb = _useHingeBottom;
        bool tabletop = ht > vh * 0.2f && hb < vh * 0.8f && hb >= ht;

        if (tabletop) arr = LayoutTabletop(vw, vh, ht, hb, qMax);
        else
        {
            switch (arr)
            {
                case Arrangement.Rows: LayoutRows(vw, vh, MathF.Max(0.1f, sRows), qMax); break;
                case Arrangement.Columns: LayoutColumns(vw, vh, MathF.Max(0.1f, sColumns), qCol); break;
                default: LayoutPortrait(vw, vh, MathF.Max(0.1f, sPortrait), qMax); break;
            }
        }
        _arr = arr;

        if (_field == null) { _field = NewTarget(App.FieldPixW, App.FieldPixH); _fieldC = new Canvas(_field); }
        if (_status == null) { _status = NewTarget(App.StatusW, App.StatusH); _statusC = new Canvas(_status); }
        if (_menu == null) { _menu = NewTarget(Gfx.W, Gfx.H); _menuC = new Canvas(_menu); }
        if (_hudL == null) { _hudL = NewTarget(App.HudW, App.HudLH); _hudLC = new Canvas(_hudL); }
        if (_hudR == null) { _hudR = NewTarget(App.HudW, App.HudRH); _hudRC = new Canvas(_hudR); }

        if (reshaped)
        {
            // ボタンの位置が変わったので、押されたままのボタンを放す。
            // 持ち替えている間に犬がやられないように、遊んでいる最中ならポーズしておく
            _pad.ReleaseAll(_app);
            _app.MobilePause();
            Android.Util.Log.Info("ShibaJintori", $"layout: {(tabletop ? "Tabletop/" : "")}{arr} {vw}x{vh}"
                                                  + (tabletop ? $" hinge {ht}-{hb}" : ""));
        }
    }

    /// <summary>縦: 上にフィールド (横幅いっぱい)、下にステータスと、それに重なる操作パッド。</summary>
    void LayoutPortrait(int vw, int vh, float scale, float qMax)
    {
        // scale は、下にステータスと操作パッドの入る高さを残した大きさ (Relayout で計算済み)
        float fw = App.FieldPixW * scale, fh = App.FieldPixH * scale;
        _fieldDst.Set((vw - fw) / 2f, 0, (vw + fw) / 2f, fh);

        // ステータス領域 = フィールドの下の全部。操作パッドはこの範囲に重ねる
        _padArea.Set(0, fh, vw, vh);
        _pad.LayoutBand(_padArea, qMax);

        // ステータスの中身は横幅に合わせて拡大し、フィールドと操作パッドの間に置く
        float room = MathF.Max(App.StatusH, _pad.ContentTop - fh);
        float ss = MathF.Min(vw / (float)App.StatusW, room / App.StatusH);
        float sw = App.StatusW * ss, sh = App.StatusH * ss;
        float sy = fh + MathF.Max(0, (room - sh) / 2f);
        _statusDst.Set((vw - sw) / 2f, sy, (vw + sw) / 2f, sy + sh);

        // タイトルなどの画面 (640x400) は、フィールドと同じ場所 (操作パッドの上) に収める
        float menuH = MathF.Max(1f, _padArea.Top);
        float ms = MathF.Min(vw / (float)Gfx.W, menuH / Gfx.H);
        float mw = Gfx.W * ms, mh = Gfx.H * ms;
        _menuDst.Set((vw - mw) / 2f, (menuH - mh) / 2f, (vw + mw) / 2f, (menuH - mh) / 2f + mh);
    }

    /// <summary>
    /// 2段: 上に PC版とまったく同じ 640x400 の画面 (フィールド + 右のパネル)、下の帯に操作パッド。
    /// タイトルなどの画面も同じ場所に出る。
    /// </summary>
    void LayoutRows(int vw, int vh, float s, float qMax)
    {
        float w = Gfx.W * s, h = Gfx.H * s;
        _menuDst.Set((vw - w) / 2f, 0, (vw + w) / 2f, h);
        _padArea.Set(0, h, vw, vh);
        _pad.LayoutBand(_padArea, qMax);
    }

    /// <summary>
    /// 3列: 真ん中にフィールド (高さいっぱい)。左の列に十字キーと START / SELECT、
    /// 右の列におしっこと音・ギブアップを下に寄せて置き、それぞれの上に HUD を出す。
    /// 指はフィールドに一切かからない。
    /// </summary>
    void LayoutColumns(int vw, int vh, float s, float q)
    {
        float fw = App.FieldPixW * s, fh = App.FieldPixH * s;
        float fx = (vw - fw) / 2f, fy = (vh - fh) / 2f;
        _fieldDst.Set(fx, fy, fx + fw, fy + fh);
        _sideL.Set(0, 0, fx, vh);
        _sideR.Set(fx + fw, 0, vw, vh);
        _pad.LayoutColumns(_sideL, _sideR, q);

        // HUD は左右で同じ拡大率にそろえる (字の大きさが左右で違うと落ち着かない)
        float m = 0.03f * q;
        float hs = MathF.Min(MathF.Min((_sideL.Width() - 2 * m) / App.HudW, (_sideR.Width() - 2 * m) / App.HudW),
                             MathF.Min((_pad.LeftTop - 2 * m) / App.HudLH, (_pad.RightTop - 2 * m) / App.HudRH));
        hs = MathF.Max(0.5f, hs);
        float hw = App.HudW * hs;
        _hudLDst.Set(_sideL.CenterX() - hw / 2f, m, _sideL.CenterX() + hw / 2f, m + App.HudLH * hs);
        _hudRDst.Set(_sideR.CenterX() - hw / 2f, m, _sideR.CenterX() + hw / 2f, m + App.HudRH * hs);

        // タイトルなどの画面 (640x400) は、フィールドの場所 (左右のボタンの間) に収める
        float ms = MathF.Min(fw / (float)Gfx.W, vh / (float)Gfx.H);
        float mw = Gfx.W * ms, mh = Gfx.H * ms;
        _menuDst.Set(vw / 2f - mw / 2f, vh / 2f - mh / 2f, vw / 2f + mw / 2f, vh / 2f + mh / 2f);
    }

    /// <summary>
    /// テーブルトップ: 半開きで机に置いたとき。折り目 (top〜bottom) でちょうど上下に分け、
    /// 立っている上の面に画面、机に寝ている下の面に操作パッドを置く (携帯ゲーム機のような持ち方)。
    /// 上の面が横長なら PC版の画面 (フィールド + パネル)、縦長の端末 (縦に折る小さな折りたたみ) なら
    /// フィールドだけを上に出し、ステータスは下の面のパッドの上に出す。フィールドが大きくなるほうを選ぶ。
    /// 戻り値は、描くときに使う並べ方 (Rows と同じ描き方か、Portrait と同じ描き方か)。
    /// </summary>
    Arrangement LayoutTabletop(int vw, int vh, int top, int bottom, float qMax)
    {
        float upper = top;                                   // 上の面の高さ
        _padArea.Set(0, bottom, vw, vh);
        _pad.LayoutBand(_padArea, qMax);

        float sWide = MathF.Min(vw / (float)Gfx.W, upper / Gfx.H);
        float sTall = MathF.Min(vw / (float)App.FieldPixW, upper / App.FieldPixH);

        if (sTall <= sWide * 1.02f)
        {
            // 上の面に PC版の画面 (タイトルなども同じ場所)
            float w = Gfx.W * sWide, h = Gfx.H * sWide;
            _menuDst.Set((vw - w) / 2f, (upper - h) / 2f, (vw + w) / 2f, (upper + h) / 2f);
            return Arrangement.Rows;
        }

        // 上の面にフィールドだけ
        float fw = App.FieldPixW * sTall, fh = App.FieldPixH * sTall;
        _fieldDst.Set((vw - fw) / 2f, (upper - fh) / 2f, (vw + fw) / 2f, (upper + fh) / 2f);

        // タイトルなどの画面も上の面に
        float ms = MathF.Min(vw / (float)Gfx.W, upper / Gfx.H);
        float mw = Gfx.W * ms, mh = Gfx.H * ms;
        _menuDst.Set((vw - mw) / 2f, (upper - mh) / 2f, (vw + mw) / 2f, (upper + mh) / 2f);

        // ステータスは下の面の、折り目とパッドのあいだに
        float room = MathF.Max(1f, _pad.ContentTop - bottom);
        float ss = MathF.Min(vw / (float)App.StatusW, room / App.StatusH);
        float sw = App.StatusW * ss, sh = App.StatusH * ss;
        float sy = bottom + (room - sh) / 2f;
        _statusDst.Set((vw - sw) / 2f, sy, (vw + sw) / 2f, sy + sh);
        return Arrangement.Portrait;
    }

    static Bitmap NewTarget(int w, int h) => Bitmap.CreateBitmap(w, h, Bitmap.Config.Argb8888!)!;

    // ------------------------------------------------------------ 本体のループ

    void Loop()
    {
        // 画面が作り直されても絵と音の用意は一度だけ
        if (!_started)
        {
            _started = true;
            _audioOwner = this;
            _app.MobileStart();
        }
        long last = Java.Lang.JavaSystem.NanoTime();
        while (_run)
        {
            if (_sleep)
            {
                Thread.Sleep(60);
                last = Java.Lang.JavaSystem.NanoTime();
                continue;
            }
            bool hingeMoved;
            lock (_lock)
            {
                hingeMoved = _hingeDirty;
                _hingeDirty = false;
                _useHingeTop = _hingeTop;
                _useHingeBottom = _hingeBottom;
            }
            if (_wantW > 0 && (_wantW != _haveW || _wantH != _haveH || hingeMoved)) Relayout(_wantW, _wantH);
            if (_haveW == 0) { Thread.Sleep(16); continue; }

            long now = Java.Lang.JavaSystem.NanoTime();
            float dt = MathF.Min(0.05f, (now - last) / 1e9f);
            last = now;
            _clock += dt;

            DrainTouch();
            _pad.Update(dt);
            _app.MobileUpdate(dt);
            DrawFrame();
            _app.MobileEndFrame();

            if (!_app.Running) { _run = false; Post(_onQuit); break; }   // 終了は UI スレッドにお願いする

            // 60fps くらいに合わせる (使い切らないように少し休む)
            long spent = (Java.Lang.JavaSystem.NanoTime() - now) / 1_000_000;
            int rest = (int)(16 - spent);
            if (rest > 1) Thread.Sleep(rest);
        }
    }

    /// <summary>アプリを閉じるとき (Activity の OnDestroy から)。</summary>
    public void Shutdown()
    {
        _run = false;
        _thread?.Join(2000);
        _thread = null;
        // 新しい画面がもう音を鳴らしているなら、ここでは止めない
        if (_started && _audioOwner == this)
        {
            _audioOwner = null;
            _app.MobileStop();
        }
        _started = false;
    }

    void DrainTouch()
    {
        if (_backPressed)
        {
            _backPressed = false;
            // 戻る操作は SELECT と同じ扱い (タイトル画面では Activity 側で終了する)。
            // ただしプレイ中は、いきなりタイトルに帰らずポーズで止める。
            // 画面の端をうっかりなぞっただけで、遊んでいた記録が消えてしまうので
            if (_app.CanBackToTitle)
            {
                Input.PadButton((byte)SDL.GamepadButton.Back, true);
                Input.PadButton((byte)SDL.GamepadButton.Back, false);
            }
            else
            {
                _app.MobilePause();
            }
        }
        lock (_lock)
        {
            if (_cancel)
            {
                _cancel = false;
                _pad.ReleaseAll(_app);
            }
            foreach (var e in _events) _pad.Pointer(e.Id, e.X, e.Y, e.Down, _app);
            _events.Clear();

            foreach (var (kind, code, down) in _keys) ApplyKey(kind, code, down);
            _keys.Clear();
            if (_stickDirty)
            {
                _stickDirty = false;
                Input.PadAxis((byte)SDL.GamepadAxis.LeftX, _stickX);
                Input.PadAxis((byte)SDL.GamepadAxis.LeftY, _stickY);
                Input.JoyHat(_hat);
            }
        }
    }

    // ------------------------------------------------------------ キーボードとゲームパッド

    // Chromebook のキーボードや Bluetooth のコントローラでも遊べるように、PC版と同じ入口 (Input) に流す。
    // キーの割り当ても PC版と同じ (矢印/WASD・スペース/Z/X・Enter・P・R・Esc・M)。
    // 届くのは UI スレッドなので、タッチと同じく _lock の下にためて、描画スレッドが DrainTouch で流す
    enum KeyKind { Key, Button, Joy }
    readonly List<(KeyKind Kind, int Code, bool Down)> _keys = new();
    // スティックと十字キー (ハット) は細かく何度も届くので、最後の値だけ覚えておく
    short _stickX, _stickY;
    byte _hat;
    bool _stickDirty;

    /// <summary>キーやボタンが押された/離された。ゲームで使うものなら true。UI スレッドから呼ぶ。</summary>
    public bool HandleKey(KeyEvent e)
    {
        bool down = e.Action == KeyEventActions.Down;
        if (!down && e.Action != KeyEventActions.Up) return false;

        KeyKind kind;
        int code;
        if (PadButtonOf(e.KeyCode) is { } b) { kind = KeyKind.Button; code = (int)b; }
        else if (e.KeyCode >= Keycode.Button1 && e.KeyCode <= Keycode.Button16)
        {
            // ボタンの配置がわからない汎用のパッド。PC版の汎用 USB パッドと同じ割り当てにする
            kind = KeyKind.Joy; code = e.KeyCode - Keycode.Button1;
        }
        else if (ScancodeOf(e.KeyCode) is { } s) { kind = KeyKind.Key; code = (int)s; }
        else return false;   // 戻る・音量などは Android に任せる

        // 押しっぱなしのリピートは PC版と同じく無視する (押した瞬間だけ数える)
        if (down && e.RepeatCount > 0) return true;
        lock (_lock) _keys.Add((kind, code, down));
        return true;
    }

    /// <summary>スティックと十字キー (ハット) の動き。ゲームパッドのものなら true。UI スレッドから呼ぶ。</summary>
    public bool HandleMotion(MotionEvent e)
    {
        if ((e.Source & InputSourceType.Joystick) != InputSourceType.Joystick
            || e.ActionMasked != MotionEventActions.Move) return false;
        float x = e.GetAxisValue(Axis.X), y = e.GetAxisValue(Axis.Y);
        float hx = e.GetAxisValue(Axis.HatX), hy = e.GetAxisValue(Axis.HatY);
        // ハットは PC版 (SDL) と同じく 上=1 右=2 下=4 左=8
        byte hat = (byte)((hy < -0.5f ? 1 : 0) | (hx > 0.5f ? 2 : 0) | (hy > 0.5f ? 4 : 0) | (hx < -0.5f ? 8 : 0));
        lock (_lock)
        {
            _stickX = (short)Math.Clamp(x * 32767f, -32767f, 32767f);
            _stickY = (short)Math.Clamp(y * 32767f, -32767f, 32767f);
            _hat = hat;
            _stickDirty = true;
        }
        // true を返すと、Android がハットから十字キーのキーを作り直さない (二重に届かない)
        return true;
    }

    /// <summary>描画スレッドで、ためておいたキーを Input に流す。</summary>
    void ApplyKey(KeyKind kind, int code, bool down)
    {
        // Esc と BACK ボタンは SELECT と同じ扱い。プレイ中は、いきなりタイトルに帰らずポーズで止める。
        // (タイトル画面では PC版と同じくアプリを閉じる。端末の「戻る」と同じ)
        bool back = kind switch
        {
            KeyKind.Key => code == (int)SDL.Scancode.Escape,
            KeyKind.Button => code == (int)SDL.GamepadButton.Back,
            _ => code == 8,   // 汎用パッドの9番目のボタン (Input.JoyButton で BACK になる)
        };
        if (back && down && !_app.AtTitle && !_app.CanBackToTitle)
        {
            _app.MobilePause();
            return;
        }

        switch (kind)
        {
            case KeyKind.Key:
                var s = (SDL.Scancode)code;
                if (down) Input.KeyDown(s); else Input.KeyUp(s);
                // M で音の切り替え (PC版と同じ。BGM → 効果音だけ → 無音)
                if (down && s == SDL.Scancode.M) { Audio.CycleMode(); Audio.Play(Sfx.Select); }
                break;
            case KeyKind.Button:
                Input.PadButton((byte)code, down);
                break;
            case KeyKind.Joy:
                Input.JoyButton((byte)code, down);
                break;
        }
    }

    static SDL.GamepadButton? PadButtonOf(Keycode k) => k switch
    {
        Keycode.ButtonA => SDL.GamepadButton.South,
        Keycode.ButtonB => SDL.GamepadButton.East,
        Keycode.ButtonX => SDL.GamepadButton.West,
        Keycode.ButtonY => SDL.GamepadButton.North,
        Keycode.ButtonStart => SDL.GamepadButton.Start,
        Keycode.ButtonSelect => SDL.GamepadButton.Back,
        _ => null,
    };

    static SDL.Scancode? ScancodeOf(Keycode k)
    {
        if (k >= Keycode.A && k <= Keycode.Z) return SDL.Scancode.A + (k - Keycode.A);
        if (k >= Keycode.Num1 && k <= Keycode.Num9) return SDL.Scancode.Alpha1 + (k - Keycode.Num1);
        return k switch
        {
            Keycode.Num0 => SDL.Scancode.Alpha0,
            // 矢印キー (ゲームパッドの十字キーがキーとして届く機種もこれ)
            Keycode.DpadUp => SDL.Scancode.Up,
            Keycode.DpadDown => SDL.Scancode.Down,
            Keycode.DpadLeft => SDL.Scancode.Left,
            Keycode.DpadRight => SDL.Scancode.Right,
            Keycode.DpadCenter or Keycode.Enter => SDL.Scancode.Return,
            Keycode.NumpadEnter => SDL.Scancode.KpEnter,
            Keycode.Space => SDL.Scancode.Space,
            Keycode.Escape => SDL.Scancode.Escape,
            Keycode.Del => SDL.Scancode.Backspace,   // Android の Del は Backspace のこと
            Keycode.Tab => SDL.Scancode.Tab,
            _ => null,
        };
    }

    void DrawFrame()
    {
        var holder = Holder;
        if (holder == null) return;
        Canvas? c = null;
        try
        {
            c = OperatingSystem.IsAndroidVersionAtLeast(26) ? holder.LockHardwareCanvas() : holder.LockCanvas();
        }
        catch (Exception e)
        {
            Android.Util.Log.Warn("ShibaJintori", "lockCanvas: " + e.Message);
        }
        if (c == null) return;

        try
        {
            // 地はパネルの色。どの並べ方でも、余った所が黒い帯に見えないように
            c.DrawPaint(_panelBg);

            switch (_arr)
            {
                case Arrangement.Rows:
                    // 上は PC版と同じ画面 (タイトルもゲームも)。まわりと下の帯はパネルの色のまま
                    Gfx.Target(_menuC);
                    _app.MobileDrawWide();
                    Blit(c, _menu, _menuDst);
                    break;

                case Arrangement.Columns:
                    DrawMain(c);
                    Gfx.Target(_hudLC);
                    _app.MobileDrawHudLeft();
                    Blit(c, _hudL, _hudLDst);
                    Gfx.Target(_hudRC);
                    _app.MobileDrawHudRight();
                    Blit(c, _hudR, _hudRDst);
                    break;

                default:
                    DrawMain(c);
                    // ステータス領域 (タイトル中は操作の説明が出る)。背景は領域いっぱいに塗る
                    c.DrawRect(_padArea, _panelBg);
                    Gfx.Target(_statusC);
                    _app.MobileDrawStatus();
                    Blit(c, _status, _statusDst);
                    break;
            }

            // いちばん上に半透明の操作パッド
            _pad.Draw(c, _app, _clock);
        }
        finally
        {
            try { holder.UnlockCanvasAndPost(c); }
            catch (Exception e) { Android.Util.Log.Warn("ShibaJintori", "unlockCanvas: " + e.Message); }
        }
    }

    /// <summary>フィールド (ゲーム中) か、タイトルなどの画面のどちらか。</summary>
    void DrawMain(Canvas c)
    {
        if (_app.MenuScene)
        {
            Gfx.Target(_menuC);
            _app.MobileDrawMenu();
            Blit(c, _menu, _menuDst);
        }
        else
        {
            Gfx.Target(_fieldC);
            _app.MobileDrawField();
            Blit(c, _field, _fieldDst);
        }
    }

    /// <summary>描き終えた小さな絵を、ぼかさずに画面の場所へ拡大する。</summary>
    void Blit(Canvas c, Bitmap? bmp, RectF dst)
    {
        Gfx.Target(null);
        if (bmp != null) c.DrawBitmap(bmp, null, dst, _blit);
    }

    // ------------------------------------------------------------ 入力

    public override bool OnTouchEvent(MotionEvent? e)
    {
        if (e == null) return false;
        lock (_lock)
        {
            switch (e.ActionMasked)
            {
                case MotionEventActions.Down:
                case MotionEventActions.PointerDown:
                {
                    int i = e.ActionIndex;
                    _events.Add((e.GetPointerId(i), e.GetX(i), e.GetY(i), true));
                    break;
                }
                case MotionEventActions.Move:
                    for (int i = 0; i < e.PointerCount; i++)
                        _events.Add((e.GetPointerId(i), e.GetX(i), e.GetY(i), true));
                    break;
                case MotionEventActions.Up:
                case MotionEventActions.PointerUp:
                {
                    int i = e.ActionIndex;
                    _events.Add((e.GetPointerId(i), e.GetX(i), e.GetY(i), false));
                    break;
                }
                case MotionEventActions.Cancel:
                    _cancel = true;
                    break;
            }
        }
        return true;
    }

    /// <summary>
    /// 半開きの折り目の位置 (この画面の座標、上端と下端)。なければ -1, -1。UI スレッドから呼ぶ。
    /// 描画スレッドが次のフレームで並べ直す。
    /// </summary>
    public void SetHinge(int top, int bottom)
    {
        lock (_lock)
        {
            if (top == _hingeTop && bottom == _hingeBottom) return;
            _hingeTop = top;
            _hingeBottom = bottom;
            _hingeDirty = true;
        }
    }

    /// <summary>端末の「戻る」。タイトル画面ならアプリを閉じたいので false を返す。</summary>
    public bool HandleBack()
    {
        if (_app.AtTitle) return false;
        _backPressed = true;
        return true;
    }

    /// <summary>アプリが裏に回った/戻った。</summary>
    public void Sleep()
    {
        _sleep = true;
        _app.MobilePause();
        Input.Reset();
        lock (_lock)
        {
            _cancel = true;
            // 裏に回っている間に離したキーは届かないので、押しっぱなしにならないよう全部忘れる
            _keys.Clear();
            _stickX = _stickY = 0;
            _hat = 0;
            _stickDirty = false;
        }
        Audio.Suspend();
    }

    public void Wake()
    {
        Audio.Resume();
        _sleep = false;
    }
}
