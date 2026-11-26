"use strict";
// 1ステージ分のゲーム状態とルール (PC版 World.cs をそのまま移したもの)。描画とは独立している。

const Dir = { Down: 0, Left: 1, Right: 2, Up: 3 };
const DX = [0, -1, 1, 0];
const DY = [1, 0, 0, -1];

const FW = 30, FH = 25, Tile = 16;
const PeeTime = 3;
const GoalCells = Math.trunc((FW * FH * 3 + 3) / 4);   // 全体の3/4
const StageTime = 240;
// 追加要素が始まるステージ (調整用)
const ItemFromStage = 5, RainFromStage = 8, BossEvery = 8, BossPeeTime = 5;
// 夜のボーナスステージ
const BonusTime = 60, BonusCellScore = 30, BonusSleeping = 2000, BonusAwake = 1000, BonusPerfect = 5000;
const WakeWalk = 2, WakePee = 3;
const ItemLife = 12, BoneTime = 12, PassTime = 10;

function rnd(n) { return Math.floor(Math.random() * n); }   // C# の Random.Next(n)
function rndRange(a, b) { return a + Math.floor(Math.random() * (b - a)); }   // Random.Next(a, b)
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function newDog() {
  return {
    id: 0, breedIndex: 0, isPlayer: false, color: 0,
    x: 0, y: 0, fromX: 0, fromY: 0, dir: Dir.Down, moving: false, moveT: 0, stepTime: 0.15, stepFlip: false,
    peeT: 0, peePole: -1, chain: [],
    alive: true, invuln: 0, area: 0, carry: 0,
    asleep: false, awakeUntil: 0,
    boss: false, peeTotal: PeeTime, boneT: 0, passT: 0,
    target: -1, think: 0, t: TemperDefault, steps: 0,
  };
}

function removeFrom(list, v) {
  const i = list.indexOf(v);
  if (i < 0) return false;
  list.splice(i, 1);
  return true;
}

class World {
  constructor(stage, shibaColor, lives, score, demo, bonus = false) {
    this.stage = stage; this.demo = demo; this.lives = lives; this.score = score; this.bonus = bonus;
    this.bonusCaught = 0; this.misses = 0; this.perfect = false;
    this.timeLeft = bonus ? BonusTime : StageTime;
    this.claimed = 0;
    this.finished = false; this.cleared = false; this.gameOver = false;
    this.clock = 0;

    this.terr = new Int32Array(FW * FH);        // [y*FW+x] なわばりの持ち主 (-1: なし)
    this.flash = new Float32Array(FW * FH);
    this.poleAt = new Int32Array(FW * FH);
    this.laneOf = new Int32Array(FH);           // 0:なし 1:左行き車線 2:右行き車線
    this.poles = []; this.dogs = []; this.cars = []; this.popups = []; this.items = [];
    this.hasBoss = false;
    this.rainWarn = 0; this.rainT = 0;
    this._rainNext = Number.MAX_VALUE;
    this._itemSpawn = 6;
    this._fresh = new Uint8Array(FW * FH);
    this._laneSpawn = new Float32Array(FH);
    this._laneSpeed = new Float32Array(FH);
    this._actionBuffer = 0; this._dripT = 0;
    this._dirBuffer = Dir.Down; this._dirBufferT = 0;
    this._inTri = new Uint8Array(FW * FH);
    this._dist = new Int32Array(FW * FH);
    this._queue = new Int32Array(FW * FH);
    this._generate(shibaColor);
  }

  get player() { return this.dogs[0]; }
  T(x, y) { return this.terr[y * FW + x]; }

  /** 実績を解除する (デモ画面では解除しない)。 */
  _ach(id) { if (!this.demo) Achievements.unlock(id); }

  // ------------------------------------------------------------ 生成

