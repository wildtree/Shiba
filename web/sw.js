// Service Worker: ゲームのファイルをすべて手元にキャッシュして、オフラインでも動くようにする。
// 新しい版は version.js の APP_VERSION が変わったときに入る。入っても勝手には切り替えず、
// 画面に出した「更新」ボタンが押されたら (SKIP_WAITING) 切り替える。
importScripts("./version.js");

const PREFIX = "shibajintori:" + self.registration.scope + ":";
const CACHE = PREFIX + self.APP_VERSION;
const FILES = [
  "./index.html",
  "./version.js",
  "./manifest.webmanifest",
  "./js/data.js",
  "./js/gfx.js",
  "./js/art.js",
  "./js/save.js",
  "./js/audio.js",
  "./js/world.js",
  "./js/input.js",
  "./js/app.js",
  "./js/pad.js",
  "./js/main.js",
  "./icons/icon-32.png",
  "./icons/icon-128.png",
  "./icons/icon-192.png",
  "./icons/icon-256.png",
  "./icons/icon-512.png",
  "./icons/maskable-512.png",
];

self.addEventListener("install", event => {
  // HTTP のキャッシュを通さず、サーバから取り直す
  event.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES.map(u => new Request(u, { cache: "reload" })))));
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    // 同じ場所に置いた古い版のキャッシュを消す (ほかのフォルダに置いたものには触らない)
    for (const key of await caches.keys())
      if (key.startsWith(PREFIX) && key !== CACHE) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener("message", event => {
  if (event.data && event.data.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // フォルダの URL (…/shiba/ など) で開いたときは、キャッシュした index.html を返す
    if (req.mode === "navigate" && new URL(req.url).pathname.endsWith("/")) {
      const page = await cache.match("./index.html");
      if (page) return page;
    }
    const hit = await cache.match(req, { ignoreSearch: true });
    if (hit) return hit;
    try {
      return await fetch(req);
    } catch (e) {
      return new Response("offline", { status: 503, statusText: "offline" });
    }
  })());
});
