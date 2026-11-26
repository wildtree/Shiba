"use strict";
// 描画まわり (PC版 Gfx.cs / Android版 GfxAndroid.cs と同じ使い方)。
// ゲームの絵はすべて「論理サイズの小さなキャンバス」に描き、最後に画面へ拡大して写す (main.js)。

const Gfx = {
  W: 640, H: 400,       // 今の描画先の論理サイズ (PC版の画面は 640x400)
  ctx: null,
  _clipped: false,

  /** 描画先を切り替える。 */
  target(ctx, w, h) {
    this.ctx = ctx; this.W = w; this.H = h;
    ctx.imageSmoothingEnabled = false;
  },

  /** 文字で描いたドット絵からスプライトを作る。パレットにない文字は透明。 */
  makeSprite(rowsArr, palette) {
    const w = rowsArr[0].length, h = rowsArr.length;
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    const cx = c.getContext("2d");
    const img = cx.createImageData(w, h);
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w && x < rowsArr[y].length; x++) {
        const rgb = palette[rowsArr[y][x]];
        if (rgb === undefined) continue;
        const i = (y * w + x) * 4;
        img.data[i] = (rgb >> 16) & 255; img.data[i + 1] = (rgb >> 8) & 255; img.data[i + 2] = rgb & 255; img.data[i + 3] = 255;
      }
    cx.putImageData(img, 0, 0);
    return { canvas: c, img, w, h, tint: 0xFFFFFF, alpha: 255, cache: new Map() };
  },

  /** SDL の color mod / alpha mod と同じ。次に変えるまで、そのスプライトに残る。 */
  tint(s, rgb, alpha = 255) { s.tint = rgb; s.alpha = alpha; },

  _tinted(s) {
    if (s.tint === 0xFFFFFF) return s.canvas;
    let c = s.cache.get(s.tint);
    if (c) return c;
    c = document.createElement("canvas");
    c.width = s.w; c.height = s.h;
    const cx = c.getContext("2d");
    const img = cx.createImageData(s.w, s.h);
    const r = (s.tint >> 16) & 255, g = (s.tint >> 8) & 255, b = s.tint & 255;
    const src = s.img.data, dst = img.data;
    for (let i = 0; i < src.length; i += 4) {
      dst[i] = src[i] * r / 255; dst[i + 1] = src[i + 1] * g / 255; dst[i + 2] = src[i + 2] * b / 255; dst[i + 3] = src[i + 3];
    }
    cx.putImageData(img, 0, 0);
    s.cache.set(s.tint, c);
    return c;
  },

  draw(s, x, y, flip = false, scale = 1) {
    const ctx = this.ctx;
    const dx = Math.floor(x), dy = Math.floor(y), dw = s.w * scale, dh = s.h * scale;
    const src = this._tinted(s);
    ctx.globalAlpha = s.alpha / 255;
    if (flip) {
      ctx.save();
      ctx.translate(dx + dw, dy);
      ctx.scale(-1, 1);
      ctx.drawImage(src, 0, 0, dw, dh);
      ctx.restore();
    } else ctx.drawImage(src, dx, dy, dw, dh);
    ctx.globalAlpha = 1;
  },

  _styles: new Map(),
  _style(rgb, a) {
    const key = rgb * 256 + a;
    let s = this._styles.get(key);
    if (!s) {
      s = `rgba(${(rgb >> 16) & 255},${(rgb >> 8) & 255},${rgb & 255},${a / 255})`;
      if (this._styles.size < 4000) this._styles.set(key, s);
    }
    return s;
  },

  fill(x, y, w, h, rgb, a = 255) {
    if (w <= 0 || h <= 0) return;
    // SDL の塗りはぼかさないので、ドットの境目にそろえる
    const x0 = Math.round(x), y0 = Math.round(y), x1 = Math.round(x + w), y1 = Math.round(y + h);
    if (x1 <= x0 || y1 <= y0) return;
    this.ctx.fillStyle = this._style(rgb, a);
    this.ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
  },

  clear(rgb) {
    this.ctx.fillStyle = this._style(rgb, 255);
    this.ctx.fillRect(0, 0, this.W, this.H);
  },

  frame(x, y, w, h, rgb) {
    this.fill(x, y, w, 1, rgb); this.fill(x, y + h - 1, w, 1, rgb);
    this.fill(x, y, 1, h, rgb); this.fill(x + w - 1, y, 1, h, rgb);
  },

  /** 動く点線。 */
  dotted(x1, y1, x2, y2, rgb, phase, a = 255) {
    const dx = x2 - x1, dy = y2 - y1;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    for (let t = phase % 6; t < len; t += 6)
      this.fill(Math.floor(x1 + dx * t / len) - 1, Math.floor(y1 + dy * t / len) - 1, 2, 2, rgb, a);
  },

  // ---------------- 文字 (SDL 内蔵の 8x8 フォント) ----------------
  _fontAtlas: null,
  _fontColored: new Map(),

  _buildFont() {
    const c = document.createElement("canvas");
    c.width = 96 * 8; c.height = 8;
    const cx = c.getContext("2d");
    const img = cx.createImageData(c.width, 8);
    for (let ch = 0; ch < 96; ch++)
      for (let row = 0; row < 8; row++) {
        const bits = FontGlyphs[ch * 8 + row];
        for (let col = 0; col < 8; col++)
          if (bits & (0x80 >> col)) {
            const i = (row * c.width + ch * 8 + col) * 4;
            img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = 255;
          }
      }
    cx.putImageData(img, 0, 0);
    this._fontAtlas = c;
  },

  _font(rgb) {
    if (!this._fontAtlas) this._buildFont();
    let c = this._fontColored.get(rgb);
    if (c) return c;
    c = document.createElement("canvas");
    c.width = this._fontAtlas.width; c.height = 8;
    const cx = c.getContext("2d");
    cx.drawImage(this._fontAtlas, 0, 0);
    cx.globalCompositeOperation = "source-in";
    cx.fillStyle = this._style(rgb, 255);
    cx.fillRect(0, 0, c.width, 8);
    this._fontColored.set(rgb, c);
    return c;
  },

  _glyphs(ctx, s, x, y, atlas, scale) {
    const sz = 8 * scale;
    for (let i = 0; i < s.length; i++) {
      let code = s.charCodeAt(i) - 32;
      if (code < 0 || code >= 96) code = 31;   // 範囲外は '?'
      if (code === 0) continue;
      ctx.drawImage(atlas, code * 8, 0, 8, 8, x + i * sz, y, sz, sz);
    }
  },

  text(s, x, y, rgb = 0xFFFFFF, scale = 1, shadow = true) {
    const ctx = this.ctx;
    x = Math.floor(x); y = Math.floor(y);
    if (shadow) {
      ctx.globalAlpha = 200 / 255;
      this._glyphs(ctx, s, x + scale, y + scale, this._font(0x000000), scale);
      ctx.globalAlpha = 1;
    }
    this._glyphs(ctx, s, x, y, this._font(rgb), scale);
  },

  textCenter(s, cx, y, rgb = 0xFFFFFF, scale = 1) {
    this.text(s, Math.floor(cx - s.length * 4 * scale), y, rgb, scale);
  },

  /** 任意の大きさのドット文字 (操作パッドのラベル用。ctx は画面そのもの)。 */
  textOn(ctx, s, x, y, cell, rgb, a = 255) {
    ctx.globalAlpha = a / 255;
    const atlas = this._font(rgb);
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i) - 32;
      if (code <= 0 || code >= 96) continue;
      ctx.drawImage(atlas, code * 8, 0, 8, 8, x + i * cell, y, cell, cell);
    }
    ctx.globalAlpha = 1;
  },

  clip(x, y, w, h) {
    if (this._clipped) this.ctx.restore();
    this.ctx.save();
    this.ctx.beginPath();
    this.ctx.rect(x, y, w, h);
    this.ctx.clip();
    this._clipped = true;
  },

  unclip() {
    if (!this._clipped) return;
    this.ctx.restore();
    this._clipped = false;
  },

  shade(rgb, f) {
    const r = Math.max(0, Math.min(255, Math.trunc(((rgb >> 16) & 255) * f)));
    const g = Math.max(0, Math.min(255, Math.trunc(((rgb >> 8) & 255) * f)));
    const b = Math.max(0, Math.min(255, Math.trunc((rgb & 255) * f)));
    return (r << 16) | (g << 8) | b;
  },
};

/** C# の書式の代わり。 */
function pad0(n, width) { return String(Math.trunc(n)).padStart(width, "0"); }
function padL(v, width) { return String(v).padStart(width, " "); }
