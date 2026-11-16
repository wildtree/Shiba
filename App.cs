using SDL3;

namespace ShibaJintori;

/// <summary>画面遷移(タイトル/デモ/プレイ/結果/ネーム入力/ハイスコア)と描画。</summary>
public sealed class App
{
    enum Scene { Title, HiScores, Demo, StageIntro, Play, StageResult, GameOver, NameEntry }

    const int FieldW = World.FW * World.Tile;   // 480
    const uint PanelBg = 0x1B2033;

    Scene _scene = Scene.Title;
    float _t;                 // 現在の画面になってからの時間
    float _clock;             // 起動からの時間(アニメ用)
    bool _running = true;
    bool _paused;
    bool _attract;            // タイトル放置からの自動進行中

    World? _world;
    int _shiba, _stage, _lives, _score, _stageStartScore, _bonus;
    readonly HiScoreTable _hi = new();
    int _newRank = -1;

    const string NameChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!? ";
    readonly char[] _name = ['A', 'A', 'A'];
    int _namePos;

    static readonly string[] ShibaNames = ["RED", "BLACK", "WHITE"];

    // 接続中のゲームパッド (ID → ハンドル)
    readonly Dictionary<uint, IntPtr> _pads = new();
    float _padKeepAlive;

    public void Run()
    {
        // ゲームパッド関連の設定 (SDL.Init より前に指定する)
        SDL.SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");   // ウィンドウが非アクティブでも入力を受ける
        SDL.SetHint("SDL_JOYSTICK_ENHANCED_REPORTS", "1");          // PS4/PS5パッドをBluetoothでも完全なレポートモードで使う
        SDL.SetHint("SDL_JOYSTICK_THREAD", "1");                    // Windows: パッドの処理を専用スレッドで回し続ける

        // アプリ名とID。LinuxではこのIDがウィンドウのクラス名になり、
        // shibajintori.desktop の StartupWMClass と一致させることでドックのアイコンが正しく出る
        SDL.SetAppMetadata("Shiba Jintori", "1.0.0", "shibajintori");

        if (!SDL.Init(SDL.InitFlags.Video))
        {
            Console.Error.WriteLine("SDL init failed: " + SDL.GetError());
            return;
        }
        if (!Gfx.Init())
        {
            Console.Error.WriteLine("Window creation failed: " + SDL.GetError());
            SDL.Quit();
            return;
        }
        Art.Load();
        Gfx.SetWindowIcon();
        if (SDL.InitSubSystem(SDL.InitFlags.Audio)) Audio.Init();
        if (!SDL.InitSubSystem(SDL.InitFlags.Gamepad))
            Console.Error.WriteLine("Gamepad init failed: " + SDL.GetError());
        Audio.PlayMusic(Tune.Title);

        ulong last = SDL.GetTicksNS();
        while (_running)
        {
            while (SDL.PollEvent(out var e))
            {
                var type = (SDL.EventType)e.Type;
                if (type == SDL.EventType.Quit) _running = false;
                else if (type == SDL.EventType.KeyDown) { if (!e.Key.Repeat) Input.KeyDown(e.Key.Scancode); }
                else if (type == SDL.EventType.KeyUp) Input.KeyUp(e.Key.Scancode);
                else if (type == SDL.EventType.WindowFocusLost) Input.Reset();
                else if (type == SDL.EventType.GamepadAdded) OpenPad(e.GDevice.Which);
                else if (type == SDL.EventType.GamepadRemoved) ClosePad(e.GDevice.Which);
                else if (type == SDL.EventType.GamepadButtonDown) Input.PadButton(e.GButton.Button, true);
                else if (type == SDL.EventType.GamepadButtonUp) Input.PadButton(e.GButton.Button, false);
                else if (type == SDL.EventType.GamepadAxisMotion) Input.PadAxis(e.GAxis.Axis, e.GAxis.Value);
            }
            KeepPadsAwake();

            ulong now = SDL.GetTicksNS();
            float dt = Math.Min(0.05f, (now - last) / 1e9f);
            last = now;
            _clock += dt;

            if (Input.Pressed(SDL.Scancode.F11)) Gfx.ToggleFullscreen();
            if (Input.Pressed(SDL.Scancode.M)) Audio.Muted = !Audio.Muted;

            Update(dt);
            Draw();
            Audio.Update();
            Input.EndFrame();
            Gfx.Present();
            if (dt < 0.002f) SDL.Delay(2);   // VSyncが効かない環境でCPUを使い切らないように
        }

        foreach (var pad in _pads.Values) SDL.CloseGamepad(pad);
        _pads.Clear();
        Audio.Shutdown();
        SDL.Quit();
    }

