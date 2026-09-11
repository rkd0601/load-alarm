import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/firebase_app_service.dart';
import '../domain/game_server.dart';
import '../domain/room.dart';

class RoomService {
  RoomService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> connect() async {
    await ensureFirebaseInitialized();
  }

  Future<void> signIn(String email, String password) async {
    await connect();
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp(String email, String password, String displayName) async {
    await connect();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(displayName.trim());
    await _saveProfile(displayName.trim());
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _saveProfile(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set({
      'displayName': displayName,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<BossRoom>> rooms() {
    return _db
        .collection('rooms')
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BossRoom.fromJson(doc.id, doc.data()))
            .toList());
  }

  Stream<List<BossRoom>> myRooms() {
    final user = _auth.currentUser;
    if (user == null) return const Stream<List<BossRoom>>.empty();
    return _db
        .collectionGroup('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((snapshot) async {
      final refs = snapshot.docs.map((doc) => doc.reference.parent.parent);
      final rooms = <BossRoom>[];
      for (final ref in refs) {
        if (ref == null) continue;
        final doc = await ref.get();
        if (doc.exists) {
          rooms.add(BossRoom.fromJson(doc.id, doc.data()!));
        }
      }
      rooms.sort((a, b) => a.serverLabel.compareTo(b.serverLabel));
      return rooms;
    });
  }

  Future<BossRoom> createRoom({
    required String name,
    required GameServer server,
    required String password,
  }) async {
    await connect();
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw StateError('방 이름을 입력해 주세요.');
    final room = _db.collection('rooms').doc();
    final hasPassword = password.trim().isNotEmpty;
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.set(room, {
      'name': trimmedName,
      'world': server.world.id,
      'worldName': server.world.name,
      'serverNo': server.number,
      'ownerUid': user.uid,
      'hasPassword': hasPassword,
      'passwordHash': hasPassword ? _passwordHash(room.id, password) : null,
      'createdAt': now,
      'updatedAt': now,
    });
    batch.set(room.collection('members').doc(user.uid), {
      'uid': user.uid,
      'displayName': user.displayName ?? user.email ?? '사용자',
      'role': 'owner',
      'pushEnabled': true,
      'joinedAt': now,
      'updatedAt': now,
    });
    final schedules = await _db.collection('bossSchedules').get();
    for (final doc in schedules.docs) {
      batch.set(room.collection('bossSchedules').doc(doc.id), {
        ...doc.data(),
        'enabled': false,
        'updatedAt': now,
        'updatedBy': user.uid,
      });
    }
    await batch.commit();
    return BossRoom(
      id: room.id,
      name: trimmedName,
      world: server.world.id,
      worldName: server.world.name,
      serverNo: server.number,
      ownerUid: user.uid,
      hasPassword: hasPassword,
    );
  }

  Future<void> joinRoom(BossRoom room, String password) async {
    await connect();
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final snapshot = await _db.collection('rooms').doc(room.id).get();
    final data = snapshot.data();
    if (data == null) throw StateError('방을 찾을 수 없습니다.');
    if (data['hasPassword'] == true &&
        data['passwordHash'] != _passwordHash(room.id, password)) {
      throw StateError('방 비밀번호가 맞지 않습니다.');
    }
    await snapshot.reference.collection('members').doc(user.uid).set({
      'uid': user.uid,
      'displayName': user.displayName ?? user.email ?? '사용자',
      'role': data['ownerUid'] == user.uid ? 'owner' : 'member',
      'pushEnabled': true,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Future<void> sendMessage(String roomId, String text) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 500) throw StateError('메시지는 500자 이하로 입력해 주세요.');
    await _db.collection('rooms').doc(roomId).collection('messages').add({
      'uid': user.uid,
      'displayName': user.displayName ?? user.email ?? '사용자',
      'text': trimmed,
      'type': 'text',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _passwordHash(String roomId, String password) {
    final bytes = utf8.encode('$roomId:${password.trim()}');
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
