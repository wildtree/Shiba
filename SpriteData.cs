namespace ShibaJintori;

/// <summary>
/// ドット絵の原画データ。1文字=1ドット。
///  . 透明   O 輪郭   E 耳(外)  P 耳(内)   F 頭   Y まゆ   Z 額の白すじ   d 頭のぶち
///  K 目     H 目のハイライト   C ほほ/口元   N 鼻   M 舌
///  B 胴体   S 背中   R 胸毛   L 足先   T しっぽ   D 胴体のぶち
/// 犬は「頭(10行)+胴(6行)」「横向き上部(13行)+脚(3行)」を組み合わせて16x16にする。
/// </summary>
public static class SpriteData
{
    // ---------- 正面の頭 (10行) ----------
    public const string FrontHeadPointy = """
        ..OO........OO..
        .OEEO......OEEO.
        .OEPEOOOOOOEPEO.
        .OEFFFFZZFFFFEO.
        OFFYYFFZZFFYYFFO
        OFFHKFFZZFFHKFFO
        OFCKKCCCCCCKKCFO
        OCCCCCCNNCCCCCCO
        .OCCCCCMMCCCCCO.
        ..OOCCCCCCCCOO..
        """;

    public const string FrontHeadBig = """
        OOO..........OOO
        OEEOO......OOEEO
        OEPPEOOOOOOEPPEO
        .OEPEFFZZFFEPEO.
        OFFYYFFZZFFYYFFO
        OFFHKFFZZFFHKFFO
        OFCKKCCCCCCKKCFO
        OCCCCCCNNCCCCCCO
        .OCCCCCMMCCCCCO.
        ..OOCCCCCCCCOO..
        """;

    public const string FrontHeadFloppy = """
        ................
        ....OOOOOOOO....
        ..OOFFdZZFFFOO..
        .OEEFFFZZFFFEEO.
        OEEFYYFZZFYYFEEO
        OEEFHKFZZFHKFEEO
        OEECKKCCCCKKCEEO
        OEECCCCNNCCCCEEO
        .OOCCCCMMCCCCOO.
        ...OOCCCCCCOO...
        """;

    // ---------- 後ろ向きの頭 (10行) ----------
    public const string BackHeadPointy = """
        ..OO........OO..
        .OEEO......OEEO.
        .OEEEOOOOOOEEEO.
        .OEFFFFFFFFFFEO.
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        .OFFFFFFFFFFFFO.
        ..OOFFFFFFFFOO..
        """;

    public const string BackHeadBig = """
        OOO..........OOO
        OEEOO......OOEEO
        OEEEEOOOOOOEEEEO
        .OEEEFFFFFFEEEO.
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        OFFFFFFFFFFFFFFO
        .OFFFFFFFFFFFFO.
        ..OOFFFFFFFFOO..
        """;

    public const string BackHeadFloppy = """
        ................
        ....OOOOOOOO....
        ..OOFFFFFdFFOO..
        .OEEFFFFFFFFEEO.
        OEEFFdFFFFFFFEEO
        OEEFFFFFFFFFFEEO
        OEEFFFFFFdFFFEEO
        OEEFFFFFFFFFFEEO
        .OOFFFFFFFFFFOO.
        ...OOFFFFFFOO...
        """;

    // ---------- 正面の胴 (6行) ----------
    public const string FrontBodyStand = """
        ...OBRRRRRRBO...
        ...OBBRRRRBBO...
        ...OBDRRRRBBO...
        ...OBLOBBOLBO...
        ...OLLO..OLLO...
        ...OOO....OOO...
        """;

    public const string FrontBodyStride = """
        ...OBRRRRRRBO...
        ...OBBRRRRBBO...
        ...OBDRRRRBBO...
        ...OBLOBBOLLO...
        ...OLLO..OOO....
        ...OOO..........
        """;

    // ---------- 後ろ向きの胴 (6行) ----------
    public const string BackBodyStand = """
        ...OBSSSSSSBO...
        ...OBSSTTDSBO...
        ...OBBTTTTBBO...
        ...OBLOTTOLBO...
        ...OLLO..OLLO...
        ...OOO....OOO...
        """;