    void OpenPad(uint id)
    {
        if (_pads.ContainsKey(id)) return;
        IntPtr pad = SDL.OpenGamepad(id);
        if (pad == IntPtr.Zero) { Console.Error.WriteLine("OpenGamepad failed: " + SDL.GetError()); return; }
        _pads[id] = pad;
        Console.WriteLine("Gamepad connected: " + (SDL.GetGamepadName(pad) ?? "unknown"));
    }

    void ClosePad(uint id)
    {
        if (!_pads.Remove(id, out IntPtr pad)) return;
        SDL.CloseGamepad(pad);
        Input.Reset();
        // プレイ中に切れたら自動でポーズする。再接続すればそのまま使える
        if (_scene == Scene.Play) _paused = true;
        Console.WriteLine("Gamepad disconnected");
    }

    /// <summary>
    /// Bluetoothパッドの省電力切断対策。入力イベントは毎フレーム受け取っているが、
    /// 機種によってはPC側から何か送られてこないと切れるものがあるため、
    /// 数秒おきに「振動なし」の出力を送って通信を保つ。
    /// </summary>
    void KeepPadsAwake()
    {
        if (_pads.Count == 0) return;
        _padKeepAlive += 1f / 60f;
        if (_padKeepAlive < 4f) return;
        _padKeepAlive = 0;
        foreach (var pad in _pads.Values) SDL.RumbleGamepad(pad, 0, 0, 0);
    }

    void Go(Scene s) { _scene = s; _t = 0; }

    // ------------------------------------------------------------ 更新

    void Update(float dt)
    {
        _t += dt;
        switch (_scene)
        {
            case Scene.Title:
                Audio.PlayMusic(Tune.Title);
                if (Input.Back) { _running = false; break; }
                if (Input.PressedDir is Dir d && (d == Dir.Left || d == Dir.Right))
                {
                    _shiba = (_shiba + (d == Dir.Left ? 2 : 1)) % 3;
                    _t = 0;
                    Audio.Play(Sfx.Select);
                }
                else if (Input.Confirm)
                {
                    Audio.Play(Sfx.Start);
                    _stage = 1; _lives = 3; _score = 0; _attract = false;
                    BeginStage();
                }
                else if (_t > 12) { _attract = true; _newRank = -1; Go(Scene.HiScores); }
                break;

            case Scene.HiScores:
                if (Input.AnyPressed || _t > 8)
                {
                    if (_attract && !Input.AnyPressed)
                    {
                        _world = new World(1 + (int)(_clock * 7) % 3, _shiba, 3, 0, demo: true);
                        Go(Scene.Demo);
                    }
                    else Go(Scene.Title);
                }
                break;

            case Scene.Demo:
                _world!.Update(dt, null, false);
                if (Input.AnyPressed || _t > 45 || _world.Finished) { _world = null; Go(Scene.Title); }
                break;

            case Scene.StageIntro:
                if (Input.Back) { ToTitle(); break; }
                if (_t > 2.2f) { Audio.PlayMusic(Tune.Game); Go(Scene.Play); }
                break;

            case Scene.Play:
            {
                var w = _world!;
                if (Input.Back) { ToTitle(); break; }
                if (Input.Pressed(SDL.Scancode.P) || Input.PadPause) { _paused = !_paused; Audio.Play(Sfx.Select); }
                if (_paused) break;
                w.Update(dt, Input.Held, Input.Action, Input.PressedDir);
                _score = w.Score; _lives = w.Lives;
                if (w.GameOver)
                {
                    Audio.PlayMusic(Tune.None);
                    Audio.Play(Sfx.GameOver);
                    Go(Scene.GameOver);
                }
                else if (w.Finished)
                {
                    Audio.PlayMusic(Tune.None);
                    _bonus = 0;
                    if (w.Cleared)
                    {
                        _bonus = w.Player.Area * 5 + (int)w.TimeLeft * 10 + 500 * _stage;
                        _score += _bonus; w.Score = _score;
                        Audio.Play(Sfx.StageClear);
                    }
                    else Audio.Play(Sfx.StageFail);
                    Go(Scene.StageResult);
                }
                break;
            }

            case Scene.StageResult:
                if ((_t > 1.5f && Input.Confirm) || _t > 9)
                {
                    if (_world!.Cleared) _stage++;
                    else _score = _stageStartScore;      // 失敗: 同じステージをやり直す
                    BeginStage();
                }
                break;

            case Scene.GameOver:
                if ((_t > 1.5f && Input.AnyPressed) || _t > 5)
                {
                    _world = null;
                    Audio.PlayMusic(Tune.Title);
                    if (_hi.Qualifies(_score))
                    {
                        _name[0] = _name[1] = _name[2] = 'A'; _namePos = 0;
                        Go(Scene.NameEntry);
                    }
                    else { _attract = false; _newRank = -1; Go(Scene.HiScores); }
                }
                break;

            case Scene.NameEntry:
                UpdateNameEntry();
                break;
        }
    }

