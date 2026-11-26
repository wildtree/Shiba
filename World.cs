namespace ShibaJintori;

public enum Dir { Down, Left, Right, Up }

public sealed class Dog
{
    public int Id;
    public int BreedIndex;
    public bool IsPlayer;
    public uint Color;

    public int X, Y;            // 現在のマス(移動中は移動先)
    public int FromX, FromY;    // 移動元のマス
    public Dir Dir = Dir.Down;
    public bool Moving;
    public float MoveT;
    public float StepTime = 0.15f;
    public bool StepFlip;

    public float PeeT;          // >0 の間はおしっこ中で動けない
    public int PeePole = -1;
    public readonly List<int> Chain = new();   // おしっこ済みで、まだなわばりになっていない電柱

    public bool Alive = true;
    public float Invuln;
    public int Area;

    public float Carry;         // 前の一歩で余った時間(歩く速さを一定に保つ)

    public bool Asleep;         // ボーナスステージ: 眠っている
    public float AwakeUntil;    // ボーナスステージ: この時刻(World.Clock)まで逃げ回り、そのあとまた眠る

    public bool Boss;           // ボス犬: なわばりを踏み越え、なわばりごと奪う
    public float PeeTotal = World.PeeTime;   // 今のおしっこにかかる時間
    public float BoneT;         // 骨の効果の残り時間(おしっこが速くなる)
    public float PassT;         // 巻物の効果の残り時間(ほかのなわばりを通れる)

    // AI用
    public int Target = -1;
    public float Think;
    public Temper T = Temper.Default;
    public int Steps;           // 次に休むまでの歩数
}

public sealed class Pole
{
    public int X, Y;
    public int Owner = -1;      // おしっこをひっかけた犬
    public bool Locked;         // なわばりに含まれた(のっとり不可)
}

public sealed class Car
{
    public float X;
    public int Row;
    public int Sign;            // -1: 左へ / +1: 右へ
    public float Speed;
    public int Color;
}

public sealed class Item
{
    public int X, Y;
    public int Kind;            // 0:骨 1:忍者の巻物
    public float T;             // 消えるまでの残り時間
}

public sealed class Popup
{
    public float X, Y, T;
    public string Text = "";
    public uint Color;
}

/// <summary>1ステージ分のゲーム状態とルール。描画とは独立している。</summary>
public sealed class World
{
    public const int FW = 30, FH = 25, Tile = 16;
    public const float PeeTime = 3f;
    public const int GoalCells = (FW * FH * 3 + 3) / 4;   // 全体の3/4
    public const float StageTime = 240f;

    // 追加要素が始まるステージ (調整用)
    public const int ItemFromStage = 5;     // アイテムが出はじめる
    public const int RainFromStage = 8;     // 雨が降りはじめる
    public const int BossEvery = 8;         // この倍数のステージにボス犬が出る
    public const float BossPeeTime = 5f;

    // 夜のボーナスステージ: 眠っている犬を起こさないように囲む。残機は減らない
    public const float BonusTime = 60f;
    public const int BonusCellScore = 30, BonusSleeping = 2000, BonusAwake = 1000, BonusPerfect = 5000;
    public const int WakeWalk = 2;          // 柴犬がこの距離(マス)まで近づくと起きる
    public const int WakePee = 3;           // この距離でおしっこをすると起きる
    public const float ItemLife = 12f, BoneTime = 12f, PassTime = 10f;

    public readonly int Stage;
    public readonly bool Demo;
    public readonly bool Bonus;
    public int BonusCaught;     // ボーナスステージで囲んだ犬の数
    public int Misses;          // このステージでミスした回数 (実績用)
    public bool Perfect;        // ボーナスステージで全員囲んだ
    public int Score, Lives;
    public float TimeLeft = StageTime;
    public int Claimed;
    public bool Finished, Cleared, GameOver;
    public float Clock;

    public readonly int[,] Terr = new int[FW, FH];
    public readonly float[,] Flash = new float[FW, FH];
    public readonly int[,] PoleAt = new int[FW, FH];
    public readonly int[] LaneOf = new int[FH];          // 0:なし 1:左行き車線 2:右行き車線
    public readonly List<Pole> Poles = new();
    public readonly List<Dog> Dogs = new();
    public readonly List<Car> Cars = new();
    public readonly List<Popup> Popups = new();
    public readonly List<Item> Items = new();
    public Dog Player => Dogs[0];
    public bool HasBoss;
    public float RainWarn;      // >0: まもなく雨が降る(予告中)
    public float RainT;         // >0: 雨が降っている
    float _rainNext = float.MaxValue;
    float _itemSpawn = 6f;
    readonly bool[] _fresh = new bool[FW * FH];   // 今回のなわばりで新しく取ったマス

    readonly Random _rng;
    readonly float[] _laneSpawn = new float[FH];
    readonly float[] _laneSpeed = new float[FH];
    float _actionBuffer;
    float _dripT;
    Dir _dirBuffer;
    float _dirBufferT;

    // 作業用バッファ
    readonly bool[] _inTri = new bool[FW * FH];
    readonly int[] _dist = new int[FW * FH];
    readonly int[] _queue = new int[FW * FH];
    readonly List<int> _cells = new();

    static readonly int[] DX = [0, -1, 1, 0];
    static readonly int[] DY = [1, 0, 0, -1];

    public World(int stage, int shibaColor, int lives, int score, bool demo, int? seed = null, bool bonus = false)
    {
        Stage = stage; Demo = demo; Lives = lives; Score = score; Bonus = bonus;
        if (bonus) TimeLeft = BonusTime;
        _rng = seed is int s ? new Random(s) : new Random();
        Generate(shibaColor);
    }

    /// <summary>実績を解除する (デモ画面では解除しない)。</summary>
    void Ach(string id)
    {
        if (!Demo) Achievements.Unlock(id);
    }

    // ------------------------------------------------------------ 生成

