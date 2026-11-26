"use strict";
// ドット絵の原画・犬種・性格・8x8フォント。PC版の SpriteData.cs / Breeds.cs / android/FontData.cs をそのまま移したもの。
//  . 透明   O 輪郭   E 耳(外)  P 耳(内)   F 頭   Y まゆ   Z 額の白すじ   d 頭のぶち
//  K 目     H 目のハイライト   C ほほ/口元   N 鼻   M 舌
//  B 胴体   S 背中   R 胸毛   L 足先   T しっぽ   D 胴体のぶち

const SpriteData = {
  FrontHeadPointy: `
..OO........OO..
.OEEO......OEEO.
.OEPEOOOOOOEPEO.
.OEFFFFZZFFFFEO.
OFFYYFFZZFFYYFFO
OFFHKFFZZFFHKFFO
OFCKKCCCCCCKKCFO
OCCCCCCNNCCCCCCO
.OCCCCCMMCCCCCO.
..OOCCCCCCCCOO..`,
  FrontHeadBig: `
OOO..........OOO
OEEOO......OOEEO
OEPPEOOOOOOEPPEO
.OEPEFFZZFFEPEO.
OFFYYFFZZFFYYFFO
OFFHKFFZZFFHKFFO
OFCKKCCCCCCKKCFO
OCCCCCCNNCCCCCCO
.OCCCCCMMCCCCCO.
..OOCCCCCCCCOO..`,
  FrontHeadFloppy: `
................
....OOOOOOOO....
..OOFFdZZFFFOO..
.OEEFFFZZFFFEEO.
OEEFYYFZZFYYFEEO
OEEFHKFZZFHKFEEO
OEECKKCCCCKKCEEO
OEECCCCNNCCCCEEO
.OOCCCCMMCCCCOO.
...OOCCCCCCOO...`,
  BackHeadPointy: `
..OO........OO..
.OEEO......OEEO.
.OEEEOOOOOOEEEO.
.OEFFFFFFFFFFEO.
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
.OFFFFFFFFFFFFO.
..OOFFFFFFFFOO..`,
  BackHeadBig: `
OOO..........OOO
OEEOO......OOEEO
OEEEEOOOOOOEEEEO
.OEEEFFFFFFEEEO.
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
OFFFFFFFFFFFFFFO
.OFFFFFFFFFFFFO.
..OOFFFFFFFFOO..`,
  BackHeadFloppy: `
................
....OOOOOOOO....
..OOFFFFFdFFOO..
.OEEFFFFFFFFEEO.
OEEFFdFFFFFFFEEO
OEEFFFFFFFFFFEEO
OEEFFFFFFdFFFEEO
OEEFFFFFFFFFFEEO
.OOFFFFFFFFFFOO.
...OOFFFFFFOO...`,
  FrontBodyStand: `
...OBRRRRRRBO...
...OBBRRRRBBO...
...OBDRRRRBBO...
...OBLOBBOLBO...
...OLLO..OLLO...
...OOO....OOO...`,
  FrontBodyStride: `
...OBRRRRRRBO...
...OBBRRRRBBO...
...OBDRRRRBBO...
...OBLOBBOLLO...
...OLLO..OOO....
...OOO..........`,
  BackBodyStand: `
...OBSSSSSSBO...
...OBSSTTDSBO...
...OBBTTTTBBO...
...OBLOTTOLBO...
...OLLO..OLLO...
...OOO....OOO...`,
  BackBodyStride: `
...OBSSSSSSBO...
...OBSSTTDSBO...
...OBBTTTTBBO...
...OLLOTTOLBO...
....OOO..OLLO...
..........OOO...`,
  SideTopPointy: `
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
..OBBBBBBBBRRO..`,
  SideTopBig: `
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
..OBBBBBBBBRRO..`,
  SideTopFloppy: `
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
..OBBDBBBBBRRO..`,
  SideLegsStand: `
..OBLOOOOOBLO...
..OLLO...OLLO...
..OOOO...OOOO...`,
  SideLegsStride: `
.OLLOOOOOOOLLO..
OLLO........OLLO
OOO..........OOO`,
  BackBodyPee: `
...OBBOOOOBBOOO.
...OBBBBBBBBLLO.
...OBBBBBBBBOOO.
...OBLOBBOBO....
...OLLO..OO.....
...OOO..........`,
  BackPeeTail: `
______OOOO______
_____OTTTTO_____
_____OTSSTO_____
_____OTTTTO_____`,
  SideBottomPeeFar: `
OOOBSSDSBBBRRO..
OLLBBBBBBBBRRO..
OOOBLOOOOOBLO...
..OLLO...OLLO...
..OOOO...OOOO...`,
  SideBottomPeeNear: `
..OBBBBBBBBRRO..
.OOLBLOOOOBLO...
OLLOOLO..OLLO...
OOO.OOO..OOOO...`,
  Bone: `
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
................`,
  Scroll: `
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
................`,
  IconFlag: `
..OOO...........
..OwOOOOOOOOO...
..OwOWWWWWWWWO..
..OwOWWWWWWWWWO.
..OwOWWWWWWWWWWO
..OwOWWWWWWWWWO.
..OwOWWWWWWWWO..
..OwOOOOOOOOO...
..OwO...........
..OwO...........
..OwO...........
..OwO...........
..OwO...........
.OOwOO..........
.OwwwO..........
.OOOOO..........`,
  IconMoon: `
................
......OOOO......
....OOMMMO......
...OMMMOO.......
..OMMMO....Y....
..OMMO....YYY...
.OMMMO.....Y....
.OMMMO..........
.OMMMO..........
.OMMMO.......Y..
..OMMO..........
..OMMMO.........
...OMMMOO.......
....OOMMMO......
......OOOO......
................`,
  IconStar: `
.......OO.......
......OYYO......
......OYYO......
.....OYYYYO.....
OOOOOOYYYYOOOOOO
OYYYYYYWYYYYYYYO
.OYYYYYWYYYYYYO.
..OYYYYYYYYYYO..
...OYYYYYYYYO...
...OYYYYYYYyO...
..OYYYYOOYYyyO..
..OYYYO..OYyyO..
.OYYYO....OyyyO.
.OYYO......OyyO.
.OOO........OOO.
................`,
  IconTrophy: `
................
..OOOOOOOOOOOO..
OOOYYYYYYYYYyOOO
OYOYWYYYYYYYyOYO
OYOYWYYYYYYYyOYO
.OYOYYYYYYYyOYO.
..OOYYYYYYYyOO..
....OYYYYYyO....
.....OYYYyO.....
......OYyO......
......OYyO......
.....OYYYyO.....
....OOOOOOOO....
....OyyyyyyO....
....OOOOOOOO....
................`,
  IconCrown: `
................
................
................
.O.....OO.....O.
OYO...OYYO...OYO
OYYO..OYYO..OYYO
OYYYOOYYYYOOYYYO
OYYYYYYYYYYYYYYO
OYYYYYYYYYYYYYYO
OYYRYYYBBYYYRYYO
OYYYYYYYYYYYYYYO
OyyyyyyyyyyyyyyO
OOOOOOOOOOOOOOOO
................
................
................`,
  IconDrop: `
.......OO.......
.......OO.......
......OBBO......
......OBBO......
.....OBBBBO.....
.....OBBBBO.....
....OBBBBBBO....
...OBBWBBBBBO...
...OBWBBBBBBO...
..OBBWBBBBBBBO..
..OBBBBBBBBBBO..
..OBBBBBBBBBbO..
..OBBBBBBBBbbO..
...OBBBBBbbbO...
....OOBbbbOO....
......OOOO......`,
  IconHeart: `
................
..OOO......OOO..
.ORRRO....ORRRO.
ORWWRRO..ORRRRRO
ORWRRRROORRRRRRO
ORRRRRRRRRRRRRRO
ORRRRRRRRRRRRrRO
.ORRRRRRRRRRrRO.
..ORRRRRRRRrRO..
...ORRRRRRrRO...
....ORRRRRRO....
.....ORRRRO.....
......ORRO......
.......OO.......
................
................`,
  IconBolt: `
.........OOOO...
........OYYYO...
.......OYYYO....
......OYYYO.....
.....OYYYO......
....OYYYOOOOO...
...OYYYYYYYYO...
...OOOOOYYYO....
.......OYYO.....
......OYYO......
.....OYYO.......
....OYYO........
...OYyO.........
...OyO..........
...OO...........
................`,
  Pole: `
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
.....OOOOOO.....`,
  PeeMark: `
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
...WWWWWWWWWW...`,
  PoleBand: `
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
................`,
  Car: `
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
................................`,
  Grass0: `
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
gggggggggggggggg`,
  Grass1: `
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
gggggggggggggggg`,
  RoadTop: `
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
rrrwwwwwwwwwrrrr`,
  RoadBottom: `
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
eeeeeeeeeeeeeeee`,
  Paw: `
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
................`,
};

