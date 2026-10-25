// Service worker: keeps the app shell on the phone so it opens fast and shows a friendly page offline.
// It NEVER stores Supabase data (logins, listings, conversations, photos or photo links): those always go to the internet.
const CACHE = 'theset-shell-v11'; // change the number after each update so phones get the new files
const SHELL = ['./', './index.html', './styles.css', './app.js', './data.js', './copy.js', './config.js',
  './offline.html', './manifest.webmanifest', './icons/icon.svg', './icons/icon-192.png', './icons/icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return; // Supabase + CDN: straight to network, never cached
  if (e.request.mode === 'navigate') {
    e.respondWith(fetch(e.request).catch(() => caches.match('./index.html').then(r => r || caches.match('./offline.html'))));
    return;
  }
  // Same-site files: use the network first so updates show up, fall back to the saved copy offline.
  e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; })
    .catch(() => caches.match(e.request)));
});
