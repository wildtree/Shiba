"use strict";
// 半透明の操作パッド (android/TouchPad.cs を移したもの)。
// 左に十字キー、右におしっこ(トリガー)とギブアップ、中央に SELECT と START、左上に音の切り替え。
// 置き方は2通り: 横長の帯 (layoutBand) と、左右の列 (layoutColumns)。座標は画面の実ドット。

const Btn = { None: 0, Up: 1, Down: 2, Left: 3, Right: 4, Trigger: 5, Start: 6, Select: 7, GiveUp: 8, Sound: 9 };
const BtnCount = 10;
const PadColor = { Cyan: 0x4FD2FF, Orange: 0xFFA040, Red: 0xFF5A5A, Gray: 0xA8B4D8 };

function rect(l, t, r, b) { return { l, t, r, b, get w() { return this.r - this.l; }, get h() { return this.b - this.t; }, get cx() { return (this.l + this.r) / 2; }, get cy() { return (this.t + this.b) / 2; } }; }
function rgba(rgb, a) { return `rgba(${(rgb >> 16) & 255},${(rgb >> 8) & 255},${rgb & 255},${a / 255})`; }

const Haptics = {
  tick() { if (navigator.vibrate) try { navigator.vibrate(6); } catch (e) { /* 使えない */ } },
  click() { if (navigator.vibrate) try { navigator.vibrate(14); } catch (e) { /* 使えない */ } },
};

class TouchPad {
  constructor() {
    this.bounds = rect(0, 0, 0, 0);
    this.shade = rect(0, 0, 0, 0); this.hasShade = false;
    this.q = 1;
    this.dcx = 0; this.dcy = 0; this.dsize = 1; this.dthick = 1;
    this.tcx = 0; this.tcy = 0; this.trad = 1;
    this.start = rect(0, 0, 0, 0); this.select = rect(0, 0, 0, 0); this.giveUpR = rect(0, 0, 0, 0); this.sound = rect(0, 0, 0, 0);
    this.arms = [rect(0, 0, 0, 0), rect(0, 0, 0, 0), rect(0, 0, 0, 0), rect(0, 0, 0, 0)];   // Dir の順
    this.art = null;
    this.touches = new Map();
    this.state = new Array(BtnCount).fill(false);
    this.armT = 0;     // ギブアップの確認待ち (秒)
    this.flashT = 0;   // 音を切り替えた直後の表示
  }

  /** 横長の帯に置く。帯が基準寸法より広いときは、十字キーとおしっこを左右の端へ寄せる。 */
  layoutBand(area, qMax) {
    const w = area.w, h = area.h;
    const q = this.q = Math.max(1, Math.min(Math.min(w, h / 0.64), qMax));
    const spread = Math.max(0, (w - q) / 2);
    const left = area.l + (w - q) / 2;
    const lx = left - spread, rx = left + spread;
    const bottom = area.b - 0.04 * q;
    const top = bottom - 0.60 * q;

    this.placeDpad(lx + 0.245 * q, bottom - 0.21 * q);
    this.placeTrigger(rx + 0.775 * q, bottom - 0.225 * q);

    const pw = 0.185 * q, ph = 0.082 * q, mid = left + 0.53 * q;
    this.start = rect(mid - pw / 2, bottom - 0.40 * q, mid + pw / 2, bottom - 0.40 * q + ph);
    this.select = rect(mid - pw / 2, bottom - 0.22 * q, mid + pw / 2, bottom - 0.22 * q + ph);

    const gw = 0.30 * q, gh = 0.095 * q, gcx = rx + 0.78 * q;
    this.giveUpR = rect(gcx - gw / 2, top, gcx + gw / 2, top + gh);
    const bw = 0.23 * q;
    this.sound = rect(lx + 0.03 * q, top, lx + 0.03 * q + bw, top + gh);

    this.shade = rect(area.l, area.t, area.r, area.b);
    this.hasShade = true;
    this.finish();
  }

