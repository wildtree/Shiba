using Android.Content.PM;
using Android.Graphics;
using Android.Runtime;
using Android.Views;
using Android.Widget;
using AndroidX.Core.Content;
using AndroidX.Window.Java.Layout;
using AndroidX.Window.Layout;

namespace ShibaJintori;

/// <summary>
/// Android版の入口。通知領域 (ステータスバー) は消さずに、その下にゲームの画面 (GameView) を置く。
/// 向きは固定しない (縦・横・折りたたみの開閉・分割画面のどれでも、GameView が画面の形に合わせて並べ直す)。
/// 回転や開閉で Activity を作り直さないように ConfigurationChanges で受け止めるので、遊んでいる途中の状態は消えない。
/// </summary>
[Activity(
    Name = "jp.wildtree.android.apps.shibajintori.MainActivity",
    Label = "Shiba Jintori",
    MainLauncher = true,
    Exported = true,
    // 端末の「自動回転」の設定に従う (オフにしている人の画面は勝手に回らない)
    ScreenOrientation = ScreenOrientation.FullUser,
    ConfigurationChanges = ConfigChanges.Orientation | ConfigChanges.ScreenSize | ConfigChanges.ScreenLayout
                           | ConfigChanges.SmallestScreenSize | ConfigChanges.KeyboardHidden | ConfigChanges.Keyboard
                           | ConfigChanges.Navigation | ConfigChanges.Touchscreen | ConfigChanges.UiMode
                           | ConfigChanges.Density | ConfigChanges.FontScale | ConfigChanges.Locale
                           | ConfigChanges.LayoutDirection | ConfigChanges.ColorMode)]
public sealed class MainActivity : Activity
{
    /// <summary>WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS。通知領域の文字を黒くするときに立てる。</summary>
    const int LightStatusBars = 8;

    GameView? _view;
    FrameLayout? _root;

    protected override void OnCreate(Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);

        // 遊んでいる間は画面を消さない
        Window?.AddFlags(WindowManagerFlags.KeepScreenOn);
        // 音量キーでゲームの音 (メディア音量) を調節できるようにする。
        // これがないと、メディア音量が 0 のままだと何も聞こえない
        VolumeControlStream = Android.Media.Stream.Music;
        Haptics.Init(this);
        _root = new FrameLayout(this);
        _root.SetBackgroundColor(Color.Argb(255, 12, 14, 24));
        _view = new GameView(this, Finish);
        _root.AddView(_view);
        // 通知領域やナビゲーションバーに隠れないように、その分だけ内側に寄せる
        _root.SetOnApplyWindowInsetsListener(new InsetPadding());
        SetContentView(_root);