    void BeginStage()
    {
        _stageStartScore = _score;
        _paused = false;
        _world = new World(_stage, _shiba, _lives, _score, demo: false);
        Audio.PlayMusic(Tune.None);
        Audio.Play(Sfx.Bark);
        Input.EndFrame();
        Go(Scene.StageIntro);
    }

    void ToTitle()
    {
        _world = null; _paused = false;
        Audio.PlayMusic(Tune.Title);
        Go(Scene.Title);
    }

    void UpdateNameEntry()
    {
        foreach (var key in Input.PressedKeys)
        {
            int k = (int)key;
            char typed = '\0';
            if (k >= (int)SDL.Scancode.A && k <= (int)SDL.Scancode.Z) typed = (char)('A' + k - (int)SDL.Scancode.A);
            else if (k >= (int)SDL.Scancode.Alpha1 && k <= (int)SDL.Scancode.Alpha9) typed = (char)('1' + k - (int)SDL.Scancode.Alpha1);
            else if (key == SDL.Scancode.Alpha0) typed = '0';

            int ci = NameChars.IndexOf(_name[_namePos]);
            if (key == SDL.Scancode.Up) { _name[_namePos] = NameChars[(ci + 1) % NameChars.Length]; Audio.Play(Sfx.Select); }
            else if (key == SDL.Scancode.Down) { _name[_namePos] = NameChars[(ci + NameChars.Length - 1) % NameChars.Length]; Audio.Play(Sfx.Select); }
            else if (key == SDL.Scancode.Left || key == SDL.Scancode.Backspace) { _namePos = Math.Max(0, _namePos - 1); Audio.Play(Sfx.Select); }
            else if (key == SDL.Scancode.Right) { _namePos = Math.Min(2, _namePos + 1); Audio.Play(Sfx.Select); }
            else if (key == SDL.Scancode.Return || key == SDL.Scancode.KpEnter || key == SDL.Scancode.Space)
            {
                if (_namePos < 2) { _namePos++; Audio.Play(Sfx.Select); }
                else
                {
                    _newRank = _hi.Add(new string(_name), _score, _stage);
                    Audio.Play(Sfx.NameOk);
                    _attract = false;
                    Go(Scene.HiScores);
                    return;
                }
            }
            else if (typed != '\0')
            {
                _name[_namePos] = typed;
                _namePos = Math.Min(2, _namePos + 1);
                Audio.Play(Sfx.Select);
            }
        }
    }

    // ------------------------------------------------------------ 描画

    void Draw()
    {
        Gfx.Clear(0x000000);
        switch (_scene)
        {
            case Scene.Title: DrawTitle(); break;
            case Scene.HiScores: DrawBackdrop(); DrawHiScores(); break;
            case Scene.NameEntry: DrawBackdrop(); DrawNameEntry(); break;
            default:
                if (_world != null)
                {
                    DrawField(_world);
                    DrawPanel(_world);
                    DrawOverlay(_world);
                }
                break;
        }
    }