  _generate(shibaColor) {
    this.terr.fill(-1); this.poleAt.fill(-1);

    // 道路(2車線)
    const roads = this.bonus ? 0 : this.stage >= 4 ? 2 : 1;
    const tops = [];
    for (let tries = 0; tops.length < roads && tries < 300; tries++) {
      const r = rndRange(4, FH - 6);
      let ok = true;
      for (const t of tops) if (Math.abs(t - r) < 6) ok = false;
      if (ok) tops.push(r);
    }
    for (const t of tops) {
      this.laneOf[t] = 1; this.laneOf[t + 1] = 2;
      for (let k = 0; k < 2; k++) {
        this._laneSpeed[t + k] = Math.min(210, 95 + rnd(60) + this.stage * 5);
        this._laneSpawn[t + k] = 1 + Math.random() * 3;
      }
    }

    // 電柱: 5x5のブロックごとに1本。外周のブロックは端に寄せる
    for (let by = 0; by < 5; by++)
      for (let bx = 0; bx < 6; bx++)
        for (let tries = 0; tries < 60; tries++) {
          let x = bx * 5 + rnd(5), y = by * 5 + rnd(5);
          if (bx === 0) x = rnd(2);
          if (bx === 5) x = FW - 1 - rnd(2);
          if (by === 0) y = rnd(2);
          if (by === 4) y = FH - 1 - rnd(2);
          if (this.laneOf[y] !== 0) continue;
          let near = false;
          for (const p of this.poles) if (Math.abs(p.x - x) <= 1 && Math.abs(p.y - y) <= 1) near = true;
          if (near) continue;
          this.poleAt[y * FW + x] = this.poles.length;
          this.poles.push({ x, y, owner: -1, locked: false });
          break;
        }

    // 柴犬(プレイヤー)
    const player = newDog();
    player.id = 0; player.isPlayer = true; player.breedIndex = shibaColor;
    player.color = Breeds[shibaColor].territoryColor; player.stepTime = 0.14;
    [player.x, player.y] = this._findCell((x, y) => Math.abs(x - Math.trunc(FW / 2)) <= 4 && Math.abs(y - Math.trunc(FH / 2)) <= 4);
    player.fromX = player.x; player.fromY = player.y;
    this.dogs.push(player);

    if (this.stage >= RainFromStage && !this.bonus) this._rainNext = 22 + Math.random() * 20;

    // 敵の犬: ステージ1は1匹、以後1匹ずつ増えて最大8匹。ボスのステージは 7匹 + ボス
    this.hasBoss = !this.bonus && this.stage >= BossEvery && this.stage % BossEvery === 0;
    const enemies = clamp(this.stage, 1, 8);
    for (let i = 0; i < enemies; i++) {
      const boss = this.hasBoss && i === enemies - 1;
      const breed = boss ? BossIndex : ShibaCount + i % EnemyBreedCount;
      const temper = temperFor(Breeds[breed]);
      const baseStep = Math.max(0.17, 0.30 - 0.012 * (this.stage - 1)) + Math.random() * 0.03;
      const d = newDog();
      d.id = this.dogs.length; d.breedIndex = breed; d.color = Breeds[breed].territoryColor; d.t = temper;
      d.stepTime = Math.max(0.12, baseStep * temper.speed);
      d.think = 0.5 + Math.random();
      d.steps = temper.stamina; d.boss = boss; d.asleep = this.bonus;
      if (this.bonus) d.stepTime = 0.2;
      [d.x, d.y] = this._findCell((x, y) => {
        for (const o of this.dogs)
          if (Math.abs(o.x - x) + Math.abs(o.y - y) < (o.isPlayer ? 9 : 4)) return false;
        return true;
      });
      d.fromX = d.x; d.fromY = d.y;
      this.dogs.push(d);
    }
  }

  _isFree(x, y) {
    return x >= 0 && y >= 0 && x < FW && y < FH && this.poleAt[y * FW + x] < 0 && this.laneOf[y] === 0 && this.terr[y * FW + x] < 0;
  }

  _findCell(extra) {
    for (let tries = 0; tries < 2000; tries++) {
      const x = rnd(FW), y = rnd(FH);
      if (this._isFree(x, y) && (tries > 1000 || extra(x, y))) return [x, y];
    }
    for (let y = 0; y < FH; y++)
      for (let x = 0; x < FW; x++)
        if (this.poleAt[y * FW + x] < 0 && this.terr[y * FW + x] < 0) return [x, y];
    for (let y = 0; y < FH; y++)
      for (let x = 0; x < FW; x++)
        if (this.poleAt[y * FW + x] < 0) return [x, y];
    return [0, 0];
  }

  // ------------------------------------------------------------ 更新

