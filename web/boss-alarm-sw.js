// Displays notifications requested by an open page. No background scheduling.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    const app = windows.find(client => client.url.startsWith(self.registration.scope));
    if (app) return app.focus();
    return self.clients.openWindow(self.registration.scope);
  })());
});
