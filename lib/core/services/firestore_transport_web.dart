// The pinned FlutterFire version does not expose these web transport settings.
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js;

bool _configured = false;
void configureFirestoreTransport() {
  if (_configured) return;
  final core = js.getProperty<Object>(js.globalThis, 'firebase_core');
  final firestore = js.getProperty<Object>(js.globalThis, 'firebase_firestore');
  final app = js.callMethod<Object>(core, 'getApp', []);
  js.callMethod<Object>(firestore, 'initializeFirestore', [
    app,
    js.jsify({'experimentalForceLongPolling': true, 'useFetchStreams': false}),
  ]);
  _configured = true;
}
