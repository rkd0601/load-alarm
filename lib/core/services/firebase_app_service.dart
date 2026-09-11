import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import 'firestore_transport.dart';

Future<FirebaseApp>? _initialization;

Future<void> ensureFirebaseInitialized() async {
  if (!BossFirebaseOptions.configured) return;
  try {
    await (_initialization ??=
        Firebase.initializeApp(options: BossFirebaseOptions.currentPlatform));
  } catch (_) {
    _initialization = null;
    rethrow;
  }
  configureFirestoreTransport();
}
