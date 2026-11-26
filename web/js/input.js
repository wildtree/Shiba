"use strict";
// キーボード・ゲームパッド・操作パッドの入力 (PC版 Input.cs と同じ考え方)。
// ゲームパッドと画面の操作パッドは「キーボードのキーを押した」のと同じ扱いにするので、画面側はキーだけ見ればよい。

const Input = (() => {
  const down = new Set();
  const pressed = [];
  const dirs = [];
  let padPause = false;

  function toDir(code) {
    switch (code) {
      case "ArrowLeft": case "KeyA": return Dir.Left;
      case "ArrowRight": case "KeyD": return Dir.Right;
      case "ArrowUp": case "KeyW": return Dir.Up;
      case "ArrowDown": case "KeyS": return Dir.Down;
    }
    return null;
  }

  function keyDown(code) {
    down.add(code);
    pressed.push(code);
    const d = toDir(code);
    if (d !== null) { removeFrom(dirs, d); dirs.push(d); }
  }

  function keyUp(code) {
    down.delete(code);
    const d = toDir(code);
    if (d !== null) {
      // 矢印キーとWASDの両方を押している場合に備えて、まだ押されているか確かめる
      let still = false;
      for (const k of down) if (toDir(k) === d) still = true;
      if (!still) removeFrom(dirs, d);
    }
  }

  // ---------------- ゲームパッド ----------------
  // 方向は矢印キー、A/B/X はスペース、Y は R、START は Enter、BACK は Esc を押したのと同じ扱い
  const DirKey = ["ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp"];
  const padDpad = [false, false, false, false], padStick = [false, false, false, false], padDir = [false, false, false, false];
  let stickX = 0, stickY = 0;

  function syncPadDirs() {
    for (let i = 0; i < 4; i++) {
      const now = padDpad[i] || padStick[i];
      if (now === padDir[i]) continue;
      padDir[i] = now;
      if (now) keyDown(DirKey[i]); else keyUp(DirKey[i]);
    }
  }

  function padKey(code, isDown) { if (isDown) keyDown(code); else keyUp(code); }

  /** b: "up" "down" "left" "right" "south" "north" "start" "back" */
  function padButton(b, isDown) {
    switch (b) {
      case "down": padDpad[Dir.Down] = isDown; syncPadDirs(); break;
      case "left": padDpad[Dir.Left] = isDown; syncPadDirs(); break;
      case "right": padDpad[Dir.Right] = isDown; syncPadDirs(); break;
      case "up": padDpad[Dir.Up] = isDown; syncPadDirs(); break;
      case "south": padKey("Space", isDown); break;
      case "north": padKey("KeyR", isDown); break;         // Y: ポーズ中のやり直し
      case "start": padKey("Enter", isDown); if (isDown) padPause = true; break;
      case "back": padKey("Escape", isDown); break;
    }
  }

  /** 左スティック。値は -1..1。倒れている量が大きい軸だけを採用する。 */
  function padAxis(x, y) {
    stickX = x; stickY = y;
    const active = padStick[0] || padStick[1] || padStick[2] || padStick[3];
    const threshold = active ? 0.30 : 0.49;
    const ax = Math.abs(stickX), ay = Math.abs(stickY);
    let dir = -1;
    if (Math.max(ax, ay) >= threshold) {
      let horizontal = ax > ay;
      // 今の向きの軸を少し優遇して、ほぼ45度のときに切り替わり続けないようにする
      if (padStick[Dir.Left] || padStick[Dir.Right]) horizontal = ax * 5 > ay * 4;
      else if (padStick[Dir.Up] || padStick[Dir.Down]) horizontal = ax * 4 > ay * 5;
      dir = horizontal ? (stickX < 0 ? Dir.Left : Dir.Right) : (stickY < 0 ? Dir.Up : Dir.Down);
    }
    for (let i = 0; i < 4; i++) padStick[i] = i === dir;
    syncPadDirs();
  }

  // ブラウザのゲームパッドは毎フレーム読みに行く。変わったところだけ押した/離したにする
  const prev = new Map();   // index → { buttons: [], name: [] }
  const StdMap = { 0: "south", 1: "south", 2: "south", 3: "north", 8: "back", 9: "start", 12: "up", 13: "down", 14: "left", 15: "right" };
  // 配置の分からない汎用パッド: 4番目=やり直し、9番目=BACK、10番目=START、それ以外は「おしっこ/決定」
  const RawMap = i => i === 3 ? "north" : i === 8 ? "back" : i === 9 ? "start" : "south";

  let padUsed = false;   // このフレームでゲームパッドのボタンが押された
  function pollPads() {
    padUsed = false;
    if (!navigator.getGamepads) return 0;
    let count = 0;
    const pads = navigator.getGamepads();
    for (const gp of pads) {
      if (!gp || !gp.connected) continue;
      count++;
      const std = gp.mapping === "standard";
      let st = prev.get(gp.index);
      if (!st) { st = { buttons: [] }; prev.set(gp.index, st); }
      if (!st.any) st.any = [];
      for (let i = 0; i < gp.buttons.length; i++) {
        const now = gp.buttons[i].pressed;
        // 操作パッドをしまう合図は、ゲームで使わないボタン (トリガーなど) でもよい
        if (now && !st.any[i]) padUsed = true;
        st.any[i] = now;
        const name = std ? StdMap[i] : (i < 12 ? RawMap(i) : undefined);
        if (!name) continue;
        if (now !== !!st.buttons[i]) { st.buttons[i] = now; padButton(name, now); }
      }
      if (gp.axes.length >= 2) {
        const x = gp.axes[0], y = gp.axes[1];
        if (Math.max(Math.abs(x), Math.abs(y)) >= 0.5) padUsed = true;
        if (x !== st.ax || y !== st.ay) { st.ax = x; st.ay = y; padAxis(x, y); }
      }
    }
    return count;
  }

  function reset() {
    down.clear(); dirs.length = 0;
    padDpad.fill(false); padStick.fill(false); padDir.fill(false);
    stickX = stickY = 0;
    for (const st of prev.values()) { st.buttons = []; st.ax = st.ay = undefined; }
  }

  return {
    keyDown, keyUp, reset, padButton, pollPads,
    forgetPad(index) { prev.delete(index); },
    get pressedKeys() { return pressed; },
    get anyPressed() { return pressed.length > 0; },
    get padPause() { return padPause; },
    get padUsed() { return padUsed; },
    endFrame() { pressed.length = 0; padPause = false; },
    pressed(code) { return pressed.includes(code); },
    /** 最後に押された方向キー。 */
    get held() { return dirs.length > 0 ? dirs[dirs.length - 1] : null; },
    get pressedDir() {
      for (const s of pressed) { const d = toDir(s); if (d !== null) return d; }
      return null;
    },
    get action() { return this.pressed("Space") || this.pressed("KeyZ") || this.pressed("KeyX"); },
    get confirm() { return this.action || this.pressed("Enter") || this.pressed("NumpadEnter"); },
    get back() { return this.pressed("Escape"); },
  };
})();