  /**
   * @param held 押しっぱなしの方向 (null: なし)
   * @param tapped このフレームに押された方向 (移動中の短い押下を取りこぼさないために覚えておく)
   */
  update(dt, held, actionPressed, tapped = null) {
    if (this.finished || this.gameOver) return;
    this.clock += dt;
    this.timeLeft -= dt;
    if (this.timeLeft <= 0) { this.timeLeft = 0; this._finish(); return; }

    for (let i = 0; i < this.flash.length; i++)
      if (this.flash[i] > 0) this.flash[i] = Math.max(0, this.flash[i] - dt);
    for (let i = this.popups.length - 1; i >= 0; i--) {
      this.popups[i].t -= dt; this.popups[i].y -= dt * 14;
      if (this.popups[i].t <= 0) this.popups.splice(i, 1);
    }

    if (actionPressed) this._actionBuffer = 0.25;
    else if (this._actionBuffer > 0) this._actionBuffer -= dt;
    if (tapped !== null) { this._dirBuffer = tapped; this._dirBufferT = 0.3; }
    else if (this._dirBufferT > 0) this._dirBufferT -= dt;

    this._updateCars(dt);
    if (this.gameOver) return;
    this._updateRain(dt);
    this._updateItems(dt);

    for (let i = 0; i < this.dogs.length; i++) {
      const d = this.dogs[i];
      if (!d.alive) continue;
      if (d.invuln > 0) d.invuln -= dt;

      if (d.moving) {
        d.moveT += dt;
        if (d.moveT >= d.stepTime) { d.moving = false; d.carry = Math.min(d.moveT - d.stepTime, d.stepTime * 0.4); }
      } else if (d.peeT > 0) {
        d.peeT -= dt;
        if (d.isPlayer) {
          this._dripT -= dt;
          if (this._dripT <= 0) { this._dripT = 0.13; Audio.play(Sfx.PeeDrip); }
        }
        if (d.peeT <= 0) { d.peeT = 0; this._completePee(d); }
      }
      if (this.finished || this.gameOver) return;
      if (!d.alive || d.moving || d.peeT > 0) continue;

      if (d.isPlayer && !this.demo) this._playerControl(d, held);
      else if (this.bonus && !d.isPlayer) this._bonusAi(d);
      else this._aiControl(d, dt);
      d.carry = 0;
    }

    // 身動きが取れなくなった柴犬は囲まれた扱い
    const pl = this.player;
    if (!this.bonus && !pl.moving && pl.peeT <= 0 && pl.invuln <= 0) {
      let stuck = true;
      for (let k = 0; k < 4; k++) if (this.canEnter(pl, pl.x + DX[k], pl.y + DY[k])) stuck = false;
      if (stuck) { this._popupDog(pl, "TRAPPED!", 0xFF4040); this._loseLife(); }
    }
  }

  _playerControl(d, held) {
    if (this._actionBuffer > 0) {
      let p = this._poleInFront(d);
      if (p < 0)
        for (let k = 0; k < 4 && p < 0; k++) {
          const nx = d.x + DX[k], ny = d.y + DY[k];
          if (nx >= 0 && ny >= 0 && nx < FW && ny < FH && this.poleAt[ny * FW + nx] >= 0) { p = this.poleAt[ny * FW + nx]; d.dir = k; }
        }
      if (p >= 0) {
        this._actionBuffer = 0;
        if (d.chain.includes(p)) { Audio.play(Sfx.Invalid); this._popupDog(d, "MARKED", 0xFFFFFF); }
        else { this._startPee(d, p); return; }
      }
    }
    // 押しっぱなしの方向を優先し、なければ直前に押された方向(先行入力)を使う
    let want = held;
    if (want === null && this._dirBufferT > 0) want = this._dirBuffer;
    if (want !== null) {
      this._dirBufferT = 0;
      if (this._tryMove(d, want)) {
        Audio.play(Sfx.Step);
        const t = this.terr[d.y * FW + d.x];
        if (d.passT > 0 && t >= 0 && t !== d.id) this._ach("NINJA");
      }
    }
  }

  /** いまおしっこ中の電柱で三角形が完成する場合、それがなわばりとして成立するか (null: 三角形にならない)。 */
  peeOutcome(d) {
    if (d.peePole < 0 || d.chain.includes(d.peePole) || d.chain.length < 2) return null;
    return this._evaluate(d.id, d.chain[d.chain.length - 2], d.chain[d.chain.length - 1], d.peePole, null) > 0;
  }

  _poleInFront(d) {
    const nx = d.x + DX[d.dir], ny = d.y + DY[d.dir];
    return nx >= 0 && ny >= 0 && nx < FW && ny < FH ? this.poleAt[ny * FW + nx] : -1;
  }

  /** 他の犬のなわばりと電柱には入れない。ボス犬と、巻物の効果中の犬は、なわばりを通れる。 */
  canEnter(d, x, y) {
    if (x < 0 || y < 0 || x >= FW || y >= FH || this.poleAt[y * FW + x] >= 0) return false;
    const t = this.terr[y * FW + x];
    return t < 0 || t === d.id || d.boss || d.passT > 0;
  }

  _tryMove(d, dir) {
    d.dir = dir;
    const nx = d.x + DX[dir], ny = d.y + DY[dir];
    if (!this.canEnter(d, nx, ny)) return false;
    d.fromX = d.x; d.fromY = d.y; d.x = nx; d.y = ny;
    d.moving = true; d.moveT = d.carry; d.carry = 0; d.stepFlip = !d.stepFlip;
    return true;
  }

  _startPee(d, pole) {
    d.peeTotal = (d.boss ? BossPeeTime : PeeTime) * (d.boneT > 0 ? 0.5 : 1);
    d.peeT = d.peeTotal; d.peePole = pole;
    if (d.isPlayer) this._dripT = 0;
  }

