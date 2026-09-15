import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_options.dart';
import '../../features/boss_alarm/domain/alarm_settings.dart';
import 'firebase_app_service.dart';

abstract class BossCloudStore {
  bool get configured;
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> document);
  Future<void> saveAlarmSettings(AlarmSettings settings) async {}
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

  DocumentReference<Map<String, dynamic>>? _memberSettings() {
    final id = roomId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    if (id == null) {
      return FirebaseFirestore.instance
          .collection('bossAlarmUsers')
          .doc(uid)
          .collection('schedules')
          .doc('current');
    }
    return FirebaseFirestore.instance
        .collection('rooms')
        .doc(id)
        .collection('memberSettings')
        .doc(uid);
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    await _connect();
    final snapshot =
        await _schedules().get(const GetOptions(source: Source.server));
    if (snapshot.docs.isEmpty) return null;
    final settingsRef = _memberSettings();
    final settingsDoc = settingsRef == null
        ? null
        : await settingsRef.get(const GetOptions(source: Source.server));
    final enabledById = <String, bool>{};
    final settingsData = settingsDoc?.data();
    if (settingsData != null) {
      final enabled = settingsData['enabledBosses'];
      if (enabled is Map) {
        for (final entry in enabled.entries) {
          if (entry.value is bool) {
            enabledById['${entry.key}'] = entry.value as bool;
          }
        }
      } else {
        final bosses = settingsData['bosses'];
        if (bosses is List) {
          for (final boss in bosses) {
            if (boss is Map && boss['id'] != null && boss['enabled'] is bool) {
              enabledById['${boss['id']}'] = boss['enabled'] as bool;
            }
          }
        }
      }
    }
    return {
      'schemaVersion': 1,
      'bosses': snapshot.docs.map((d) {
        final data = {...d.data()};
        data['enabled'] = enabledById['${data['id']}'] ?? false;
        return data;
      }).toList(),
      'alarmSettings': AlarmSettings.fromJson(settingsData).toJson(),
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
      final enabled = fields.remove('enabled');
      final allowed = [
        'anchorMs',
        'intervalMinutes',
        'weekdays',
        'minuteOfDay',
      ];
      if (fields.keys.any((k) => !allowed.contains(k))) {
        throw const FormatException('공유 시간 변경 필드가 올바르지 않습니다.');
      }
      if (fields.isNotEmpty) {
        batch.update(_schedules().doc(entry.key as String), {
          ...fields,
          'updatedAt': FieldValue.serverTimestamp(),
          if (roomId != null)
            'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }
      if (enabled is bool) {
        final settingsRef = _memberSettings();
        if (settingsRef != null) {
          batch.set(
              settingsRef,
              {
                'uid': FirebaseAuth.instance.currentUser?.uid,
                'enabledBosses': {entry.key as String: enabled},
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }
      }
    }
    await batch.commit();
  }

  @override
  Future<void> saveAlarmSettings(AlarmSettings settings) async {
    await _connect();
    final settingsRef = _memberSettings();
    if (settingsRef == null) return;
    await settingsRef.set({
      'uid': FirebaseAuth.instance.currentUser?.uid,
      ...settings.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