    static Sprite GroundTile(World? w, int x, int y)
    {
        if (w != null && y < World.FH && w.LaneOf[y] == 1) return Art.RoadTop;
        if (w != null && y < World.FH && w.LaneOf[y] == 2) return Art.RoadBottom;
        return (x * 7 + y * 13 + x * y) % 5 == 0 ? Art.Grass1 : Art.Grass0;
    }

    void DrawField(World w)
    {
        const int T = World.Tile;
        Gfx.Clip(0, 0, FieldW, Gfx.H);

        for (int y = 0; y < World.FH; y++)
            for (int x = 0; x < World.FW; x++)
                Gfx.Draw(GroundTile(w, x, y), x * T, y * T);

        // なわばり(犬ごとの色)
        for (int y = 0; y < World.FH; y++)
            for (int x = 0; x < World.FW; x++)
            {
                int o = w.Terr[x, y];
                if (o < 0) continue;
                uint col = w.Dogs[o].Color;
                Gfx.Fill(x * T, y * T, T, T, col, 150);
                if (((x + y) & 1) == 0) Gfx.Fill(x * T + 6, y * T + 6, 4, 4, Gfx.Shade(col, 1.25f), 110);
                uint edge = Gfx.Shade(col, 0.6f);
                if (x == 0 || w.Terr[x - 1, y] != o) Gfx.Fill(x * T, y * T, 2, T, edge);
                if (x == World.FW - 1 || w.Terr[x + 1, y] != o) Gfx.Fill(x * T + T - 2, y * T, 2, T, edge);
                if (y == 0 || w.Terr[x, y - 1] != o) Gfx.Fill(x * T, y * T, T, 2, edge);
                if (y == World.FH - 1 || w.Terr[x, y + 1] != o) Gfx.Fill(x * T, y * T + T - 2, T, 2, edge);
                float f = w.Flash[x, y];
                if (f > 0) Gfx.Fill(x * T, y * T, T, T, 0xFFFFFF, (byte)(f * 200));
            }

        // 作りかけの三角形(おしっこ済みの電柱を点線で結ぶ)
        foreach (var d in w.Dogs)
        {
            if (!d.Alive) continue;
            byte a = d.IsPlayer ? (byte)255 : (byte)170;
            for (int i = 1; i < d.Chain.Count; i++)
                ChainLine(w, d.Chain[i - 1], d.Chain[i], d.Color, a);
            if (d.PeeT > 0 && d.PeePole >= 0 && ((int)(_clock * 8) & 1) == 0)
            {
                // 完成予定の三角形の予告線。柴犬の場合、成立しない三角形は赤で警告する
                uint col = d.IsPlayer && w.PeeOutcome(d) == false ? 0xFF2020u : d.Color;
                for (int i = Math.Max(0, d.Chain.Count - 2); i < d.Chain.Count; i++)
                    ChainLine(w, d.Chain[i], d.PeePole, col, a);
            }
        }

        // 電柱
        for (int i = 0; i < w.Poles.Count; i++)
        {
            var p = w.Poles[i];
            if (p.Owner >= 0)
            {
                Gfx.Tint(Art.PeeMark, w.Dogs[p.Owner].Color);
                Gfx.Draw(Art.PeeMark, p.X * T, p.Y * T);
            }
            Gfx.Draw(Art.Pole, p.X * T, p.Y * T);
            if (p.Locked && p.Owner >= 0)
            {
                Gfx.Tint(Art.PoleBand, w.Dogs[p.Owner].Color);
                Gfx.Draw(Art.PoleBand, p.X * T, p.Y * T);
            }
            if (w.Player.Chain.Contains(i) && ((int)(_clock * 4) & 1) == 0)
                Gfx.Frame(p.X * T, p.Y * T, T, T, 0xFFFFFF);
        }

        // 犬(奥から手前の順)
        var order = new List<Dog>();
        foreach (var d in w.Dogs) if (d.Alive) order.Add(d);
        order.Sort((a, b) => a.Y != b.Y ? a.Y.CompareTo(b.Y) : b.Id.CompareTo(a.Id));
        foreach (var d in order) DrawDog(w, d);

        foreach (var c in w.Cars)
            Gfx.Draw(Art.Cars[c.Color], c.X, c.Row * T, flip: c.Sign > 0);

        foreach (var p in w.Popups)
            Gfx.Text(p.Text, p.X, p.Y, p.Color);

        Gfx.Unclip();
    }