/** 文字で描いた絵を行の配列にする (空行は捨てる)。 */
function rows(art) {
  return art.split("\n").map(s => s.trim()).filter(s => s.length > 0);
}

const Ear = { Pointy: 0, Big: 1, Floppy: 2 };

/**
 * 犬種。palette は "文字=RRGGBB" または "文字=別の文字" (同じ色を使う) を空白区切りで並べる。
 * 0-2: 柴犬 (茶/黒/白)、3以降: 敵の犬種、最後: ボス犬。
 */
const Breeds = [
  ["ShibaRed", "SHIBA", Ear.Pointy, 0xFF8C1A,
    "O=5A3214 E=D9822E P=F7B9A6 F=E8973C Y=F F=E8973C Z=F d=F K=2A1A10 H=FFFFFF C=FFF3DC N=2A1A10 M=F0707F B=F S=D9822E R=FFF3DC L=FFF3DC T=FFF3DC D=B"],
  ["ShibaBlack", "SHIBA", Ear.Pointy, 0xFF8C1A,
    "O=0C0C10 E=2E2E38 P=C98A80 F=3A3A46 Y=E0A050 Z=F d=F K=0C0C10 H=FFFFFF C=F6EAD0 N=0C0C10 M=F0707F B=F S=2E2E38 R=F6EAD0 L=E0A050 T=F6EAD0 D=B"],
  ["ShibaWhite", "SHIBA", Ear.Pointy, 0xFF8C1A,
    "O=8C7A66 E=F6ECD8 P=F7B9A6 F=FFFDF6 Y=F Z=F d=F K=2A1A10 H=FFFFFF C=FFFFFF N=2A1A10 M=F0707F B=F S=F1E6D0 R=FFFFFF L=FFFFFF T=F1E6D0 D=B"],
  ["Corgi", "CORGI", Ear.Big, 0xFFE02E,
    "O=5C3410 E=E89030 P=F7B9A6 F=F2A444 Y=F Z=FFFFFF d=F K=2A1A10 H=FFFFFF C=FFFFFF N=2A1A10 M=F0707F B=F S=E89030 R=FFFFFF L=FFFFFF T=FFFFFF D=B"],
  ["Chihuahua", "CHIHUAHUA", Ear.Big, 0xFF7EB6,
    "O=7A5630 E=EBC98A P=FFC8C0 F=F7E0AE Y=F Z=F d=F K=1A1010 H=FFFFFF C=FFF8E6 N=4A2A20 M=F0707F B=F S=EBC98A R=FFF8E6 L=FFF8E6 T=EBC98A D=B"],
  ["Sheltie", "SHELTIE", Ear.Pointy, 0xB86CFF,
    "O=3A2414 E=7A4A22 P=E0A090 F=B8742E Y=F Z=FFFFFF d=F K=1A1010 H=FFFFFF C=FFFFFF N=1A1010 M=F0707F B=F S=7A4A22 R=FFFFFF L=FFFFFF T=7A4A22 D=B"],
  ["Husky", "HUSKY", Ear.Pointy, 0x38B6FF,
    "O=1E222A E=59636F P=E8B0A8 F=7C8794 Y=FFFFFF Z=FFFFFF d=F K=2E9BE8 H=FFFFFF C=FFFFFF N=1E222A M=F0707F B=F S=59636F R=FFFFFF L=FFFFFF T=FFFFFF D=B"],
  ["Pug", "PUG", Ear.Floppy, 0xA8845C,
    "O=3A2A1A E=2A2220 P=E F=EBCB92 Y=F Z=F d=F K=000000 H=FFFFFF C=5E4C40 N=000000 M=F0707F B=F S=DDB878 R=F4DEB0 L=F T=DDB878 D=B"],
  ["Dalmatian", "DALMATIAN", Ear.Floppy, 0xE8E8F0,
    "O=3A3A40 E=26262C P=E F=FFFFFF Y=F Z=F d=26262C K=101014 H=FFFFFF C=FFFFFF N=101014 M=F0707F B=F S=F R=F L=F T=F D=26262C"],
  ["Poodle", "POODLE", Ear.Floppy, 0xFF5A4A,
    "O=6A3A20 E=B06A34 P=E F=CC8A4E Y=F Z=F d=DDA066 K=1A1010 H=FFFFFF C=DDA066 N=1A1010 M=F0707F B=F S=B06A34 R=DDA066 L=F T=B06A34 D=DDA066"],
  ["Beagle", "BEAGLE", Ear.Floppy, 0x3AD6A0,
    "O=3A2010 E=8A4A1A P=E F=B86A2A Y=F Z=FFFFFF d=F K=1A1010 H=FFFFFF C=FFFFFF N=1A1010 M=F0707F B=FFFFFF S=2A2A2E R=FFFFFF L=FFFFFF T=FFFFFF D=B86A2A"],
  ["StBernard", "ST.BERNARD", Ear.Floppy, 0x9C2040,
    "O=3A2010 E=7A3A14 P=E F=A8501E Y=F Z=FFFFFF d=F K=1A1010 H=FFFFFF C=FFFFFF N=1A1010 M=F0707F B=FFFFFF S=A8501E R=FFFFFF L=FFFFFF T=FFFFFF D=A8501E"],
].map(([name, display, ear, territoryColor, palette]) => ({ name, display, ear, territoryColor, palette }));

