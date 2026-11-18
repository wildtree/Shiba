namespace ShibaJintori;

/// <summary>
/// Android版のための App の追加部分。
/// 画面の中身 (タイトル・フィールド・結果画面) は PC版と同じコードを使い、
/// ここでは「毎フレームの進行」と「縦画面用のステータス領域」だけを足している。
/// PC版の横長パネル (DrawPanel) は使わず、下に横並びのステータスを描く。
/// </summary>
public sealed partial class App
{
    /// <summary>ステータス領域の論理サイズ (このドット数で描いて、画面幅に合わせて拡大する)。</summary>
    public const int StatusW = 480, StatusH = 190;

    /// <summary>フィールドの論理サイズ。</summary>
    public const int FieldPixW = FieldW, FieldPixH = World.FH * World.Tile;

    public bool Running => _running;

    /// <summary>タイトル系の画面か (640x400 で描く画面)。false ならゲーム画面。</summary>
    public bool MenuScene => _scene is Scene.Title or Scene.HiScores or Scene.NameEntry or Scene.Achievements;

    public bool Paused => _paused && _scene == Scene.Play;

    /// <summary>タイトル画面にいるか (ここでの SELECT / 戻るはゲームを終わらせてしまうので区別する)。</summary>
    public bool AtTitle => _scene == Scene.Title;

    /// <summary>アプリが裏に回ったときは、プレイ中なら自動でポーズする。</summary>
    public void MobileAutoPause()
    {
        if (_scene == Scene.Play) _paused = true;
    }

    /// <summary>ギブアップできる場面か (プレイ中で、ボーナスステージではない)。</summary>
    public bool CanGiveUp => _scene == Scene.Play && _world is { Bonus: false };

    /// <summary>絵と音の用意。画面が出る前に一度だけ呼ぶ。</summary>
    public void MobileStart()
    {
        Art.Load();
        Audio.Init();
        Audio.PlayMusic(Tune.Title);
    }

    public void MobileStop() => Audio.Shutdown();

    /// <summary>1フレームぶん進める (描画の前に呼ぶ)。</summary>
    public void MobileUpdate(float dt)
    {
        _clock += dt;
        Update(dt);
    }

    /// <summary>1フレームの後始末 (音の送り出しと、押されたキーの消去)。</summary>
    public void MobileEndFrame()
    {
        Audio.Update();
        Input.EndFrame();
    }

    /// <summary>ギブアップ (ポーズ中の R と同じ)。確認は操作パッド側で取る。</summary>
    public void MobileGiveUp()
    {
        if (!CanGiveUp) return;
        Achievements.Unlock("GIVE_UP");
        _score = _stageStartScore;
        _paused = false;
        BeginStage();
    }

    /// <summary>ゲーム画面 (480x400)。フィールドと、その上に重なる案内。</summary>
    public void MobileDrawField()
    {
        Gfx.Clear(0x000000);
        if (_world == null) return;
        DrawField(_world);
        DrawOverlay(_world);
        Achievements.DrawToast();
    }

    /// <summary>タイトル系の画面 (640x400)。PC版とまったく同じ絵。</summary>
    public void MobileDrawMenu()
    {
        Gfx.Clear(0x000000);
        switch (_scene)
        {
            case Scene.Title: DrawTitle(); break;
            case Scene.HiScores: DrawBackdrop(); DrawHiScores(); break;
            case Scene.NameEntry: DrawBackdrop(); DrawNameEntry(); break;
            case Scene.Achievements: DrawBackdrop(); DrawAchievements(); break;
        }
        Achievements.DrawToast();
    }