  /** 横向き用。左の列: 十字キーと START / SELECT。右の列: おしっこと音・ギブアップ。 */
  layoutColumns(left, right, q) {
    q = this.q = Math.max(1, q);
    const bottom = Math.min(left.b, right.b) - 0.04 * q;

    this.placeDpad(left.cx, bottom - 0.21 * q);
    const pw = 0.185 * q, ph = 0.082 * q, gap = 0.03 * q;
    const rowTop = this.dcy - this.dsize / 2 - 0.22 * q - ph;
    const lc = left.cx;
    this.start = rect(lc - gap / 2 - pw, rowTop, lc - gap / 2, rowTop + ph);
    this.select = rect(lc + gap / 2, rowTop, lc + gap / 2 + pw, rowTop + ph);

    this.placeTrigger(right.cx, bottom - 0.225 * q);
    const gw = 0.26 * q, bw = 0.21 * q, gh = 0.095 * q;
    const top = this.tcy - this.trad - 0.07 * q - gh;
    const x0 = right.cx - (bw + gap + gw) / 2;
    this.sound = rect(x0, top, x0 + bw, top + gh);
    this.giveUpR = rect(x0 + bw + gap, top, x0 + bw + gap + gw, top + gh);

    this.hasShade = false;
    this.finish();
  }

  placeDpad(cx, cy) {
    this.dsize = 0.38 * this.q;
    this.dthick = this.dsize * 0.40;
    this.dcx = cx; this.dcy = cy;
    const half = this.dsize / 2, t2 = this.dthick / 2;
    this.arms[Dir.Up] = rect(cx - t2, cy - half, cx + t2, cy - t2);
    this.arms[Dir.Down] = rect(cx - t2, cy + t2, cx + t2, cy + half);
    this.arms[Dir.Left] = rect(cx - half, cy - t2, cx - t2, cy + t2);
    this.arms[Dir.Right] = rect(cx + t2, cy - t2, cx + half, cy + t2);
  }

  placeTrigger(cx, cy) { this.trad = 0.125 * this.q; this.tcx = cx; this.tcy = cy; }

  finish() {
    const m = 0.05 * this.q, half = this.dsize / 2;
    let l = Math.min(this.dcx - half, this.tcx - this.trad), t = Math.min(this.dcy - half, this.tcy - this.trad);
    let r = Math.max(this.dcx + half, this.tcx + this.trad), b = Math.max(this.dcy + half, this.tcy + this.trad);
    for (const x of [this.start, this.select, this.giveUpR, this.sound]) {
      l = Math.min(l, x.l); t = Math.min(t, x.t); r = Math.max(r, x.r); b = Math.max(b, x.b);
    }
    l -= m; t -= m; r += m; b += m;
    if (this.hasShade) { l = Math.min(l, this.shade.l); t = Math.min(t, this.shade.t); r = Math.max(r, this.shade.r); b = Math.max(b, this.shade.b); }
    this.bounds = rect(Math.floor(l), Math.floor(t), Math.ceil(r), Math.ceil(b));
    this.art = null;
  }

  /** パッドのいちばん上 (帯に置いたとき)。 */
  get contentTop() { return this.giveUpR.t; }
  get leftTop() { return this.start.t; }
  get rightTop() { return this.giveUpR.t; }

  update(dt) {
    if (this.armT > 0) this.armT = Math.max(0, this.armT - dt);
    if (this.flashT > 0) this.flashT = Math.max(0, this.flashT - dt);
  }

  // ------------------------------------------------------------ 指の扱い

  pointer(id, x, y, isDown, app) {
    if (!isDown) this.touches.delete(id);
    else {
      const hit = this.hitTest(x, y);
      if (hit === Btn.None) this.touches.delete(id);
      else this.touches.set(id, hit);
    }
    this.sync(app);
  }

  releaseAll(app) { this.touches.clear(); this.sync(app); }

