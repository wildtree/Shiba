"use strict";
// 画面遷移 (タイトル/デモ/プレイ/結果/ネーム入力/ハイスコア/実績) と描画。PC版 App.cs と android/AppMobile.cs を移したもの。

const Scene = { Title: 0, HiScores: 1, Demo: 2, StageIntro: 3, Play: 4, StageResult: 5, GameOver: 6, NameEntry: 7, Achievements: 8 };
const FieldW = FW * Tile;          // 480
const FieldH = FH * Tile;          // 400
const PanelBg = 0x1B2033;
const StatusW = 480, StatusH = 190;           // 縦画面のステータス領域
const HudW = 160, HudLH = 76, HudRH = 182;    // 横向き (3列) の左右の HUD
const NameChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!? ";
const ShibaNames = ["RED", "BLACK", "WHITE"];
const FirstExtend = 20000, ExtendEvery = 40000;   // 残機が増える得点: 20,000 点、その後は 40,000 点ごと
const AppVersion = (self.APP_VERSION || "web");

class App {
  constructor(startStage = 1, startBonus = false) {
    this.scene = Scene.Title;
    this.t = 0; this.clock = 0;
    this.paused = false; this.attract = false;
    this.world = null;
    this.shiba = 0; this.stage = 1; this.lives = 3; this.score = 0; this.stageStartScore = 0; this.bonusPts = 0;
    this.hi = new HiScoreTable();
    this.newRank = -1;
    this.name = ["A", "A", "A"]; this.namePos = 0;
    this.achCursor = 0; this.viewTime = 8;
    this.nextExtend = FirstExtend;
    this.startStage = Math.max(1, startStage); this.startBonus = startBonus;
    this.bonusStartScore = 0;
    this.touch = false;      // 画面の操作パッドを出しているか (案内の言い方を変える)
    this.pads = 0;           // つながっているゲームパッドの数
    this.isFullscreen = () => false;
    this._backdrop = null;
  }

  go(s) { this.scene = s; this.t = 0; }

  // ------------------------------------------------------------ 外 (main.js / 操作パッド) から見る状態
  /** タイトル系の画面か (640x400 で描く画面)。false ならゲーム画面。 */
  get menuScene() { return this.scene === Scene.Title || this.scene === Scene.HiScores || this.scene === Scene.NameEntry || this.scene === Scene.Achievements; }
  /** SELECT でタイトルに帰れる場面か。プレイ中はポーズしてからだけ受け付ける。 */
  get canBackToTitle() {
    if (this.scene === Scene.Title || this.scene === Scene.StageIntro) return false;
    if (this.scene === Scene.Play) return this.paused;
    return true;
  }
  /** ギブアップできる場面か (プレイ中で、ボーナスステージではない)。 */
  get canGiveUp() { return this.scene === Scene.Play && this.world !== null && !this.world.bonus; }
  /** プレイ中ならポーズする (画面が裏に回ったとき、並べ方が変わったときなど)。 */
  pauseIfPlaying() { if (this.scene === Scene.Play) this.paused = true; }
  /** ギブアップ (ポーズ中の R と同じ)。確認は操作パッド側で取る。 */
  giveUp() {
    if (!this.canGiveUp) return;
    Achievements.unlock("GIVE_UP");
    this.score = this.stageStartScore;
    this.paused = false;
    this.beginStage();
  }

  // ------------------------------------------------------------ 更新

  update(dt) {
    this.clock += dt;
    this.t += dt;
    Achievements.updateToast(dt);
    switch (this.scene) {
      case Scene.Title: {
        Audio.playMusic(Tune.Title);
        const d = Input.pressedDir;
        if (d === Dir.Left || d === Dir.Right) {
          this.shiba = (this.shiba + (d === Dir.Left ? 2 : 1)) % 3;
          this.t = 0;
          Audio.play(Sfx.Select);
        } else if (d === Dir.Up) {
          Audio.play(Sfx.Select);
          this.attract = false; this.newRank = -1; this.viewTime = 30;
          this.go(Scene.HiScores);
        } else if (d === Dir.Down) {
          Audio.play(Sfx.Select);
          this.achCursor = 0;
          this.go(Scene.Achievements);
        } else if (Input.confirm) {
          Audio.play(Sfx.Start);
          this.stage = this.startStage; this.lives = 3; this.score = 0; this.attract = false;
          this.nextExtend = FirstExtend;
          if (this.startBonus) this.beginBonus(); else this.beginStage();
        } else if (this.t > 12) { this.attract = true; this.newRank = -1; this.viewTime = 8; this.go(Scene.HiScores); }
        break;
      }

      case Scene.HiScores:
        if (Input.anyPressed || this.t > this.viewTime) {
          if (this.attract && !Input.anyPressed) {
            this.world = new World(1 + Math.trunc(this.clock * 7) % 3, this.shiba, 3, 0, true);
            this.go(Scene.Demo);
          } else this.go(Scene.Title);
        }
        break;

      case Scene.Achievements: {
        const ad = Input.pressedDir;
        if (ad !== null) {
          const cols = Achievements.Columns, count = Achievements.All.length;
          let c = this.achCursor % cols, r = Math.trunc(this.achCursor / cols);
          const rowsN = Math.trunc((count + cols - 1) / cols);
          if (ad === Dir.Left) c = (c + cols - 1) % cols;
          if (ad === Dir.Right) c = (c + 1) % cols;
          if (ad === Dir.Up) r = (r + rowsN - 1) % rowsN;
          if (ad === Dir.Down) r = (r + 1) % rowsN;
          this.achCursor = Math.min(r * cols + c, count - 1);
          Audio.play(Sfx.Select);
        } else if (Input.back || Input.confirm || this.t > 60) { Audio.play(Sfx.Select); this.go(Scene.Title); }
        break;
      }

      case Scene.Demo:
        this.world.update(dt, null, false);
        if (Input.anyPressed || this.t > 45 || this.world.finished) { this.world = null; this.go(Scene.Title); }
        break;

      case Scene.StageIntro:
        if (Input.back) { this.toTitle(); break; }
        if (this.t > (this.world.bonus ? 4 : 2.2)) {
          // 夜のボーナスステージは、ゆっくりした曲(タイトルと同じ)
          Audio.playMusic(this.world.bonus ? Tune.Title : Tune.Game);
          this.go(Scene.Play);
        }
        break;

      case Scene.Play: {
        const w = this.world;
        // Esc (パッドの BACK) は、プレイ中はまずポーズ。ポーズ中にもう一度でタイトルへ
        // (ブラウザでは Esc がフルスクリーン解除も兼ねるので、いきなり記録が消えないように)
        if (Input.back) {
          if (this.paused) { this.toTitle(); break; }
          this.paused = true; Audio.play(Sfx.Select);
        } else if (Input.pressed("KeyP") || Input.padPause) { this.paused = !this.paused; Audio.play(Sfx.Select); }
        if (this.paused) {
          // ギブアップ: ポーズ中に R (パッドは Y) で、このステージを最初からやり直す
          if (Input.pressed("KeyR") && !w.bonus) {
            Achievements.unlock("GIVE_UP");
            this.score = this.stageStartScore;
            this.beginStage();
          }
          break;
        }
        w.update(dt, Input.held, Input.action, Input.pressedDir);
        this.score = w.score;
        this.checkExtend(w);
        this.lives = w.lives;
        if (this.score >= 100000) Achievements.unlock("SCORE_100K");
        if (w.gameOver) {
          Audio.playMusic(Tune.None);
          Audio.play(Sfx.GameOver);
          this.go(Scene.GameOver);
        } else if (w.finished) {
          Audio.playMusic(Tune.None);
          this.bonusPts = 0;
          if (w.bonus) {
            Audio.play(Sfx.StageClear);
            Achievements.unlock("BONUS_CLEAR");
            if (w.perfect) Achievements.unlock("BONUS_PERFECT");
          } else if (w.cleared) {
            this.bonusPts = w.player.area * 5 + Math.trunc(w.timeLeft) * 10 + 500 * this.stage;
            this.score += this.bonusPts; w.score = this.score;
            this.checkExtend(w);
            this.lives = w.lives;
            Audio.play(Sfx.StageClear);
            this.stageClearAchievements(w);
          } else Audio.play(Sfx.StageFail);
          if (this.score >= 100000) Achievements.unlock("SCORE_100K");
          this.go(Scene.StageResult);
        }
        break;
      }

      case Scene.StageResult:
        if ((this.t > 1.5 && Input.confirm) || this.t > 9) {
          const done = this.world;
          if (done.bonus) { this.stage++; this.beginStage(); }                 // ボーナスの次は通常ステージ
          else if (done.cleared && this.stage % 4 === 0) this.beginBonus();    // 4の倍数をクリアしたらボーナス
          else {
            if (done.cleared) this.stage++;
            else this.score = this.stageStartScore;      // 失敗: 同じステージをやり直す
            this.beginStage();
          }
        }
        break;

      case Scene.GameOver:
        if ((this.t > 1.5 && Input.anyPressed) || this.t > 5) {
          this.world = null;
          Audio.playMusic(Tune.Title);
          if (this.hi.qualifies(this.score)) {
            this.name = ["A", "A", "A"]; this.namePos = 0;
            this.go(Scene.NameEntry);
          } else { this.attract = false; this.newRank = -1; this.viewTime = 8; this.go(Scene.HiScores); }
        }
        break;

      case Scene.NameEntry:
        this.updateNameEntry();
        break;
    }
  }

