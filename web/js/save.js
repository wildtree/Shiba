"use strict";
// ハイスコア・実績・設定の保存。すべてブラウザの localStorage に置き、どこにも送らない。
// 中身の形は PC版の hiscores.json / achievements.json / settings.json と同じ。

const Store = {
  prefix: "shibajintori.",
  read(name) {
    try {
      const s = localStorage.getItem(this.prefix + name);
      return s ? JSON.parse(s) : null;
    } catch (e) { return null; }
  },
  write(name, obj) {
    try { localStorage.setItem(this.prefix + name, JSON.stringify(obj)); return true; }
    catch (e) { console.warn("save failed", e); return false; }
  },
};

/** ハイスコア上位10件。 { "version": 1, "scores": [ { "name": "SHB", "score": 10000, "stage": 1 }, ... ] } */
class HiScoreTable {
  constructor() {
    this.entries = [];
    const doc = Store.read("hiscores");
    if (doc && Array.isArray(doc.scores)) {
      for (const e of doc.scores) {
        if (!e || typeof e !== "object") continue;
        const name = String(typeof e.name === "string" ? e.name : "???").padEnd(3).slice(0, 3);
        const score = Number.isFinite(e.score) ? Math.trunc(e.score) : 0;
        const stage = Math.max(1, Number.isFinite(e.stage) ? Math.trunc(e.stage) : 1);
        if (!this.entries.some(h => h.name === name && h.score === score && h.stage === stage))
          this.entries.push({ name, score, stage });
      }
    }
    const names = ["SHB", "KRO", "SRO", "CRG", "CHW", "SLT", "HSK", "PUG", "DAL", "BGL"];
    for (let i = this.entries.length; i < HiScoreTable.Max; i++)
      this.entries.push({ name: names[i], score: (HiScoreTable.Max - i) * 1000, stage: 1 });
    this.entries.sort((a, b) => b.score - a.score);
    this.entries.length = Math.min(this.entries.length, HiScoreTable.Max);
  }
  get top() { return this.entries.length > 0 ? this.entries[0].score : 0; }
  qualifies(score) {
    return score > 0 && (this.entries.length < HiScoreTable.Max || score > this.entries[this.entries.length - 1].score);
  }
  /** 登録して順位(0始まり)を返す。 */
  add(name, score, stage) {
    let rank = 0;
    while (rank < this.entries.length && this.entries[rank].score >= score) rank++;
    this.entries.splice(rank, 0, { name, score, stage });
    this.entries.length = Math.min(this.entries.length, HiScoreTable.Max);
    Store.write("hiscores", { version: 1, scores: this.entries });
    return rank;
  }
}
HiScoreTable.Max = 10;

/**
 * 実績。解除した日時を { "version": 1, "unlocked": {...}, "progress": {...} } の形で保存する (日時は ISO 8601)。
 * 名前と条件は、解除されるまで画面に出さない。
 */
