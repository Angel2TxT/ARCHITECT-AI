/* Service worker ARCHITECT — PWA + shell offline para Casa hogar. */
const CACHE_NAME = "architect-pwa-v3";
const PRECACHE = [
  "/",
  "/legacy-app",
  "/login",
  "/manifest.webmanifest",
  "/static/manifest.webmanifest",
  "/static/pwa.js?v=2",
  "/static/offline-store.js?v=1",
  "/static/auth.js?v=32",
  "/static/home-projects.js?v=59",
  "/static/style.css?v=163",
  "/static/dialogs.js?v=4",
  "/static/brand/pwa-icon-192.png",
  "/static/brand/pwa-icon-512.png",
  "/static/brand/architect-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) =>
        Promise.all(
          PRECACHE.map((url) =>
            cache.add(url).catch(() => {
              /* Ignora assets opcionales que fallen en precache. */
            })
          )
        )
      )
      .then(() => self.skipWaiting())
      .catch(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // API / media: red únicamente (offline lo resuelve la app + IndexedDB).
  if (
    url.pathname.startsWith("/api/") ||
    url.pathname.startsWith("/media/") ||
    url.pathname.startsWith("/uploads/")
  ) {
    return;
  }

  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(async () => {
          const cached =
            (await caches.match(req)) ||
            (await caches.match("/legacy-app")) ||
            (await caches.match("/"));
          return (
            cached ||
            new Response(
              "<!doctype html><title>Sin conexión</title><h1>Sin conexión</h1><p>Abre ARCHITECT cuando hayas cargado Casa hogar al menos una vez online.</p>",
              { headers: { "Content-Type": "text/html; charset=utf-8" } }
            )
          );
        })
    );
    return;
  }

  if (url.pathname.startsWith("/static/") || url.pathname === "/sw.js") {
    event.respondWith(
      caches.match(req).then((cached) => {
        const network = fetch(req)
          .then((res) => {
            if (res && res.ok) {
              const copy = res.clone();
              caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
            }
            return res;
          })
          .catch(() => cached);
        return cached || network;
      })
    );
  }
});
