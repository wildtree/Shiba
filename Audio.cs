#if ANDROID
using Android.Media;
#endif
using SDL3;

namespace ShibaJintori;

public enum Sfx
{
    Step, PeeDrip, Mark, Overwrite, Territory, EnemyTerritory, Invalid, Miss, EnemyOut,
    StageClear, StageFail, GameOver, Select, Start, CarHit, Bark, NameOk,
    Item, Thunder, Rain, Kicked, Extend, Achievement,
}

public enum Tune { None, Title, Game }

/// <summary>音の出し方。All: BGMも効果音も / SfxOnly: 効果音だけ / Silent: どちらも鳴らさない。</summary>
public enum SoundMode { All, SfxOnly, Silent }

/// <summary>
/// 効果音とBGM。音声ファイルは使わず、矩形波・三角波・ノイズをその場で合成して
/// 音の出口へ流し込む(昔のゲーム機風の音)。
/// 合成の部分は共通で、出口だけが OS ごとに違う (PC: SDL のオーディオストリーム / Android: AudioTrack)。
/// </summary>
public static class Audio
{
    const int Rate = 44100;

    sealed class Voice
    {
        public int Wave;            // 0:矩形波 1:矩形波(25%) 2:三角波 3:ノイズ
        public float F0, F1, Vol;
        public int Pos, Len, Delay;
        public double Phase;
        public uint Noise = 0x2545F491;
        public float NoiseOut;
    }

    static bool _ok;
    static readonly List<Voice> _voices = new();
    static readonly Random _rng = new();
    static readonly byte[] _bytes = new byte[512 * 2];
    static short[] _titleTune = [], _gameTune = [];
    static short[]? _music;
    static int _musicPos;
    static Tune _current = Tune.None;
    /// <summary>音の出し方。Silent は効果音も鳴らさない「マナーモード」。</summary>
    public static SoundMode Mode { get; private set; } = SoundMode.All;

    /// <summary>音を出せているか (端末の音の出口を開けたか)。画面の表示に使う。</summary>
    public static bool Ok => _ok;

    /// <summary>BGMあり → BGMなし(効果音だけ) → 全部なし、の順に切り替えて覚えておく。</summary>
    public static void CycleMode()
    {
        Mode = Mode switch { SoundMode.All => SoundMode.SfxOnly, SoundMode.SfxOnly => SoundMode.Silent, _ => SoundMode.All };
        if (Mode == SoundMode.Silent) lock (_voices) _voices.Clear();   // 鳴りかけの音も止める
        SaveMode();
    }

    static readonly string[] ModeNames = ["all", "sfx", "silent"];

    static void LoadMode()
    {
        using var doc = SaveData.ReadJson(SaveData.PathOf("settings.json"));
        if (doc == null) return;
        string name = SaveData.GetString(doc.RootElement, "sound", "all");
        int i = Array.IndexOf(ModeNames, name);
        if (i >= 0) Mode = (SoundMode)i;
    }

    static void SaveMode() => SaveData.WriteJson(SaveData.PathOf("settings.json"), w =>
    {
        w.WriteStartObject();
        w.WriteString("sound", ModeNames[(int)Mode]);
        w.WriteEndObject();
    });

    /// <summary>音まわりの覚え書き。Android では logcat (タグ ShibaJintori) に出る。</summary>
    static void Note(string msg)
    {
#if ANDROID
        Android.Util.Log.Info("ShibaJintori", "audio: " + msg);
#else
        Console.Error.WriteLine("audio: " + msg);
#endif
    }

    public static void Init()
    {
        if (_ok) { Note("already open"); return; }   // 画面が作り直されたときに二重に開かないように
        try
        {
            LoadMode();
            if (!OpenDevice()) { Note("device not opened - no sound"); return; }
            BuildTunes();
            _ok = true;
            Note($"ready (mode={Mode})");
        }
        catch (Exception e)
        {
            Note("disabled: " + e);
        }
    }

    public static void Shutdown()
    {
        CloseDevice();
        _ok = false;
    }

    public static void PlayMusic(Tune t)
    {
        if (t == _current) return;
        _current = t;
        _music = t switch { Tune.Title => _titleTune, Tune.Game => _gameTune, _ => null };
        _musicPos = 0;
    }

