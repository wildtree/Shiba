using Android.Content;
using Android.Graphics;
using Android.Views;
using SDL3;

namespace ShibaJintori;

/// <summary>
/// ゲームの表示と操作をまとめた画面。縦画面で、
///   上: ゲームフィールド (480x400 のドット絵を横幅いっぱいに拡大)
///   下: ステータス領域 (480x190 を横幅に合わせて拡大) + 半透明の操作パッド
/// という作りになっている。タイトルなどの画面は PC版と同じ 640x400 を上側に出す。
/// 描画は専用のスレッドで回し、小さなビットマップに描いてから画面へ拡大する。
/// </summary>
public sealed class GameView : SurfaceView, ISurfaceHolderCallback
{
    readonly App _app = new();
    readonly TouchPad _pad = new();
    readonly Action _onQuit;

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
    Bitmap? _field, _status, _menu;
    Canvas? _fieldC, _statusC, _menuC;
    readonly RectF _fieldDst = new(), _statusDst = new(), _menuDst = new(), _padArea = new();
    readonly Paint _blit = new() { AntiAlias = false, FilterBitmap = false, Dither = false };
    readonly Paint _panelBg = new() { Color = Color.Argb(255, 0x1B, 0x20, 0x33) };

    readonly object _lock = new();
    readonly List<(int Id, float X, float Y, bool Down)> _events = new();
    bool _cancel;

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
        _wantW = width;
        _wantH = height;
    }

    public void SurfaceDestroyed(ISurfaceHolder holder)
    {
        _run = false;
        _thread?.Join(2000);
        _thread = null;
    }

    /// <summary>縦画面のどこに何を置くかを決める。</summary>
    void Relayout(int vw, int vh)
    {
        _haveW = vw; _haveH = vh;

        // 操作パッドのために下に取っておく高さ。残りをフィールドに使う
        float minStatus = 0.52f * vw;
        float scale = MathF.Min(vw / (float)App.FieldPixW, MathF.Max(1f, vh - minStatus) / App.FieldPixH);
        float fw = App.FieldPixW * scale, fh = App.FieldPixH * scale;
        _fieldDst.Set((vw - fw) / 2f, 0, (vw + fw) / 2f, fh);

        // ステータス領域 = フィールドの下の全部。操作パッドはこの範囲に重ねる
        _padArea.Set(0, fh, vw, vh);

        _pad.Layout(_padArea);

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

        if (_field == null) { _field = NewTarget(App.FieldPixW, App.FieldPixH); _fieldC = new Canvas(_field); }
        if (_status == null) { _status = NewTarget(App.StatusW, App.StatusH); _statusC = new Canvas(_status); }
        if (_menu == null) { _menu = NewTarget(Gfx.W, Gfx.H); _menuC = new Canvas(_menu); }
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
            if (_wantW > 0 && (_wantW != _haveW || _wantH != _haveH)) Relayout(_wantW, _wantH);
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
        }
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
            c.DrawColor(Color.Argb(255, 8, 10, 20));

            if (_app.MenuScene)
            {
                Gfx.Target(_menuC);
                _app.MobileDrawMenu();
                Gfx.Target(null);
                if (_menu != null) c.DrawBitmap(_menu, null, _menuDst, _blit);
            }
            else
            {
                Gfx.Target(_fieldC);
                _app.MobileDrawField();
                Gfx.Target(null);
                if (_field != null) c.DrawBitmap(_field, null, _fieldDst, _blit);
            }

            // ステータス領域 (タイトル中は操作の説明が出る)。背景は領域いっぱいに塗る
            c.DrawRect(_padArea, _panelBg);
            Gfx.Target(_statusC);
            _app.MobileDrawStatus();
            Gfx.Target(null);
            if (_status != null) c.DrawBitmap(_status, null, _statusDst, _blit);

            // いちばん上に半透明の操作パッド
            _pad.Draw(c, _app, _clock);
        }
        finally
        {
            try { holder.UnlockCanvasAndPost(c); }
            catch (Exception e) { Android.Util.Log.Warn("ShibaJintori", "unlockCanvas: " + e.Message); }
        }
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
        lock (_lock) { _cancel = true; }
        Audio.Suspend();
    }

    public void Wake()
    {
        Audio.Resume();
        _sleep = false;
    }
}
