import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';

abstract class BossCloudStore {
  bool get configured;
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> document);
}

class FirestoreBossCloudStore implements BossCloudStore {
  @override
  bool get configured => BossFirebaseOptions.configured;
  Future<DocumentReference<Map<String, dynamic>>>? _document;

  Future<DocumentReference<Map<String, dynamic>>> _connect() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: BossFirebaseOptions.currentPlatform);
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    return FirebaseFirestore.instance
        .collection('bossAlarmUsers')
        .doc(user.uid)
        .collection('schedules')
        .doc('current');
  }

  Future<DocumentReference<Map<String, dynamic>>> _reference() async {
    try {
      return await (_document ??= _connect());
    } catch (_) {
      _document = null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final ref = await _reference();
    return (await ref.get(const GetOptions(source: Source.server))).data();
  }

  @override
  Future<void> save(Map<String, dynamic> document) async {
    final ref = await _reference();
    await ref.set({...document, 'updatedAt': FieldValue.serverTimestamp()});
  }
}