const ShibaCount = 3;
const BossIndex = Breeds.length - 1;
const EnemyBreedCount = Breeds.length - ShibaCount - 1;

function buildPalette(breed) {
  const raw = {};
  for (const kv of breed.palette.split(" ").filter(s => s)) raw[kv[0]] = kv.slice(2);
  const pal = {};
  for (const k of Object.keys(raw)) {
    let v = raw[k];
    for (let guard = 0; v.length === 1 && guard < 8; guard++) v = raw[v[0]];
    pal[k] = parseInt(v, 16);
  }
  return pal;
}

/**
 * 敵の犬種ごとの性格 (Breeds.cs の Temper と同じ数値)。
 *  speed 1歩の時間の倍率 / reach 2本目の好みの距離 / sizeWeight 面積の重視 / aggro 柴犬を囲む強さ
 *  herd ほかの犬を囲む強さ / steal 印の上書き / caution 道路の用心 / stamina 休むまでの歩数 / restTime 休む秒数
 *  dither おしっこ後のぼんやり / noise 気まぐれさ
 */
function T(speed, reach, sizeWeight, aggro, herd, steal, caution, stamina, restTime, dither, noise, restText, trait) {
  return { speed, reach, sizeWeight, aggro, herd, steal, caution, stamina, restTime, dither, noise, restText, trait };
}
const TemperDefault = T(1, 7, 1, 1, 0, 1, 1, 0, 0, 1, 1, "", "");
const Tempers = {
  Corgi: T(1.08, 6, 1.0, 0.8, 0.5, 1.0, 1.6, 0, 0, 1.0, 1.0, "", "STEADY"),
  Chihuahua: T(0.70, 3, 0.25, 0.4, 0, 0.5, 1.2, 28, 2.4, 0.5, 1.2, "HAH..", "QUICK"),
  Sheltie: T(0.92, 8, 1.0, 1.2, 2.0, 1.0, 1.2, 0, 0, 0.7, 0.6, "", "HERDER"),
  Husky: T(0.86, 13, 1.6, 2.4, 0.5, 1.5, 0.6, 0, 0, 0.6, 0.8, "", "FIERCE"),
  Pug: T(1.35, 5, 0.7, 0.5, 0, 0.5, 1.5, 16, 3.2, 2.0, 1.0, "ZZZ", "LAZY"),
  Dalmatian: T(0.78, 11, 1.2, 0.8, 0, 1.0, 0.25, 0, 0, 0.8, 1.5, "", "RUNNER"),
  Poodle: T(0.95, 7, 1.0, 1.0, 0.3, 3.0, 1.3, 0, 0, 0.5, 0.4, "", "CLEVER"),
  Beagle: T(1.0, 7, 0.9, 0.7, 0, 2.0, 0.8, 20, 1.2, 1.2, 3.0, "SNIFF", "NOSY"),
  StBernard: T(1.45, 12, 1.5, 2.0, 1.0, 1.0, 2.0, 0, 0, 1.5, 0.6, "", "BOSS"),
};
function temperFor(breed) { return Tempers[breed.name] || TemperDefault; }

