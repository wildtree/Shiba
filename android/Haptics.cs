using Android.Content;
using Android.OS;
using Android.Provider;

namespace ShibaJintori;

/// <summary>
/// 操作パッドの手ごたえ (振動)。十字キーは軽く、ボタンは少し強く鳴らす。
/// 端末の「タップ時の振動」設定がオフのときは何もしない。
/// </summary>
public static class Haptics
{
    static Vibrator? _vib;
    static bool _enabled;

    public static void Init(Context ctx)
    {
        try
        {
            if (OperatingSystem.IsAndroidVersionAtLeast(31))
            {
                var mgr = (VibratorManager?)ctx.GetSystemService(Context.VibratorManagerService);
                _vib = mgr?.DefaultVibrator;
            }
            else
            {
#pragma warning disable CA1422, CS0618
                _vib = (Vibrator?)ctx.GetSystemService(Context.VibratorService);
#pragma warning restore CA1422, CS0618
            }
            // 端末の「タップ時の振動」設定を尊重する。
            // この設定名は Android 13 で非推奨になったが、読めれば今も正しい値が返るので使う
            // (読めない端末では既定値の「オン」になる)。
#pragma warning disable CA1422, CS0618
            bool system = Settings.System.GetInt(ctx.ContentResolver, Settings.System.HapticFeedbackEnabled, 1) != 0;
#pragma warning restore CA1422, CS0618
            _enabled = _vib is { HasVibrator: true } && system;
            Android.Util.Log.Info("ShibaJintori", "haptics: " + (_enabled ? "on" : "off"));
        }
        catch (Exception e)
        {
            Android.Util.Log.Warn("ShibaJintori", "haptics: " + e.Message);
            _enabled = false;
        }
    }

    /// <summary>十字キー用の、ごく軽い手ごたえ。</summary>
    public static void Tick() => Buzz(tick: true);

    /// <summary>おしっこ・START などの、はっきりした手ごたえ。</summary>
    public static void Click() => Buzz(tick: false);

    static void Buzz(bool tick)
    {
        var vib = _vib;
        if (!_enabled || vib == null) return;
        try
        {
            if (OperatingSystem.IsAndroidVersionAtLeast(29))
            {
                // 端末ごとに作り込まれた「カチッ」を使う (いちばん自然に感じる)
                int id = tick ? VibrationEffect.EffectTick : VibrationEffect.EffectClick;
                vib.Vibrate(VibrationEffect.CreatePredefined(id)!);
            }
            else if (OperatingSystem.IsAndroidVersionAtLeast(26))
            {
                int amp = vib.HasAmplitudeControl ? (tick ? 70 : 150) : VibrationEffect.DefaultAmplitude;
                vib.Vibrate(VibrationEffect.CreateOneShot(tick ? 8 : 16, amp)!);
            }
            else
            {
#pragma warning disable CA1422, CS0618
                vib.Vibrate(tick ? 8 : 16);
#pragma warning restore CA1422, CS0618
            }
        }
        catch (Exception e)
        {
            Android.Util.Log.Warn("ShibaJintori", "vibrate: " + e.Message);
            _enabled = false;      // 一度でも失敗したら、以後は静かにあきらめる
        }
    }
}