const Achievements = (() => {
  const All = [
    ["FIRST_TURF", "MY FIRST TURF", "CLAIM YOUR FIRST TERRITORY."],
    ["BIG_TURF", "BIG TURF", "CLAIM 100 OR MORE TILES AT ONCE."],
    ["HALF", "HALF THE TOWN", "OWN HALF OF THE FIELD IN ONE STAGE."],
    ["CATCH_DOG", "GOTCHA!", "SURROUND ANOTHER DOG WITH YOUR TERRITORY."],
    ["DOUBLE_CATCH", "DOUBLE CATCH", "SURROUND TWO OR MORE DOGS AT ONCE."],
    ["BOSS_DOWN", "GIANT SLAYER", "SURROUND THE BOSS DOG."],
    ["GOT_CAUGHT", "SURROUNDED...", "GET SURROUNDED BY ANOTHER DOG'S TERRITORY."],
    ["CAR_HIT", "WATCH THE ROAD", "GET HIT BY A CAR."],

    ["OVERWRITE", "MY POLE NOW", "PEE OVER ANOTHER DOG'S MARK."],
    ["WASHED", "WASHED AWAY", "HAVE YOUR MARKS WASHED AWAY BY THE RAIN."],
    ["BONE", "GOOD BOY", "PICK UP A BONE."],
    ["NINJA", "NINJA DOG", "WALK THROUGH ANOTHER DOG'S TERRITORY."],
    ["GIVE_UP", "I GIVE UP", "GIVE UP A STAGE FROM THE PAUSE MENU."],
    ["ONE_UP", "ONE MORE LIFE", "EARN AN EXTRA LIFE."],
    ["NO_MISS", "FLAWLESS", "CLEAR A STAGE WITHOUT A SINGLE MISS."],
    ["SPEEDY", "SPEED RUN", "CLEAR A STAGE WITHIN 2 MINUTES."],

    ["STAGE4", "STAGE 4 CLEAR", "CLEAR STAGE 4."],
    ["STAGE8", "STAGE 8 CLEAR", "CLEAR STAGE 8."],
    ["STAGE16", "STAGE 16 CLEAR", "CLEAR STAGE 16."],
    ["BONUS_CLEAR", "NIGHT WALK", "FINISH A BONUS STAGE."],
    ["BONUS_PERFECT", "SWEET DREAMS", "SURROUND ALL THE SLEEPING DOGS IN A BONUS STAGE."],
    ["SCORE_100K", "BIG SCORE", "SCORE 100,000 POINTS IN ONE GAME."],
    ["ALL_SHIBA", "SHIBA TRIO", "CLEAR A STAGE WITH ALL THREE SHIBA COLORS."],
    ["HIGH_SCORE", "HALL OF FAME", "ENTER YOUR NAME IN THE HIGH SCORE TABLE."],
  ].map(([id, name, desc]) => ({ id, name, desc }));

  const Columns = 8, ToastTime = 3.5;
  // ID → 解除した日時 (ミリ秒)。"_" で始まるIDは画面に出さない途中経過
  const got = new Map();
  const toasts = [];
  let toastT = 0;

  const doc = Store.read("achievements");
  if (doc && typeof doc === "object") {
    for (const sec of ["unlocked", "progress"]) {
      const o = doc[sec];
      if (!o || typeof o !== "object") continue;
      for (const k of Object.keys(o)) {
        const t = Date.parse(o[k]);
        if (!Number.isNaN(t) && !got.has(k)) got.set(k, t);
      }
    }
  }

  function save() {
    const unlocked = {}, progress = {};
    for (const d of All) if (got.has(d.id)) unlocked[d.id] = new Date(got.get(d.id)).toISOString();
    for (const [k, v] of got) if (k.startsWith("_")) progress[k] = new Date(v).toISOString();
    Store.write("achievements", { version: 1, unlocked, progress });
  }

  function drawIcon(index, x, y) {
    const dogs = Art.Dogs;
    switch (All[index].id) {
      case "FIRST_TURF":
        Gfx.tint(Art.PeeMark, 0xFF8C1A); Gfx.draw(Art.PeeMark, x, y, false, 2); Gfx.tint(Art.PeeMark, 0xFFFFFF);
        Gfx.draw(Art.Pole, x, y, false, 2);
        Gfx.tint(Art.PoleBand, 0xFF8C1A); Gfx.draw(Art.PoleBand, x, y, false, 2); Gfx.tint(Art.PoleBand, 0xFFFFFF);
        break;
      case "BIG_TURF":
        Gfx.tint(Art.Paw, 0xFF8C1A); Gfx.draw(Art.Paw, x, y, false, 2); Gfx.tint(Art.Paw, 0xFFFFFF);
        break;
      case "HALF":
        Gfx.draw(Art.Grass0, x, y, false, 2);
        Gfx.fill(x, y, 16, 32, 0xFF8C1A, 170);
        Gfx.fill(x + 15, y, 2, 32, 0x8A4A10);
        break;
      case "CATCH_DOG": Gfx.draw(dogs[ShibaCount][0], x, y, false, 2); break;
      case "DOUBLE_CATCH":
        Gfx.draw(dogs[ShibaCount + 1][0], x, y + 4);
        Gfx.draw(dogs[ShibaCount + 4][0], x + 16, y + 4);
        Gfx.text("x2", x + 8, y + 22, 0xFFD840);
        break;
      case "BOSS_DOWN": Gfx.draw(dogs[BossIndex][0], x, y, false, 2); break;
      case "GOT_CAUGHT":
        Gfx.tint(dogs[0][0], 0x8090B0); Gfx.draw(dogs[0][0], x, y, false, 2); Gfx.tint(dogs[0][0], 0xFFFFFF);
        Gfx.text("!", x + 24, y, 0xFF5050);
        break;
      case "CAR_HIT": Gfx.draw(Art.Cars[0], x, y + 8); break;
      case "OVERWRITE": Gfx.draw(dogs[0][8], x, y, false, 2); break;
      case "WASHED": Gfx.draw(Art.Icons.Drop, x, y, false, 2); break;
      case "BONE": Gfx.draw(Art.Items[0], x, y, false, 2); break;
      case "NINJA": Gfx.draw(Art.Items[1], x, y, false, 2); break;
      case "GIVE_UP": Gfx.draw(Art.Icons.Flag, x, y, false, 2); break;
      case "ONE_UP":
        Gfx.draw(dogs[0][0], x, y, false, 2);
        Gfx.text("1UP", x + 4, y + 24, 0x60FF90);
        break;
      case "NO_MISS": Gfx.draw(Art.Icons.Heart, x, y, false, 2); break;
      case "SPEEDY": Gfx.draw(Art.Icons.Bolt, x, y, false, 2); break;
      case "STAGE4": case "STAGE8": case "STAGE16": {
        Gfx.draw(Art.Icons.Trophy, x, y, false, 2);
        const num = All[index].id.slice(5);
        Gfx.text(num, x + 16 - num.length * 4, y + 6, 0x8A5A10, 1, false);
        break;
      }
      case "BONUS_CLEAR": Gfx.draw(Art.Icons.Moon, x, y, false, 2); break;
      case "BONUS_PERFECT":
        Gfx.draw(Art.Icons.Moon, x, y, false, 2);
        Gfx.draw(Art.Icons.Star, x + 16, y + 16);
        break;
      case "SCORE_100K": Gfx.draw(Art.Icons.Star, x, y, false, 2); break;
      case "ALL_SHIBA":
        Gfx.draw(dogs[1][0], x + 8, y + 2);
        Gfx.draw(dogs[0][0], x, y + 14);
        Gfx.draw(dogs[2][0], x + 16, y + 14);
        break;
      case "HIGH_SCORE": Gfx.draw(Art.Icons.Crown, x, y, false, 2); break;
    }
  }

  /** 40x40 の台座にアイコンを描く。未解除なら「?」だけ。 */
  function drawPlate(index, x, y, unlocked) {
    if (!unlocked) {
      Gfx.fill(x, y, 40, 40, 0x0C0E18);
      Gfx.frame(x, y, 40, 40, 0x3A4468);
      Gfx.text("?", x + 12, y + 12, 0x5A6488, 2, false);
      return;
    }
    Gfx.fill(x, y, 40, 40, 0x2C3558);
    Gfx.frame(x, y, 40, 40, 0xFFD840);
    Gfx.frame(x + 1, y + 1, 38, 38, 0xC89A20);
    Gfx.clip(Math.trunc(x) + 2, Math.trunc(y) + 2, 36, 36);
    drawIcon(index, x + 4, y + 4);
    Gfx.unclip();
  }

  return {
    All, Columns,
    get unlocked() { let n = 0; for (const d of All) if (got.has(d.id)) n++; return n; },
    has(id) { return got.has(id); },
    when(id) { return got.has(id) ? new Date(got.get(id)) : null; },

    /** 実績を解除する。初めてなら保存して、画面上部に通知を出す。 */
    unlock(id) {
      if (got.has(id)) return;
      const index = All.findIndex(d => d.id === id);
      if (index < 0) return;
      got.set(id, Date.now());
      save();
      toasts.push(index);
      if (toasts.length === 1) toastT = 0;
      Audio.play(Sfx.Achievement);
    },

    /** 画面に出さない途中経過を記録する。 */
    mark(key) {
      if (got.has(key)) return;
      got.set(key, Date.now());
      save();
    },

    updateToast(dt) {
      if (toasts.length === 0) return;
      toastT += dt;
      if (toastT < ToastTime) return;
      toasts.shift();
      toastT = 0;
    },

    /** 解除したときの通知。画面上部に上からすべり込む。 */
    drawToast() {
      if (toasts.length === 0) return;
      const index = toasts[0];
      const W = 300, H = 48;
      const slide = Math.min(Math.min(toastT, ToastTime - toastT) / 0.25, 1);
      const x = (Gfx.W - W) / 2, y = -H + (H + 6) * slide;
      Gfx.fill(x + 3, y + 3, W, H, 0x000000, 120);
      Gfx.fill(x, y, W, H, 0x1B2033, 240);
      Gfx.frame(x, y, W, H, 0xFFD840);
      drawPlate(index, x + 4, y + 4, true);
      Gfx.text("ACHIEVEMENT UNLOCKED!", x + 50, y + 12, 0xFFD840);
      Gfx.text(All[index].name, x + 50, y + 28, 0xFFFFFF);
    },

    drawPlate,
  };
})();
