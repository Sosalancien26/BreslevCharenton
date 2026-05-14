/* Service Worker — CRM Synagogue Charenton */
const CACHE = 'synagogue-charenton-v1';
const CORE = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './flame.png',
  './favicon.ico',
  './favicon.png'
];

// Installation : pré-cache de la coquille de l'application
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(CORE)).then(() => self.skipWaiting())
  );
});

// Activation : nettoyage des anciens caches + prise de contrôle immédiate
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Ne jamais mettre en cache les appels à Supabase (données dynamiques)
  if (url.hostname.endsWith('supabase.co') || url.hostname.endsWith('supabase.in')) {
    return; // laisse passer vers le réseau
  }

  // Navigation : réseau d'abord, repli sur la coquille en cache (mode hors-ligne)
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(() => caches.match('./index.html').then((r) => r || caches.match('./')))
    );
    return;
  }

  // Autres ressources (CDN, polices, icônes) : cache d'abord, mise à jour en arrière-plan
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
});