  stageClearAchievements(w) {
    if (this.stage === 4) Achievements.unlock("STAGE4");
    if (this.stage === 8) Achievements.unlock("STAGE8");
    if (this.stage === 16) Achievements.unlock("STAGE16");
    if (w.misses === 0) Achievements.unlock("NO_MISS");
    if (w.timeLeft >= StageTime - 120) Achievements.unlock("SPEEDY");
    // 柴犬の3色それぞれでクリアしたか (途中経過は画面に出さない)
    Achievements.mark("_SHIBA" + this.shiba);
    if (Achievements.has("_SHIBA0") && Achievements.has("_SHIBA1") && Achievements.has("_SHIBA2"))
      Achievements.unlock("ALL_SHIBA");
  }

  /** 得点が基準を超えたら残機を1つ増やす。基準は下がらないので、やり直しで二度は増えない。 */
  checkExtend(w) {
    while (this.score >= this.nextExtend) {
      this.nextExtend += ExtendEvery;
      w.lives++;
      w.announce("1UP!", 0xFF3030);
      Audio.play(Sfx.Extend);
      Achievements.unlock("ONE_UP");
    }
  }

  beginStage() {
    this.stageStartScore = this.score;
    this.paused = false;
    this.world = new World(this.stage, this.shiba, this.lives, this.score, false);
    Audio.playMusic(Tune.None);
    Audio.play(Sfx.Bark);
    Input.endFrame();
    this.go(Scene.StageIntro);
  }

  /** 夜のボーナスステージ(ステージ番号なし)。 */
  beginBonus() {
    this.bonusStartScore = this.score;
    this.paused = false;
    this.world = new World(this.stage, this.shiba, this.lives, this.score, false, true);
    Audio.playMusic(Tune.None);
    Audio.play(Sfx.Start);
    Input.endFrame();
    this.go(Scene.StageIntro);
  }

  toTitle() {
    this.world = null; this.paused = false;
    Audio.playMusic(Tune.Title);
    this.go(Scene.Title);
  }

  updateNameEntry() {
    for (const key of Input.pressedKeys) {
      let typed = "";
      if (/^Key[A-Z]$/.test(key)) typed = key[3];
      else if (/^Digit[0-9]$/.test(key)) typed = key[5];
      const ci = NameChars.indexOf(this.name[this.namePos]);
      if (key === "ArrowUp") { this.name[this.namePos] = NameChars[(ci + 1) % NameChars.length]; Audio.play(Sfx.Select); }
      else if (key === "ArrowDown") { this.name[this.namePos] = NameChars[(ci + NameChars.length - 1) % NameChars.length]; Audio.play(Sfx.Select); }
      else if (key === "ArrowLeft" || key === "Backspace") { this.namePos = Math.max(0, this.namePos - 1); Audio.play(Sfx.Select); }
      else if (key === "ArrowRight") { this.namePos = Math.min(2, this.namePos + 1); Audio.play(Sfx.Select); }
      else if (key === "Enter" || key === "NumpadEnter" || key === "Space") {
        if (this.namePos < 2) { this.namePos++; Audio.play(Sfx.Select); }
        else {
          this.newRank = this.hi.add(this.name.join(""), this.score, this.stage);
          this.viewTime = 8;
          Achievements.unlock("HIGH_SCORE");
          Audio.play(Sfx.NameOk);
          this.attract = false;
          this.go(Scene.HiScores);
          return;
        }
      } else if (typed !== "") {
        this.name[this.namePos] = typed;
        this.namePos = Math.min(2, this.namePos + 1);
        Audio.play(Sfx.Select);
      }
    }
  }

  // ------------------------------------------------------------ 描画: 画面の組み合わせ

  /** PC版と同じ 640x400 の画面 (フィールド + 右のパネル、タイトルなども)。 */
  drawWide() {
    Gfx.clear(0x000000);
    switch (this.scene) {
      case Scene.Title: this.drawTitle(); break;
      case Scene.HiScores: this.drawBackdrop(); this.drawHiScores(); break;
      case Scene.NameEntry: this.drawBackdrop(); this.drawNameEntry(); break;
      case Scene.Achievements: this.drawBackdrop(); this.drawAchievements(); break;
      default:
        if (this.world) {
          this.drawField(this.world);
          this.drawPanel(this.world);
          this.drawOverlay(this.world);
        }
        break;
    }
    Achievements.drawToast();
  }

  /** タイトル系の画面だけ (640x400)。 */
  drawMenu() { this.drawWide(); }

  /** ゲーム画面だけ (480x400)。フィールドと、その上に重なる案内。 */
  drawFieldOnly() {
    Gfx.clear(0x000000);
    if (this.world) {
      this.drawField(this.world);
      this.drawOverlay(this.world);
    }
    Achievements.drawToast();
  }