    void Generate(int shibaColor)
    {
        for (int y = 0; y < FH; y++)
            for (int x = 0; x < FW; x++) { Terr[x, y] = -1; PoleAt[x, y] = -1; }

        // 道路(2車線)
        int roads = Bonus ? 0 : Stage >= 4 ? 2 : 1;   // ボーナスステージは道路なし
        var tops = new List<int>();
        for (int tries = 0; tops.Count < roads && tries < 300; tries++)
        {
            int r = _rng.Next(4, FH - 6);
            bool ok = true;
            foreach (int t in tops) if (Math.Abs(t - r) < 6) ok = false;
            if (ok) tops.Add(r);
        }
        foreach (int t in tops)
        {
            LaneOf[t] = 1; LaneOf[t + 1] = 2;
            for (int k = 0; k < 2; k++)
            {
                _laneSpeed[t + k] = Math.Min(210f, 95f + _rng.Next(60) + Stage * 5);
                _laneSpawn[t + k] = 1f + (float)_rng.NextDouble() * 3f;
            }
        }

        // 電柱: 5x5のブロックごとに1本。外周のブロックは端に寄せて、なわばりが全体を覆えるようにする
        for (int by = 0; by < 5; by++)
            for (int bx = 0; bx < 6; bx++)
                for (int tries = 0; tries < 60; tries++)
                {
                    int x = bx * 5 + _rng.Next(5), y = by * 5 + _rng.Next(5);
                    if (bx == 0) x = _rng.Next(2);
                    if (bx == 5) x = FW - 1 - _rng.Next(2);
                    if (by == 0) y = _rng.Next(2);
                    if (by == 4) y = FH - 1 - _rng.Next(2);
                    if (LaneOf[y] != 0) continue;
                    bool near = false;
                    foreach (var p in Poles)
                        if (Math.Abs(p.X - x) <= 1 && Math.Abs(p.Y - y) <= 1) near = true;
                    if (near) continue;
                    PoleAt[x, y] = Poles.Count;
                    Poles.Add(new Pole { X = x, Y = y });
                    break;
                }

        // 柴犬(プレイヤー)
        var player = new Dog
        {
            Id = 0, IsPlayer = true, BreedIndex = shibaColor,
            Color = Breed.All[shibaColor].TerritoryColor, StepTime = 0.14f,
        };
        (player.X, player.Y) = FindCell((x, y) => Math.Abs(x - FW / 2) <= 4 && Math.Abs(y - FH / 2) <= 4);
        player.FromX = player.X; player.FromY = player.Y;
        Dogs.Add(player);

        if (Stage >= RainFromStage && !Bonus) _rainNext = 22f + (float)_rng.NextDouble() * 20f;

        // 敵の犬: ステージ1は1匹、以後1匹ずつ増えて最大8匹。ボスのステージは 7匹 + ボス
        HasBoss = !Bonus && Stage >= BossEvery && Stage % BossEvery == 0;
        int enemies = Math.Clamp(Stage, 1, 8);
        for (int i = 0; i < enemies; i++)
        {
            bool boss = HasBoss && i == enemies - 1;
            int breed = boss ? Breed.BossIndex : Breed.ShibaCount + i % Breed.EnemyBreedCount;
            var temper = Temper.For(Breed.All[breed]);
            float baseStep = Math.Max(0.17f, 0.30f - 0.012f * (Stage - 1)) + (float)_rng.NextDouble() * 0.03f;
            var d = new Dog
            {
                Id = Dogs.Count, BreedIndex = breed, Color = Breed.All[breed].TerritoryColor, T = temper,
                StepTime = Math.Max(0.12f, baseStep * temper.Speed),
                Think = 0.5f + (float)_rng.NextDouble(),
                Steps = temper.Stamina, Boss = boss, Asleep = Bonus,
            };
            if (Bonus) d.StepTime = 0.2f;
            (d.X, d.Y) = FindCell((x, y) =>
            {
                foreach (var o in Dogs)
                    if (Math.Abs(o.X - x) + Math.Abs(o.Y - y) < (o.IsPlayer ? 9 : 4)) return false;
                return true;
            });
            d.FromX = d.X; d.FromY = d.Y;
            Dogs.Add(d);
        }
    }

    bool IsFree(int x, int y) =>
        x >= 0 && y >= 0 && x < FW && y < FH && PoleAt[x, y] < 0 && LaneOf[y] == 0 && Terr[x, y] < 0;

    (int, int) FindCell(Func<int, int, bool> extra)
    {
        for (int tries = 0; tries < 2000; tries++)
        {
            int x = _rng.Next(FW), y = _rng.Next(FH);
            if (IsFree(x, y) && (tries > 1000 || extra(x, y))) return (x, y);
        }
        for (int y = 0; y < FH; y++)
            for (int x = 0; x < FW; x++)
                if (PoleAt[x, y] < 0 && Terr[x, y] < 0) return (x, y);
        for (int y = 0; y < FH; y++)
            for (int x = 0; x < FW; x++)
                if (PoleAt[x, y] < 0) return (x, y);
        return (0, 0);
    }

    // ------------------------------------------------------------ 更新

