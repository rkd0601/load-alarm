import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_options.dart';
import 'firebase_app_service.dart';

abstract class BossCloudStore {
  bool get configured;
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> document);
}

class FirestoreBossCloudStore implements BossCloudStore {
  FirestoreBossCloudStore({this.roomId});

  final String? roomId;

  @override
  bool get configured => BossFirebaseOptions.configured;

  Future<void> _connect() async {
    await ensureFirebaseInitialized();
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
  }

  CollectionReference<Map<String, dynamic>> _schedules() {
    final db = FirebaseFirestore.instance;
    final id = roomId;
    if (id == null) return db.collection('bossSchedules');
    return db.collection('rooms').doc(id).collection('bossSchedules');
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    await _connect();
    final snapshot =
        await _schedules().get(const GetOptions(source: Source.server));
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
      final allowed = [
            'anchorMs',
            'intervalMinutes',
            'weekdays',
            'minuteOfDay',
            if (roomId != null) 'enabled',
          ];
      if (fields.keys.any((k) => !allowed.contains(k))) {
        throw const FormatException('공유 시간 변경 필드가 올바르지 않습니다.');
      }
      batch.update(_schedules().doc(entry.key as String), {
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
        if (roomId != null) 'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      });
    }
    await batch.commit();
  }
}