    /// <summary>
    /// 毎フレーム呼ぶ。PC版はここで続きを合成して流し込む。
    /// Android版は専用のスレッドが鳴らしているので、ここですることはない。
    /// </summary>
    public static void Update()
    {
        if (!_ok) return;
        Pump();
    }

    /// <summary>
    /// 次の len バイトぶんの音を作って buf に入れる (BGM + 鳴っている効果音を混ぜる)。
    /// Android版では音のスレッドから呼ばれるので、効果音の一覧はロックで守る。
    /// </summary>
    static void Mix(byte[] buf, int len)
    {
        int n = len / 2;
        var music = _music;
        lock (_voices)
        {
            for (int i = 0; i < n; i++)
            {
                float v = 0;
                if (music != null && music.Length > 0)
                {
                    if (_musicPos >= music.Length) _musicPos = 0;
                    if (Mode == SoundMode.All) v += music[_musicPos] / 32768f;
                    if (++_musicPos >= music.Length) _musicPos = 0;
                }
                for (int k = _voices.Count - 1; k >= 0; k--)
                {
                    var vo = _voices[k];
                    if (vo.Delay > 0) { vo.Delay--; continue; }
                    float t = (float)vo.Pos / vo.Len;
                    float f = vo.F0 + (vo.F1 - vo.F0) * t;
                    float env = Math.Min(1f, vo.Pos / 60f) * Math.Min(1f, (vo.Len - vo.Pos) / (vo.Len * 0.35f + 1));
                    v += Osc(vo, f) * vo.Vol * env;
                    if (++vo.Pos >= vo.Len) _voices.RemoveAt(k);
                }
                int s = (int)(Math.Clamp(v, -1f, 1f) * 30000);
                buf[i * 2] = (byte)s;
                buf[i * 2 + 1] = (byte)(s >> 8);
            }
        }
    }

    // ------------------------------------------------------------ 音の出口 (OSごと)
#if ANDROID
    // Android は専用のスレッドから AudioTrack へ書き込む。
    // 書き込みは「空きができるまで待つ」やり方なので、これだけで 44.1kHz ちょうどの速さで進む
    // (再生位置を見て間隔を測る必要がない)。
    static AudioTrack? _track;
    static Thread? _thread;
    static volatile bool _running;
    static long _written;         // これまでに書き込んだフレーム数 (ログ用)

    static bool OpenDevice()
    {
        int min = AudioTrack.GetMinBufferSize(Rate, ChannelOut.Mono, Android.Media.Encoding.Pcm16bit);
        int size = Math.Max(min, Rate * 2 * 2 / 10);      // 0.2秒ぶん
        Note($"open rate={Rate} minBuffer={min} buffer={size}");
        using var attrs = new AudioAttributes.Builder()
            .SetUsage(AudioUsageKind.Game)!.SetContentType(AudioContentType.Music)!.Build()!;
        using var fmt = new AudioFormat.Builder()
            .SetEncoding(Android.Media.Encoding.Pcm16bit)!.SetSampleRate(Rate)!
            .SetChannelMask(ChannelOut.Mono)!.Build()!;
        try
        {
            _track = new AudioTrack.Builder()
                .SetAudioAttributes(attrs)!.SetAudioFormat(fmt)!
                .SetBufferSizeInBytes(size)!.SetTransferMode(AudioTrackMode.Stream)!.Build();
        }
        catch (Exception e)
        {
            // 端末によっては Builder で作れないことがあるので、昔ながらの作り方でもう一度試す
            Note("builder failed (" + e.Message + ") - falling back");
#pragma warning disable CA1422, CS0618
            _track = new AudioTrack(Android.Media.Stream.Music, Rate, ChannelOut.Mono,
                                    Android.Media.Encoding.Pcm16bit, size, AudioTrackMode.Stream);
#pragma warning restore CA1422, CS0618
        }
        if (_track == null) { Note("AudioTrack could not be created"); return false; }
        Note($"track state={_track.State} session={_track.AudioSessionId}");
        if (_track.State != AudioTrackState.Initialized) { Note("track not initialized"); CloseDevice(); return false; }

        _written = 0;
        _track.Play();
        _running = true;
        _thread = new Thread(AudioLoop) { IsBackground = true, Name = "shiba-audio", Priority = ThreadPriority.AboveNormal };
        _thread.Start();
        Note($"play state={_track.PlayState}");
        return true;
    }