    public const string BackBodyStride = """
        ...OBSSSSSSBO...
        ...OBSSTTDSBO...
        ...OBBTTTTBBO...
        ...OLLOTTOLBO...
        ....OOO..OLLO...
        ..........OOO...
        """;

    // ---------- 横向き(右向き)の上部 (13行) ----------
    public const string SideTopPointy = """
        ........OO..OO..
        .......OEEOOEPO.
        .......OEEFFEPO.
        .......OFFFFFFFO
        .......OFFFFYFFO
        .......OFFFFKHFO
        .OO....OFFFCKCCO
        OTTO...OFCCCCCNO
        OTTTO...OCCCCMO.
        .OTTOOOOOOOOOO..
        ..OSSSSSSBBRRO..
        ..OBSSDSBBBRRO..
        ..OBBBBBBBBRRO..
        """;

    public const string SideTopBig = """
        .......OOO.OOO..
        .......OEEOEPEO.
        .......OEEFEPPO.
        .......OFFFFFFFO
        .......OFFFFYFFO
        .......OFFFFKHFO
        .OO....OFFFCKCCO
        OTTO...OFCCCCCNO
        OTTTO...OCCCCMO.
        .OTTOOOOOOOOOO..
        ..OSSSSSSBBRRO..
        ..OBSSDSBBBRRO..
        ..OBBBBBBBBRRO..
        """;

    public const string SideTopFloppy = """
        ................
        .........OOOOO..
        .......OOFFdFFO.
        .......OEEFFFFFO
        .......OEEFFYFFO
        .......OEEFFKHFO
        .OO....OEEFCKCCO
        OTTO...OOECCCCNO
        OTTTO...OOCCCMO.
        .OTTOOOOOOOOOO..
        ..OSSSSSSBBRRO..
        ..OBSSDSBBBRRO..
        ..OBBDBBBBBRRO..
        """;

    // ---------- 横向きの脚 (3行) ----------
    public const string SideLegsStand = """
        ..OBLOOOOOBLO...
        ..OLLO...OLLO...
        ..OOOO...OOOO...
        """;

    public const string SideLegsStride = """
        .OLLOOOOOOOLLO..
        OLLO........OLLO
        OOO..........OOO
        """;

    // ---------- おしっこポーズ ----------
    // 正面向きで画面右側の後ろ足を上げる (電柱が右。左は反転して使う)
    public const string FrontBodyPee = """
        ...OBRRRRRRBO...
        ...OBBRRRRBBOOO.
        ...OBDRRRRBBBLLO
        ...OBLOBBOBOOOO.
        ...OLLO..OO.....
        ...OOO..........
        """;

    // 横向きで奥側の後ろ足を水平に上げる (電柱が上)。横向き上部の先頭11行に続ける
    public const string SideBottomPeeFar = """
        OOOBSSDSBBBRRO..
        OLLBBBBBBBBRRO..
        OOOBLOOOOOBLO...
        ..OLLO...OLLO...
        ..OOOO...OOOO...
        """;

    // 横向きで手前側の後ろ足を斜め下に上げる (電柱が下)。横向き上部の先頭12行に続ける
    public const string SideBottomPeeNear = """
        ..OBBBBBBBBRRO..
        .OOLBLOOOOBLO...
        OLLOOLO..OLLO...
        OOO.OOO..OOOO...
        """;

    // ---------- アイテム ----------
    // 骨: W 白  w 影
    public const string Bone = """
        ................
        ................
        ..OO........OO..
        .OWWO......OWWO.
        OWWWWO....OWWWWO
        OWWWWWOOOOWWWWWO
        .OWWWWWWWWWWWWO.
        ..OWWWWWWWWWWO..
        .OWwwwwwwwwwwWO.
        OWWwwwOOOOwwwWWO
        OWwwwO....OwwwWO
        .OwwO......OwwO.
        ..OO........OO..
        ................
        ................
        ................
        """;

    // 忍者の巻物: P 紫  R 赤い印  y 金の軸
    public const string Scroll = """
        ................
        ................
        ................
        .OO..........OO.
        OyyOOOOOOOOOOyyO
        OyyOPPPPPPPPOyyO
        OyyOPPPRRPPPOyyO
        OyyOPPRRRRPPOyyO
        OyyOPPRRRRPPOyyO
        OyyOPPPRRPPPOyyO
        OyyOPPPPPPPPOyyO
        OyyOOOOOOOOOOyyO
        .OO..........OO.
        ................
        ................
        ................
        """;

