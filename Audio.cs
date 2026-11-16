using SDL3;

namespace ShibaJintori;

public enum Sfx
{
    Step, PeeDrip, Mark, Overwrite, Territory, EnemyTerritory, Invalid, Miss, EnemyOut,
    StageClear, StageFail, GameOver, Select, Start, CarHit, Bark, NameOk,
    Item, Thunder, Rain, Kicked,
}

public enum Tune { None, Title, Game }

/// <summary>
/// 効果音とBGM。音声ファイルは使わず、矩形波・三角波・ノイズをその場で合成して
/// SDL のオーディオストリームへ流し込む(昔のゲーム機風の音)。
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

    static IntPtr _stream;
    static bool _ok;
    static readonly List<Voice> _voices = new();
    static readonly Random _rng = new();
    static readonly byte[] _bytes = new byte[512 * 2];
    static short[] _titleTune = [], _gameTune = [];
    static short[]? _music;
    static int _musicPos;
    static Tune _current = Tune.None;
    public static bool Muted;

    public static void Init()
    {
        try
        {
            var spec = new SDL.AudioSpec { Format = SDL.AudioFormat.AudioS16LE, Channels = 1, Freq = Rate };
            _stream = SDL.OpenAudioDeviceStream(SDL.AudioDeviceDefaultPlayback, spec, null, IntPtr.Zero);
            if (_stream == IntPtr.Zero) return;
            SDL.ResumeAudioStreamDevice(_stream);
            BuildTunes();
            _ok = true;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("Audio disabled: " + e.Message);
        }
    }

    public static void Shutdown()
    {
        if (_stream != IntPtr.Zero) SDL.DestroyAudioStream(_stream);
        _stream = IntPtr.Zero; _ok = false;
    }

    public static void PlayMusic(Tune t)
    {
        if (t == _current) return;
        _current = t;
        _music = t switch { Tune.Title => _titleTune, Tune.Game => _gameTune, _ => null };
        _musicPos = 0;
    }

    /// <summary>毎フレーム呼ぶ。再生待ちが0.1秒分を切ったら続きを合成して足す。</summary>
    public static void Update()
    {
        if (!_ok) return;
        int guard = 0;
        while (SDL.GetAudioStreamQueued(_stream) < Rate * 2 / 10 && guard++ < 40)
        {
            int n = _bytes.Length / 2;
            for (int i = 0; i < n; i++)
            {
                float v = 0;
                if (_music != null && _music.Length > 0)
                {
                    if (!Muted) v += _music[_musicPos] / 32768f;
                    if (++_musicPos >= _music.Length) _musicPos = 0;
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
                _bytes[i * 2] = (byte)s;
                _bytes[i * 2 + 1] = (byte)(s >> 8);
            }
            SDL.PutAudioStreamData(_stream, _bytes, _bytes.Length);
        }
    }

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
        if (_voices.Count >= 40) return;
        _voices.Add(new Voice
        {
            Wave = wave, F0 = f0, F1 = f1, Vol = vol,
            Len = Math.Max(1, (int)(dur * Rate)), Delay = (int)(delay * Rate),
        });
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
        if (!_ok) return;
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
