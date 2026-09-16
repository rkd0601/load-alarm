import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/firebase_app_service.dart';
import '../domain/app_popup.dart';
import '../domain/game_server.dart';
import '../domain/room.dart';
import '../domain/room_member.dart';

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

  Stream<AppPopup?> activePopup() {
    return _db.collection('appPopups').doc('current').snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final popup = AppPopup.fromJson(doc.id, data);
      return popup.visible ? popup : null;
    });
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
    if (trimmedName.length > 40) throw StateError('방 이름은 40자 이하로 입력해 주세요.');
    final owned = await _db
        .collection('rooms')
        .where('ownerUid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (owned.docs.isNotEmpty) {
      throw StateError('방은 계정당 1개만 생성할 수 있습니다.');
    }
    final room = _db.collection('rooms').doc();
    final hasPassword = password.trim().isNotEmpty;
    final createdMs = DateTime.now().millisecondsSinceEpoch;
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
    if (hasPassword) {
      batch.set(room.collection('secrets').doc('password'), {
        'password': password.trim(),
        'updatedAt': now,
        'updatedBy': user.uid,
      });
    }
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
      final data = {...doc.data()};
      final weekdays = data['weekdays'];
      if (weekdays is List && weekdays.isEmpty) {
        data['anchorMs'] = createdMs;
      }
      data.remove('enabled');
      batch.set(room.collection('bossSchedules').doc(doc.id), {
        ...data,
        'updatedAt': now,
        'updatedBy': user.uid,
      });
    }
    batch.set(room.collection('memberSettings').doc(user.uid), {
      'uid': user.uid,
      'enabledBosses': {},
      'quietEnabled': false,
      'quietStartMinute': 0,
      'quietEndMinute': 0,
      'updatedAt': now,
    });
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
    final memberRef = snapshot.reference.collection('members').doc(user.uid);
    final settingsRef =
        snapshot.reference.collection('memberSettings').doc(user.uid);
    final reads = await Future.wait([memberRef.get(), settingsRef.get()]);
    final existingMember = reads[0];
    final existingSettings = reads[1];
    final batch = _db.batch();
    if (existingMember.exists) {
      batch.update(memberRef, {
        'displayName': user.displayName ?? user.email ?? '사용자',
        'pushEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(memberRef, {
        'uid': user.uid,
        'displayName': user.displayName ?? user.email ?? '사용자',
        'role': data['ownerUid'] == user.uid ? 'owner' : 'member',
        'pushEnabled': true,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (!existingSettings.exists) {
      batch.set(settingsRef, {
        'uid': user.uid,
        'enabledBosses': {},
        'quietEnabled': false,
        'quietStartMinute': 0,
        'quietEndMinute': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<String?> roomPassword(String roomId) async {
    await connect();
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final doc = await _db
        .collection('rooms')
        .doc(roomId)
        .collection('secrets')
        .doc('password')
        .get();
    final value = doc.data()?['password'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Stream<RoomMember?> myMember(String roomId) {
    final user = _auth.currentUser;
    if (user == null) return const Stream<RoomMember?>.empty();
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(user.uid)
        .snapshots()
        .map((doc) =>
            doc.data() == null ? null : RoomMember.fromJson(doc.data()!));
  }

  Stream<List<RoomMember>> members(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RoomMember.fromJson(doc.data()))
            .toList());
  }

  Future<void> setMemberRole(String roomId, String uid, String role) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    if (!['member', 'editor'].contains(role)) {
      throw StateError('설정할 수 없는 권한입니다.');
    }
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .update({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> transferOwner(String roomId, String uid) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final room = _db.collection('rooms').doc(roomId);
    final batch = _db.batch();
    batch.update(
        room, {'ownerUid': uid, 'updatedAt': FieldValue.serverTimestamp()});
    batch.update(room.collection('members').doc(user.uid), {
      'role': 'editor',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(room.collection('members').doc(uid), {
      'role': 'owner',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