  hitTest(x, y) {
    // 小さいボタンから先に調べる (十字キーとトリガーは判定を広めに取ってあるため)
    if (this.near(this.start, x, y)) return Btn.Start;
    if (this.near(this.select, x, y)) return Btn.Select;
    if (this.near(this.giveUpR, x, y)) return Btn.GiveUp;
    if (this.near(this.sound, x, y)) return Btn.Sound;
    if (Math.hypot(x - this.tcx, y - this.tcy) <= this.trad * 1.25) return Btn.Trigger;
    const half = this.dsize / 2 * 1.12;
    const dx = x - this.dcx, dy = y - this.dcy;
    if (Math.abs(dx) <= half && Math.abs(dy) <= half) {
      const dead = this.dsize * 0.09;
      if (Math.abs(dx) < dead && Math.abs(dy) < dead) return Btn.None;
      return Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? Btn.Left : Btn.Right) : (dy < 0 ? Btn.Up : Btn.Down);
    }
    return Btn.None;
  }

  /** そこがパッドのボタンの上か (ボタン以外のところを触ったときの扱いを分けるため)。 */
  isOnButton(x, y) { return this.hitTest(x, y) !== Btn.None; }

  near(r, x, y) {
    const m = 0.012 * this.q;
    return x >= r.l - m && x <= r.r + m && y >= r.t - m && y <= r.b + m;
  }

  sync(app) {
    const want = new Array(BtnCount).fill(false);
    for (const b of this.touches.values()) want[b] = true;
    for (let i = 1; i < BtnCount; i++) {
      if (want[i] === this.state[i]) continue;
      this.state[i] = want[i];
      this.apply(i, want[i], app);
    }
  }

  apply(b, isDown, app) {
    if (isDown) {
      if (b === Btn.Up || b === Btn.Down || b === Btn.Left || b === Btn.Right) Haptics.tick();
      else Haptics.click();
    }
    switch (b) {
      case Btn.Up: Input.padButton("up", isDown); break;
      case Btn.Down: Input.padButton("down", isDown); break;
      case Btn.Left: Input.padButton("left", isDown); break;
      case Btn.Right: Input.padButton("right", isDown); break;
      case Btn.Trigger: Input.padButton("south", isDown); break;
      case Btn.Start: Input.padButton("start", isDown); break;
      case Btn.Select:
        // タイトル画面では効かない。プレイ中は、うっかりタップで記録が消えないようにポーズ中だけ受け付ける
        if (!isDown || app.canBackToTitle) Input.padButton("back", isDown);
        break;
      case Btn.GiveUp:
        if (!isDown) break;
        if (!app.canGiveUp) { this.armT = 0; break; }
        // 誤って押したときのために、2回押しで確定する
        if (this.armT > 0) { this.armT = 0; app.giveUp(); }
        else { this.armT = 3; Audio.play(Sfx.Select); }
        break;
      case Btn.Sound:
        if (!isDown) break;
        Audio.cycleMode();
        this.flashT = 1.2;
        Audio.play(Sfx.Select);
        break;
    }
  }

  // ------------------------------------------------------------ 描画

  draw(ctx, app, clock) {
    if (!this.art) this.art = this.buildArt();
    ctx.drawImage(this.art, this.bounds.l, this.bounds.t);

    // 押されている十字キー
    for (let i = 0; i < 4; i++) {
      const btn = [Btn.Down, Btn.Left, Btn.Right, Btn.Up][i];
      if (!this.state[btn]) continue;
      ctx.fillStyle = rgba(PadColor.Cyan, 150);
      roundRectPath(ctx, this.arms[i], this.dthick * 0.28);
      ctx.fill();
      this.arrow(ctx, i, 0xFFFFFF, 255);
    }

    if (this.state[Btn.Trigger]) {
      ctx.fillStyle = rgba(0xFFE0B0, 180);
      ctx.beginPath(); ctx.arc(this.tcx, this.tcy, this.trad * 0.94, 0, Math.PI * 2); ctx.fill();
      label(ctx, "PEE", this.tcx, this.tcy, this.trad * 1.60, this.trad * 0.44, 0x201008, 255);
    }

    if (this.state[Btn.Start]) pressPill(ctx, this.start, "START", PadColor.Cyan);
    if (this.state[Btn.Select] && app.canBackToTitle) pressPill(ctx, this.select, "SELECT", PadColor.Cyan);
    // 今は効かない SELECT は、押せないことが分かるようにくすませる
    if (!app.canBackToTitle) {
      ctx.fillStyle = rgba(0x0C0E18, 185);
      roundRectPath(ctx, this.select, this.select.h / 2); ctx.fill();
      label(ctx, "SELECT", this.select.cx, this.select.cy, this.select.w, this.select.h * 0.42, 0x4A5368, 255);
    }

    // ギブアップ: 1回目は確認待ち (点滅して SURE? になる)
    if (this.armT > 0 && app.canGiveUp) {
      const on = (Math.trunc(clock * 6) & 1) === 0;
      ctx.fillStyle = rgba(PadColor.Red, on ? 210 : 90);
      roundRectPath(ctx, this.giveUpR, this.giveUpR.h / 2); ctx.fill();
      label(ctx, "SURE?", this.giveUpR.cx, this.giveUpR.cy, this.giveUpR.w, this.giveUpR.h * 0.44, 0x201008, 255);
    } else if (this.state[Btn.GiveUp]) pressPill(ctx, this.giveUpR, "GIVE UP", PadColor.Red);

    // 音の状態
    const noSound = Audio.failed;
    const m = Audio.mode;
    const text = noSound ? "NO SOUND" : m === SoundMode.All ? "BGM ON" : m === SoundMode.SfxOnly ? "BGM OFF" : "SILENT";
    const col = noSound ? 0xE07878 : m === SoundMode.All ? 0x80E0A0 : m === SoundMode.SfxOnly ? 0xD8D070 : 0x8894B8;
    if (this.state[Btn.Sound] || this.flashT > 0) pressPill(ctx, this.sound, text, col);
    else label(ctx, text, this.sound.cx, this.sound.cy, this.sound.w, this.sound.h * 0.40, col, 235);
  }

  arrow(ctx, d, rgb, a) {
    const s = this.dsize * 0.085, off = this.dsize * 0.33;
    const cx = this.dcx + (d === Dir.Left ? -off : d === Dir.Right ? off : 0);
    const cy = this.dcy + (d === Dir.Up ? -off : d === Dir.Down ? off : 0);
    ctx.beginPath();
    switch (d) {
      case Dir.Up: ctx.moveTo(cx, cy - s); ctx.lineTo(cx + s, cy + s * 0.8); ctx.lineTo(cx - s, cy + s * 0.8); break;
      case Dir.Down: ctx.moveTo(cx, cy + s); ctx.lineTo(cx + s, cy - s * 0.8); ctx.lineTo(cx - s, cy - s * 0.8); break;
      case Dir.Left: ctx.moveTo(cx - s, cy); ctx.lineTo(cx + s * 0.8, cy + s); ctx.lineTo(cx + s * 0.8, cy - s); break;
      default: ctx.moveTo(cx + s, cy); ctx.lineTo(cx - s * 0.8, cy + s); ctx.lineTo(cx - s * 0.8, cy - s); break;
    }
    ctx.closePath();
    ctx.fillStyle = rgba(rgb, a);
    ctx.fill();
  }

  /** 動かない部分 (枠・光り・ラベル) を1枚の絵に描きためる。 */
  buildArt() {
    const w = Math.max(1, this.bounds.w), h = Math.max(1, this.bounds.h);
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    const ctx = c.getContext("2d");
    ctx.translate(-this.bounds.l, -this.bounds.t);
    const q = this.q;

    if (this.hasShade) {
      const g = ctx.createLinearGradient(0, this.shade.t, 0, this.shade.b);
      g.addColorStop(0, rgba(0x0C1222, 0)); g.addColorStop(1, rgba(0x05070E, 150));
      ctx.fillStyle = g;
      ctx.fillRect(this.shade.l, this.shade.t, this.shade.w, this.shade.h);
    }

    // 十字キー
    const plus = () => plusPath(ctx, this.dcx, this.dcy, this.dsize, this.dthick, this.dthick * 0.30);
    glow(ctx, plus, PadColor.Cyan, this.dthick * 0.30);
    glass(ctx, plus, this.dcy - this.dsize / 2, this.dcy + this.dsize / 2, 0x2A4A6E, 0x101A2C, 150);
    edge(ctx, plus, PadColor.Cyan, q * 0.004, 200);
    for (let i = 0; i < 4; i++) this.arrow(ctx, i, 0xDCEAFF, 220);

    // トリガー (おしっこ)
    const circle = () => { ctx.beginPath(); ctx.arc(this.tcx, this.tcy, this.trad, 0, Math.PI * 2); };
    glow(ctx, circle, PadColor.Orange, this.trad * 0.22);
    const rg = ctx.createRadialGradient(this.tcx - this.trad * 0.3, this.tcy - this.trad * 0.4, 0,
                                        this.tcx - this.trad * 0.3, this.tcy - this.trad * 0.4, this.trad * 1.6);
    rg.addColorStop(0, rgba(0xFFC070, 225)); rg.addColorStop(1, rgba(0xC4521C, 205));
    circle(); ctx.fillStyle = rg; ctx.fill();
    edge(ctx, circle, 0xFFE0B0, q * 0.005, 230);
    ctx.beginPath(); ctx.arc(this.tcx, this.tcy, this.trad * 0.84, 0, Math.PI * 2);
    ctx.lineWidth = Math.max(1, q * 0.0025); ctx.strokeStyle = rgba(0xFFFFFF, 60); ctx.stroke();
    label(ctx, "PEE", this.tcx, this.tcy, this.trad * 1.60, this.trad * 0.44, 0x3A1808, 255);

    pill(ctx, this.start, "START", PadColor.Cyan, q);
    pill(ctx, this.select, "SELECT", PadColor.Cyan, q);
    pill(ctx, this.giveUpR, "GIVE UP", PadColor.Red, q);
    pill(ctx, this.sound, "", PadColor.Gray, q);   // 中の文字は状態によって変わるので draw 側で描く
    return c;
  }
}

