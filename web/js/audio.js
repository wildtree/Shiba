"use strict";
// 効果音と BGM (PC版 Audio.cs と同じ合成)。音声ファイルは使わず、矩形波・三角波・ノイズをその場で作る。
// 出口は Web Audio。効果音は鳴らすたびに短い波形を合成してバッファで流し、BGM は起動時に1周ぶん作ってループさせる。

const Sfx = {
  Step: 0, PeeDrip: 1, Mark: 2, Overwrite: 3, Territory: 4, EnemyTerritory: 5, Invalid: 6, Miss: 7, EnemyOut: 8,
  StageClear: 9, StageFail: 10, GameOver: 11, Select: 12, Start: 13, CarHit: 14, Bark: 15, NameOk: 16,
  Item: 17, Thunder: 18, Rain: 19, Kicked: 20, Extend: 21, Achievement: 22,
};
const Tune = { None: 0, Title: 1, Game: 2 };
/** All: BGMも効果音も / SfxOnly: 効果音だけ / Silent: どちらも鳴らさない */
const SoundMode = { All: 0, SfxOnly: 1, Silent: 2 };

const Audio = (() => {
  let ctx = null, master = null, musicGain = null;
  let rate = 44100;
  let ok = false, failed = false;
  let mode = SoundMode.All;
  let current = Tune.None;
  let musicSrc = null;
  const tunes = {};
  const live = new Set();
  const ModeNames = ["all", "sfx", "silent"];

  // 保存してある音の設定 (ブラウザの中だけ)
  const saved = Store.read("settings");
  if (saved && typeof saved.sound === "string") {
    const i = ModeNames.indexOf(saved.sound);
    if (i >= 0) mode = i;
  }

  function saveMode() {
    const s = Store.read("settings") || {};
    s.sound = ModeNames[mode];
    Store.write("settings", s);
  }

  // ------------------------------------------------------------ 合成
  function newVoice(wave) { return { wave, phase: 0, noise: 0x2545F491, noiseOut: 0 }; }

  function osc(v, freq) {
    v.phase += freq / rate;
    if (v.phase >= 1) {
      v.phase -= Math.floor(v.phase);
      if (v.wave === 3) {
        let n = v.noise;
        n ^= n << 13; n >>>= 0;
        n ^= n >>> 17;
        n ^= n << 5; n >>>= 0;
        v.noise = n;
        v.noiseOut = (n & 0xFFFF) / 32768 - 1;
      }
    }
    switch (v.wave) {
      case 0: return v.phase < 0.5 ? 1 : -1;
      case 1: return v.phase < 0.25 ? 1 : -1;
      case 2: return v.phase < 0.5 ? 4 * v.phase - 1 : 3 - 4 * v.phase;
      default: return v.noiseOut;
    }
  }

  /** "e5:2" = ミ(オクターブ5)を2ステップ。"r" は休符。"c#4" のように半音も書ける。 */
  function parseNote(tok) {
    let steps = 1;
    const colon = tok.indexOf(":");
    if (colon >= 0) { steps = parseInt(tok.slice(colon + 1), 10); tok = tok.slice(0, colon); }
    if (tok === "r") return [0, steps];
    let semi = "c d ef g a b".indexOf(tok[0]);
    let i = 1;
    if (i < tok.length && tok[i] === "#") { semi++; i++; }
    const octave = tok.charCodeAt(i) - 48;
    const midi = 12 * (octave + 1) + semi;
    return [440 * Math.pow(2, (midi - 69) / 12), steps];
  }

  // 1回の Play で鳴らす音 (複数の声) を集めて、ひとつの波形にする
  let pending = null;
  function V(wave, f0, f1, dur, vol, delay = 0) {
    pending.push({ wave, f0, f1, vol, len: Math.max(1, Math.trunc(dur * rate)), delay: Math.trunc(delay * rate) });
  }
  function Notes(wave, notes, each, vol, start = 0) {
    let t = start;
    for (const tok of notes.split(" ").filter(s => s)) {
      const [freq, steps] = parseNote(tok);
      if (freq > 0) V(wave, freq, freq, each * steps * 0.95, vol, t);
      t += each * steps;
    }
  }

  function renderVoices(voices) {
    let total = 1;
    for (const v of voices) total = Math.max(total, v.delay + v.len);
    const buf = ctx.createBuffer(1, total, rate);
    const out = buf.getChannelData(0);
    for (const vo of voices) {
      const v = newVoice(vo.wave);
      for (let pos = 0; pos < vo.len; pos++) {
        const t = pos / vo.len;
        const f = vo.f0 + (vo.f1 - vo.f0) * t;
        const env = Math.min(1, pos / 60) * Math.min(1, (vo.len - pos) / (vo.len * 0.35 + 1));
        out[vo.delay + pos] += osc(v, f) * vo.vol * env;
      }
    }
    for (let i = 0; i < total; i++) out[i] = Math.max(-1, Math.min(1, out[i]));
    return buf;
  }

  function define(s, r) {
    switch (s) {
      case Sfx.Step: V(1, 480, 620, 0.035, 0.05); break;
      case Sfx.PeeDrip: V(2, 1500 + r * 900, 1000 + r * 500, 0.06, 0.16); break;
      case Sfx.Mark: Notes(0, "e6 a6:2", 0.06, 0.12); break;
      case Sfx.Overwrite: Notes(1, "a5 e5 a5 e6", 0.05, 0.13); break;
      case Sfx.Territory:
        Notes(0, "c5 e5 g5 c6 e6 g6 c7:4", 0.06, 0.14);
        Notes(2, "c4 g4 c5:6", 0.12, 0.22);
        break;
      case Sfx.EnemyTerritory: Notes(1, "g3 a#3 d4 g4:3", 0.07, 0.11); break;
      case Sfx.Invalid: V(0, 120, 100, 0.18, 0.14); V(0, 126, 105, 0.18, 0.10); break;
      case Sfx.Miss:
        V(0, 900, 110, 0.7, 0.16);
        V(3, 3000, 400, 0.35, 0.14);
        Notes(2, "e5 c5 a4 f4:3", 0.12, 0.2, 0.15);
        break;
      case Sfx.EnemyOut:
        V(1, 700, 1700, 0.09, 0.14); V(1, 800, 1900, 0.10, 0.14, 0.12);
        Notes(0, "g5 c6 e6 g6:3", 0.07, 0.12, 0.26);
        break;
      case Sfx.StageClear:
        Notes(0, "c5 c5 c5 e5:2 g5:2 e5 g5 c6:6", 0.11, 0.15);
        Notes(2, "c4:3 g4:2 c4:2 e4 g4 c5:6", 0.11, 0.22);
        break;
      case Sfx.StageFail: Notes(2, "e4:2 d#4:2 d4:2 c#4:6", 0.14, 0.24); V(0, 150, 90, 0.9, 0.06, 0.84); break;
      case Sfx.GameOver: Notes(0, "c5:2 g4:2 e4:2 a4 b4 a4 g#4:2 g4:6", 0.15, 0.14); Notes(2, "c3:6 f3:5 c3:8", 0.15, 0.22); break;
      case Sfx.Select: V(1, 880, 880, 0.04, 0.10); break;
      case Sfx.Start: Notes(0, "c5 e5 g5 c6:3", 0.06, 0.14); break;
      case Sfx.CarHit: V(3, 5000, 600, 0.3, 0.22); V(0, 300, 60, 0.3, 0.16); break;
      case Sfx.Bark:
        V(1, 500, 900, 0.07, 0.16); V(3, 2500, 1500, 0.05, 0.08);
        V(1, 520, 950, 0.08, 0.16, 0.16); V(3, 2500, 1500, 0.05, 0.08, 0.16);
        break;
      case Sfx.NameOk: Notes(0, "g5 c6 e6 c6 e6 g6:4", 0.07, 0.13); break;
      case Sfx.Item: Notes(0, "e6 g6 e6 c7:3", 0.05, 0.13); break;
      case Sfx.Thunder:
        V(3, 900, 120, 1.1, 0.22); V(0, 70, 45, 1.2, 0.12);
        V(3, 700, 100, 0.8, 0.14, 0.5);
        break;
      case Sfx.Rain: V(3, 7000, 5500, 3.8, 0.07); V(3, 3000, 2500, 3.8, 0.04); break;
      case Sfx.Extend: Notes(0, "e6 g6 e7 c7 d7 g7:4", 0.08, 0.16); Notes(2, "c5 e5 g5 c6 e6 g6:4", 0.08, 0.2); break;
      case Sfx.Achievement:
        Notes(1, "g5 c6 e6 g6 e6 g6 c7:4", 0.055, 0.12);
        Notes(2, "c5:3 e5:3 g5:6", 0.055, 0.18);
        break;
      case Sfx.Kicked: Notes(1, "c6 g5 e5 c5", 0.05, 0.13); break;
    }
  }

  // 乱数を使わない効果音は一度作ったら使い回す
  const sfxCache = new Map();

  function play(s) {
    if (!ok || mode === SoundMode.Silent) return;
    if (ctx.state !== "running") return;
    let buf = sfxCache.get(s);
    if (!buf) {
      pending = [];
      define(s, Math.random());
      buf = renderVoices(pending);
      pending = null;
      if (s !== Sfx.PeeDrip) sfxCache.set(s, buf);
    }
    if (live.size >= 40) return;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(master);
    src.onended = () => live.delete(src);
    live.add(src);
    src.start();
  }

  // ------------------------------------------------------------ BGM
  function renderTrack(buf, notes, step, wave, vol, gate) {
    const v = newVoice(wave);
    let t = 0;
    for (const tok of notes.split(" ").filter(s => s)) {
      const [freq, steps] = parseNote(tok);
      const start = Math.trunc(t * rate);
      const len = Math.trunc(step * steps * gate * rate);
      t += step * steps;
      if (freq <= 0) continue;
      v.phase = 0;
      for (let i = 0; i < len && start + i < buf.length; i++) {
        const env = Math.min(1, i / 100) * Math.min(1, (len - i) / 500) * (1 - 0.55 * i / len);
        buf[start + i] += osc(v, freq) * vol * env;
      }
    }
  }

  function renderTune(step, leadWave, leadVol) {
    // メロディ(1小節=8ステップ、16小節でループ)
    const melody =
      "e5 e5 g5 e5 c6:2 g5:2  d5 d5 g5 d5 b5:2 g5:2  c5 c5 e5 c5 a5:2 e5:2  f5 g5 a5 g5 f5:2 r:2 " +
      "e5 e5 g5 e5 c6:2 e6:2  d6 c6 b5 a5 g5:2 b5:2  a5 f5 a5 c6 b5 g5 b5 d6  c6:4 r:2 g5:2 " +
      "a5:2 c6 a5 f5:2 a5:2  g5:2 c6 g5 e5:2 g5:2  a5:2 c6 a5 f5:2 c6:2  b5 a5 g5 a5 b5:2 d6:2 " +
      "c6:2 a5 e5 a5:2 c6:2  b5:2 g5 e5 g5:2 b5:2  a5 f5 a5 c6 d6 b5 g5 b5  c6:4 r:4";
    const chords = [
      "C", "C", "G", "G", "Am", "Am", "F", "F", "C", "C", "G", "G", "F", "G", "C", "C",
      "F", "F", "C", "C", "F", "F", "G", "G", "Am", "Am", "Em", "Em", "F", "G", "C", "C",
    ];
    let bass = "", chop = "";
    for (const c of chords) {
      const [root, fifth, third] =
        c === "G" ? ["g2", "d3", "b4"] : c === "Am" ? ["a2", "e3", "c5"] : c === "F" ? ["f2", "c3", "a4"]
        : c === "Em" ? ["e2", "b2", "g4"] : ["c3", "g2", "e4"];
      bass += `${root}:2 ${fifth}:2 `;
      chop += `r ${third} r ${third} `;
    }
    const total = Math.trunc(step * 128 * rate);
    const ab = ctx.createBuffer(1, total, rate);
    const buf = ab.getChannelData(0);
    renderTrack(buf, melody, step, leadWave, leadVol, 0.8);
    renderTrack(buf, bass, step, 2, 0.20, 0.7);
    renderTrack(buf, chop, step, 1, 0.035, 0.5);
    for (let i = 0; i < total; i++) buf[i] = Math.max(-1, Math.min(1, buf[i])) * (32000 / 32768);
    return ab;
  }

  function startMusic() {
    if (musicSrc) { try { musicSrc.stop(); } catch (e) { /* もう止まっている */ } musicSrc.disconnect(); musicSrc = null; }
    if (!ok) return;
    const buf = current === Tune.Title ? tunes.title : current === Tune.Game ? tunes.game : null;
    if (!buf) return;
    musicSrc = ctx.createBufferSource();
    musicSrc.buffer = buf;
    musicSrc.loop = true;
    musicSrc.connect(musicGain);
    musicSrc.start();
  }

  function applyMode() {
    if (musicGain) musicGain.gain.value = mode === SoundMode.All ? 1 : 0;
    if (mode === SoundMode.Silent) {
      for (const s of live) { try { s.stop(); } catch (e) { /* 終わっている */ } }
      live.clear();
    }
  }

  return {
    get ok() { return ok; },
    get failed() { return failed; },
    get mode() { return mode; },

    /** 最初のタップやキー入力のときに呼ぶ (ブラウザはそれまで音を出させてくれない)。 */
    unlock() {
      if (failed) return;
      if (!ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) { failed = true; return; }
        try {
          ctx = new AC();
          rate = ctx.sampleRate;
          master = ctx.createGain();
          master.gain.value = 30000 / 32768;
          master.connect(ctx.destination);
          musicGain = ctx.createGain();
          musicGain.connect(master);
          tunes.game = renderTune(0.16, 1, 0.085);
          tunes.title = renderTune(0.21, 2, 0.20);
          ok = true;
          applyMode();
          startMusic();
        } catch (e) {
          console.warn("audio disabled", e);
          failed = true; ok = false;
          return;
        }
      }
      if (ctx.state === "suspended") ctx.resume();
    },

    suspend() { if (ctx && ctx.state === "running") ctx.suspend(); },
    resume() { if (ctx && ctx.state === "suspended") ctx.resume(); },

    /** BGMあり → BGMなし(効果音だけ) → 全部なし、の順に切り替えて覚えておく。 */
    cycleMode() {
      mode = mode === SoundMode.All ? SoundMode.SfxOnly : mode === SoundMode.SfxOnly ? SoundMode.Silent : SoundMode.All;
      applyMode();
      saveMode();
    },

    playMusic(t) {
      if (t === current) return;
      current = t;
      startMusic();
    },

    play,
  };
})();