    /// <summary>音のスレッド。合成しては AudioTrack に渡す、のくり返し。</summary>
    static void AudioLoop()
    {
        var track = _track;
        if (track == null) return;
        var buf = new byte[1024];
        int reports = 0;
        while (_running)
        {
            Mix(buf, buf.Length);
            try
            {
                int n = track.Write(buf, 0, buf.Length, WriteMode.Blocking);
                if (n < 0) { Note($"write error {n}"); break; }
                _written += n / 2;
            }
            catch (Exception e)
            {
                Note("write: " + e.Message);
                break;
            }
            // 最初の数秒だけ、ちゃんと進んでいるかを記録する
            if (reports < 4 && _written > (long)Rate * (reports + 1) / 2)
            {
                reports++;
                Note($"written={_written} head={track.PlaybackHeadPosition} mode={Mode}");
            }
        }
        Note("audio thread finished");
    }

    static void Pump() { }        // 音のスレッドがやるので、ここですることはない

    static void CloseDevice()
    {
        _running = false;
        var track = _track;
        _track = null;
        if (track == null) return;
        try { track.Pause(); track.Flush(); track.Stop(); } catch (Exception e) { Note("stop: " + e.Message); }
        _thread?.Join(1000);
        _thread = null;
        track.Release();
        track.Dispose();
    }

    /// <summary>アプリが裏に回ったとき/戻ったとき (Android版のみ)。</summary>
    public static void Suspend() { try { _track?.Pause(); } catch (Exception e) { Note("pause: " + e.Message); } }
    public static void Resume() { try { _track?.Play(); } catch (Exception e) { Note("resume: " + e.Message); } }
#else
    static IntPtr _stream;

    static bool OpenDevice()
    {
        var spec = new SDL.AudioSpec { Format = SDL.AudioFormat.AudioS16LE, Channels = 1, Freq = Rate };
        _stream = SDL.OpenAudioDeviceStream(SDL.AudioDeviceDefaultPlayback, spec, null, IntPtr.Zero);
        if (_stream == IntPtr.Zero) return false;
        SDL.ResumeAudioStreamDevice(_stream);
        return true;
    }

    static void CloseDevice()
    {
        if (_stream != IntPtr.Zero) SDL.DestroyAudioStream(_stream);
        _stream = IntPtr.Zero;
    }

    /// <summary>再生待ちが0.1秒分を切ったら、続きを合成して足す。</summary>
    static void Pump()
    {
        int guard = 0;
        while (SDL.GetAudioStreamQueued(_stream) < Rate * 2 / 10 && guard++ < 40)
        {
            Mix(_bytes, _bytes.Length);
            SDL.PutAudioStreamData(_stream, _bytes, _bytes.Length);
        }
    }
#endif

    static float Osc(Voice v, float freq)
    {
        v.Phase += freq / Rate;
        if (v.Phase >= 1)
        {
            v.Phase -= Math.Floor(v.Phase);
            if (v.Wave == 3)
            {
                v.Noise ^= v.Noise << 13; v.Noise ^= v.Noise >> 17; v.Noise ^= v.Noise << 5;
                v.NoiseOut = (v.Noise & 0xFFFF) / 32768f - 1f;
            }
        }
        return v.Wave switch
        {
            0 => v.Phase < 0.5 ? 1f : -1f,
            1 => v.Phase < 0.25 ? 1f : -1f,
            2 => (float)(v.Phase < 0.5 ? 4 * v.Phase - 1 : 3 - 4 * v.Phase),
            _ => v.NoiseOut,
        };
    }

    static void V(int wave, float f0, float f1, float dur, float vol, float delay = 0)
    {
        lock (_voices)
        {
            if (_voices.Count >= 40) return;
            _voices.Add(new Voice
            {
                Wave = wave, F0 = f0, F1 = f1, Vol = vol,
                Len = Math.Max(1, (int)(dur * Rate)), Delay = (int)(delay * Rate),
            });
        }
    }

    /// <summary>音名を順番に鳴らす(ジングル用)。</summary>
    static void Notes(int wave, string notes, float each, float vol, float start = 0)
    {
        float t = start;
        foreach (var tok in notes.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            var (freq, steps) = ParseNote(tok);
            if (freq > 0) V(wave, freq, freq, each * steps * 0.95f, vol, t);
            t += each * steps;
        }
    }