    /// <param name="held">押しっぱなしの方向</param>
    /// <param name="tapped">このフレームに押された方向(移動中の短い押下を取りこぼさないために覚えておく)</param>
    public void Update(float dt, Dir? held, bool actionPressed, Dir? tapped = null)
    {
        if (Finished || GameOver) return;
        Clock += dt;
        TimeLeft -= dt;
        if (TimeLeft <= 0) { TimeLeft = 0; Finish(); return; }

        for (int y = 0; y < FH; y++)
            for (int x = 0; x < FW; x++)
                if (Flash[x, y] > 0) Flash[x, y] = Math.Max(0, Flash[x, y] - dt);
        for (int i = Popups.Count - 1; i >= 0; i--)
        {
            Popups[i].T -= dt; Popups[i].Y -= dt * 14;
            if (Popups[i].T <= 0) Popups.RemoveAt(i);
        }

        if (actionPressed) _actionBuffer = 0.25f;
        else if (_actionBuffer > 0) _actionBuffer -= dt;
        if (tapped is Dir tap) { _dirBuffer = tap; _dirBufferT = 0.3f; }
        else if (_dirBufferT > 0) _dirBufferT -= dt;

        UpdateCars(dt);
        if (GameOver) return;
        UpdateRain(dt);
        UpdateItems(dt);

        for (int i = 0; i < Dogs.Count; i++)
        {
            var d = Dogs[i];
            if (!d.Alive) continue;
            if (d.Invuln > 0) d.Invuln -= dt;

            if (d.Moving)
            {
                d.MoveT += dt;
                if (d.MoveT >= d.StepTime) { d.Moving = false; d.Carry = Math.Min(d.MoveT - d.StepTime, d.StepTime * 0.4f); }
            }
            else if (d.PeeT > 0)
            {
                d.PeeT -= dt;
                if (d.IsPlayer)
                {
                    _dripT -= dt;
                    if (_dripT <= 0) { _dripT = 0.13f; Audio.Play(Sfx.PeeDrip); }
                }
                if (d.PeeT <= 0) { d.PeeT = 0; CompletePee(d); }
            }
            if (Finished || GameOver) return;
            if (!d.Alive || d.Moving || d.PeeT > 0) continue;

            if (d.IsPlayer && !Demo) PlayerControl(d, held);
            else if (Bonus && !d.IsPlayer) BonusAi(d);
            else AiControl(d, dt);
            d.Carry = 0;
        }

        // 身動きが取れなくなった柴犬は囲まれた扱い
        var pl = Player;
        if (!Bonus && !pl.Moving && pl.PeeT <= 0 && pl.Invuln <= 0)
        {
            bool stuck = true;
            for (int k = 0; k < 4; k++) if (CanEnter(pl, pl.X + DX[k], pl.Y + DY[k])) stuck = false;
            if (stuck) { AddPopup(pl, "TRAPPED!", 0xFF4040); LoseLife(); }
        }
    }

    void PlayerControl(Dog d, Dir? held)
    {
        if (_actionBuffer > 0)
        {
            int p = PoleInFront(d);
            if (p < 0)
                for (int k = 0; k < 4 && p < 0; k++)
                {
                    int nx = d.X + DX[k], ny = d.Y + DY[k];
                    if (nx >= 0 && ny >= 0 && nx < FW && ny < FH && PoleAt[nx, ny] >= 0) { p = PoleAt[nx, ny]; d.Dir = (Dir)k; }
                }
            if (p >= 0)
            {
                _actionBuffer = 0;
                if (d.Chain.Contains(p)) { Audio.Play(Sfx.Invalid); AddPopup(d, "MARKED", 0xFFFFFF); }
                else { StartPee(d, p); return; }
            }
        }
        // 押しっぱなしの方向を優先し、なければ直前に押された方向(先行入力)を使う
        Dir? want = held;
        if (want == null && _dirBufferT > 0) want = _dirBuffer;
        if (want is Dir dir)
        {
            _dirBufferT = 0;
            if (TryMove(d, dir))
            {
                Audio.Play(Sfx.Step);
                int t = Terr[d.X, d.Y];
                if (d.PassT > 0 && t >= 0 && t != d.Id) Ach("NINJA");
            }
        }
    }

    /// <summary>いまおしっこ中の電柱で三角形が完成する場合、それがなわばりとして成立するか(予告線の色分け用)。</summary>
    public bool? PeeOutcome(Dog d)
    {
        if (d.PeePole < 0 || d.Chain.Contains(d.PeePole) || d.Chain.Count < 2) return null;
        return Evaluate(d.Id, d.Chain[^2], d.Chain[^1], d.PeePole, null) > 0;
    }

    int PoleInFront(Dog d)
    {
        int nx = d.X + DX[(int)d.Dir], ny = d.Y + DY[(int)d.Dir];
        return nx >= 0 && ny >= 0 && nx < FW && ny < FH ? PoleAt[nx, ny] : -1;
    }

    /// <summary>他の犬のなわばりと電柱には入れない。ボス犬と、巻物の効果中の犬は、なわばりを通れる。</summary>
    public bool CanEnter(Dog d, int x, int y) =>
        x >= 0 && y >= 0 && x < FW && y < FH && PoleAt[x, y] < 0
        && (Terr[x, y] < 0 || Terr[x, y] == d.Id || d.Boss || d.PassT > 0);

    bool TryMove(Dog d, Dir dir)
    {
        d.Dir = dir;
        int nx = d.X + DX[(int)dir], ny = d.Y + DY[(int)dir];
        if (!CanEnter(d, nx, ny)) return false;
        d.FromX = d.X; d.FromY = d.Y; d.X = nx; d.Y = ny;
        d.Moving = true; d.MoveT = d.Carry; d.Carry = 0; d.StepFlip = !d.StepFlip;
        return true;
    }

    void StartPee(Dog d, int pole)
    {
        d.PeeTotal = (d.Boss ? BossPeeTime : PeeTime) * (d.BoneT > 0 ? 0.5f : 1f);
        d.PeeT = d.PeeTotal; d.PeePole = pole;
        if (d.IsPlayer) _dripT = 0;
    }