  // ------------------------------------------------------------ 描画: 各画面

  drawAchievements() {
    const CX = Gfx.W / 2;
    const all = Achievements.All;
    this.box(40, 10, 560, 380);
    Gfx.textCenter("ACHIEVEMENTS", CX, 22, 0xFFD840, 3);
    Gfx.textCenter(`${Achievements.unlocked} / ${all.length} UNLOCKED`, CX, 52, 0x9AA4C8);

    const GX = 64, GY = 70, Cell = 64;
    for (let i = 0; i < all.length; i++) {
      const x = GX + i % Achievements.Columns * Cell + 12, y = GY + Math.trunc(i / Achievements.Columns) * Cell + 8;
      Achievements.drawPlate(i, x, y, Achievements.has(all[i].id));
      if (i === this.achCursor) {
        const col = (Math.trunc(this.clock * 4) & 1) === 0 ? 0xFFFFFF : 0xFFD840;
        Gfx.frame(x - 4, y - 4, 48, 48, col);
        Gfx.frame(x - 3, y - 3, 46, 46, col);
      }
    }

    const def = all[this.achCursor];
    const when = Achievements.when(def.id);
    Gfx.fill(64, 270, 512, 84, 0x0C0E18, 200);
    Gfx.frame(64, 270, 512, 84, 0x3A4468);
    if (when) {
      const p2 = n => String(n).padStart(2, "0");
      const stamp = `${when.getFullYear()}-${p2(when.getMonth() + 1)}-${p2(when.getDate())} ${p2(when.getHours())}:${p2(when.getMinutes())}`;
      Gfx.textCenter(def.name, CX, 280, 0xFFFFFF, 2);
      Gfx.textCenter(def.desc, CX, 306, 0xC0C8E0);
      Gfx.textCenter("UNLOCKED " + stamp, CX, 330, 0xFFD840);
    } else {
      Gfx.textCenter("??????", CX, 280, 0x5A6488, 2);
      Gfx.textCenter("??????????????????", CX, 306, 0x5A6488);
      Gfx.textCenter("LOCKED", CX, 330, 0x5A6488);
    }
    Gfx.textCenter(this.touch ? "PAD: SELECT    PEE: BACK" : "ARROWS: SELECT    ESC / SPACE: BACK", CX, 366, 0x9AA4C8);
  }

  static groundTile(w, x, y) {
    if (w && y < FH && w.laneOf[y] === 1) return Art.RoadTop;
    if (w && y < FH && w.laneOf[y] === 2) return Art.RoadBottom;
    return (x * 7 + y * 13 + x * y) % 5 === 0 ? Art.Grass1 : Art.Grass0;
  }

  /** 地面は動かないので、ステージごとに1枚の絵にしておく。 */
  groundOf(w) {
    if (w._ground) return w._ground;
    const c = document.createElement("canvas");
    c.width = FieldW; c.height = FieldH;
    const saved = [Gfx.ctx, Gfx.W, Gfx.H];
    Gfx.target(c.getContext("2d"), FieldW, FieldH);
    for (let y = 0; y < FH; y++)
      for (let x = 0; x < FW; x++)
        Gfx.draw(App.groundTile(w, x, y), x * Tile, y * Tile);
    Gfx.target(...saved);
    w._ground = c;
    return c;
  }

  drawField(w) {
    const T = Tile;
    Gfx.clip(0, 0, FieldW, Gfx.H);
    Gfx.ctx.drawImage(this.groundOf(w), 0, 0);

    // なわばり(犬ごとの色)
    for (let y = 0; y < FH; y++)
      for (let x = 0; x < FW; x++) {
        const o = w.terr[y * FW + x];
        if (o < 0) continue;
        const col = w.dogs[o].color;
        Gfx.fill(x * T, y * T, T, T, col, 150);
        if (((x + y) & 1) === 0) Gfx.fill(x * T + 6, y * T + 6, 4, 4, Gfx.shade(col, 1.25), 110);
        const edge = Gfx.shade(col, 0.6);
        if (x === 0 || w.terr[y * FW + x - 1] !== o) Gfx.fill(x * T, y * T, 2, T, edge);
        if (x === FW - 1 || w.terr[y * FW + x + 1] !== o) Gfx.fill(x * T + T - 2, y * T, 2, T, edge);
        if (y === 0 || w.terr[(y - 1) * FW + x] !== o) Gfx.fill(x * T, y * T, T, 2, edge);
        if (y === FH - 1 || w.terr[(y + 1) * FW + x] !== o) Gfx.fill(x * T, y * T + T - 2, T, 2, edge);
        const f = w.flash[y * FW + x];
        if (f > 0) Gfx.fill(x * T, y * T, T, T, 0xFFFFFF, Math.trunc(f * 200));
      }

    // 作りかけの三角形(おしっこ済みの電柱を点線で結ぶ)
    for (const d of w.dogs) {
      if (!d.alive) continue;
      const a = d.isPlayer ? 255 : 170;
      for (let i = 1; i < d.chain.length; i++)
        this.chainLine(w, d.chain[i - 1], d.chain[i], d.color, a);
      if (d.peeT > 0 && d.peePole >= 0 && (Math.trunc(this.clock * 8) & 1) === 0) {
        // 完成予定の三角形の予告線。柴犬の場合、成立しない三角形は赤で警告する
        const col = d.isPlayer && w.peeOutcome(d) === false ? 0xFF2020 : d.color;
        for (let i = Math.max(0, d.chain.length - 2); i < d.chain.length; i++)
          this.chainLine(w, d.chain[i], d.peePole, col, a);
      }
    }

    // 電柱
    for (let i = 0; i < w.poles.length; i++) {
      const p = w.poles[i];
      if (p.owner >= 0) {
        Gfx.tint(Art.PeeMark, w.dogs[p.owner].color);
        Gfx.draw(Art.PeeMark, p.x * T, p.y * T);
      }
      Gfx.draw(Art.Pole, p.x * T, p.y * T);
      if (p.locked && p.owner >= 0) {
        Gfx.tint(Art.PoleBand, w.dogs[p.owner].color);
        Gfx.draw(Art.PoleBand, p.x * T, p.y * T);
      }
      if (w.player.chain.includes(i) && (Math.trunc(this.clock * 4) & 1) === 0)
        Gfx.frame(p.x * T, p.y * T, T, T, 0xFFFFFF);
    }

    // アイテム(消える3秒前から点滅)
    for (const it of w.items) {
      if (it.t < 3 && (Math.trunc(this.clock * 8) & 1) === 0) continue;
      const bob = Math.sin(this.clock * 5 + it.x) * 1.5;
      Gfx.fill(it.x * T + 4, it.y * T + 13, 8, 2, 0x000000, 70);
      Gfx.draw(Art.Items[it.kind], it.x * T, it.y * T - 2 + bob);
    }

    // 犬(奥から手前の順)
    const order = w.dogs.filter(d => d.alive);
    order.sort((a, b) => a.y !== b.y ? a.y - b.y : b.id - a.id);
    for (const d of order) this.drawDog(w, d);

    for (const c of w.cars) Gfx.draw(Art.Cars[c.color], c.x, c.row * T, c.sign > 0);

    this.drawWeather(w);
    if (w.bonus) this.drawNight(w);

    for (const p of w.popups) Gfx.text(p.text, p.x, p.y, p.color);

    Gfx.unclip();
  }