    void ChainLine(World w, int a, int b, uint color, byte alpha)
    {
        var p = w.Poles[a]; var q = w.Poles[b];
        Gfx.Dotted(p.X * 16 + 8, p.Y * 16 + 8, q.X * 16 + 8, q.Y * 16 + 8, 0x000000, _clock * 12 + 1, (byte)(alpha / 2));
        Gfx.Dotted(p.X * 16 + 8, p.Y * 16 + 8, q.X * 16 + 8, q.Y * 16 + 8, color, _clock * 12, alpha);
    }

    void DrawDog(World w, Dog d)
    {
        if (d.Invuln > 0 && ((int)(_clock * 14) & 1) == 0) return;
        var (px, py, stride) = w.DogPixel(d);
        bool vertical = d.Dir == Dir.Down || d.Dir == Dir.Up;
        int idx = (d.Dir == Dir.Down ? 0 : d.Dir == Dir.Up ? 2 : 4) + (stride ? 1 : 0);
        // 横向きの絵は右向き。左向きは反転。上下移動は一歩ごとに出す足を入れ替える
        bool flip = d.Dir == Dir.Left || (vertical && stride && d.StepFlip);
        if (d.PeeT > 0 && d.PeePole >= 0)
        {
            // 電柱のある側の後ろ足を上げたポーズ (犬は電柱の方を向いている)
            idx = d.Dir switch { Dir.Up => 7, Dir.Down => 8, _ => 6 };
            flip = d.Dir == Dir.Left || d.Dir == Dir.Up;
        }
        Gfx.Draw(Art.Dogs[d.BreedIndex][idx], px, py, flip);

        if (d.PeeT > 0 && d.PeePole >= 0)
        {
            // おしっこ: しずくと残り時間バー
            var pole = w.Poles[d.PeePole];
            float tx = pole.X * 16 + 8, ty = pole.Y * 16 + 13, sx = px + 8, sy = py + 11;
            for (int k = 0; k < 3; k++)
            {
                float u = (_clock * 3f + k / 3f) % 1f;
                Gfx.Fill(sx + (tx - sx) * u - 1, sy + (ty - sy) * u - MathF.Sin(u * MathF.PI) * 4, 2, 2, 0xFFF060);
            }
            float prog = 1f - d.PeeT / World.PeeTime;
            Gfx.Fill(px, py - 5, 16, 4, 0x000000, 200);
            Gfx.Fill(px + 1, py - 4, 14 * prog, 2, d.Color);
        }
        else if (d.IsPlayer && _scene == Scene.StageIntro)
        {
            float bob = MathF.Abs(MathF.Sin(_clock * 6)) * 4;
            Gfx.Text("YOU", px - 4, py - 14 - bob, 0xFFFF60);
        }
    }