    // ---------- 電柱 ----------
    // G/g コンクリート  W 腕金  I がいし  O 輪郭
    public const string Pole = """
        ................
        ..OOOOOOOOOOOO..
        ..OIWWWWWWWWIO..
        ..OOOOOggOOOOO..
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        ......OgGO......
        .....OOgGOO.....
        .....OgggGO.....
        .....OOOOOO.....
        """;

    // おしっこ跡 (白で描いて犬ごとの色を乗算する)
    public const string PeeMark = """
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ..........WW....
        ...WW....WWWW...
        ..WWWW..WWWWWW..
        ..WWWWWWWWWWWW..
        ...WWWWWWWWWW...
        """;

    // 電柱に巻くなわばりの印 (白で描いて色を乗算)
    public const string PoleBand = """
        ................
        ................
        ................
        ................
        ................
        ......OWWO......
        ......OWWO......
        ......OWWO......
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        """;

    // ---------- 車 (32x16, 左向き) ----------
    // A 車体  a 車体の影  G 窓  K タイヤ  S ホイール  Y ヘッドライト  R テールランプ
    public const string Car = """
        ................................
        ..........OOOOOOOOOOOOO.........
        .........OAAAAAAAAAAAAAO........
        ........OAGGGGGAOAGGGGGAO.......
        .......OAGGGGGGAOAGGGGGGAO......
        ..OOOOOOAAAAAAAAAAAAAAAAAOOOOO..
        .OAAAAAAAAAAAAAAAAAAAAAAAAAAAAO.
        OYYAAAAAAAAAAAAAAAAAAAAAAAAAARRO
        OYYAAAAAAAAAAAOAAAAAAAAAAAAAARRO
        OAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAO
        OaaaaOOOOaaaaaaaaaaaaaaOOOOaaaaO
        .OOOOKKKKOOOOOOOOOOOOOOKKKKOOOO.
        ....OKSSKO............OKSSKO....
        ....OKSSKO............OKSSKO....
        .....OKKO..............OKKO.....
        ................................
        """;

    // ---------- 地面 ----------
    public const string Grass0 = """
        gggggggggggggggg
        gggGgggggggggggg
        ggGggggggggdgggg
        gggggggggggggggg
        gggggggggggggggg
        ggggggggGggggggg
        gggggggGgggggggg
        gdgggggggggggggg
        gggggggggggggggg
        ggggggggggggGggg
        gggggggggggGgggg
        ggggdggggggggggg
        gggggggggggggggg
        ggGggggggggggggg
        gGgggggggdgggggg
        gggggggggggggggg
        """;

    public const string Grass1 = """
        gggggggggggggggg
        gggggggggggggggg
        gggggggggGgggggg
        ggggggggGggggggg
        ggdggggggggggggg
        gggggggggggggggg
        ggggggggggggdggg
        gggggggggggggggg
        gggGgggggggggggg
        ggGggggggggggggg
        gggggggfgggggggg
        ggggggfyfggggggg
        gggggggfgggggggg
        ggggggggggggggGg
        gggggggggggggGgg
        gggggggggggggggg
        """;

    // 道路 (上車線 / 下車線)。r 路面  w 白線  e 路肩
    public const string RoadTop = """
        eeeeeeeeeeeeeeee
        wwwwwwwwwwwwwwww
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrwwwwwwwwwrrrr
        """;

    public const string RoadBottom = """
        rrrwwwwwwwwwrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        rrrrrrrrrrrrrrrr
        wwwwwwwwwwwwwwww
        eeeeeeeeeeeeeeee
        """;

    // 肉球 (白で描いて色を乗算)
    public const string Paw = """
        ................
        ....WW....WW....
        ...WWWW..WWWW...
        ...WWWW..WWWW...
        ....WW....WW....
        .WW..........WW.
        WWWW...WW...WWWW
        WWWW.WWWWWW.WWWW
        .WW.WWWWWWWW.WW.
        ...WWWWWWWWWW...
        ...WWWWWWWWWW...
        ..WWWWWWWWWWWW..
        ..WWWWWWWWWWWW..
        ...WWWW..WWWW...
        ....WW....WW....
        ................
        """;
}
