// Service worker minimal — hanya untuk memenuhi syarat "Add to Home Screen"
// di Android/Chrome. Aplikasi ini tetap butuh koneksi internet untuk
// mengambil/menyimpan data (Supabase), jadi tidak ada caching offline data.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Teruskan semua request apa adanya (tanpa cache) — data harus selalu
  // terbaru dari server.
  event.respondWith(fetch(event.request));
});