  _completePee(d) {
    const idx = d.peePole;
    d.peePole = -1;
    if (idx < 0) return;
    const pole = this.poles[idx];
    if (!pole.locked) {
      // なわばりになっていない電柱は上書きできる
      if (pole.owner >= 0 && pole.owner !== d.id) {
        const prev = this.dogs[pole.owner];
        removeFrom(prev.chain, idx);
        if (d.isPlayer || prev.isPlayer) Audio.play(Sfx.Overwrite);
        if (d.isPlayer) this._ach("OVERWRITE");
        if (prev.isPlayer) this._popupAt(pole.x, pole.y, "LOST!", 0xFF6060);
      }
      pole.owner = d.id;
    }
    removeFrom(d.chain, idx);
    d.chain.push(idx);
    if (d.isPlayer) Audio.play(Sfx.Mark);
    if (d.chain.length >= 3) this._tryTerritory(d);
  }

  _tryTerritory(d) {
    const ch = d.chain;
    const a = ch[ch.length - 3], b = ch[ch.length - 2], c = ch[ch.length - 1];
    const cells = [];
    const n = this._evaluate(d.id, a, b, c, cells);
    if (n <= 0) {
      // 作れない三角形。印は全部取り消して最初からやり直し
      for (const pi of d.chain)
        if (!this.poles[pi].locked && this.poles[pi].owner === d.id) this.poles[pi].owner = -1;
      d.chain.length = 0;
      if (d.isPlayer) { Audio.play(Sfx.Invalid); this._popupDog(d, "NO GOOD", 0xFFFFFF); }
      return;
    }

    this._fresh.fill(0);
    for (const i of cells) {
      // ボス犬の場合は、ほかの犬のなわばりだったマスも含まれる(奪い取る)
      const prev = this.terr[i];
      if (prev >= 0) this.dogs[prev].area--; else this.claimed++;
      this.terr[i] = d.id;
      this.flash[i] = 1;
      this._fresh[i] = 1;
    }
    d.area += n;
    d.chain.length = 0;
    this.items = this.items.filter(it => this.terr[it.y * FW + it.x] < 0);   // なわばりになった場所のアイテムは消える
    for (let i = 0; i < this.poles.length; i++) {
      const p = this.poles[i];
      if (this.terr[p.y * FW + p.x] !== d.id || (p.locked && p.owner === d.id)) continue;
      p.locked = true; p.owner = d.id;
      // なわばりに取り込まれた電柱についていた、ほかの犬の印は解除する
      for (const o of this.dogs)
        if (o !== d && removeFrom(o.chain, i) && o.isPlayer) this._popupAt(p.x, p.y, "LOST!", 0xFF6060);
    }

    if (d.isPlayer) {
      const gain = n * (this.bonus ? BonusCellScore : 10);
      this.score += gain;
      this._popupDog(d, "+" + gain, 0xFFFF60);
      Audio.play(Sfx.Territory);
      this._ach("FIRST_TURF");
      if (n >= 100) this._ach("BIG_TURF");
      if (d.area * 2 >= FW * FH) this._ach("HALF");
    } else Audio.play(Sfx.EnemyTerritory);

    // 囲まれた犬の処理
    let caught = 0;
    for (const o of this.dogs) {
      // 今回新しく取ったマスにいる犬だけが対象
      if (!o.alive || o === d || !this._fresh[o.y * FW + o.x]) continue;
      if (o.isPlayer) {
        this._popupDog(o, "CAUGHT!", 0xFF4040);
        this._ach("GOT_CAUGHT");
        this._loseLife();
        if (this.gameOver) return;
      } else {
        o.alive = false;
        o.chain.length = 0;
        for (const p of this.poles)
          if (!p.locked && p.owner === o.id) p.owner = -1;
        const bonus = this.bonus ? (o.asleep ? BonusSleeping : BonusAwake) : o.boss ? 3000 : 500;
        if (this.bonus) this.bonusCaught++;
        this._popupDog(o, d.isPlayer ? "OUT! +" + bonus : "OUT!", 0xFFFFFF);
        if (d.isPlayer) {
          this.score += bonus;
          caught++;
          this._ach("CATCH_DOG");
          if (o.boss) this._ach("BOSS_DOWN");
        }
        Audio.play(Sfx.EnemyOut);
      }
    }
    if (caught >= 2) this._ach("DOUBLE_CATCH");

    if (this.bonus) {
      // 全員囲んだらパーフェクトで終了
      let any = false;
      for (const o of this.dogs) if (!o.isPlayer && o.alive) any = true;
      if (!any) { this.perfect = true; this.score += BonusPerfect; this._finish(); }
      return;
    }
    if (this.claimed >= GoalCells) this._finish();
  }

