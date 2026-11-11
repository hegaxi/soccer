// Service worker: hace instalable la app y guarda la interfaz para que abra al instante.
// Nunca guarda /api (datos, sesión, videos): eso siempre va a la red.
const CACHE = 'soccer-v1';

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(['/', '/manifest.webmanifest', '/icono-192.png'])).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;

  // navegación: red primero (para recibir versiones nuevas); sin conexión, la interfaz guardada
  if (request.mode === 'navigate') {
    e.respondWith(fetch(request).then(r => {
      if (r.ok) caches.open(CACHE).then(c => c.put('/', r.clone()));
      return r;
    }).catch(() => caches.match('/')));
    return;
  }
  // recursos con nombre versionado (/assets/…): caché primero
  e.respondWith(caches.match(request).then(hit => hit || fetch(request).then(r => {
    if (r.ok && url.pathname.startsWith('/assets/')) { const copia = r.clone(); caches.open(CACHE).then(c => c.put(request, copia)); }
    return r;
  })));
});