        // 通知領域の文字・アイコンは白のまま (背景が暗いので)。
        // InsetsController は画面がつながってからでないと取れないので、ここで後回しにする
        _root.Post(() =>
        {
            if (OperatingSystem.IsAndroidVersionAtLeast(30))
                Window?.InsetsController?.SetSystemBarsAppearance(0, LightStatusBars);
        });
    }

    // ------------------------------------------------------------ 折りたたみの姿勢

    // 半開きで机に置いた「テーブルトップ」の姿勢を知るために、折り目 (ヒンジ) の位置と状態を見張る。
    // 見張るのは画面が見えている間だけ (OnStart 〜 OnStop)
    WindowInfoTrackerCallbackAdapter? _fold;
    FoldListener? _foldListener;

    protected override void OnStart()
    {
        base.OnStart();
        try
        {
            _fold ??= new WindowInfoTrackerCallbackAdapter(WindowInfoTracker.Companion.GetOrCreate(this));
            _foldListener ??= new FoldListener(this);
            _fold.AddWindowLayoutInfoListener(this, ContextCompat.GetMainExecutor(this)!, _foldListener);
        }
        catch (Exception e)
        {
            // 折り目の情報が取れない端末でも、ふつうに遊べればよい
            Android.Util.Log.Warn("ShibaJintori", "fold: " + e.Message);
        }
    }

    protected override void OnStop()
    {
        try { if (_foldListener != null) _fold?.RemoveWindowLayoutInfoListener(_foldListener); }
        catch (Exception e) { Android.Util.Log.Warn("ShibaJintori", "fold: " + e.Message); }
        base.OnStop();
    }

    /// <summary>
    /// 折り目の様子が変わった。横向きの折り目で半開き (テーブルトップ) なら、その位置を GameView に知らせる。
    /// それ以外 (平らに開いている・本のように縦の折り目・折り目のない端末) なら「なし」を知らせる。
    /// </summary>
    void OnFoldChanged(WindowLayoutInfo info)
    {
        var view = _view;
        if (view == null) return;
        foreach (var feature in info.DisplayFeatures)
        {
            // (Java のオブジェクトなので == ではなく Equals で比べる)
            if (AsFold(feature) is { } fold
                && FoldingFeatureState.HalfOpened.Equals(fold.State)
                && FoldingFeatureOrientation.Horizontal.Equals(fold.Orientation))
            {
                // 折り目の位置はウィンドウの座標で来るので、ゲーム画面の座標に直す (上の通知領域の分などをずらす)
                var at = new int[2];
                view.GetLocationInWindow(at);
                var b = fold.Bounds;
                view.SetHinge(b.Top - at[1], b.Bottom - at[1]);
                Android.Util.Log.Info("ShibaJintori", $"fold: tabletop, hinge {b.Top - at[1]}-{b.Bottom - at[1]}");
                return;
            }
        }
        view.SetHinge(-1, -1);
    }

    /// <summary>
    /// 表示上の特徴のうち、折り目 (FoldingFeature) だけを取り出す。
    /// Java のインターフェースとして届くので、C# の is ではなく JavaCast で確かめる必要がある。
    /// </summary>
    static IFoldingFeature? AsFold(IDisplayFeature feature)
    {
        try { return feature.JavaCast<IFoldingFeature>(); }
        catch (InvalidCastException) { return null; }
    }

    sealed class FoldListener(MainActivity owner) : Java.Lang.Object, AndroidX.Core.Util.IConsumer
    {
        public void Accept(Java.Lang.Object? value)
        {
            if (value is WindowLayoutInfo info) owner.OnFoldChanged(info);
        }
    }

    // ------------------------------------------------------------

    protected override void OnDestroy()
    {
        _view?.Shutdown();
        base.OnDestroy();
    }

    protected override void OnPause()
    {
        base.OnPause();
        _view?.Sleep();
    }

    protected override void OnResume()
    {
        base.OnResume();
        _view?.Wake();
    }

    // キーボードとゲームパッドは、画面のどこに焦点があっても GameView に渡す。
    // ゲームで使わないキー (戻る・音量など) は Android にそのまま任せる
    public override bool DispatchKeyEvent(KeyEvent? e)
    {
        if (e != null && _view?.HandleKey(e) == true) return true;
        return base.DispatchKeyEvent(e);
    }

    public override bool DispatchGenericMotionEvent(MotionEvent? e)
    {
        if (e != null && _view?.HandleMotion(e) == true) return true;
        return base.DispatchGenericMotionEvent(e);
    }

#pragma warning disable CA1422   // 新しい端末では予測型の「戻る」が使われるが、どちらでもここに来る
    public override void OnBackPressed()
    {
        if (_view?.HandleBack() == true) return;
        base.OnBackPressed();
    }
#pragma warning restore CA1422

    /// <summary>システムの帯 (通知領域・ナビゲーションバー・切り欠き) の分だけ余白を作る。</summary>
    sealed class InsetPadding : Java.Lang.Object, View.IOnApplyWindowInsetsListener
    {
        public WindowInsets OnApplyWindowInsets(View v, WindowInsets insets)
        {
            int l, t, r, b;
            if (OperatingSystem.IsAndroidVersionAtLeast(30))
            {
                var i = insets.GetInsets(WindowInsets.Type.SystemBars() | WindowInsets.Type.DisplayCutout());
                l = i.Left; t = i.Top; r = i.Right; b = i.Bottom;
            }
            else
            {
#pragma warning disable CA1422, CS0618
                l = insets.SystemWindowInsetLeft; t = insets.SystemWindowInsetTop;
                r = insets.SystemWindowInsetRight; b = insets.SystemWindowInsetBottom;
#pragma warning restore CA1422, CS0618
            }
            v.SetPadding(l, t, r, b);
            return insets;
        }
    }
}