    void CompletePee(Dog d)
    {
        int idx = d.PeePole;
        d.PeePole = -1;
        if (idx < 0) return;
        var pole = Poles[idx];
        if (!pole.Locked)
        {
            // なわばりになっていない電柱は上書きできる
            if (pole.Owner >= 0 && pole.Owner != d.Id)
            {
                var prev = Dogs[pole.Owner];
                prev.Chain.Remove(idx);
                if (d.IsPlayer || prev.IsPlayer) Audio.Play(Sfx.Overwrite);
                if (d.IsPlayer) Ach("OVERWRITE");
                if (prev.IsPlayer) AddPopup(pole.X, pole.Y, "LOST!", 0xFF6060);
            }
            pole.Owner = d.Id;
        }
        else
        {
            // なわばりの頂点になった電柱は共有できるが、印は 1 匹分だけ。
            // ほかの犬がつけていた印は消える (上書き)
            foreach (var o in Dogs)
            {
                if (o == d || !o.Chain.Remove(idx)) continue;
                if (d.IsPlayer || o.IsPlayer) Audio.Play(Sfx.Overwrite);
                if (d.IsPlayer) Ach("OVERWRITE");
                if (o.IsPlayer) AddPopup(pole.X, pole.Y, "LOST!", 0xFF6060);
            }
        }
        d.Chain.Remove(idx);
        d.Chain.Add(idx);
        if (d.IsPlayer) Audio.Play(Sfx.Mark);
        if (d.Chain.Count >= 3) TryTerritory(d);
    }

    void TryTerritory(Dog d)
    {
        int a = d.Chain[^3], b = d.Chain[^2], c = d.Chain[^1];
        _cells.Clear();
        int n = Evaluate(d.Id, a, b, c, _cells);
        if (n <= 0)
        {
            // 作れない三角形(他のなわばりと重なる・一直線など)。印は全部取り消して最初からやり直し
            foreach (int pi in d.Chain)
                if (!Poles[pi].Locked && Poles[pi].Owner == d.Id) Poles[pi].Owner = -1;
            d.Chain.Clear();
            if (d.IsPlayer) { Audio.Play(Sfx.Invalid); AddPopup(d, "NO GOOD", 0xFFFFFF); }
            return;
        }

        Array.Clear(_fresh);
        foreach (int i in _cells)
        {
            // ボス犬の場合は、ほかの犬のなわばりだったマスも含まれる(奪い取る)
            int prev = Terr[i % FW, i / FW];
            if (prev >= 0) Dogs[prev].Area--; else Claimed++;
            Terr[i % FW, i / FW] = d.Id;
            Flash[i % FW, i / FW] = 1f;
            _fresh[i] = true;
        }
        d.Area += n;
        d.Chain.Clear();
        Items.RemoveAll(it => Terr[it.X, it.Y] >= 0);   // なわばりになった場所のアイテムは消える
        for (int i = 0; i < Poles.Count; i++)
        {
            var p = Poles[i];
            if (Terr[p.X, p.Y] != d.Id || (p.Locked && p.Owner == d.Id)) continue;
            p.Locked = true; p.Owner = d.Id;
            // なわばりに取り込まれた電柱についていた、ほかの犬の印は解除する。
            // おしっこ中の印も同じ扱いにする (3 秒の間に取り込まれたのに、終わったら印がつくのはおかしい)。
            // すでに取り込まれている電柱におしっこをする(電柱の共有)のはかまわない
            foreach (var o in Dogs)
            {
                if (o == d) continue;
                bool lost = o.Chain.Remove(i);
                if (o.PeePole == i) { o.PeeT = 0; o.PeePole = -1; lost = true; }
                if (lost && o.IsPlayer) AddPopup(p.X, p.Y, "LOST!", 0xFF6060);
            }
        }

        if (d.IsPlayer)
        {
            int gain = n * (Bonus ? BonusCellScore : 10);
            Score += gain;
            AddPopup(d, "+" + gain, 0xFFFF60);
            Audio.Play(Sfx.Territory);
            Ach("FIRST_TURF");
            if (n >= 100) Ach("BIG_TURF");
            if (d.Area * 2 >= FW * FH) Ach("HALF");
        }
        else Audio.Play(Sfx.EnemyTerritory);

        // 囲まれた犬の処理
        int caught = 0;
        foreach (var o in Dogs)
        {
            // 今回新しく取ったマスにいる犬だけが対象 (巻物で以前からのなわばりに入り込んでいる犬は対象外)
            if (!o.Alive || o == d || !_fresh[o.Y * FW + o.X]) continue;
            if (o.IsPlayer)
            {
                AddPopup(o, "CAUGHT!", 0xFF4040);
                Ach("GOT_CAUGHT");
                LoseLife();
                if (GameOver) return;
            }
            else
            {
                o.Alive = false;
                o.Chain.Clear();
                foreach (var p in Poles)
                    if (!p.Locked && p.Owner == o.Id) p.Owner = -1;
                int bonus = Bonus ? (o.Asleep ? BonusSleeping : BonusAwake) : o.Boss ? 3000 : 500;
                if (Bonus) BonusCaught++;
                AddPopup(o, d.IsPlayer ? "OUT! +" + bonus : "OUT!", 0xFFFFFF);
                if (d.IsPlayer)
                {
                    Score += bonus;
                    caught++;
                    Ach("CATCH_DOG");
                    if (o.Boss) Ach("BOSS_DOWN");
                }
                Audio.Play(Sfx.EnemyOut);
            }
        }
        if (caught >= 2) Ach("DOUBLE_CATCH");

        if (Bonus)
        {
            // 全員囲んだらパーフェクトで終了
            bool any = false;
            foreach (var o in Dogs) if (!o.IsPlayer && o.Alive) any = true;
            if (!any) { Perfect = true; Score += BonusPerfect; Finish(); }
            return;
        }
        if (Claimed >= GoalCells) Finish();
    }