function roundRectPath(ctx, r, rad) {
  rad = Math.min(rad, r.w / 2, r.h / 2);
  ctx.beginPath();
  ctx.moveTo(r.l + rad, r.t);
  ctx.arcTo(r.r, r.t, r.r, r.b, rad);
  ctx.arcTo(r.r, r.b, r.l, r.b, rad);
  ctx.arcTo(r.l, r.b, r.l, r.t, rad);
  ctx.arcTo(r.l, r.t, r.r, r.t, rad);
  ctx.closePath();
}

/** 十字の形 (角を丸めた12角形)。 */
function plusPath(ctx, cx, cy, size, thick, round) {
  const h = size / 2, t = thick / 2;
  const pts = [
    [cx - t, cy - h], [cx + t, cy - h], [cx + t, cy - t], [cx + h, cy - t], [cx + h, cy + t], [cx + t, cy + t],
    [cx + t, cy + h], [cx - t, cy + h], [cx - t, cy + t], [cx - h, cy + t], [cx - h, cy - t], [cx - t, cy - t],
  ];
  ctx.beginPath();
  const n = pts.length;
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const start = mid(pts[n - 1], pts[0]);
  ctx.moveTo(start[0], start[1]);
  for (let i = 0; i < n; i++) {
    const p = pts[i], nx = pts[(i + 1) % n];
    // 内側の角 (くぼみ) は丸めない
    const concave = i % 3 === 2;
    ctx.arcTo(p[0], p[1], nx[0], nx[1], concave ? 0.01 : round);
  }
  ctx.closePath();
}

