namespace ShibaJintori;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--selftest") { SelfTest(); return; }
        try
        {
            // テストプレイ用: "--stage 8" で指定したステージから始める
            int startStage = 1;
            int at = Array.IndexOf(args, "--stage");
            if (at >= 0 && at + 1 < args.Length) int.TryParse(args[at + 1], out startStage);
            // "--bonus" で夜のボーナスステージから始める
            new App(startStage, Array.IndexOf(args, "--bonus") >= 0).Run();
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e);
            try { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "crash.log"), e.ToString()); } catch { }
        }
    }

    /// <summary>
    /// 画面を出さずにAI同士で対戦させ、ルールとAIが破綻していないか確かめる開発用の機能。
    /// 実行: dotnet run -- --selftest
    /// </summary>
    private static void SelfTest()
    {
        Console.WriteLine("stage seed  time claimed% player bestEnemy alive result");
        for (int stage = 1; stage <= 8; stage++)
            for (int seed = 1; seed <= 4; seed++)
            {
                var w = new World(stage, 0, 3, 0, demo: true, seed: stage * 100 + seed);
                while (!w.Finished) w.Update(1f / 60f, null, false);
                int best = 0, alive = 0, sum = 0;
                foreach (var d in w.Dogs)
                {
                    sum += d.Area;
                    if (d.IsPlayer) continue;
                    best = Math.Max(best, d.Area);
                    if (d.Alive) alive++;
                }
                if (sum != w.Claimed) throw new InvalidOperationException("area mismatch");
                Console.WriteLine($"{stage,5} {seed,4} {World.StageTime - w.TimeLeft,5:0} {w.Claimed * 100 / (World.FW * World.FH),7} " +
                                  $"{w.Player.Area,6} {best,9} {alive,5}/{w.Dogs.Count - 1} {(w.Cleared ? "clear" : "fail")}");
            }
    }
}
