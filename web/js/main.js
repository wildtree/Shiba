"use strict";
// 起動・画面の割り付け・毎フレームの処理・入力イベント・PWA (Service Worker と更新の知らせ)。
// 画面の割り付けは Android版 (android/GameView.cs) と同じ考え方:
//   操作パッドなし: PC版と同じ 640x400 の画面を、ウィンドウいっぱいに拡大する
//   操作パッドあり: 縦 / 2段 / 3列 のうち、フィールドがいちばん大きくなる並べ方を選ぶ

(() => {
  const screen = document.getElementById("screen");
  const sctx = screen.getContext("2d");

  Art.load();
  const params = new URLSearchParams(location.search);
  const app = new App(parseInt(params.get("stage") || "1", 10) || 1, params.has("bonus"));
  const pad = new TouchPad();
  app.isFullscreen = () => !!document.fullscreenElement;

  // 論理サイズの描画先 (ここに描いてから画面へ拡大する)
  function target(w, h) {
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    return { c, ctx: c.getContext("2d"), w, h };
  }
  const tMenu = target(640, 400), tField = target(FieldW, FieldH), tStatus = target(StatusW, StatusH);
  const tHudL = target(HudW, HudLH), tHudR = target(HudW, HudRH);

  // ------------------------------------------------------------ 画面の割り付け
  const Arr = { Wide: 0, Portrait: 1, Rows: 2, Columns: 3 };
  let arr = Arr.Wide;
  let vw = 0, vh = 0, dpr = 1;
  let menuDst, fieldDst, statusDst, padArea, hudLDst, hudRDst;
  const PadMaxCss = 420;            // 操作パッドの基準寸法の上限 (CSS px。スマホの縦画面の幅くらい)
  const PortraitStatusRatio = 0.75;

  const R = (l, t, w, h) => rect(l, t, l + w, t + h);

  function relayout(reshaped) {
    dpr = Math.min(window.devicePixelRatio || 1, 3);
    vw = Math.max(1, Math.round(window.innerWidth * dpr));
    vh = Math.max(1, Math.round(window.innerHeight * dpr));
    screen.width = vw; screen.height = vh;

    if (!app.touch) {
      arr = Arr.Wide;
      const s = Math.min(vw / 640, vh / 400);
      const w = 640 * s, h = 400 * s;
      menuDst = R((vw - w) / 2, (vh - h) / 2, w, h);
    } else {
      const qMax = PadMaxCss * dpr;
      const qBand = Math.min(qMax, vw);
      const qCol = Math.min(qMax, vh);
      const colW = 0.56 * qCol;
      const qPortrait = Math.min(qMax, vw);
      const sPortrait = Math.min(vw / FieldW, (vh - 0.64 * qPortrait) / (FieldH + PortraitStatusRatio * StatusH));
      const sRows = Math.min(vw / 640, (vh - 0.64 * qBand) / 400);
      const sColumns = Math.min((vw - 2 * colW) / FieldW, vh / FieldH);
      arr = Arr.Portrait;
      let best = sPortrait;
      if (sRows >= best * 0.98) { arr = Arr.Rows; best = sRows; }
      if (sColumns > best * 1.02) { arr = Arr.Columns; best = sColumns; }

      if (arr === Arr.Rows) {
        const s = Math.max(0.1, sRows), w = 640 * s, h = 400 * s;
        menuDst = R((vw - w) / 2, 0, w, h);
        padArea = rect(0, h, vw, vh);
        pad.layoutBand(padArea, qMax);
      } else if (arr === Arr.Columns) {
        const s = Math.max(0.1, sColumns), fw = FieldW * s, fh = FieldH * s;
        const fx = (vw - fw) / 2, fy = (vh - fh) / 2;
        fieldDst = R(fx, fy, fw, fh);
        const sideL = rect(0, 0, fx, vh), sideR = rect(fx + fw, 0, vw, vh);
        pad.layoutColumns(sideL, sideR, qCol);
        const m = 0.03 * qCol;
        let hs = Math.min(Math.min((sideL.w - 2 * m) / HudW, (sideR.w - 2 * m) / HudW),
                          Math.min((pad.leftTop - 2 * m) / HudLH, (pad.rightTop - 2 * m) / HudRH));
        hs = Math.max(0.5, hs);
        const hw = HudW * hs;
        hudLDst = R(sideL.cx - hw / 2, m, hw, HudLH * hs);
        hudRDst = R(sideR.cx - hw / 2, m, hw, HudRH * hs);
        const ms = Math.min(fw / 640, vh / 400);
        menuDst = R(vw / 2 - 320 * ms, vh / 2 - 200 * ms, 640 * ms, 400 * ms);
      } else {
        const s = Math.max(0.1, sPortrait), fw = FieldW * s, fh = FieldH * s;
        fieldDst = R((vw - fw) / 2, 0, fw, fh);
        padArea = rect(0, fh, vw, vh);
        pad.layoutBand(padArea, qMax);
        const room = Math.max(StatusH, pad.contentTop - fh);
        const ss = Math.min(vw / StatusW, room / StatusH);
        const sw = StatusW * ss, sh = StatusH * ss;
        const sy = fh + Math.max(0, (room - sh) / 2);
        statusDst = R((vw - sw) / 2, sy, sw, sh);
        const menuH = Math.max(1, padArea.t);
        const ms = Math.min(vw / 640, menuH / 400);
        menuDst = R((vw - 640 * ms) / 2, (menuH - 400 * ms) / 2, 640 * ms, 400 * ms);
      }
    }

    if (reshaped && app.touch) {
      // ボタンの位置が変わったので、押されたままのボタンを放す。持ち替えている間にやられないようにポーズ
      pad.releaseAll(app);
      app.pauseIfPlaying();
    }
  }

  function showPad() {
    if (app.touch) return;
    app.touch = true;
    relayout(false);
  }

  // キーボードやゲームパッドを使い始めたら操作パッドをしまって、画面を広く使う
  function hidePad() {
    if (!app.touch || pad.touches.size > 0) return;
    pad.releaseAll(app);
    app.touch = false;
    relayout(false);
  }

  // ------------------------------------------------------------ 描画
  function blit(t, dst) {
    const l = Math.round(dst.l), tp = Math.round(dst.t);
    sctx.drawImage(t.c, l, tp, Math.round(dst.r) - l, Math.round(dst.b) - tp);
  }

  function render() {
    sctx.imageSmoothingEnabled = false;
    sctx.fillStyle = arr === Arr.Wide ? "#000" : "#1B2033";
    sctx.fillRect(0, 0, vw, vh);

    const drawMain = () => {
      if (app.menuScene) {
        Gfx.target(tMenu.ctx, 640, 400); app.drawMenu(); blit(tMenu, menuDst);
      } else {
        Gfx.target(tField.ctx, FieldW, FieldH); app.drawFieldOnly(); blit(tField, fieldDst);
      }
    };

    switch (arr) {
      case Arr.Wide:
      case Arr.Rows:
        Gfx.target(tMenu.ctx, 640, 400); app.drawWide(); blit(tMenu, menuDst);
        break;
      case Arr.Columns:
        drawMain();
        Gfx.target(tHudL.ctx, HudW, HudLH); app.drawHudLeft(); blit(tHudL, hudLDst);
        Gfx.target(tHudR.ctx, HudW, HudRH); app.drawHudRight(); blit(tHudR, hudRDst);
        break;
      default:
        drawMain();
        Gfx.target(tStatus.ctx, StatusW, StatusH); app.drawStatus(); blit(tStatus, statusDst);
        break;
    }
    if (app.touch) pad.draw(sctx, app, app.clock);
  }

  // ------------------------------------------------------------ 画面が暗くならないように
  // ゲームの最中 (ポーズ中を除く) だけ Screen Wake Lock を持つ。HTTPS (か localhost) でないと使えない。
  // タブが裏に回ると勝手に放されるので、毎フレーム「持つべきか」を見て取り直す
  let wakeLock = null, wakeBusy = false;
  function updateWakeLock() {
    if (!navigator.wakeLock || wakeBusy) return;
    const want = document.visibilityState === "visible" && !app.paused &&
      (app.scene === Scene.StageIntro || app.scene === Scene.Play || app.scene === Scene.StageResult);
    if (want && !wakeLock) {
      wakeBusy = true;
      navigator.wakeLock.request("screen").then(l => {
        wakeLock = l;
        l.addEventListener("release", () => { if (wakeLock === l) wakeLock = null; });
      }).catch(() => { /* 電池が少ないときなどは断られる。次の機会にまた頼む */ })
        .finally(() => { setTimeout(() => { wakeBusy = false; }, 1000); });
    } else if (!want && wakeLock) {
      const l = wakeLock; wakeLock = null;
      l.release().catch(() => {});
    }
  }

  // ------------------------------------------------------------ 毎フレーム
  let last = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, Math.max(0, (now - last) / 1000));
    last = now;
    app.pads = Input.pollPads();
    if (Input.padUsed) hidePad();
    if (Input.pressed("KeyM")) Audio.cycleMode();   // BGM → 効果音だけ → 無音
    app.update(dt);
    pad.update(dt);
    updateWakeLock();
    render();
    Input.endFrame();
    requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------ 入力イベント
  const GameKeys = new Set(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Enter", "NumpadEnter", "Backspace", "Escape"]);

  function toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen?.();
    else document.documentElement.requestFullscreen?.().catch(() => { /* 許されない環境 */ });
  }

  window.addEventListener("keydown", e => {
    Audio.unlock();
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (GameKeys.has(e.code)) e.preventDefault();
    if (e.repeat) return;
    hidePad();
    // F: フルスクリーン (ネーム入力では文字として使う)。フルスクリーンにできるのはキー操作の中だけ
    if (e.code === "KeyF" && app.scene !== Scene.NameEntry) toggleFullscreen();
    Input.keyDown(e.code);
  });
  window.addEventListener("keyup", e => Input.keyUp(e.code));
  window.addEventListener("blur", () => { Input.reset(); pad.releaseAll(app); });

  // 指 (とペン)。マウスでも、操作パッドを出しているときはパッドを押せる
  const toScreen = e => [e.clientX * dpr, e.clientY * dpr];
  screen.addEventListener("pointerdown", e => {
    Audio.unlock();
    if (e.pointerType !== "mouse") showPad();
    if (!app.touch) return;
    e.preventDefault();
    try { screen.setPointerCapture(e.pointerId); } catch (err) { /* 古いブラウザ */ }
    const [x, y] = toScreen(e);
    pad.pointer(e.pointerId, x, y, true, app);
  });
  screen.addEventListener("pointermove", e => {
    if (!app.touch || !pad.touches.has(e.pointerId) && e.buttons === 0) return;
    const [x, y] = toScreen(e);
    pad.pointer(e.pointerId, x, y, true, app);
  });
  const up = e => { if (app.touch) pad.pointer(e.pointerId, 0, 0, false, app); };
  screen.addEventListener("pointerup", up);
  screen.addEventListener("pointercancel", up);
  screen.addEventListener("contextmenu", e => e.preventDefault());
  // iOS Safari は touchend の中でないと音を出させてくれないことがある
  window.addEventListener("touchend", () => Audio.unlock(), { passive: true });

  window.addEventListener("gamepadconnected", () => Audio.unlock());
  window.addEventListener("gamepaddisconnected", e => {
    Input.forgetPad(e.gamepad.index);
    Input.reset();
    app.pauseIfPlaying();   // プレイ中に切れたら自動でポーズする
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      app.pauseIfPlaying();
      Input.reset(); pad.releaseAll(app);
      Audio.suspend();
    } else Audio.resume();
  });

  let resizeTimer = 0;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => relayout(true), 60);
  });

  // 指で操作する端末なら、最初から操作パッドを出しておく
  if (window.matchMedia && matchMedia("(pointer: coarse)").matches && !matchMedia("(any-pointer: fine)").matches) app.touch = true;
  relayout(false);
  requestAnimationFrame(t => { last = t; requestAnimationFrame(frame); });

  // ------------------------------------------------------------ PWA: オフライン用のキャッシュと、更新の知らせ
  const banner = document.getElementById("update");
  let updateRequested = false;

  function offerUpdate(worker) {
    banner.hidden = false;
    document.getElementById("update-now").onclick = () => {
      updateRequested = true;
      banner.querySelector(".msg").textContent = "更新しています… / Updating…";
      worker.postMessage({ type: "SKIP_WAITING" });
    };
    document.getElementById("update-later").onclick = () => { banner.hidden = true; };
  }

  if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost" || location.hostname === "127.0.0.1")) {
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (updateRequested) location.reload();   // 新しい版に切り替わったので読み直す
    });
    // 前回までに新しい版を受け取ってあれば、オフラインでも (register が失敗しても) 知らせる
    navigator.serviceWorker.getRegistration().then(reg => {
      if (reg && reg.waiting && navigator.serviceWorker.controller) offerUpdate(reg.waiting);
    }).catch(() => { /* 使えない */ });
    navigator.serviceWorker.register("./sw.js", { updateViaCache: "none" }).then(reg => {
      if (reg.waiting && navigator.serviceWorker.controller) offerUpdate(reg.waiting);
      reg.addEventListener("updatefound", () => {
        const nw = reg.installing;
        if (!nw) return;
        nw.addEventListener("statechange", () => {
          // すでに古い版で動いているときだけ知らせる (はじめて開いたときは黙ってキャッシュする)
          if (nw.state === "installed" && navigator.serviceWorker.controller) offerUpdate(nw);
        });
      });
      // 開いている間も、ときどきサーバに新しい版がないか見に行く
      const check = () => { if (navigator.onLine !== false) reg.update().catch(() => { /* オフライン */ }); };
      setInterval(check, 30 * 60 * 1000);
      document.addEventListener("visibilitychange", () => { if (!document.hidden) check(); });
    }).catch(e => console.warn("service worker registration failed", e));
  }
})();
