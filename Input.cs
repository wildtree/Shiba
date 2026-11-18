using SDL3;

namespace ShibaJintori;

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
    // 方向(Dパッド/左スティック)は矢印キー、A/B/X はスペース、Y は R、START は Enter、BACK は Esc
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
                PadKey(SDL.Scancode.Space, down); break;
            case SDL.GamepadButton.North:
                PadKey(SDL.Scancode.R, down); break;       // Y: ポーズ中のやり直し
            case SDL.GamepadButton.Start:
                PadKey(SDL.Scancode.Return, down);
                if (down) _padPause = true;
                break;
            case SDL.GamepadButton.Back:
                PadKey(SDL.Scancode.Escape, down); break;
        }
    }

    // ---------------- 汎用のUSBジョイパッド ----------------
    // SDLがボタン配置を知らないパッド(ゲームパッドとして認識されないもの)用。
    // 軸0/1 を左スティック、ハット0 を十字キーとして扱う。ボタンは機種ごとに並びが違うので、
    // 4番目(番号3)=やり直し、9番目(番号8)=BACK、10番目(番号9)=START、それ以外はすべて「おしっこ/決定」にする。

    public static void JoyButton(byte button, bool down)
    {
        var mapped = button switch
        {
            3 => SDL.GamepadButton.North,
            8 => SDL.GamepadButton.Back,
            9 => SDL.GamepadButton.Start,
            _ => SDL.GamepadButton.South,
        };
        PadButton((byte)mapped, down);
    }

    public static void JoyAxis(byte axis, short value)
    {
        if (axis == 0) PadAxis((byte)SDL.GamepadAxis.LeftX, value);
        else if (axis == 1) PadAxis((byte)SDL.GamepadAxis.LeftY, value);
    }

    /// <summary>ハットスイッチ(十字キー)。value は 上=1 右=2 下=4 左=8 の組み合わせ。</summary>
    public static void JoyHat(byte value)
    {
        _padDpad[(int)Dir.Up] = (value & 1) != 0;
        _padDpad[(int)Dir.Right] = (value & 2) != 0;
        _padDpad[(int)Dir.Down] = (value & 4) != 0;
        _padDpad[(int)Dir.Left] = (value & 8) != 0;
        SyncPadDirs();
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
