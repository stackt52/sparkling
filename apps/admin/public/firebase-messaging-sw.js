/* global importScripts, firebase, self, clients */
// Firebase Cloud Messaging service worker for the Sparkling admin dashboard (INT-003).
// Background pushes are displayed by the Firebase SDK; clicking one opens the page in `fcm_options.link`
// (set by the API) or, failing that, the page derived from the payload below.
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBfVXE1ZkHDHgbfrmdpkVD6ZPOp89TOktQ',
  authDomain: 'sparkling-4e89d.firebaseapp.com',
  projectId: 'sparkling-4e89d',
  storageBucket: 'sparkling-4e89d.firebasestorage.app',
  messagingSenderId: '700174326619',
  appId: '1:700174326619:web:bc3dca8003ddeb15c5587e',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage(() => {
  // Keep the SDK's default notification (title/body/icon from the message); nothing extra to show.
});

function targetPath(data) {
  const type = (data && data.type) || '';
  if (type === 'quotation' && data.quotation_id) return '/quotations?focus=' + encodeURIComponent(data.quotation_id);
  if ((type === 'booking' || type === 'payment' || type === 'loyalty') && data.booking_id) return '/bookings?focus=' + encodeURIComponent(data.booking_id);
  if ((type === 'work_order' || type === 'task') && data.work_order_id) return '/work-orders?focus=' + encodeURIComponent(data.work_order_id);
  return '/notifications';
}

self.addEventListener('notificationclick', (event) => {
  const fcm = event.notification && event.notification.data && event.notification.data.FCM_MSG;
  const link = (fcm && fcm.fcmOptions && fcm.fcmOptions.link) || (fcm && fcm.notification && fcm.notification.click_action);
  const url = link || new URL(targetPath(fcm && fcm.data), self.location.origin).toString();
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const same = list.find((c) => c.url.startsWith(self.location.origin) && 'focus' in c);
      if (same) return same.navigate(url).then((c) => (c ? c.focus() : undefined));
      return clients.openWindow(url);
    }),
  );
});