    /// <summary>
    /// 電柱 a,b,c の三角形で新しく取れるマス数を返す。作れない場合は -1。
    /// 作れない条件: 一直線 / 新しく取れるマスがない / 三角形の内側に他の犬のなわばりが少しでもある
    /// (細い三角形がなわばりのマスのあいだをすり抜ける場合も含む。CrossesOther を参照)。
    /// (辺の上や頂点の電柱で接しているだけなら可。隣り合うなわばりや、電柱の共有はできる)
    /// ボス犬だけは例外で、内側にあるほかの犬のなわばりも「取れるマス」に数える(奪い取る)。
    /// 呼び出し後 _inTri に三角形内のマスが入っている。
    /// </summary>
    int Evaluate(int id, int a, int b, int c, List<int>? outCells)
    {
        Pole A = Poles[a], B = Poles[b], C = Poles[c];
        int area2 = (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X);
        if (area2 == 0) return -1;
        Array.Clear(_inTri);
        int minX = Math.Min(A.X, Math.Min(B.X, C.X)), maxX = Math.Max(A.X, Math.Max(B.X, C.X));
        int minY = Math.Min(A.Y, Math.Min(B.Y, C.Y)), maxY = Math.Max(A.Y, Math.Max(B.Y, C.Y));
        int n = 0;
        bool other = false;
        bool steal = Dogs[id].Boss;
        for (int y = minY; y <= maxY; y++)
            for (int x = minX; x <= maxX; x++)
            {
                int d1 = (B.X - A.X) * (y - A.Y) - (B.Y - A.Y) * (x - A.X);
                int d2 = (C.X - B.X) * (y - B.Y) - (C.Y - B.Y) * (x - B.X);
                int d3 = (A.X - C.X) * (y - C.Y) - (A.Y - C.Y) * (x - C.X);
                bool neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
                if (neg && pos) continue;
                int i = y * FW + x;
                _inTri[i] = true;
                int t = Terr[x, y];
                if (t < 0) { n++; outCells?.Add(i); }
                else if (t != id)
                {
                    if (steal) { n++; outCells?.Add(i); }
                    else if (d1 != 0 && d2 != 0 && d3 != 0) other = true;
                }
            }
        if (n == 0 || other) return -1;
        if (!steal && CrossesOther(id, A, B, C, area2, minX, maxX, minY, maxY)) return -1;
        return n;
    }

    static readonly int[] CrossDX = [1, 0, 1, -1], CrossDY = [0, 1, 1, 1];

    /// <summary>
    /// 細い三角形が、ほかの犬のなわばりのマスの中心と中心のあいだをすり抜けていないか。
    /// マスの中心だけで見ると、高さが 1 マスもない三角形はなわばりを素通りできてしまう。
    /// そこで、同じ犬のなわばりで隣り合う(斜めも含む) 2 マスの中心を結ぶ線分が、
    /// 三角形の内側(辺は含まない)を通っていたら「横切っている」とみなす。
    /// 辺や頂点で接しているだけ(共有)なら、その線分は辺の外側か辺の上にしかないので引っかからない。
    /// </summary>
    bool CrossesOther(int id, Pole A, Pole B, Pole C, int area2, int minX, int maxX, int minY, int maxY)
    {
        int s = area2 > 0 ? 1 : -1;
        for (int y = minY; y <= maxY; y++)
            for (int x = minX; x <= maxX; x++)
            {
                int t = Terr[x, y];
                if (t < 0 || t == id) continue;
                for (int k = 0; k < 4; k++)
                {
                    int qx = x + CrossDX[k], qy = y + CrossDY[k];
                    // 箱の外へ出る線分は、三角形の内側には届かない
                    if (qx < minX || qx > maxX || qy > maxY || Terr[qx, qy] != t) continue;
                    if (SegmentInside(A, B, C, s, x, y, qx, qy)) return true;
                }
            }
        return false;
    }

    /// <summary>線分 (px,py)-(qx,qy) が三角形の内側(辺は含まない)を通るか。分離軸で調べる。</summary>
    static bool SegmentInside(Pole A, Pole B, Pole C, int s, int px, int py, int qx, int qy)
    {
        // 三角形の辺: 両端とも辺の外側か辺の上なら、内側には入らない (s を掛けると内側が正)
        if (OutOrOn(A, B, s, px, py, qx, qy) || OutOrOn(B, C, s, px, py, qx, qy) || OutOrOn(C, A, s, px, py, qx, qy))
            return false;
        // 線分の向き: 3 つの頂点がすべて線分の片側(線上を含む)にあれば、内側は線分に触れない
        int ux = qx - px, uy = qy - py;
        int ca = ux * (A.Y - py) - uy * (A.X - px);
        int cb = ux * (B.Y - py) - uy * (B.X - px);
        int cc = ux * (C.Y - py) - uy * (C.X - px);
        if ((ca >= 0 && cb >= 0 && cc >= 0) || (ca <= 0 && cb <= 0 && cc <= 0)) return false;
        return true;
    }

    static bool OutOrOn(Pole P, Pole Q, int s, int px, int py, int qx, int qy)
    {
        int ep = s * ((Q.X - P.X) * (py - P.Y) - (Q.Y - P.Y) * (px - P.X));
        int eq = s * ((Q.X - P.X) * (qy - P.Y) - (Q.Y - P.Y) * (qx - P.X));
        return ep <= 0 && eq <= 0;
    }

    void LoseLife()
    {
        var d = Player;
        Misses++;
        Audio.Play(Sfx.Miss);
        if (!Demo)
        {
            Lives--;
            if (Lives <= 0) { Lives = 0; GameOver = true; return; }
        }
        Respawn(d);
        d.Invuln = 3f;
    }

    void Respawn(Dog d)
    {
        d.PeeT = 0; d.PeePole = -1; d.Moving = false; d.Target = -1;
        (d.X, d.Y) = FindCell((x, y) =>
        {
            for (int k = 0; k < 4; k++) if (IsFree(x + DX[k], y + DY[k])) return true;
            return false;
        });
        d.FromX = d.X; d.FromY = d.Y;
    }

    void Finish()
    {
        if (Finished) return;
        Finished = true;
        if (Bonus) { Cleared = true; return; }
        int best = 0;
        foreach (var d in Dogs) if (!d.IsPlayer && d.Area > best) best = d.Area;
        Cleared = Player.Area > 0 && Player.Area >= best;
    }

    /// <summary>柴犬の頭上に文字を出す(残機が増えたときなど)。</summary>
    public void Announce(string text, uint color) => AddPopup(Player.X, Player.Y - 1, text, color);

    void AddPopup(Dog d, string text, uint color) => AddPopup(d.X, d.Y, text, color);

