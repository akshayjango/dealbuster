self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data.json(); } catch {}
  const title = data.title || 'Dealbuster Admin';
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || '',
    tag: 'dealbuster-sync',
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/'));
});