    public static void Play(Sfx s)
    {
        if (!_ok || Mode == SoundMode.Silent) return;
        float r = (float)_rng.NextDouble();
        switch (s)
        {
            case Sfx.Step: V(1, 480, 620, 0.035f, 0.05f); break;
            case Sfx.PeeDrip: V(2, 1500 + r * 900, 1000 + r * 500, 0.06f, 0.16f); break;
            case Sfx.Mark: Notes(0, "e6 a6:2", 0.06f, 0.12f); break;
            case Sfx.Overwrite: Notes(1, "a5 e5 a5 e6", 0.05f, 0.13f); break;
            case Sfx.Territory:
                Notes(0, "c5 e5 g5 c6 e6 g6 c7:4", 0.06f, 0.14f);
                Notes(2, "c4 g4 c5:6", 0.12f, 0.22f);
                break;
            case Sfx.EnemyTerritory: Notes(1, "g3 a#3 d4 g4:3", 0.07f, 0.11f); break;
            case Sfx.Invalid: V(0, 120, 100, 0.18f, 0.14f); V(0, 126, 105, 0.18f, 0.10f); break;
            case Sfx.Miss:
                V(0, 900, 110, 0.7f, 0.16f);
                V(3, 3000, 400, 0.35f, 0.14f);
                Notes(2, "e5 c5 a4 f4:3", 0.12f, 0.2f, 0.15f);
                break;
            case Sfx.EnemyOut:
                V(1, 700, 1700, 0.09f, 0.14f); V(1, 800, 1900, 0.10f, 0.14f, 0.12f);
                Notes(0, "g5 c6 e6 g6:3", 0.07f, 0.12f, 0.26f);
                break;
            case Sfx.StageClear:
                Notes(0, "c5 c5 c5 e5:2 g5:2 e5 g5 c6:6", 0.11f, 0.15f);
                Notes(2, "c4:3 g4:2 c4:2 e4 g4 c5:6", 0.11f, 0.22f);
                break;
            case Sfx.StageFail: Notes(2, "e4:2 d#4:2 d4:2 c#4:6", 0.14f, 0.24f); V(0, 150, 90, 0.9f, 0.06f, 0.84f); break;
            case Sfx.GameOver: Notes(0, "c5:2 g4:2 e4:2 a4 b4 a4 g#4:2 g4:6", 0.15f, 0.14f); Notes(2, "c3:6 f3:5 c3:8", 0.15f, 0.22f); break;
            case Sfx.Select: V(1, 880, 880, 0.04f, 0.10f); break;
            case Sfx.Start: Notes(0, "c5 e5 g5 c6:3", 0.06f, 0.14f); break;
            case Sfx.CarHit: V(3, 5000, 600, 0.3f, 0.22f); V(0, 300, 60, 0.3f, 0.16f); break;
            case Sfx.Bark:
                V(1, 500, 900, 0.07f, 0.16f); V(3, 2500, 1500, 0.05f, 0.08f);
                V(1, 520, 950, 0.08f, 0.16f, 0.16f); V(3, 2500, 1500, 0.05f, 0.08f, 0.16f);
                break;
            case Sfx.NameOk: Notes(0, "g5 c6 e6 c6 e6 g6:4", 0.07f, 0.13f); break;
            case Sfx.Item: Notes(0, "e6 g6 e6 c7:3", 0.05f, 0.13f); break;
            case Sfx.Thunder:
                V(3, 900, 120, 1.1f, 0.22f); V(0, 70, 45, 1.2f, 0.12f);
                V(3, 700, 100, 0.8f, 0.14f, 0.5f);
                break;
            case Sfx.Rain: V(3, 7000, 5500, 3.8f, 0.07f); V(3, 3000, 2500, 3.8f, 0.04f); break;
            case Sfx.Extend: Notes(0, "e6 g6 e7 c7 d7 g7:4", 0.08f, 0.16f); Notes(2, "c5 e5 g5 c6 e6 g6:4", 0.08f, 0.2f); break;
            case Sfx.Achievement:
                Notes(1, "g5 c6 e6 g6 e6 g6 c7:4", 0.055f, 0.12f);
                Notes(2, "c5:3 e5:3 g5:6", 0.055f, 0.18f);
                break;
            case Sfx.Kicked: Notes(1, "c6 g5 e5 c5", 0.05f, 0.13f); break;
        }
    }