    void AddPopup(int cx, int cy, string text, uint color)
    {
        float x = Math.Clamp(cx * Tile + 8 - text.Length * 4, 2, FW * Tile - text.Length * 8 - 2);
        Popups.Add(new Popup { X = x, Y = cy * Tile - 6, T = 1.4f, Text = text, Color = color });
    }

    // ------------------------------------------------------------ 雨とアイテム

    /// <summary>
    /// 雨: 5秒の予告のあと降りだし、降りだした瞬間に「まだなわばりになっていない印」が全部流れる。
    /// なわばりになった電柱と、なわばりそのものは残る。
    /// </summary>
    void UpdateRain(float dt)
    {
        if (RainT > 0) { RainT -= dt; return; }
        if (RainWarn > 0)
        {
            RainWarn -= dt;
            if (RainWarn > 0) return;
            RainWarn = 0;
            RainT = 4f;
            _rainNext = 35f + (float)_rng.NextDouble() * 25f;
            foreach (var p in Poles) if (!p.Locked) p.Owner = -1;
            foreach (var d in Dogs)
            {
                if (d.IsPlayer && d.Alive && d.Chain.Count > 0)
                {
                    AddPopup(d, "WASHED AWAY!", 0x80C0FF);
                    Ach("WASHED");
                }
                d.Chain.Clear();
                d.Target = -1;
            }
            Audio.Play(Sfx.Rain);
            return;
        }
        _rainNext -= dt;
        if (_rainNext <= 0) { RainWarn = 5f; Audio.Play(Sfx.Thunder); }
    }

    /// <summary>
    /// アイテム: なわばりの外に現れ、一定時間で消える。踏んだ犬が拾う(敵も拾う)。
    ///  骨   … しばらくおしっこの時間が半分になる
    ///  巻物 … しばらくほかの犬のなわばりを通り抜けられる。切れたときに他のなわばりの中にいると外へ放り出される
    /// </summary>
    void UpdateItems(float dt)
    {
        for (int i = Items.Count - 1; i >= 0; i--)
        {
            Items[i].T -= dt;
            if (Items[i].T <= 0) Items.RemoveAt(i);
        }

        if (Stage >= ItemFromStage && !Bonus)
        {
            _itemSpawn -= dt;
            if (_itemSpawn <= 0)
            {
                _itemSpawn = 9f + (float)_rng.NextDouble() * 9f;
                if (Items.Count < 2)
                {
                    var (x, y) = FindCell((cx, cy) =>
                    {
                        foreach (var o in Dogs) if (o.Alive && Math.Abs(o.X - cx) + Math.Abs(o.Y - cy) < 3) return false;
                        foreach (var it in Items) if (it.X == cx && it.Y == cy) return false;
                        return true;
                    });
                    if (IsFree(x, y)) Items.Add(new Item { X = x, Y = y, Kind = _rng.Next(3) == 0 ? 1 : 0, T = ItemLife });
                }
            }
        }

        foreach (var d in Dogs)
        {
            if (!d.Alive) continue;
            if (d.BoneT > 0) d.BoneT -= dt;
            if (d.PassT > 0)
            {
                d.PassT -= dt;
                int t = Terr[d.X, d.Y];
                if (d.PassT <= 0 && !d.Boss && t >= 0 && t != d.Id)
                {
                    // 効果が切れたとき他のなわばりの中にいたら、外へ放り出される(残機は減らない)
                    AddPopup(d, "KICKED OUT!", 0xC0A0FF);
                    if (d.IsPlayer) Audio.Play(Sfx.Kicked);
                    Respawn(d);
                    d.Invuln = 1.5f;
                }
            }

            for (int i = Items.Count - 1; i >= 0; i--)
            {
                var it = Items[i];
                if (it.X != d.X || it.Y != d.Y) continue;
                Items.RemoveAt(i);
                if (it.Kind == 0)
                {
                    d.BoneT = BoneTime;
                    AddPopup(d, d.IsPlayer ? "BONE! +100" : "BONE!", 0xFFFFFF);
                    if (d.IsPlayer) Ach("BONE");
                }
                else { d.PassT = PassTime; AddPopup(d, d.IsPlayer ? "NINJA! +100" : "NINJA!", 0xC0A0FF); }
                if (d.IsPlayer) { Score += 100; Audio.Play(Sfx.Item); }
            }
        }
    }

    // ------------------------------------------------------------ 車

    void UpdateCars(float dt)
    {
        for (int r = 0; r < FH; r++)
        {
            if (LaneOf[r] == 0) continue;
            _laneSpawn[r] -= dt;
            if (_laneSpawn[r] > 0) continue;
            int sign = LaneOf[r] == 1 ? -1 : 1;
            Cars.Add(new Car { Row = r, Sign = sign, Speed = _laneSpeed[r], X = sign < 0 ? FW * Tile : -32, Color = _rng.Next(4) });
            _laneSpawn[r] = Math.Max(1.5f, 5.5f - Stage * 0.3f) * (0.6f + (float)_rng.NextDouble() * 0.9f);
        }
        for (int i = Cars.Count - 1; i >= 0; i--)
        {
            var c = Cars[i];
            c.X += c.Sign * c.Speed * dt;
            if (c.X < -40 || c.X > FW * Tile + 8) { Cars.RemoveAt(i); continue; }
            foreach (var d in Dogs)
            {
                if (!d.Alive || d.Invuln > 0) continue;
                var (px, py, _) = DogPixel(d);
                if (px + 13 < c.X + 2 || px + 3 > c.X + 30 || py + 13 < c.Row * Tile + 3 || py + 3 > c.Row * Tile + 14) continue;
                Audio.Play(Sfx.CarHit);
                if (d.IsPlayer)
                {
                    AddPopup(d, "OUCH!", 0xFF4040);
                    Ach("CAR_HIT");
                    LoseLife();
                    if (GameOver) return;
                }
                else
                {
                    AddPopup(d, "KYAN!", 0xFFFFFF);
                    Respawn(d);
                    d.Invuln = 2f; d.Think = 1f;
                }
            }
        }
    }

