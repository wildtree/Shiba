using Android.Content.PM;
using Android.Graphics;
using Android.Views;
using Android.Widget;

namespace ShibaJintori;

/// <summary>
/// Android版の入口。縦画面に固定し、通知領域 (ステータスバー) は消さずに、
/// その下にゲームの画面 (GameView) を置く。
/// </summary>
[Activity(
    Name = "jp.wildtree.android.apps.shibajintori.MainActivity",
    Label = "Shiba Jintori",
    MainLauncher = true,
    Exported = true,
    ScreenOrientation = ScreenOrientation.Portrait,
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