    void DrawPanel(World w)
    {
        const int X = FieldW + 8;
        Gfx.Fill(FieldW, 0, Gfx.W - FieldW, Gfx.H, PanelBg);
        Gfx.Fill(FieldW, 0, 2, Gfx.H, 0x0C0E18);
        Gfx.Fill(FieldW + 2, 0, 1, Gfx.H, 0x3A4468);

        Gfx.Text("SHIBA JINTORI", X + 20, 8, 0xFFB040);
        Gfx.Tint(Art.Paw, 0xFFB040);
        Gfx.Draw(Art.Paw, X, 4);

        Gfx.Text($"STAGE {w.Stage:00}", X, 30, 0xFFFFFF);
        Gfx.Text("SCORE", X, 46, 0x9AA4C8); Gfx.Text($"{w.Score:0000000}", X + 88, 46);
        Gfx.Text("HI", X, 58, 0x9AA4C8); Gfx.Text($"{Math.Max(_hi.Top, w.Score):0000000}", X + 88, 58);

        Gfx.Text("LIVES", X, 78, 0x9AA4C8);
        for (int i = 0; i < Math.Min(w.Lives, 5); i++)
            Gfx.Draw(Art.Dogs[w.Player.BreedIndex][0], X + 48 + i * 18, 73);

        int time = (int)MathF.Ceiling(w.TimeLeft);
        Gfx.Text("TIME", X, 98, 0x9AA4C8);
        Gfx.Text($"{time,3}", X + 120, 98, time <= 20 && ((int)(_clock * 4) & 1) == 0 ? 0xFF5050 : 0xFFFFFFu);

        // 全体のなわばり率。3/4 (白い目印) でステージ終了
        int total = World.FW * World.FH;
        Gfx.Text("AREA", X, 116, 0x9AA4C8);
        Gfx.Text($"{w.Claimed * 100 / total,3}%/75%", X + 80, 116);
        Gfx.Fill(X, 128, 144, 10, 0x0C0E18);
        float bx = X;
        foreach (var d in w.Dogs)
        {
            float bw = d.Area * 144f / total;
            Gfx.Fill(bx, 129, bw, 8, d.Color);
            bx += bw;
        }
        Gfx.Fill(X + 108, 126, 1, 14, 0xFFFFFF);

        // 犬ごとの面積
        int y = 148;
        foreach (var d in w.Dogs)
        {
            if (d.IsPlayer) Gfx.Fill(X - 4, y - 2, 152, 20, 0x2C3558);
            Gfx.Fill(X - 4, y - 2, 3, 20, d.Color);
            Gfx.Tint(Art.Dogs[d.BreedIndex][0], d.Alive ? 0xFFFFFFu : 0x606060u);
            Gfx.Draw(Art.Dogs[d.BreedIndex][0], X + 2, y);
            Gfx.Tint(Art.Dogs[d.BreedIndex][0], 0xFFFFFF);
            Gfx.Text(d.Alive ? Breed.All[d.BreedIndex].Display : "OUT", X + 22, d.IsPlayer ? y + 4 : y, d.Alive ? 0xFFFFFFu : 0x808080u);
            if (!d.IsPlayer) Gfx.Text(d.T.Trait, X + 22, y + 9, 0x7C86AC, shadow: false);
            Gfx.Text($"{d.Area,3}", X + 120, y + 4, d.Color);
            y += 21;
        }

        if (_pads.Count > 0) Gfx.Text("GAMEPAD: OK", X, 334, 0x60D080);
        Gfx.Text("ARROWS: MOVE", X, 348, 0x7C86AC);
        Gfx.Text("SPACE : PEE (3s)", X, 360, 0x7C86AC);
        Gfx.Text("P:PAUSE ESC:QUIT", X, 372, 0x7C86AC);
        Gfx.Text("M:BGM  F11:FULL", X, 384, 0x7C86AC);
    }

    void DrawOverlay(World w)
    {
        const float CX = FieldW / 2f;
        switch (_scene)
        {
            case Scene.StageIntro:
                Box(120, 150, 240, 70);
                Gfx.TextCenter($"STAGE {w.Stage}", CX, 162, 0xFFFFFF, 3);
                Gfx.TextCenter(_t < 1.4f ? "READY?" : "GO!", CX, 196, 0xFFE040, 2);
                break;

            case Scene.Play when _paused:
                Box(150, 170, 180, 50);
                Gfx.TextCenter("PAUSE", CX, 180, 0xFFFFFF, 3);
                Gfx.TextCenter("P / START: RESUME", CX, 208, 0x9AA4C8);
                break;

            case Scene.Demo:
                if (((int)(_clock * 2) & 1) == 0) Gfx.TextCenter("- DEMO -", CX, 12, 0xFFFFFF, 2);
                Gfx.TextCenter("PRESS ANY KEY", CX, 380, 0xFFE040);
                break;

            case Scene.GameOver:
                Box(110, 160, 260, 70);
                Gfx.TextCenter("GAME OVER", CX, 172, 0xFF5050, 3);
                Gfx.TextCenter($"SCORE {_score}", CX, 208, 0xFFFFFF);
                break;

            case Scene.StageResult:
            {
                var list = new List<Dog>(w.Dogs);
                list.Sort((a, b) => b.Area != a.Area ? b.Area.CompareTo(a.Area) : a.Id.CompareTo(b.Id));
                int h = 96 + list.Count * 18;
                int top = (Gfx.H - h) / 2;
                Box(90, top, 300, h);
                if (w.Cleared) Gfx.TextCenter("STAGE CLEAR!", CX, top + 10, 0xFFE040, 2);
                else Gfx.TextCenter("STAGE FAILED", CX, top + 10, 0xFF5050, 2);
                int y = top + 36;
                int total = World.FW * World.FH;
                for (int i = 0; i < list.Count; i++)
                {
                    var d = list[i];
                    if (d.IsPlayer) Gfx.Fill(100, y - 1, 280, 18, 0x38457A);
                    Gfx.Text($"{i + 1}", 108, y + 4, 0x9AA4C8);
                    Gfx.Draw(Art.Dogs[d.BreedIndex][0], 124, y);
                    Gfx.Text(Breed.All[d.BreedIndex].Display + (d.IsPlayer ? " (YOU)" : ""), 146, y + 4);
                    Gfx.Text($"{d.Area,3} {d.Area * 100 / total,2}%", 316, y + 4, d.Color);
                    y += 18;
                }
                y += 6;
                if (w.Cleared) Gfx.TextCenter($"BONUS +{_bonus}", CX, y, 0xFFFFFF);
                else Gfx.TextCenter("YOUR TERRITORY WAS TOO SMALL", CX, y, 0xFFFFFF);
                if (_t > 1.5f && ((int)(_clock * 2) & 1) == 0)
                    Gfx.TextCenter(w.Cleared ? "PRESS SPACE: NEXT STAGE" : "PRESS SPACE: TRY AGAIN", CX, y + 18, 0xFFE040);
                break;
            }
        }
    }