  /**
   * 電柱 a,b,c の三角形で新しく取れるマス数を返す。作れない場合は -1。
   * 作れない条件: 一直線 / 新しく取れるマスがない / 三角形の内側に他の犬のなわばりが少しでもある。
   * ボス犬だけは例外で、内側にあるほかの犬のなわばりも「取れるマス」に数える。
   * 呼び出し後 _inTri に三角形内のマスが入っている。
   */
  _evaluate(id, a, b, c, outCells) {
    const A = this.poles[a], B = this.poles[b], C = this.poles[c];
    const area2 = (B.x - A.x) * (C.y - A.y) - (B.y - A.y) * (C.x - A.x);
    if (area2 === 0) return -1;
    this._inTri.fill(0);
    const minX = Math.min(A.x, B.x, C.x), maxX = Math.max(A.x, B.x, C.x);
    const minY = Math.min(A.y, B.y, C.y), maxY = Math.max(A.y, B.y, C.y);
    let n = 0, other = false;
    const steal = this.dogs[id].boss;
    for (let y = minY; y <= maxY; y++)
      for (let x = minX; x <= maxX; x++) {
        const d1 = (B.x - A.x) * (y - A.y) - (B.y - A.y) * (x - A.x);
        const d2 = (C.x - B.x) * (y - B.y) - (C.y - B.y) * (x - B.x);
        const d3 = (A.x - C.x) * (y - C.y) - (A.y - C.y) * (x - C.x);
        const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
        if (neg && pos) continue;
        const i = y * FW + x;
        this._inTri[i] = 1;
        const t = this.terr[i];
        if (t < 0) { n++; if (outCells) outCells.push(i); }
        else if (t !== id) {
          if (steal) { n++; if (outCells) outCells.push(i); }
          else if (d1 !== 0 && d2 !== 0 && d3 !== 0) other = true;
        }
      }
    if (n === 0 || other) return -1;
    return n;
  }

  _loseLife() {
    const d = this.player;
    this.misses++;
    Audio.play(Sfx.Miss);
    if (!this.demo) {
      this.lives--;
      if (this.lives <= 0) { this.lives = 0; this.gameOver = true; return; }
    }
    this._respawn(d);
    d.invuln = 3;
  }

  _respawn(d) {
    d.peeT = 0; d.peePole = -1; d.moving = false; d.target = -1;
    [d.x, d.y] = this._findCell((x, y) => {
      for (let k = 0; k < 4; k++) if (this._isFree(x + DX[k], y + DY[k])) return true;
      return false;
    });
    d.fromX = d.x; d.fromY = d.y;
  }

  _finish() {
    if (this.finished) return;
    this.finished = true;
    if (this.bonus) { this.cleared = true; return; }
    let best = 0;
    for (const d of this.dogs) if (!d.isPlayer && d.area > best) best = d.area;
    this.cleared = this.player.area > 0 && this.player.area >= best;
  }

  /** 柴犬の頭上に文字を出す(残機が増えたときなど)。 */
  announce(text, color) { this._popupAt(this.player.x, this.player.y - 1, text, color); }
  _popupDog(d, text, color) { this._popupAt(d.x, d.y, text, color); }
  _popupAt(cx, cy, text, color) {
    const x = clamp(cx * Tile + 8 - text.length * 4, 2, FW * Tile - text.length * 8 - 2);
    this.popups.push({ x, y: cy * Tile - 6, t: 1.4, text, color });
  }

  // ------------------------------------------------------------ 雨とアイテム

  /** 雨: 5秒の予告のあと降りだし、降りだした瞬間に「まだなわばりになっていない印」が全部流れる。 */
  _updateRain(dt) {
    if (this.rainT > 0) { this.rainT -= dt; return; }
    if (this.rainWarn > 0) {
      this.rainWarn -= dt;
      if (this.rainWarn > 0) return;
      this.rainWarn = 0;
      this.rainT = 4;
      this._rainNext = 35 + Math.random() * 25;
      for (const p of this.poles) if (!p.locked) p.owner = -1;
      for (const d of this.dogs) {
        if (d.isPlayer && d.alive && d.chain.length > 0) {
          this._popupDog(d, "WASHED AWAY!", 0x80C0FF);
          this._ach("WASHED");
        }
        d.chain.length = 0;
        d.target = -1;
      }
      Audio.play(Sfx.Rain);
      return;
    }
    this._rainNext -= dt;
    if (this._rainNext <= 0) { this.rainWarn = 5; Audio.play(Sfx.Thunder); }
  }