/** SDL3 の内蔵デバッグフォント (8x8)。ASCII 32..127。1文字8バイト、最上位ビットが左端。 */
const FontGlyphs = [
  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00,
  0x6C,0x6C,0x00,0x00,0x00,0x00,0x00,0x00, 0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0x00,
  0x30,0x7C,0xC0,0x78,0x0C,0xF8,0x30,0x00, 0x00,0xC6,0xCC,0x18,0x30,0x66,0xC6,0x00,
  0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00, 0x60,0x60,0xC0,0x00,0x00,0x00,0x00,0x00,
  0x18,0x30,0x60,0x60,0x60,0x30,0x18,0x00, 0x60,0x30,0x18,0x18,0x18,0x30,0x60,0x00,
  0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00, 0x00,0x30,0x30,0xFC,0x30,0x30,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x60, 0x00,0x00,0x00,0xFC,0x00,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x00, 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00,
  0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0x7C,0x00, 0x30,0x70,0x30,0x30,0x30,0x30,0xFC,0x00,
  0x78,0xCC,0x0C,0x38,0x60,0xCC,0xFC,0x00, 0x78,0xCC,0x0C,0x38,0x0C,0xCC,0x78,0x00,
  0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x1E,0x00, 0xFC,0xC0,0xF8,0x0C,0x0C,0xCC,0x78,0x00,
  0x38,0x60,0xC0,0xF8,0xCC,0xCC,0x78,0x00, 0xFC,0xCC,0x0C,0x18,0x30,0x30,0x30,0x00,
  0x78,0xCC,0xCC,0x78,0xCC,0xCC,0x78,0x00, 0x78,0xCC,0xCC,0x7C,0x0C,0x18,0x70,0x00,
  0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x00, 0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x60,
  0x18,0x30,0x60,0xC0,0x60,0x30,0x18,0x00, 0x00,0x00,0xFC,0x00,0x00,0xFC,0x00,0x00,
  0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00, 0x78,0xCC,0x0C,0x18,0x30,0x00,0x30,0x00,
  0x7C,0xC6,0xDE,0xDE,0xDE,0xC0,0x78,0x00, 0x30,0x78,0xCC,0xCC,0xFC,0xCC,0xCC,0x00,
  0xFC,0x66,0x66,0x7C,0x66,0x66,0xFC,0x00, 0x3C,0x66,0xC0,0xC0,0xC0,0x66,0x3C,0x00,
  0xF8,0x6C,0x66,0x66,0x66,0x6C,0xF8,0x00, 0xFE,0x62,0x68,0x78,0x68,0x62,0xFE,0x00,
  0xFE,0x62,0x68,0x78,0x68,0x60,0xF0,0x00, 0x3C,0x66,0xC0,0xC0,0xCE,0x66,0x3E,0x00,
  0xCC,0xCC,0xCC,0xFC,0xCC,0xCC,0xCC,0x00, 0x78,0x30,0x30,0x30,0x30,0x30,0x78,0x00,
  0x1E,0x0C,0x0C,0x0C,0xCC,0xCC,0x78,0x00, 0xE6,0x66,0x6C,0x78,0x6C,0x66,0xE6,0x00,
  0xF0,0x60,0x60,0x60,0x62,0x66,0xFE,0x00, 0xC6,0xEE,0xFE,0xFE,0xD6,0xC6,0xC6,0x00,
  0xC6,0xE6,0xF6,0xDE,0xCE,0xC6,0xC6,0x00, 0x38,0x6C,0xC6,0xC6,0xC6,0x6C,0x38,0x00,
  0xFC,0x66,0x66,0x7C,0x60,0x60,0xF0,0x00, 0x78,0xCC,0xCC,0xCC,0xDC,0x78,0x1C,0x00,
  0xFC,0x66,0x66,0x7C,0x6C,0x66,0xE6,0x00, 0x78,0xCC,0xE0,0x70,0x1C,0xCC,0x78,0x00,
  0xFC,0xB4,0x30,0x30,0x30,0x30,0x78,0x00, 0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xFC,0x00,
  0xCC,0xCC,0xCC,0xCC,0xCC,0x78,0x30,0x00, 0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0x00,
  0xC6,0xC6,0x6C,0x38,0x38,0x6C,0xC6,0x00, 0xCC,0xCC,0xCC,0x78,0x30,0x30,0x78,0x00,
  0xFE,0xC6,0x8C,0x18,0x32,0x66,0xFE,0x00, 0x78,0x60,0x60,0x60,0x60,0x60,0x78,0x00,
  0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00, 0x78,0x18,0x18,0x18,0x18,0x18,0x78,0x00,
  0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,
  0x30,0x30,0x18,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x78,0x0C,0x7C,0xCC,0x76,0x00,
  0xE0,0x60,0x60,0x7C,0x66,0x66,0xDC,0x00, 0x00,0x00,0x78,0xCC,0xC0,0xCC,0x78,0x00,
  0x1C,0x0C,0x0C,0x7C,0xCC,0xCC,0x76,0x00, 0x00,0x00,0x78,0xCC,0xFC,0xC0,0x78,0x00,
  0x38,0x6C,0x60,0xF0,0x60,0x60,0xF0,0x00, 0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0xF8,
  0xE0,0x60,0x6C,0x76,0x66,0x66,0xE6,0x00, 0x30,0x00,0x70,0x30,0x30,0x30,0x78,0x00,
  0x0C,0x00,0x0C,0x0C,0x0C,0xCC,0xCC,0x78, 0xE0,0x60,0x66,0x6C,0x78,0x6C,0xE6,0x00,
  0x70,0x30,0x30,0x30,0x30,0x30,0x78,0x00, 0x00,0x00,0xCC,0xFE,0xFE,0xD6,0xC6,0x00,
  0x00,0x00,0xF8,0xCC,0xCC,0xCC,0xCC,0x00, 0x00,0x00,0x78,0xCC,0xCC,0xCC,0x78,0x00,
  0x00,0x00,0xDC,0x66,0x66,0x7C,0x60,0xF0, 0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0x1E,
  0x00,0x00,0xDC,0x76,0x66,0x60,0xF0,0x00, 0x00,0x00,0x7C,0xC0,0x78,0x0C,0xF8,0x00,
  0x10,0x30,0x7C,0x30,0x30,0x34,0x18,0x00, 0x00,0x00,0xCC,0xCC,0xCC,0xCC,0x76,0x00,
  0x00,0x00,0xCC,0xCC,0xCC,0x78,0x30,0x00, 0x00,0x00,0xC6,0xD6,0xFE,0xFE,0x6C,0x00,
  0x00,0x00,0xC6,0x6C,0x38,0x6C,0xC6,0x00, 0x00,0x00,0xCC,0xCC,0xCC,0x7C,0x0C,0xF8,
  0x00,0x00,0xFC,0x98,0x30,0x64,0xFC,0x00, 0x1C,0x30,0x30,0xE0,0x30,0x30,0x1C,0x00,
  0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00, 0xE0,0x30,0x30,0x1C,0x30,0x30,0xE0,0x00,
  0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
];