    static void Box(float x, float y, float w, float h)
    {
        Gfx.Fill(x + 3, y + 3, w, h, 0x000000, 120);
        Gfx.Fill(x, y, w, h, 0x1B2033, 235);
        Gfx.Frame(x, y, w, h, 0xFFFFFF);
        Gfx.Frame(x + 2, y + 2, w - 4, h - 4, 0x3A4468);
    }

    void DrawBackdrop()
    {
        for (int y = 0; y < Gfx.H / 16; y++)
            for (int x = 0; x < Gfx.W / 16; x++)
                Gfx.Draw(GroundTile(null, x, y), x * 16, y * 16);
        Gfx.Fill(0, 0, Gfx.W, Gfx.H, 0x102018, 120);
    }

    void DrawTitle()
    {
        DrawBackdrop();
        const float CX = Gfx.W / 2f;

        // 肉球の飾り
        Gfx.Tint(Art.Paw, 0xFFFFFF, 60);
        for (int i = 0; i < 8; i++)
            Gfx.Draw(Art.Paw, 40 + i * 78, 22 + (i & 1) * 26, flip: (i & 1) == 1, scale: 2);
        Gfx.Tint(Art.Paw, 0xFFFFFF, 255);

        Gfx.TextCenter($"HI-SCORE {_hi.Top:0000000}", CX, 6, 0xFFFFFF);
        float wob = MathF.Sin(_clock * 2.5f) * 3;
        Gfx.TextCenter("SHIBA JINTORI", CX + 3, 43 + wob, 0x5A2A08, 5);
        Gfx.TextCenter("SHIBA JINTORI", CX, 40 + wob, 0xFFB040, 5);
        Gfx.TextCenter("- DEFEND YOUR TERRITORY! -", CX, 96, 0xFFFFFF, 1);

        // 柴犬の色えらび
        Gfx.TextCenter("< SELECT YOUR SHIBA >", CX, 128, 0xFFE040);
        for (int i = 0; i < 3; i++)
        {
            float x = CX + (i - 1) * 96 - 24, y = 148;
            bool sel = i == _shiba;
            if (sel)
            {
                Gfx.Fill(x - 10, y - 6, 68, 78, 0x1B2033, 200);
                Gfx.Frame(x - 10, y - 6, 68, 78, 0xFFE040);
                y -= MathF.Abs(MathF.Sin(_clock * 5)) * 5;
            }
            int frame = sel && ((int)(_clock * 5) & 1) == 0 ? 1 : 0;
            Gfx.Draw(Art.Dogs[i][frame], x, y, scale: 3);
            Gfx.TextCenter(ShibaNames[i], x + 24, 206, sel ? 0xFFFFFFu : 0xA0A8A0u);
        }

        if (((int)(_clock * 2) & 1) == 0)
            Gfx.TextCenter("PRESS SPACE OR ENTER TO START", CX, 244, 0xFFFFFF, 2);

        Gfx.TextCenter("PEE ON 3 POLES TO CLAIM THE TRIANGLE AS YOUR TERRITORY.", CX, 280, 0xE0F0E0);
        Gfx.TextCenter("DON'T GET SURROUNDED BY OTHER DOGS. WATCH OUT FOR CARS!", CX, 292, 0xE0F0E0);
        Gfx.TextCenter("ARROWS/WASD:MOVE  SPACE/Z:PEE  F11:FULLSCREEN  ESC:QUIT", CX, 310, 0xA8C0A8);

        // 行進する犬たち
        int count = Breed.EnemyBreedCount + 1;
        for (int i = 0; i < count; i++)
        {
            int breed = i == 0 ? _shiba : Breed.ShibaCount + i - 1;
            float x = (_clock * 44 - i * 34 - (i > 0 ? 40 : 0)) % (Gfx.W + 420) - 40;
            if (x < -40) x += Gfx.W + 420;
            int frame = 4 + ((int)(_clock * 7 + i) & 1);
            Gfx.Draw(Art.Dogs[breed][frame], x, 336 + (frame == 5 ? -2 : 0), scale: 2);
        }
        Gfx.Fill(0, 370, Gfx.W, 30, 0x000000, 90);
        Gfx.TextCenter("DOTNET + SDL3   2026", CX, 381, 0x90A890);
    }