function glow(ctx, pathFn, rgb, radius) {
  ctx.save();
  pathFn();
  ctx.lineWidth = Math.max(1, radius * 0.9);
  ctx.strokeStyle = rgba(rgb, 70);
  ctx.shadowColor = rgba(rgb, 140);
  ctx.shadowBlur = Math.max(1, radius * 1.5);
  ctx.stroke();
  ctx.restore();
}

function glass(ctx, pathFn, top, bottom, hi, lo, alpha) {
  const g = ctx.createLinearGradient(0, top, 0, bottom);
  g.addColorStop(0, rgba(hi, alpha)); g.addColorStop(1, rgba(lo, Math.min(255, alpha + 40)));
  pathFn();
  ctx.fillStyle = g;
  ctx.fill();
}

function edge(ctx, pathFn, rgb, width, alpha) {
  pathFn();
  ctx.lineWidth = Math.max(1.5, width);
  ctx.strokeStyle = rgba(rgb, alpha);
  ctx.stroke();
}

function pill(ctx, r, text, tint, q) {
  const p = () => roundRectPath(ctx, r, r.h / 2);
  glow(ctx, p, tint, r.h * 0.22);
  glass(ctx, p, r.t, r.b, 0x24304E, 0x0E1420, 160);
  edge(ctx, p, tint, q * 0.0035, 190);
  label(ctx, text, r.cx, r.cy, r.w, r.h * 0.42, 0xE8F0FF, 240);
}

function pressPill(ctx, r, text, tint) {
  ctx.fillStyle = rgba(tint, 170);
  roundRectPath(ctx, r, r.h / 2); ctx.fill();
  label(ctx, text, r.cx, r.cy, r.w, r.h * 0.42, 0x101620, 255);
}

/** 中央そろえのドット文字 (枠の幅に収まるように字の大きさを決める)。 */
function label(ctx, s, cx, cy, maxW, cell, rgb, a) {
  if (s.length === 0) return;
  const use = Math.min(cell, maxW * 0.84 / s.length);
  ctx.imageSmoothingEnabled = false;
  Gfx.textOn(ctx, s, cx - s.length * use / 2, cy - use / 2, use, rgb, a);
}