  /** アイテム: 骨 (おしっこが半分の時間に) と忍者の巻物 (ほかのなわばりを通り抜けられる)。 */
  _updateItems(dt) {
    for (let i = this.items.length - 1; i >= 0; i--) {
      this.items[i].t -= dt;
      if (this.items[i].t <= 0) this.items.splice(i, 1);
    }

    if (this.stage >= ItemFromStage && !this.bonus) {
      this._itemSpawn -= dt;
      if (this._itemSpawn <= 0) {
        this._itemSpawn = 9 + Math.random() * 9;
        if (this.items.length < 2) {
          const [x, y] = this._findCell((cx, cy) => {
            for (const o of this.dogs) if (o.alive && Math.abs(o.x - cx) + Math.abs(o.y - cy) < 3) return false;
            for (const it of this.items) if (it.x === cx && it.y === cy) return false;
            return true;
          });
          if (this._isFree(x, y)) this.items.push({ x, y, kind: rnd(3) === 0 ? 1 : 0, t: ItemLife });
        }
      }
    }

    for (const d of this.dogs) {
      if (!d.alive) continue;
      if (d.boneT > 0) d.boneT -= dt;
      if (d.passT > 0) {
        d.passT -= dt;
        const t = this.terr[d.y * FW + d.x];
        if (d.passT <= 0 && !d.boss && t >= 0 && t !== d.id) {
          // 効果が切れたとき他のなわばりの中にいたら、外へ放り出される(残機は減らない)
          this._popupDog(d, "KICKED OUT!", 0xC0A0FF);
          if (d.isPlayer) Audio.play(Sfx.Kicked);
          this._respawn(d);
          d.invuln = 1.5;
        }
      }

      for (let i = this.items.length - 1; i >= 0; i--) {
        const it = this.items[i];
        if (it.x !== d.x || it.y !== d.y) continue;
        this.items.splice(i, 1);
        if (it.kind === 0) {
          d.boneT = BoneTime;
          this._popupDog(d, d.isPlayer ? "BONE! +100" : "BONE!", 0xFFFFFF);
          if (d.isPlayer) this._ach("BONE");
        } else { d.passT = PassTime; this._popupDog(d, d.isPlayer ? "NINJA! +100" : "NINJA!", 0xC0A0FF); }
        if (d.isPlayer) { this.score += 100; Audio.play(Sfx.Item); }
      }
    }
  }

  // ------------------------------------------------------------ 車