    void DrawHiScores()
    {
        const float CX = Gfx.W / 2f;
        Box(140, 30, 360, 330);
        Gfx.TextCenter("HIGH SCORES", CX, 44, 0xFFE040, 3);
        Gfx.Text("RANK  NAME    SCORE  STAGE", 216, 86, 0x9AA4C8);
        for (int i = 0; i < _hi.Entries.Count; i++)
        {
            var e = _hi.Entries[i];
            bool me = i == _newRank;
            uint col = me && ((int)(_clock * 4) & 1) == 0 ? 0xFFE040u : i == 0 ? 0xFFB040u : 0xFFFFFFu;
            int y = 106 + i * 22;
            if (me) Gfx.Fill(196, y - 5, 248, 18, 0x38457A);
            Gfx.Text($"{i + 1,3}.   {e.Name}   {e.Score,7}    {e.Stage,2}", 216, y, col);
        }
        Gfx.TextCenter("PRESS ANY KEY", CX, 338, 0x9AA4C8);
    }

    void DrawNameEntry()
    {
        const float CX = Gfx.W / 2f;
        Box(120, 80, 400, 240);
        Gfx.TextCenter("YOU GOT A HIGH SCORE!", CX, 98, 0xFFE040, 2);
        Gfx.TextCenter($"SCORE {_score}   STAGE {_stage}", CX, 132, 0xFFFFFF);
        Gfx.TextCenter("ENTER YOUR INITIALS", CX, 156, 0x9AA4C8);
        for (int i = 0; i < 3; i++)
        {
            float x = CX - 84 + i * 60;
            bool cur = i == _namePos;
            Gfx.Fill(x, 178, 48, 56, cur ? 0x38457Au : 0x0C0E18u);
            Gfx.Frame(x, 178, 48, 56, cur ? 0xFFE040u : 0x3A4468u);
            Gfx.Text(_name[i].ToString(), x + 8, 190, 0xFFFFFF, 4);
            if (cur && ((int)(_clock * 3) & 1) == 0)
            {
                Gfx.TextCenter("^", x + 24, 168, 0xFFE040);
                Gfx.TextCenter("v", x + 24, 238, 0xFFE040);
            }
        }
        Gfx.Draw(Art.Dogs[_shiba][((int)(_clock * 5) & 1)], CX + 110, 186, scale: 3);
        Gfx.TextCenter("UP/DOWN OR TYPE: LETTER", CX, 264, 0x9AA4C8);
        Gfx.TextCenter("LEFT/RIGHT: MOVE   ENTER: OK", CX, 278, 0x9AA4C8);
    }
}
