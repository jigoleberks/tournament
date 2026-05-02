const CACHE = "shell-v6";
const SHELL = ["/manifest.webmanifest", "/icon.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET") return;
  if (url.pathname.startsWith("/api/")) return;       // never cache API

  // Network-first for navigations so dynamic HTML stays fresh; cache on success for offline fallback.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).then((res) => {
        if (res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(event.request, copy));
        }
        return res;
      }).catch(() => caches.match(event.request).then((c) => c || new Response("offline", { status: 503 })))
    );
    return;
  }

  // Cache-first for static assets.
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request).then((res) => {
      if (res.status === 200 && url.origin === location.origin) {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(event.request, copy));
      }
      return res;
    }))
  );
});

self.addEventListener("sync", (event) => {
  if (event.tag === "catch-sync") {
    event.waitUntil(self.clients.matchAll().then((clients) => {
      clients.forEach((c) => c.postMessage({ type: "drain" }))
    }))
  }
});

self.addEventListener("push", (event) => {
  if (!event.data) return
  const data = event.data.json()
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      data: { url: data.url || "/" }
    })
  )
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const target = event.notification.data?.url || "/"
  event.waitUntil(self.clients.matchAll({ type: "window" }).then((clients) => {
    const open = clients.find((c) => c.url.includes(target))
    if (open) return open.focus()
    return self.clients.openWindow(target)
  }))
})
