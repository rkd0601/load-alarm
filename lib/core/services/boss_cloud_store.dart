import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import 'firestore_transport.dart';

abstract class BossCloudStore {
  bool get configured;
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> document);
}

class FirestoreBossCloudStore implements BossCloudStore {
  @override
  bool get configured => BossFirebaseOptions.configured;
  static Future<FirebaseApp>? _initialization;

  Future<void> _connect() async {
    // Firebase.apps on web requires JS SDK globals installed by initializeApp.
    // Querying apps before initialization prevents the first DB load entirely.
    try {
      await (_initialization ??=
          Firebase.initializeApp(options: BossFirebaseOptions.currentPlatform));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    configureFirestoreTransport();
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    await _connect();
    final snapshot = await FirebaseFirestore.instance
        .collection('bossSchedules')
        .get(const GetOptions(source: Source.server));
    if (snapshot.docs.isEmpty) return null;
    return {
      'schemaVersion': 1,
      'bosses': snapshot.docs.map((d) => d.data()).toList()
    };
  }

  @override
  Future<void> save(Map<String, dynamic> document) async {
    await _connect();
    final changes = document['changes'] as Map;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final entry in changes.entries) {
      // Only changed fields are sent. Other users' changes to other bosses or
      // other fields are not overwritten by a stale full-list upload.
      final fields = Map<String, dynamic>.from(entry.value as Map);
      if (fields.keys.any((k) => !const [
            'anchorMs',
            'intervalMinutes',
            'weekdays',
            'minuteOfDay'
          ].contains(k))) {
        throw const FormatException('공유 시간 변경 필드가 올바르지 않습니다.');
      }
      batch.update(db.collection('bossSchedules').doc(entry.key as String),
          {...fields, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }
}
