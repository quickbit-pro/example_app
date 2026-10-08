'use strict';

// The branded build/deploy tools version this cache from the delivered content
// so precached assets never outlive a release; the app shows its "update
// available" banner when a new worker takes control.
const CACHE_NAME = 'example-app-v2';

// The application shell. The page registers this worker after its first
// frame, so these requests are answered from the browser's HTTP cache rather
// than downloaded a second time. CanvasKit lives in a versioned folder
// (canvaskit-<engine revision>/) and is added on request by the page, which
// knows which variant this browser loaded.
const APP_SHELL = [
  './',
  './index.html',
  './flutter_bootstrap.js',
  './app_recovery.js',
  './main.dart.js',
  './manifest.json',
  './favicon.png',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  './assets/assets/crypto/usdc.png',
  './assets/assets/crypto/usdt.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
];

// Each release installs its HTML and JavaScript together. Navigation uses that
// shell; the page's update check activates the next complete release.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(
        keys
          .filter((key) => key.startsWith('example-app-') && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'precache' || !Array.isArray(data.urls)) return;
  const urls = data.urls.filter((url) => {
    try { return new URL(url, self.location.href).origin === self.location.origin; } catch (e) { return false; }
  });
  if (!urls.length) return;
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.all(urls.map((url) =>
        cache.match(url).then((hit) => hit ? undefined : cache.add(url).catch(() => undefined)),
      )),
    ),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // Legal documents are real files, including when opened from an installed
  // PWA. Let the browser fetch the PDF instead of returning the app shell.
  if (url.pathname.toLowerCase().endsWith('.pdf')) return;

  if (request.mode === 'navigate') {
    // Launch the HTML and JS from the same installed release. A fresh HTML
    // page paired with cache-first JS from the previous release can fail to
    // boot. Worker updates replace the complete shell in the next cache.
    event.respondWith(
      caches.open(CACHE_NAME).then(async (cache) => {
        var shell = await cache.match('./index.html');
        if (shell) return shell;
        return fetch(request);
      }),
    );
    return;
  }

  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      // Never pick up an obsolete Flutter worker's JS or another release's
      // assets from CacheStorage's global match order.
      const cached = await cache.match(request);
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          event.waitUntil(cache.put(request, copy).catch(() => undefined));
        }
        return response;
      });
    }),
  );
});