    /// <summary>t秒以内に(x,row)のマスへ車が来るか。</summary>
    bool CarDanger(int x, int row, float t)
    {
        float cx0 = x * Tile - 6, cx1 = x * Tile + Tile + 6;
        foreach (var c in Cars)
        {
            if (c.Row != row) continue;
            float a = c.X, b = c.X + c.Sign * c.Speed * t;
            float lo = Math.Min(a, b), hi = Math.Max(a, b) + 32;
            if (hi > cx0 && lo < cx1) return true;
        }
        // これから画面外から入ってくる車
        if (LaneOf[row] != 0 && _laneSpawn[row] < t)
        {
            float reach = _laneSpeed[row] * (t - Math.Max(0, _laneSpawn[row]));
            if (LaneOf[row] == 1 ? FW * Tile - reach < cx1 : -32 + reach + 32 > cx0) return true;
        }
        return false;
    }

    /// <summary>描画位置。移動の前半は8ドットずらした位置で足を伸ばした絵、後半は移動先で立ち絵。</summary>
    public (float x, float y, bool stride) DogPixel(Dog d)
    {
        if (d.Moving && d.MoveT < d.StepTime * 0.5f)
            return (d.FromX * Tile + (d.X - d.FromX) * 8, d.FromY * Tile + (d.Y - d.FromY) * 8, true);
        return (d.X * Tile, d.Y * Tile, false);
    }

    // ------------------------------------------------------------ ボーナスステージの犬

    /// <summary>
    /// 眠っている犬は、柴犬が近づくか近くでおしっこをすると目を覚ます。
    /// 起きた犬は数秒間、柴犬から離れるように逃げ、十分離れたらまた眠る。
    /// </summary>
    void BonusAi(Dog d)
    {
        var pl = Player;
        int dist = Math.Abs(pl.X - d.X) + Math.Abs(pl.Y - d.Y);
        if (d.Asleep)
        {
            if (dist > WakeWalk && !(pl.PeeT > 0 && dist <= WakePee)) return;
            d.Asleep = false;
            d.AwakeUntil = Clock + 5f;
            AddPopup(d, "!?", 0xFFFF60);
            Audio.Play(Sfx.Bark);
            return;
        }
        if (Clock >= d.AwakeUntil && dist >= 6)
        {
            d.Asleep = true; d.Dir = Dir.Down;
            return;
        }
        // 柴犬からいちばん遠ざかる方向へ(少し気まぐれ)
        int best = -1;
        double bestScore = double.MinValue;
        for (int k = 0; k < 4; k++)
        {
            int nx = d.X + DX[k], ny = d.Y + DY[k];
            if (!CanEnter(d, nx, ny)) continue;
            double s = Math.Abs(pl.X - nx) + Math.Abs(pl.Y - ny) + _rng.NextDouble() * 1.5;
            if (s > bestScore) { bestScore = s; best = k; }
        }
        if (best >= 0) TryMove(d, (Dir)best);
    }

    // ------------------------------------------------------------ 敵AI

    void AiControl(Dog d, float dt)
    {
        d.Think -= dt;
        if (d.Think > 0) return;

        if (d.Target >= 0 && d.Chain.Contains(d.Target)) d.Target = -1;
        if (d.Target < 0)
        {
            ChooseTarget(d);
            if (d.Target < 0) { Wander(d); d.Think = 0.25f; return; }
        }

        var pole = Poles[d.Target];
        if (Math.Abs(pole.X - d.X) + Math.Abs(pole.Y - d.Y) == 1)
        {
            for (int k = 0; k < 4; k++)
                if (d.X + DX[k] == pole.X && d.Y + DY[k] == pole.Y) d.Dir = (Dir)k;
            if (d.Chain.Count >= 2 && Evaluate(d.Id, d.Chain[^2], d.Chain[^1], d.Target, null) < 0)
            {
                d.Target = -1;      // 状況が変わって三角形が作れなくなった
                return;
            }
            StartPee(d, d.Target);
            d.Target = -1;
            d.Think = (0.15f + (float)_rng.NextDouble() * (Stage >= 6 ? 0.2f : 0.6f)) * d.T.Dither;
            return;
        }

        int dir = NextStepToward(d, pole);
        if (dir < 0) { d.Target = -1; Wander(d); d.Think = 0.2f; return; }
        int nx = d.X + DX[dir], ny = d.Y + DY[dir];
        if (LaneOf[ny] != 0 && (d.T.Caution >= 1f || _rng.NextDouble() < d.T.Caution))
        {
            // 車が来ていたら渡らずに待つ(道路の上にいるときは急いで抜ける)。用心深い犬ほど早めに止まる
            float look = Math.Max(1f, d.T.Caution);
            bool danger = CarDanger(nx, ny, d.StepTime * 2.2f * look);
            int ny2 = ny + DY[dir];
            if (!danger && DY[dir] != 0 && ny2 >= 0 && ny2 < FH && LaneOf[ny2] != 0)
                danger = CarDanger(nx, ny2, d.StepTime * 3.4f * look);
            if (danger && LaneOf[d.Y] == 0) { d.Dir = (Dir)dir; d.Think = 0.12f; return; }
        }
        if (!TryMove(d, (Dir)dir) || d.T.Stamina <= 0) return;

        // スタミナ切れ: 道路の上では休まない
        if (--d.Steps > 0) return;
        if (LaneOf[d.Y] != 0) { d.Steps = 1; return; }
        d.Steps = (int)(d.T.Stamina * (0.6 + _rng.NextDouble() * 0.8));
        d.Think = d.T.RestTime * (0.7f + (float)_rng.NextDouble() * 0.6f);
        if (d.T.RestText.Length > 0) AddPopup(d, d.T.RestText, 0xFFFFFF);
    }