    /// <summary>
    /// 縦画面用のステータス領域 (480x190)。
    /// 上段にステージ・残り時間・スコア・残機、中段になわばりの割合、下段に犬ごとの面積。
    /// この上に半透明の操作パッドが重なるので、数字は上のほうに置いてある。
    /// </summary>
    public void MobileDrawStatus()
    {
        var w = _world;
        Gfx.Clear(PanelBg);
        // 上端の光る線 (フィールドとの境目)
        Gfx.Fill(0, 0, StatusW, 1, 0x0C0E18);
        Gfx.Fill(0, 1, StatusW, 1, 0x3A4468);

        if (w == null)
        {
            // タイトル系の画面では、操作の説明を出しておく
            Gfx.Tint(Art.Paw, 0xFFB040);
            Gfx.Draw(Art.Paw, 8, 8, scale: 2);
            Gfx.Text("SHIBA JINTORI", 44, 12, 0xFFB040, 2);
            Gfx.Text($"HI-SCORE {_hi.Top:0000000}", 44, 40, 0xFFE040);
            Gfx.Tint(Art.Paw, 0xFFFFFF);
            Gfx.Text("PAD   : MOVE / SELECT", 12, 70, 0x9AA4C8);
            Gfx.Text("PEE   : DECIDE, PEE ON A POLE", 12, 86, 0x9AA4C8);
            Gfx.Text("START : START, PAUSE", 12, 102, 0x9AA4C8);
            Gfx.Text("SELECT: BACK TO TITLE", 12, 118, 0x9AA4C8);
            Gfx.Text("UP: HIGH SCORES   DOWN: ACHIEVEMENTS", 12, 142, 0x7C86AC);
            Gfx.Text("v" + AppVersion, StatusW - 8 - (AppVersion.Length + 1) * 8, 170, 0x708870);
            return;
        }

        // ---- 上段: ステージと残り時間
        if (w.Bonus) Gfx.Text("BONUS", 10, 8, 0xFFE040, 2);
        else Gfx.Text($"STAGE {w.Stage:00}", 10, 8, 0xFFFFFF, 2);

        int time = (int)MathF.Ceiling(w.TimeLeft);
        uint timeCol = time <= 20 && ((int)(_clock * 4) & 1) == 0 ? 0xFF5050 : 0xFFFFFFu;
        Gfx.Text("TIME", 352, 12, 0x9AA4C8);
        Gfx.Text($"{time,3}", 400, 8, timeCol, 2);

        // ---- スコアとハイスコア
        Gfx.Text("SCORE", 10, 36, 0x9AA4C8);
        Gfx.Text($"{w.Score:0000000}", 58, 32, 0xFFFFFF, 2);
        Gfx.Text("HI", 258, 36, 0x9AA4C8);
        Gfx.Text($"{Math.Max(_hi.Top, w.Score):0000000}", 282, 36, 0xFFE040);

        // ---- 残機
        Gfx.Text("LIVES", 10, 58, 0x9AA4C8);
        if (w.Lives <= 5)
        {
            for (int i = 0; i < w.Lives; i++)
                Gfx.Draw(Art.Dogs[w.Player.BreedIndex][0], 58 + i * 18, 52);
        }
        else
        {
            Gfx.Draw(Art.Dogs[w.Player.BreedIndex][0], 58, 52);
            Gfx.Text($"x {w.Lives}", 80, 58);
        }

        // ---- なわばりの割合 (3/4 でステージ終了。白い目印がその位置)
        int total = World.FW * World.FH;
        Gfx.Text("AREA", 258, 58, 0x9AA4C8);
        Gfx.Text($"{w.Claimed * 100 / total,3}%/75%", 300, 58, 0xFFFFFF);
        const float BarX = 10, BarY = 76, BarW = 460;
        Gfx.Fill(BarX, BarY, BarW, 12, 0x0C0E18);
        float bx = BarX;
        foreach (var d in w.Dogs)
        {
            float bw = d.Area * BarW / total;
            Gfx.Fill(bx, BarY + 1, bw, 10, d.Color);
            bx += bw;
        }
        Gfx.Fill(BarX + BarW * 0.75f, BarY - 2, 1, 16, 0xFFFFFF);

        // ---- 犬ごとの面積 (2列。多いときは左列から詰める)
        int rows = (w.Dogs.Count + 1) / 2;
        for (int i = 0; i < w.Dogs.Count; i++)
        {
            var d = w.Dogs[i];
            float x = i < rows ? 6 : 246, y = 96 + (i % rows) * 19;
            if (d.IsPlayer) Gfx.Fill(x, y - 2, 228, 18, 0x2C3558);
            Gfx.Fill(x, y - 2, 3, 18, d.Color);
            Gfx.Tint(Art.Dogs[d.BreedIndex][0], d.Alive ? 0xFFFFFFu : 0x606060u);
            Gfx.Draw(Art.Dogs[d.BreedIndex][0], x + 6, y);
            Gfx.Tint(Art.Dogs[d.BreedIndex][0], 0xFFFFFF);
            Gfx.Text(d.Alive ? Breed.All[d.BreedIndex].Display : "OUT", x + 26, y, d.Alive ? 0xFFFFFFu : 0x808080u);
            if (!d.IsPlayer)
            {
                string note = !w.Bonus ? d.T.Trait : !d.Alive ? "CAUGHT" : d.Asleep ? "ZZZ" : "AWAKE!";
                Gfx.Text(note, x + 26, y + 9, w.Bonus && d.Alive && !d.Asleep ? 0xFFF060u : 0x7C86ACu, shadow: false);
            }
            else Gfx.Text("(YOU)", x + 26, y + 9, 0xFFE040, shadow: false);
            Gfx.Text($"{d.Area,3}", x + 196, y + 4, d.Color);
        }
    }
}