  _updateCars(dt) {
    for (let r = 0; r < FH; r++) {
      if (this.laneOf[r] === 0) continue;
      this._laneSpawn[r] -= dt;
      if (this._laneSpawn[r] > 0) continue;
      const sign = this.laneOf[r] === 1 ? -1 : 1;
      this.cars.push({ row: r, sign, speed: this._laneSpeed[r], x: sign < 0 ? FW * Tile : -32, color: rnd(4) });
      this._laneSpawn[r] = Math.max(1.5, 5.5 - this.stage * 0.3) * (0.6 + Math.random() * 0.9);
    }
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i];
      c.x += c.sign * c.speed * dt;
      if (c.x < -40 || c.x > FW * Tile + 8) { this.cars.splice(i, 1); continue; }
      for (const d of this.dogs) {
        if (!d.alive || d.invuln > 0) continue;
        const [px, py] = this.dogPixel(d);
        if (px + 13 < c.x + 2 || px + 3 > c.x + 30 || py + 13 < c.row * Tile + 3 || py + 3 > c.row * Tile + 14) continue;
        Audio.play(Sfx.CarHit);
        if (d.isPlayer) {
          this._popupDog(d, "OUCH!", 0xFF4040);
          this._ach("CAR_HIT");
          this._loseLife();
          if (this.gameOver) return;
        } else {
          this._popupDog(d, "KYAN!", 0xFFFFFF);
          this._respawn(d);
          d.invuln = 2; d.think = 1;
        }
      }
    }
  }

  /** t秒以内に(x,row)のマスへ車が来るか。 */
  _carDanger(x, row, t) {
    const cx0 = x * Tile - 6, cx1 = x * Tile + Tile + 6;
    for (const c of this.cars) {
      if (c.row !== row) continue;
      const a = c.x, b = c.x + c.sign * c.speed * t;
      const lo = Math.min(a, b), hi = Math.max(a, b) + 32;
      if (hi > cx0 && lo < cx1) return true;
    }
    // これから画面外から入ってくる車
    if (this.laneOf[row] !== 0 && this._laneSpawn[row] < t) {
      const reach = this._laneSpeed[row] * (t - Math.max(0, this._laneSpawn[row]));
      if (this.laneOf[row] === 1 ? FW * Tile - reach < cx1 : -32 + reach + 32 > cx0) return true;
    }
    return false;
  }

  /** 描画位置 [x, y, stride]。移動の前半は8ドットずらした位置で足を伸ばした絵、後半は移動先で立ち絵。 */
  dogPixel(d) {
    if (d.moving && d.moveT < d.stepTime * 0.5)
      return [d.fromX * Tile + (d.x - d.fromX) * 8, d.fromY * Tile + (d.y - d.fromY) * 8, true];
    return [d.x * Tile, d.y * Tile, false];
  }

  // ------------------------------------------------------------ ボーナスステージの犬

  _bonusAi(d) {
    const pl = this.player;
    const dist = Math.abs(pl.x - d.x) + Math.abs(pl.y - d.y);
    if (d.asleep) {
      if (dist > WakeWalk && !(pl.peeT > 0 && dist <= WakePee)) return;
      d.asleep = false;
      d.awakeUntil = this.clock + 5;
      this._popupDog(d, "!?", 0xFFFF60);
      Audio.play(Sfx.Bark);
      return;
    }
    if (this.clock >= d.awakeUntil && dist >= 6) {
      d.asleep = true; d.dir = Dir.Down;
      return;
    }
    // 柴犬からいちばん遠ざかる方向へ(少し気まぐれ)
    let best = -1, bestScore = -Number.MAX_VALUE;
    for (let k = 0; k < 4; k++) {
      const nx = d.x + DX[k], ny = d.y + DY[k];
      if (!this.canEnter(d, nx, ny)) continue;
      const s = Math.abs(pl.x - nx) + Math.abs(pl.y - ny) + Math.random() * 1.5;
      if (s > bestScore) { bestScore = s; best = k; }
    }
    if (best >= 0) this._tryMove(d, best);
  }

  // ------------------------------------------------------------ 敵AI

  _aiControl(d, dt) {
    d.think -= dt;
    if (d.think > 0) return;

    if (d.target >= 0 && d.chain.includes(d.target)) d.target = -1;
    if (d.target < 0) {
      this._chooseTarget(d);
      if (d.target < 0) { this._wander(d); d.think = 0.25; return; }
    }

    const pole = this.poles[d.target];
    if (Math.abs(pole.x - d.x) + Math.abs(pole.y - d.y) === 1) {
      for (let k = 0; k < 4; k++)
        if (d.x + DX[k] === pole.x && d.y + DY[k] === pole.y) d.dir = k;
      const ch = d.chain;
      if (ch.length >= 2 && this._evaluate(d.id, ch[ch.length - 2], ch[ch.length - 1], d.target, null) < 0) {
        d.target = -1;      // 状況が変わって三角形が作れなくなった
        return;
      }
      this._startPee(d, d.target);
      d.target = -1;
      d.think = (0.15 + Math.random() * (this.stage >= 6 ? 0.2 : 0.6)) * d.t.dither;
      return;
    }

    const dir = this._nextStepToward(d, pole);
    if (dir < 0) { d.target = -1; this._wander(d); d.think = 0.2; return; }
    const nx = d.x + DX[dir], ny = d.y + DY[dir];
    if (this.laneOf[ny] !== 0 && (d.t.caution >= 1 || Math.random() < d.t.caution)) {
      // 車が来ていたら渡らずに待つ(道路の上にいるときは急いで抜ける)。用心深い犬ほど早めに止まる
      const look = Math.max(1, d.t.caution);
      let danger = this._carDanger(nx, ny, d.stepTime * 2.2 * look);
      const ny2 = ny + DY[dir];
      if (!danger && DY[dir] !== 0 && ny2 >= 0 && ny2 < FH && this.laneOf[ny2] !== 0)
        danger = this._carDanger(nx, ny2, d.stepTime * 3.4 * look);
      if (danger && this.laneOf[d.y] === 0) { d.dir = dir; d.think = 0.12; return; }
    }
    if (!this._tryMove(d, dir) || d.t.stamina <= 0) return;

    // スタミナ切れ: 道路の上では休まない
    if (--d.steps > 0) return;
    if (this.laneOf[d.y] !== 0) { d.steps = 1; return; }
    d.steps = Math.trunc(d.t.stamina * (0.6 + Math.random() * 0.8));
    d.think = d.t.restTime * (0.7 + Math.random() * 0.6);
    if (d.t.restText.length > 0) this._popupDog(d, d.t.restText, 0xFFFFFF);
  }

  _wander(d) {
    const k = rnd(4);
    const ny = d.y + DY[k];
    if (ny >= 0 && ny < FH && this.laneOf[ny] !== 0 && this.laneOf[d.y] === 0) return;
    this._tryMove(d, k);
  }

  /** dから歩いて行けるマスまでの歩数を _dist に入れる(行けないマスは -1)。 */
  _flood(d) {
    const dist = this._dist, q = this._queue;
    dist.fill(-1);
    let head = 0, tail = 0;
    q[tail++] = d.y * FW + d.x; dist[d.y * FW + d.x] = 0;
    while (head < tail) {
      const cur = q[head++];
      const cx = cur % FW, cy = Math.trunc(cur / FW);
      for (let k = 0; k < 4; k++) {
        const nx = cx + DX[k], ny = cy + DY[k];
        if (!this.canEnter(d, nx, ny)) continue;
        const ni = ny * FW + nx;
        if (dist[ni] >= 0) continue;
        dist[ni] = dist[cur] + 1; q[tail++] = ni;
      }
    }
  }

  /** 電柱の隣まで歩く歩数(_dist基準)。行けなければ -1。 */
  _travelTo(p) {
    let best = -1;
    for (let k = 0; k < 4; k++) {
      const nx = p.x + DX[k], ny = p.y + DY[k];
      if (nx < 0 || ny < 0 || nx >= FW || ny >= FH) continue;
      const v = this._dist[ny * FW + nx];
      if (v >= 0 && (best < 0 || v < best)) best = v;
    }
    return best;
  }

  _chooseTarget(d) {
    this._flood(d);
    const travel = this.poles.map(p => this._travelTo(p));

    for (let attempt = 0; attempt < 2; attempt++) {
      let best = -1, bestScore = -Number.MAX_VALUE;
      const pl = this.player;
      const ch = d.chain;
      for (let i = 0; i < this.poles.length; i++) {
        if (travel[i] < 0 || ch.includes(i)) continue;
        const p = this.poles[i];
        let s;
        if (ch.length === 0) {
          s = -travel[i] + Math.random() * 10 * d.t.noise;
          if (!p.locked && p.owner >= 0 && p.owner !== d.id) s += 4 * d.t.steal;   // 他の犬の印を上書きしたがる
          if (p.locked && p.owner !== d.id) s -= 3;
          // 攻撃的な犬は柴犬の近くから始める
          if (!d.isPlayer && d.t.aggro > 1)
            s -= (Math.abs(p.x - pl.x) + Math.abs(p.y - pl.y)) * 0.35 * (d.t.aggro - 1);
        } else if (ch.length === 1) {
          const f = this.poles[ch[0]];
          const ideal = Math.min(15, d.t.reach + Math.trunc(this.stage / 3));
          const dd = Math.abs(f.x - p.x) + Math.abs(f.y - p.y);
          s = -Math.abs(dd - ideal) * 1.5 - travel[i] * 0.5 + Math.random() * 6 * d.t.noise;
        } else {
          const n = this._evaluate(d.id, ch[ch.length - 2], ch[ch.length - 1], i, null);
          if (n < 0) continue;
          s = Math.min(n, 150) * d.t.sizeWeight - travel[i] * 1.2 + Math.random() * 12 * d.t.noise;
          // 柴犬を囲めるなら狙う
          if (!d.isPlayer && pl.invuln <= 0 && this._inTri[pl.y * FW + pl.x]) s += (30 + this.stage * 3) * d.t.aggro;
          // ほかの犬を囲めるなら狙う (デモの柴犬と、牧羊犬気質の犬)
          const herd = d.isPlayer ? 1.6 : d.t.herd;
          if (herd > 0)
            for (const o of this.dogs)
              if (o.alive && o !== d && !o.isPlayer && this._inTri[o.y * FW + o.x]) s += 25 * herd;
        }
        if (s > bestScore) { bestScore = s; best = i; }
      }
      if (best >= 0) { d.target = best; return; }
      if (ch.length < 2) return;
      ch.shift();    // 3本目が見つからないので組み直す
    }
  }

  /** 電柱の隣のマスへ向かう最短経路の最初の一歩。行けなければ -1。 */
  _nextStepToward(d, pole) {
    const dist = this._dist, q = this._queue;
    dist.fill(-1);
    let head = 0, tail = 0;
    for (let k = 0; k < 4; k++) {
      const gx = pole.x + DX[k], gy = pole.y + DY[k];
      if (!this.canEnter(d, gx, gy)) continue;
      dist[gy * FW + gx] = 0; q[tail++] = gy * FW + gx;
    }
    while (head < tail) {
      const cur = q[head++];
      const cx = cur % FW, cy = Math.trunc(cur / FW);
      for (let k = 0; k < 4; k++) {
        const nx = cx + DX[k], ny = cy + DY[k];
        if (!this.canEnter(d, nx, ny)) continue;
        const ni = ny * FW + nx;
        if (dist[ni] >= 0) continue;
        dist[ni] = dist[cur] + 1; q[tail++] = ni;
      }
    }
    const here = dist[d.y * FW + d.x];
    if (here <= 0) return -1;
    let bestDir = -1, bestDist = here;
    const startK = rnd(4);
    for (let j = 0; j < 4; j++) {
      const k = (startK + j) % 4;
      const nx = d.x + DX[k], ny = d.y + DY[k];
      if (!this.canEnter(d, nx, ny)) continue;
      const v = dist[ny * FW + nx];
      if (v >= 0 && v < bestDist) { bestDist = v; bestDir = k; }
    }
    return bestDir;
  }
}