    void Wander(Dog d)
    {
        int k = _rng.Next(4);
        int nx = d.X + DX[k], ny = d.Y + DY[k];
        if (ny >= 0 && ny < FH && LaneOf[ny] != 0 && LaneOf[d.Y] == 0) return;
        TryMove(d, (Dir)k);
    }

    /// <summary>dから歩いて行けるマスまでの歩数を _dist に入れる(行けないマスは -1)。</summary>
    void Flood(Dog d)
    {
        Array.Fill(_dist, -1);
        int head = 0, tail = 0;
        _queue[tail++] = d.Y * FW + d.X; _dist[d.Y * FW + d.X] = 0;
        while (head < tail)
        {
            int cur = _queue[head++];
            int cx = cur % FW, cy = cur / FW;
            for (int k = 0; k < 4; k++)
            {
                int nx = cx + DX[k], ny = cy + DY[k];
                if (!CanEnter(d, nx, ny)) continue;
                int ni = ny * FW + nx;
                if (_dist[ni] >= 0) continue;
                _dist[ni] = _dist[cur] + 1; _queue[tail++] = ni;
            }
        }
    }

    /// <summary>電柱の隣まで歩く歩数(_dist基準)。行けなければ -1。</summary>
    int TravelTo(Pole p)
    {
        int best = -1;
        for (int k = 0; k < 4; k++)
        {
            int nx = p.X + DX[k], ny = p.Y + DY[k];
            if (nx < 0 || ny < 0 || nx >= FW || ny >= FH) continue;
            int v = _dist[ny * FW + nx];
            if (v >= 0 && (best < 0 || v < best)) best = v;
        }
        return best;
    }

    void ChooseTarget(Dog d)
    {
        Flood(d);
        var travel = new int[Poles.Count];
        for (int i = 0; i < Poles.Count; i++) travel[i] = TravelTo(Poles[i]);

        for (int attempt = 0; attempt < 2; attempt++)
        {
            int best = -1;
            double bestScore = double.MinValue;
            var pl = Player;
            for (int i = 0; i < Poles.Count; i++)
            {
                if (travel[i] < 0 || d.Chain.Contains(i)) continue;
                var p = Poles[i];
                double s;
                if (d.Chain.Count == 0)
                {
                    s = -travel[i] + _rng.NextDouble() * 10 * d.T.Noise;
                    if (!p.Locked && p.Owner >= 0 && p.Owner != d.Id) s += 4 * d.T.Steal;   // 他の犬の印を上書きしたがる
                    if (p.Locked && p.Owner != d.Id) s -= 3;
                    // 攻撃的な犬は柴犬の近くから始める
                    if (!d.IsPlayer && d.T.Aggro > 1f)
                        s -= (Math.Abs(p.X - pl.X) + Math.Abs(p.Y - pl.Y)) * 0.35 * (d.T.Aggro - 1f);
                }
                else if (d.Chain.Count == 1)
                {
                    var f = Poles[d.Chain[0]];
                    int ideal = Math.Min(15, d.T.Reach + Stage / 3);
                    int dd = Math.Abs(f.X - p.X) + Math.Abs(f.Y - p.Y);
                    s = -Math.Abs(dd - ideal) * 1.5 - travel[i] * 0.5 + _rng.NextDouble() * 6 * d.T.Noise;
                }
                else
                {
                    int n = Evaluate(d.Id, d.Chain[^2], d.Chain[^1], i, null);
                    if (n < 0) continue;
                    s = Math.Min(n, 150) * d.T.SizeWeight - travel[i] * 1.2 + _rng.NextDouble() * 12 * d.T.Noise;
                    // 柴犬を囲めるなら狙う
                    if (!d.IsPlayer && pl.Invuln <= 0 && _inTri[pl.Y * FW + pl.X]) s += (30 + Stage * 3) * d.T.Aggro;
                    // ほかの犬を囲めるなら狙う (デモの柴犬と、牧羊犬気質の犬)
                    float herd = d.IsPlayer ? 1.6f : d.T.Herd;
                    if (herd > 0)
                        foreach (var o in Dogs)
                            if (o.Alive && o != d && !o.IsPlayer && _inTri[o.Y * FW + o.X]) s += 25 * herd;
                }
                if (s > bestScore) { bestScore = s; best = i; }
            }
            if (best >= 0) { d.Target = best; return; }
            if (d.Chain.Count < 2) return;
            d.Chain.RemoveAt(0);    // 3本目が見つからないので組み直す
        }
    }

    /// <summary>電柱の隣のマスへ向かう最短経路の最初の一歩。行けなければ -1。</summary>
    int NextStepToward(Dog d, Pole pole)
    {
        Array.Fill(_dist, -1);
        int head = 0, tail = 0;
        for (int k = 0; k < 4; k++)
        {
            int gx = pole.X + DX[k], gy = pole.Y + DY[k];
            if (!CanEnter(d, gx, gy)) continue;
            _dist[gy * FW + gx] = 0; _queue[tail++] = gy * FW + gx;
        }
        while (head < tail)
        {
            int cur = _queue[head++];
            int cx = cur % FW, cy = cur / FW;
            for (int k = 0; k < 4; k++)
            {
                int nx = cx + DX[k], ny = cy + DY[k];
                if (!CanEnter(d, nx, ny)) continue;
                int ni = ny * FW + nx;
                if (_dist[ni] >= 0) continue;
                _dist[ni] = _dist[cur] + 1; _queue[tail++] = ni;
            }
        }
        int here = _dist[d.Y * FW + d.X];
        if (here <= 0) return -1;
        int bestDir = -1, bestDist = here;
        int startK = _rng.Next(4);
        for (int j = 0; j < 4; j++)
        {
            int k = (startK + j) % 4;
            int nx = d.X + DX[k], ny = d.Y + DY[k];
            if (!CanEnter(d, nx, ny)) continue;
            int v = _dist[ny * FW + nx];
            if (v >= 0 && v < bestDist) { bestDist = v; bestDir = k; }
        }
        return bestDir;
    }
}