  /** 雨の予告と雨。効果中のアイテムの残り時間もここで出す。 */
  drawWeather(w) {
    const CX = FieldW / 2;
    if (w.rainWarn > 0) {
      Gfx.fill(0, 0, FieldW, Gfx.H, 0x101830, Math.trunc((5 - w.rainWarn) / 5 * 90));
      if ((Math.trunc(this.clock * 4) & 1) === 0) Gfx.textCenter("RAIN IS COMING!", CX, 30, 0x80C0FF, 2);
      Gfx.textCenter(`${Math.ceil(w.rainWarn)}`, CX, 52, 0xFFFFFF, 2);
    } else if (w.rainT > 0) {
      Gfx.fill(0, 0, FieldW, Gfx.H, 0x101830, Math.trunc(Math.min(1, w.rainT) * 90));
      for (let i = 0; i < 90; i++) {
        const x = (i * 97 + this.clock * 60) % (FieldW + 40) - 20;
        const y = (i * 53 + this.clock * (420 + i % 5 * 30)) % (Gfx.H + 20) - 10;
        Gfx.fill(x, y, 1, 7, 0xB0D8FF, 170);
      }
    }

    const pl = w.player;
    let hy = 4;
    if (pl.boneT > 0) {
      Gfx.draw(Art.Items[0], 4, hy);
      Gfx.text(`${Math.ceil(pl.boneT)}`, 24, hy + 4, 0xFFFFFF);
      hy += 18;
    }
    if (pl.passT > 0) {
      Gfx.draw(Art.Items[1], 4, hy);
      Gfx.text(`${Math.ceil(pl.passT)}`, 24, hy + 4, 0xC0A0FF);
    }
  }

  /** 夜の暗がり。柴犬の周りと、印をつけた電柱の周り、自分のなわばりだけが明るい。 */
  drawNight(w) {
    const lights = [];
    const [ppx, ppy] = w.dogPixel(w.player);
    lights.push([ppx + 8, ppy + 8, 64 + Math.sin(this.clock * 3) * 2]);
    for (const p of w.poles)
      if (p.owner === 0) lights.push([p.x * 16 + 8, p.y * 16 + 6, p.locked ? 44 : 36]);

    const B = 8;
    for (let gy = 0; gy < Gfx.H / B; gy++)
      for (let gx = 0; gx < FieldW / B; gx++) {
        const cx = gx * B + B / 2, cy = gy * B + B / 2;
        let dark = 1;
        for (const [lx, ly, r] of lights) {
          const dx = cx - lx, dy = cy - ly;
          const dist = Math.sqrt(dx * dx + dy * dy);
          const f = clamp((dist - r * 0.5) / (r * 0.5), 0, 1);
          if (f < dark) dark = f;
        }
        if (w.terr[Math.trunc(gy * B / 16) * FW + Math.trunc(gx * B / 16)] === 0) dark = Math.min(dark, 0.35);   // 自分のなわばりはうっすら明るい
        dark = Math.round(dark * 4) / 4;      // 4段階にして段々をはっきりさせる
        if (dark > 0) Gfx.fill(gx * B, gy * B, B, B, 0x060A20, Math.trunc(dark * 208));
      }

    for (const d of w.dogs) {
      if (d.isPlayer || !d.alive) continue;
      const [px, py] = w.dogPixel(d);
      if (d.asleep) {
        const u = (this.clock * 0.8 + d.id * 0.37) % 1;
        Gfx.text("z", px + 10 + u * 6, py - 4 - u * 10, 0xC0D0FF, 1, false);
        Gfx.text("Z", px + 14 + ((u + 0.5) % 1) * 6, py - 10 - ((u + 0.5) % 1) * 10, 0x90A8FF, 1, false);
      } else {
        Gfx.fill(px + 4, py + 5, 2, 2, 0xFFF060);
        Gfx.fill(px + 10, py + 5, 2, 2, 0xFFF060);
      }
    }

    // 星
    for (let i = 0; i < 14; i++) {
      const sx = (i * 131) % FieldW, sy = (i * 71) % 60;
      if ((Math.trunc(this.clock * 2 + i) % 5) !== 0) Gfx.fill(sx, sy, 1, 1, 0xFFFFE0, 200);
    }
  }

  chainLine(w, a, b, color, alpha) {
    const p = w.poles[a], q = w.poles[b];
    Gfx.dotted(p.x * 16 + 8, p.y * 16 + 8, q.x * 16 + 8, q.y * 16 + 8, 0x000000, this.clock * 12 + 1, Math.trunc(alpha / 2));
    Gfx.dotted(p.x * 16 + 8, p.y * 16 + 8, q.x * 16 + 8, q.y * 16 + 8, color, this.clock * 12, alpha);
  }

  drawDog(w, d) {
    if (d.invuln > 0 && (Math.trunc(this.clock * 14) & 1) === 0) return;
    const [px, py, stride] = w.dogPixel(d);
    if (d.asleep) {
      // 眠っている犬: 正面向きで、寝息に合わせて少し上下する
      Gfx.draw(Art.Dogs[d.breedIndex][0], px, py + (Math.sin(this.clock * 2 + d.id) > 0 ? 1 : 0));
      return;
    }
    const vertical = d.dir === Dir.Down || d.dir === Dir.Up;
    let idx = (d.dir === Dir.Down ? 0 : d.dir === Dir.Up ? 2 : 4) + (stride ? 1 : 0);
    // 横向きの絵は右向き。左向きは反転。上下移動は一歩ごとに出す足を入れ替える
    let flip = d.dir === Dir.Left || (vertical && stride && d.stepFlip);
    if (d.peeT > 0 && d.peePole >= 0) {
      // 電柱のある側の後ろ足を上げたポーズ
      idx = d.dir === Dir.Up ? 7 : d.dir === Dir.Down ? 8 : 6;
      flip = d.dir === Dir.Left || d.dir === Dir.Up;
    }
    const sprite = Art.Dogs[d.breedIndex][idx];
    // 巻物の効果中は半透明(切れる3秒前から点滅)
    const ghost = d.passT > 0 && !d.boss;
    if (ghost) Gfx.tint(sprite, 0xD8C8FF, d.passT < 3 && (Math.trunc(this.clock * 10) & 1) === 0 ? 230 : 130);
    if (d.boss) Gfx.draw(sprite, px - 8, py - 16, flip, 2);   // ボスは2倍の大きさ(足元をマスに合わせる)
    else Gfx.draw(sprite, px, py, flip);
    if (ghost) Gfx.tint(sprite, 0xFFFFFF, 255);

    if (d.peeT > 0 && d.peePole >= 0) {
      // おしっこ: しずくと残り時間バー
      const pole = w.poles[d.peePole];
      const tx = pole.x * 16 + 8, ty = pole.y * 16 + 13, sx = px + 8, sy = py + 11;
      for (let k = 0; k < 3; k++) {
        const u = (this.clock * 3 + k / 3) % 1;
        Gfx.fill(sx + (tx - sx) * u - 1, sy + (ty - sy) * u - Math.sin(u * Math.PI) * 4, 2, 2, 0xFFF060);
      }
      const prog = 1 - d.peeT / d.peeTotal;
      Gfx.fill(px, py - 5, 16, 4, 0x000000, 200);
      Gfx.fill(px + 1, py - 4, 14 * prog, 2, d.color);
    } else if (d.isPlayer && this.scene === Scene.StageIntro) {
      const bob = Math.abs(Math.sin(this.clock * 6)) * 4;
      Gfx.text("YOU", px - 4, py - 14 - bob, 0xFFFF60);
    }
  }