    // ------------------------------------------------------------ BGM

    /// <summary>"e5:2" = ミ(オクターブ5)を2ステップ。"r" は休符。"c#4" のように半音も書ける。</summary>
    static (float freq, int steps) ParseNote(string tok)
    {
        int steps = 1;
        int colon = tok.IndexOf(':');
        if (colon >= 0) { steps = int.Parse(tok[(colon + 1)..]); tok = tok[..colon]; }
        if (tok == "r") return (0, steps);
        int semi = "c d ef g a b".IndexOf(tok[0]);
        int i = 1;
        if (i < tok.Length && tok[i] == '#') { semi++; i++; }
        int octave = tok[i] - '0';
        int midi = 12 * (octave + 1) + semi;
        return ((float)(440.0 * Math.Pow(2, (midi - 69) / 12.0)), steps);
    }

    static void RenderTrack(float[] buf, string notes, double step, int wave, float vol, float gate)
    {
        var v = new Voice { Wave = wave };
        double t = 0;
        foreach (var tok in notes.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            var (freq, steps) = ParseNote(tok);
            int start = (int)(t * Rate);
            int len = (int)(step * steps * gate * Rate);
            t += step * steps;
            if (freq <= 0) continue;
            v.Phase = 0;
            for (int i = 0; i < len && start + i < buf.Length; i++)
            {
                float env = Math.Min(1f, i / 100f) * Math.Min(1f, (len - i) / 500f) * (1f - 0.55f * i / len);
                buf[start + i] += Osc(v, freq) * vol * env;
            }
        }
    }

    static short[] RenderTune(double step, int leadWave, float leadVol)
    {
        // メロディ(1小節=8ステップ、16小節でループ)
        const string melody =
            "e5 e5 g5 e5 c6:2 g5:2  d5 d5 g5 d5 b5:2 g5:2  c5 c5 e5 c5 a5:2 e5:2  f5 g5 a5 g5 f5:2 r:2 " +
            "e5 e5 g5 e5 c6:2 e6:2  d6 c6 b5 a5 g5:2 b5:2  a5 f5 a5 c6 b5 g5 b5 d6  c6:4 r:2 g5:2 " +
            "a5:2 c6 a5 f5:2 a5:2  g5:2 c6 g5 e5:2 g5:2  a5:2 c6 a5 f5:2 c6:2  b5 a5 g5 a5 b5:2 d6:2 " +
            "c6:2 a5 e5 a5:2 c6:2  b5:2 g5 e5 g5:2 b5:2  a5 f5 a5 c6 d6 b5 g5 b5  c6:4 r:4";
        // 半小節ごとのコード: (ベースの根音, 5度, 裏拍で鳴らす音)
        string[] chords =
        [
            "C", "C", "G", "G", "Am", "Am", "F", "F", "C", "C", "G", "G", "F", "G", "C", "C",
            "F", "F", "C", "C", "F", "F", "G", "G", "Am", "Am", "Em", "Em", "F", "G", "C", "C",
        ];
        var bass = new System.Text.StringBuilder();
        var chop = new System.Text.StringBuilder();
        foreach (var c in chords)
        {
            var (root, fifth, third) = c switch
            {
                "G" => ("g2", "d3", "b4"),
                "Am" => ("a2", "e3", "c5"),
                "F" => ("f2", "c3", "a4"),
                "Em" => ("e2", "b2", "g4"),
                _ => ("c3", "g2", "e4"),
            };
            bass.Append($"{root}:2 {fifth}:2 ");
            chop.Append($"r {third} r {third} ");
        }

        int total = (int)(step * 128 * Rate);
        var buf = new float[total];
        RenderTrack(buf, melody, step, leadWave, leadVol, 0.8f);
        RenderTrack(buf, bass.ToString(), step, 2, 0.20f, 0.7f);
        RenderTrack(buf, chop.ToString(), step, 1, 0.035f, 0.5f);
        var pcm = new short[total];
        for (int i = 0; i < total; i++) pcm[i] = (short)(Math.Clamp(buf[i], -1f, 1f) * 32000);
        return pcm;
    }

    static void BuildTunes()
    {
        _gameTune = RenderTune(0.16, 1, 0.085f);
        _titleTune = RenderTune(0.21, 2, 0.20f);
    }
}
