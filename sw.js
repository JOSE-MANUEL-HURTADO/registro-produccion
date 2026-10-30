// Registro de producción — service worker
// Solo guarda la "cáscara" de la app. Los datos (Supabase) siempre van por internet.
const CACHE = 'registro-v7.72';
const SHELL = ['./', './index.html', './manifest.json', './icons/logo-192.png', './icons/logo-180.png', './apple-touch-icon.png', './icons/ios-180.png', './icons/artica_simbolo.png', './icons/artica_simbolo_negro.png',
  './lib/supabase.js', './lib/jsqr.js', './lib/qrcode.js', './lib/jspdf.js', './icons/logo-etiqueta.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(()=>{})); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.hostname.endsWith('supabase.co')) return;           // datos: nunca de caché
  if (u.origin === location.origin && (u.pathname.endsWith('/') || u.pathname.endsWith('.html'))) {
    e.respondWith(fetch(u.href, {cache:'no-cache', credentials:'same-origin'}).then(r => { const c = r.clone(); caches.open(CACHE).then(x => x.put(e.request, c)); return r; })
      .catch(() => caches.match(e.request)));                                                 // app: primero internet
    return;
  }
  e.respondWith(caches.match(e.request).then(c => c || fetch(e.request).then(r => {
    if (r && r.status === 200) { const cl = r.clone(); caches.open(CACHE).then(x => x.put(e.request, cl)); }
    return r;
  })));
});

// Avisos al celular (web push)
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Elíptica', {
    body: d.body || '', tag: d.tag, icon: './icons/logo-192.png', badge: './icons/logo-192.png', data: { url: d.url || './' }
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(ws => {
    for (const w of ws) if (w.url.startsWith(self.registration.scope) && 'focus' in w) return w.focus();
    return clients.openWindow(e.notification.data && e.notification.data.url || './');
  }));
});