  drawPanel(w) {
    const X = FieldW + 8;
    Gfx.fill(FieldW, 0, Gfx.W - FieldW, Gfx.H, PanelBg);
    Gfx.fill(FieldW, 0, 2, Gfx.H, 0x0C0E18);
    Gfx.fill(FieldW + 2, 0, 1, Gfx.H, 0x3A4468);

    Gfx.text("SHIBA JINTORI", X + 20, 8, 0xFFB040);
    Gfx.tint(Art.Paw, 0xFFB040);
    Gfx.draw(Art.Paw, X, 4);
    Gfx.tint(Art.Paw, 0xFFFFFF);

    if (w.bonus) Gfx.text("BONUS STAGE", X, 30, 0xFFE040);
    else Gfx.text(`STAGE ${pad0(w.stage, 2)}`, X, 30, 0xFFFFFF);
    Gfx.text("SCORE", X, 46, 0x9AA4C8); Gfx.text(pad0(w.score, 7), X + 88, 46);
    Gfx.text("HI", X, 58, 0x9AA4C8); Gfx.text(pad0(Math.max(this.hi.top, w.score), 7), X + 88, 58);

    Gfx.text("LIVES", X, 78, 0x9AA4C8);
    this.drawLives(w, X + 48, 73, X + 70, 78);

    const time = Math.ceil(w.timeLeft);
    Gfx.text("TIME", X, 98, 0x9AA4C8);
    Gfx.text(padL(time, 3), X + 120, 98, time <= 20 && (Math.trunc(this.clock * 4) & 1) === 0 ? 0xFF5050 : 0xFFFFFF);

    // 全体のなわばり率。3/4 (白い目印) でステージ終了
    const total = FW * FH;
    Gfx.text("AREA", X, 116, 0x9AA4C8);
    Gfx.text(`${padL(Math.trunc(w.claimed * 100 / total), 3)}%/75%`, X + 80, 116);
    Gfx.fill(X, 128, 144, 10, 0x0C0E18);
    let bx = X;
    for (const d of w.dogs) {
      const bw = d.area * 144 / total;
      Gfx.fill(bx, 129, bw, 8, d.color);
      bx += bw;
    }
    Gfx.fill(X + 108, 126, 1, 14, 0xFFFFFF);

    // 犬ごとの面積
    let y = 148;
    for (const d of w.dogs) {
      if (d.isPlayer) Gfx.fill(X - 4, y - 2, 152, 20, 0x2C3558);
      Gfx.fill(X - 4, y - 2, 3, 20, d.color);
      const s = Art.Dogs[d.breedIndex][0];
      Gfx.tint(s, d.alive ? 0xFFFFFF : 0x606060);
      Gfx.draw(s, X + 2, y);
      Gfx.tint(s, 0xFFFFFF);
      Gfx.text(d.alive ? Breeds[d.breedIndex].display : "OUT", X + 22, d.isPlayer ? y + 4 : y, d.alive ? 0xFFFFFF : 0x808080);
      if (!d.isPlayer) {
        const note = !w.bonus ? d.t.trait : !d.alive ? "CAUGHT" : d.asleep ? "ZZZ" : "AWAKE!";
        Gfx.text(note, X + 22, y + 9, w.bonus && d.alive && !d.asleep ? 0xFFF060 : 0x7C86AC, 1, false);
      }
      Gfx.text(padL(d.area, 3), X + 120, y + 4, d.color);
      y += 21;
    }

    if (this.touch) {
      Gfx.text("PAD   : MOVE", X, 360, 0x7C86AC);
      Gfx.text("PEE   : PEE (3s)", X, 372, 0x7C86AC);
      Gfx.text("START : PAUSE", X, 384, 0x7C86AC);
    } else {
      // パネル幅は 152px (19字) しかないので 1 行 16 字までに収める
      if (this.pads > 0) Gfx.text("GAMEPAD: OK", X, 336, 0x60D080);
      Gfx.text("ARROWS: MOVE", X, 348, 0x7C86AC);
      Gfx.text("SPACE : PEE (3s)", X, 358, 0x7C86AC);
      Gfx.text("P/ESC : PAUSE", X, 368, 0x7C86AC);
      Gfx.text(Audio.mode === SoundMode.All ? "M:SOUND ALL" : Audio.mode === SoundMode.SfxOnly ? "M:SOUND SE" : "M:SOUND OFF", X, 378, 0x7C86AC);
      Gfx.text(this.isFullscreen() ? "F:WINDOW" : "F:FULLSCREEN", X, 388, 0x7C86AC);
    }
  }

  /** 残機。5つまでは並べ、6つ以上は「絵 x 数」で出す。 */
  drawLives(w, x, y, tx, ty) {
    const s = Art.Dogs[w.player.breedIndex][0];
    if (w.lives <= 5) {
      for (let i = 0; i < w.lives; i++) Gfx.draw(s, x + i * 18, y);
    } else {
      Gfx.draw(s, x, y);
      Gfx.text(`x ${w.lives}`, tx, ty);
    }
  }

  drawOverlay(w) {
    const CX = FieldW / 2;
    const touch = this.touch;
    switch (this.scene) {
      case Scene.StageIntro:
        if (w.bonus) {
          this.box(100, 140, 280, 100);
          Gfx.textCenter("BONUS STAGE", CX, 152, 0xFFE040, 3);
          Gfx.textCenter("SURROUND THE SLEEPING DOGS!", CX, 188, 0xFFFFFF);
          Gfx.textCenter("SHH... DON'T WAKE THEM UP", CX, 202, 0xC0D0FF);
          Gfx.textCenter("NO LIVES LOST - 60 SECONDS", CX, 220, 0x9AA4C8);
        } else {
          this.box(120, 150, 240, 70);
          Gfx.textCenter(`STAGE ${w.stage}`, CX, 162, 0xFFFFFF, 3);
          Gfx.textCenter(this.t < 1.4 ? "READY?" : "GO!", CX, 196, 0xFFE040, 2);
          if (w.hasBoss && (Math.trunc(this.clock * 4) & 1) === 0) Gfx.textCenter("!! BOSS DOG APPEARS !!", CX, 232, 0xFF5050);
        }
        break;

      case Scene.StageResult:
        if (w.bonus) {
          const enemies = w.dogs.length - 1;
          this.box(100, 130, 280, 140);
          Gfx.textCenter(w.perfect ? "PERFECT!!" : "BONUS RESULT", CX, 142, 0xFFE040, 2);
          Gfx.text("TERRITORY", 124, 174); Gfx.text(`${padL(w.player.area, 3)} x ${BonusCellScore}`, 292, 174, 0xFFFFFF);
          Gfx.text("DOGS CAUGHT", 124, 190); Gfx.text(`${w.bonusCaught} / ${enemies}`, 316, 190, 0xFFFFFF);
          if (w.perfect) Gfx.textCenter(`PERFECT BONUS +${BonusPerfect}`, CX, 208, 0xFFF060);
          Gfx.textCenter(`TOTAL +${w.score - this.bonusStartScore}`, CX, 228, 0xFFE040, 2);
          if (this.t > 1.5 && (Math.trunc(this.clock * 2) & 1) === 0)
            Gfx.textCenter(touch ? "TAP PEE: NEXT STAGE" : "PRESS SPACE: NEXT STAGE", CX, 254, 0x9AA4C8);
        } else {
          const list = [...w.dogs];
          list.sort((a, b) => b.area !== a.area ? b.area - a.area : a.id - b.id);
          const h = 96 + list.length * 18;
          const top = Math.trunc((Gfx.H - h) / 2);
          this.box(90, top, 300, h);
          if (w.cleared) Gfx.textCenter("STAGE CLEAR!", CX, top + 10, 0xFFE040, 2);
          else Gfx.textCenter("STAGE FAILED", CX, top + 10, 0xFF5050, 2);
          let y = top + 36;
          const total = FW * FH;
          for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (d.isPlayer) Gfx.fill(100, y - 1, 280, 18, 0x38457A);
            Gfx.text(`${i + 1}`, 108, y + 4, 0x9AA4C8);
            Gfx.draw(Art.Dogs[d.breedIndex][0], 124, y);
            Gfx.text(Breeds[d.breedIndex].display + (d.isPlayer ? " (YOU)" : ""), 146, y + 4);
            Gfx.text(`${padL(d.area, 3)} ${padL(Math.trunc(d.area * 100 / total), 2)}%`, 316, y + 4, d.color);
            y += 18;
          }
          y += 6;
          if (w.cleared) Gfx.textCenter(`BONUS +${this.bonusPts}`, CX, y, 0xFFFFFF);
          else Gfx.textCenter("YOUR TERRITORY WAS TOO SMALL", CX, y, 0xFFFFFF);
          if (this.t > 1.5 && (Math.trunc(this.clock * 2) & 1) === 0)
            Gfx.textCenter(w.cleared ? (touch ? "TAP PEE: NEXT STAGE" : "PRESS SPACE: NEXT STAGE")
                                     : (touch ? "TAP PEE: TRY AGAIN" : "PRESS SPACE: TRY AGAIN"), CX, y + 18, 0xFFE040);
        }
        break;

      case Scene.Play:
        if (!this.paused) break;
        this.box(120, 150, 240, 96);
        Gfx.textCenter("PAUSE", CX, 160, 0xFFFFFF, 3);
        Gfx.textCenter(touch ? "START   : RESUME" : "P / START : RESUME", CX, 194, 0xFFFFFF);
        if (!w.bonus) Gfx.textCenter(touch ? "GIVE UP : RETRY STAGE" : "R / Y     : RETRY STAGE", CX, 208, 0xFFE040);
        Gfx.textCenter(touch ? "SELECT  : TITLE" : "ESC / BACK: TITLE", CX, 222, 0x9AA4C8);
        break;

      case Scene.Demo:
        if ((Math.trunc(this.clock * 2) & 1) === 0) Gfx.textCenter("- DEMO -", CX, 12, 0xFFFFFF, 2);
        Gfx.textCenter(touch ? "TOUCH THE PAD" : "PRESS ANY KEY", CX, 380, 0xFFE040);
        break;

      case Scene.GameOver:
        this.box(110, 160, 260, 70);
        Gfx.textCenter("GAME OVER", CX, 172, 0xFF5050, 3);
        Gfx.textCenter(`SCORE ${this.score}`, CX, 208, 0xFFFFFF);
        break;
    }
  }

  box(x, y, w, h) {
    Gfx.fill(x + 3, y + 3, w, h, 0x000000, 120);
    Gfx.fill(x, y, w, h, 0x1B2033, 235);
    Gfx.frame(x, y, w, h, 0xFFFFFF);
    Gfx.frame(x + 2, y + 2, w - 4, h - 4, 0x3A4468);
  }

  drawBackdrop() {
    if (!this._backdrop) {
      const c = document.createElement("canvas");
      c.width = 640; c.height = 400;
      const saved = [Gfx.ctx, Gfx.W, Gfx.H];
      Gfx.target(c.getContext("2d"), 640, 400);
      for (let y = 0; y < 400 / 16; y++)
        for (let x = 0; x < 640 / 16; x++)
          Gfx.draw(App.groundTile(null, x, y), x * 16, y * 16);
      Gfx.fill(0, 0, 640, 400, 0x102018, 120);
      Gfx.target(...saved);
      this._backdrop = c;
    }
    Gfx.ctx.drawImage(this._backdrop, 0, 0);
  }

  drawTitle() {
    this.drawBackdrop();
    const CX = Gfx.W / 2;
    const touch = this.touch;

    // 肉球の飾り
    Gfx.tint(Art.Paw, 0xFFFFFF, 60);
    for (let i = 0; i < 8; i++)
      Gfx.draw(Art.Paw, 40 + i * 78, 22 + (i & 1) * 26, (i & 1) === 1, 2);
    Gfx.tint(Art.Paw, 0xFFFFFF, 255);

    Gfx.textCenter(`HI-SCORE ${pad0(this.hi.top, 7)}`, CX, 6, 0xFFFFFF);
    const wob = Math.sin(this.clock * 2.5) * 3;
    Gfx.textCenter("SHIBA JINTORI", CX + 3, 43 + wob, 0x5A2A08, 5);
    Gfx.textCenter("SHIBA JINTORI", CX, 40 + wob, 0xFFB040, 5);
    Gfx.textCenter("- DEFEND YOUR TERRITORY! -", CX, 96, 0xFFFFFF, 1);

    // 柴犬の色えらび
    Gfx.textCenter("< SELECT YOUR SHIBA >", CX, 128, 0xFFE040);
    for (let i = 0; i < 3; i++) {
      const x = CX + (i - 1) * 96 - 24;
      let y = 148;
      const sel = i === this.shiba;
      if (sel) {
        Gfx.fill(x - 10, y - 6, 68, 78, 0x1B2033, 200);
        Gfx.frame(x - 10, y - 6, 68, 78, 0xFFE040);
        y -= Math.abs(Math.sin(this.clock * 5)) * 5;
      }
      const frame = sel && (Math.trunc(this.clock * 5) & 1) === 0 ? 1 : 0;
      Gfx.draw(Art.Dogs[i][frame], x, y, false, 3);
      Gfx.textCenter(ShibaNames[i], x + 24, 206, sel ? 0xFFFFFF : 0xA0A8A0);
    }

    if ((Math.trunc(this.clock * 2) & 1) === 0)
      Gfx.textCenter(touch ? "PRESS START TO BEGIN" : "PRESS SPACE OR ENTER TO START", CX, 244, 0xFFFFFF, 2);

    Gfx.textCenter("PEE ON 3 POLES TO CLAIM THE TRIANGLE AS YOUR TERRITORY.", CX, 280, 0xE0F0E0);
    Gfx.textCenter("DON'T GET SURROUNDED BY OTHER DOGS. WATCH OUT FOR CARS!", CX, 292, 0xE0F0E0);
    Gfx.textCenter(touch ? "PAD:MOVE   PEE:PEE ON A POLE   START:PAUSE"
                         : "ARROWS/WASD:MOVE  SPACE/Z:PEE  M:SOUND  " + (this.isFullscreen() ? "F:WINDOW" : "F:FULLSCREEN"), CX, 310, 0xA8C0A8);
    Gfx.textCenter("UP: HIGH SCORES     DOWN: ACHIEVEMENTS", CX, 322, 0xFFE040);

    // 行進する犬たち
    const count = EnemyBreedCount + 1;
    for (let i = 0; i < count; i++) {
      const breed = i === 0 ? this.shiba : ShibaCount + i - 1;
      let x = (this.clock * 44 - i * 34 - (i > 0 ? 40 : 0)) % (Gfx.W + 420) - 40;
      if (x < -40) x += Gfx.W + 420;
      const frame = 4 + (Math.trunc(this.clock * 7 + i) & 1);
      Gfx.draw(Art.Dogs[breed][frame], x, 336 + (frame === 5 ? -2 : 0), false, 2);
    }
    Gfx.fill(0, 370, Gfx.W, 30, 0x000000, 90);
    // "Copyright (C) 2026 wildtree with Claude AI"。内蔵フォントに (C) マークがないので、そこだけドットで描く
    const c1 = "Copyright", c2 = "2026 wildtree with Claude AI";
    const cx0 = Math.floor(CX - (c1.length + 1 + c2.length) * 4);
    Gfx.text(c1, cx0, 381, 0x90A890);
    const mark = ["..XXXX..", ".X....X.", "X..XX..X", "X.X....X", "X.X....X", "X..XX..X", ".X....X.", "..XXXX.."];
    for (let my = 0; my < 8; my++)
      for (let mx = 0; mx < 8; mx++)
        if (mark[my][mx] === "X") Gfx.fill(cx0 + c1.length * 8 + mx, 381 + my, 1, 1, 0x90A890);
    Gfx.text(c2, cx0 + (c1.length + 1) * 8, 381, 0x90A890);
    Gfx.text("v" + AppVersion, Gfx.W - 8 - (AppVersion.length + 1) * 8, 381, 0x708870);
  }

  drawHiScores() {
    const CX = Gfx.W / 2;
    this.box(140, 30, 360, 330);
    Gfx.textCenter("HIGH SCORES", CX, 44, 0xFFE040, 3);
    Gfx.text("RANK  NAME    SCORE  STAGE", 216, 86, 0x9AA4C8);
    for (let i = 0; i < this.hi.entries.length; i++) {
      const e = this.hi.entries[i];
      const me = i === this.newRank;
      const col = me && (Math.trunc(this.clock * 4) & 1) === 0 ? 0xFFE040 : i === 0 ? 0xFFB040 : 0xFFFFFF;
      const y = 106 + i * 22;
      if (me) Gfx.fill(196, y - 5, 248, 18, 0x38457A);
      Gfx.text(`${padL(i + 1, 3)}.   ${e.name}   ${padL(e.score, 7)}    ${padL(e.stage, 2)}`, 216, y, col);
    }
    Gfx.textCenter(this.touch ? "TOUCH THE PAD" : "PRESS ANY KEY", CX, 338, 0x9AA4C8);
  }

  drawNameEntry() {
    const CX = Gfx.W / 2;
    this.box(120, 80, 400, 240);
    Gfx.textCenter("YOU GOT A HIGH SCORE!", CX, 98, 0xFFE040, 2);
    Gfx.textCenter(`SCORE ${this.score}   STAGE ${this.stage}`, CX, 132, 0xFFFFFF);
    Gfx.textCenter("ENTER YOUR INITIALS", CX, 156, 0x9AA4C8);
    for (let i = 0; i < 3; i++) {
      const x = CX - 84 + i * 60;
      const cur = i === this.namePos;
      Gfx.fill(x, 178, 48, 56, cur ? 0x38457A : 0x0C0E18);
      Gfx.frame(x, 178, 48, 56, cur ? 0xFFE040 : 0x3A4468);
      Gfx.text(this.name[i], x + 8, 190, 0xFFFFFF, 4);
      if (cur && (Math.trunc(this.clock * 3) & 1) === 0) {
        Gfx.textCenter("^", x + 24, 168, 0xFFE040);
        Gfx.textCenter("v", x + 24, 238, 0xFFE040);
      }
    }
    Gfx.draw(Art.Dogs[this.shiba][Math.trunc(this.clock * 5) & 1], CX + 110, 186, false, 3);
    Gfx.textCenter(this.touch ? "UP/DOWN: LETTER" : "UP/DOWN OR TYPE: LETTER", CX, 264, 0x9AA4C8);
    Gfx.textCenter(this.touch ? "LEFT/RIGHT: MOVE   PEE: OK" : "LEFT/RIGHT: MOVE   ENTER: OK", CX, 278, 0x9AA4C8);
  }

  // ------------------------------------------------------------ タッチ操作のときのステータス (android/AppMobile.cs)

  /** 横向き (3列) の左の HUD (160x76)。ステージと残り時間、残機。 */
  drawHudLeft() {
    Gfx.clear(PanelBg);
    const w = this.world;
    if (!w) {
      Gfx.tint(Art.Paw, 0xFFB040);
      Gfx.draw(Art.Paw, 4, 4);
      Gfx.tint(Art.Paw, 0xFFFFFF);
      Gfx.text("SHIBA JINTORI", 24, 8, 0xFFB040);
      Gfx.text("HI-SCORE", 4, 30, 0x9AA4C8);
      Gfx.text(pad0(this.hi.top, 7), 4, 42, 0xFFE040, 2);
      Gfx.text("v" + AppVersion, 4, 66, 0x708870);
      return;
    }
    if (w.bonus) Gfx.text("BONUS", 4, 4, 0xFFE040, 2);
    else Gfx.text(`STAGE ${pad0(w.stage, 2)}`, 4, 4, 0xFFFFFF, 2);
    const time = Math.ceil(w.timeLeft);
    const timeCol = time <= 20 && (Math.trunc(this.clock * 4) & 1) === 0 ? 0xFF5050 : 0xFFFFFF;
    Gfx.text("TIME", 4, 32, 0x9AA4C8);
    Gfx.text(padL(time, 3), 52, 28, timeCol, 2);
    Gfx.text("LIVES", 4, 58, 0x9AA4C8);
    this.drawLives(w, 52, 53, 74, 58);
  }

  /** 横向き (3列) の右の HUD (160x182)。スコア、なわばりの割合、犬ごとの面積。 */
  drawHudRight() {
    Gfx.clear(PanelBg);
    const w = this.world;
    if (!w) {
      const help = ["PAD  : MOVE", "PEE  : DECIDE / PEE", "START: START, PAUSE", "SELECT: TITLE", "   (WHEN PAUSED)", "", "UP  : HIGH SCORES", "DOWN: ACHIEVEMENTS"];
      for (let i = 0; i < help.length; i++) Gfx.text(help[i], 4, 4 + i * 14, i < 5 ? 0x9AA4C8 : 0x7C86AC);
      return;
    }
    Gfx.text("SCORE", 4, 2, 0x9AA4C8);
    Gfx.text(pad0(w.score, 7), 4, 12, 0xFFFFFF, 2);
    Gfx.text("HI", 4, 32, 0x9AA4C8);
    Gfx.text(pad0(Math.max(this.hi.top, w.score), 7), 28, 32, 0xFFE040);

    const total = FW * FH;
    Gfx.text("AREA", 4, 46, 0x9AA4C8);
    Gfx.text(`${padL(Math.trunc(w.claimed * 100 / total), 3)}%/75%`, 52, 46, 0xFFFFFF);
    const BarX = 4, BarY = 58, BarW = 152;
    Gfx.fill(BarX, BarY, BarW, 10, 0x0C0E18);
    let bx = BarX;
    for (const d of w.dogs) {
      const bw = d.area * BarW / total;
      Gfx.fill(bx, BarY + 1, bw, 8, d.color);
      bx += bw;
    }
    Gfx.fill(BarX + BarW * 0.75, BarY - 2, 1, 14, 0xFFFFFF);

    let y = 74;
    for (const d of w.dogs) {
      if (d.isPlayer) Gfx.fill(2, y - 2, 156, 12, 0x2C3558);
      Gfx.fill(4, y, 6, 8, d.alive ? d.color : 0x505050);
      let name = d.alive ? Breeds[d.breedIndex].display : "OUT";
      let col = d.alive ? 0xFFFFFF : 0x808080;
      if (w.bonus && !d.isPlayer && d.alive) {
        name = d.asleep ? "ZZZ" : "AWAKE!";
        col = d.asleep ? 0x7C86AC : 0xFFF060;
      }
      Gfx.text(name, 14, y, col);
      Gfx.text(padL(d.area, 3), 132, y, d.color);
      y += 12;
    }
  }

  /** 縦画面用のステータス領域 (480x190)。この上に半透明の操作パッドが重なる。 */
  drawStatus() {
    const w = this.world;
    Gfx.clear(PanelBg);
    Gfx.fill(0, 0, StatusW, 1, 0x0C0E18);
    Gfx.fill(0, 1, StatusW, 1, 0x3A4468);

    if (!w) {
      Gfx.tint(Art.Paw, 0xFFB040);
      Gfx.draw(Art.Paw, 8, 8, false, 2);
      Gfx.text("SHIBA JINTORI", 44, 12, 0xFFB040, 2);
      Gfx.text(`HI-SCORE ${pad0(this.hi.top, 7)}`, 44, 40, 0xFFE040);
      Gfx.tint(Art.Paw, 0xFFFFFF);
      Gfx.text("PAD   : MOVE / SELECT", 12, 70, 0x9AA4C8);
      Gfx.text("PEE   : DECIDE, PEE ON A POLE", 12, 86, 0x9AA4C8);
      Gfx.text("START : START, PAUSE", 12, 102, 0x9AA4C8);
      Gfx.text("SELECT: BACK TO TITLE (WHEN PAUSED)", 12, 118, 0x9AA4C8);
      Gfx.text("UP: HIGH SCORES   DOWN: ACHIEVEMENTS", 12, 142, 0x7C86AC);
      Gfx.text("v" + AppVersion, StatusW - 8 - (AppVersion.length + 1) * 8, 170, 0x708870);
      return;
    }

    if (w.bonus) Gfx.text("BONUS", 10, 8, 0xFFE040, 2);
    else Gfx.text(`STAGE ${pad0(w.stage, 2)}`, 10, 8, 0xFFFFFF, 2);
    const time = Math.ceil(w.timeLeft);
    const timeCol = time <= 20 && (Math.trunc(this.clock * 4) & 1) === 0 ? 0xFF5050 : 0xFFFFFF;
    Gfx.text("TIME", 352, 12, 0x9AA4C8);
    Gfx.text(padL(time, 3), 400, 8, timeCol, 2);

    Gfx.text("SCORE", 10, 36, 0x9AA4C8);
    Gfx.text(pad0(w.score, 7), 58, 32, 0xFFFFFF, 2);
    Gfx.text("HI", 258, 36, 0x9AA4C8);
    Gfx.text(pad0(Math.max(this.hi.top, w.score), 7), 282, 36, 0xFFE040);

    Gfx.text("LIVES", 10, 58, 0x9AA4C8);
    this.drawLives(w, 58, 52, 80, 58);

    const total = FW * FH;
    Gfx.text("AREA", 258, 58, 0x9AA4C8);
    Gfx.text(`${padL(Math.trunc(w.claimed * 100 / total), 3)}%/75%`, 300, 58, 0xFFFFFF);
    const BarX = 10, BarY = 76, BarW = 460;
    Gfx.fill(BarX, BarY, BarW, 12, 0x0C0E18);
    let bx = BarX;
    for (const d of w.dogs) {
      const bw = d.area * BarW / total;
      Gfx.fill(bx, BarY + 1, bw, 10, d.color);
      bx += bw;
    }
    Gfx.fill(BarX + BarW * 0.75, BarY - 2, 1, 16, 0xFFFFFF);

    // 犬ごとの面積 (2列)
    const rowsN = Math.trunc((w.dogs.length + 1) / 2);
    for (let i = 0; i < w.dogs.length; i++) {
      const d = w.dogs[i];
      const x = i < rowsN ? 6 : 246, y = 96 + (i % rowsN) * 19;
      if (d.isPlayer) Gfx.fill(x, y - 2, 228, 18, 0x2C3558);
      Gfx.fill(x, y - 2, 3, 18, d.color);
      const s = Art.Dogs[d.breedIndex][0];
      Gfx.tint(s, d.alive ? 0xFFFFFF : 0x606060);
      Gfx.draw(s, x + 6, y);
      Gfx.tint(s, 0xFFFFFF);
      Gfx.text(d.alive ? Breeds[d.breedIndex].display : "OUT", x + 26, y, d.alive ? 0xFFFFFF : 0x808080);
      if (!d.isPlayer) {
        const note = !w.bonus ? d.t.trait : !d.alive ? "CAUGHT" : d.asleep ? "ZZZ" : "AWAKE!";
        Gfx.text(note, x + 26, y + 9, w.bonus && d.alive && !d.asleep ? 0xFFF060 : 0x7C86AC, 1, false);
      } else Gfx.text("(YOU)", x + 26, y + 9, 0xFFE040, 1, false);
      Gfx.text(padL(d.area, 3), x + 196, y + 4, d.color);
    }
  }
}
