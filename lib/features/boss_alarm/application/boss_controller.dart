import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/services/alarm_platform.dart';
import '../../../core/services/boss_cloud_store.dart';
import '../domain/boss.dart';

class BossController extends ChangeNotifier {
  BossController({AlarmPlatform? platform, BossCloudStore? cloud})
      : platform = platform ?? AlarmPlatform(),
        cloud = cloud ?? FirestoreBossCloudStore();
  final AlarmPlatform platform;
  final BossCloudStore cloud;
  bool _refreshRequested = false;
  List<String> _cutTokens = [];
  Map<String, Map<String, dynamic>> _pending = {};
  List<Boss> _persisted = [];
  static const timeFields = [
    'intervalMinutes',
    'weekdays',
    'minuteOfDay',
    'anchorMs'
  ];
  String? cloudError;
  String get cloudStatus => !cloud.configured
      ? 'Firebase 연결 설정 필요'
      : cloudError != null
          ? '공통 DB 연결 실패 · 캐시 사용 중, 새로고침으로 재시도'
          : _pending.isNotEmpty
              ? '공통 DB 변경 전송 대기 중'
              : '공통 DB 동기화 완료';
  List<Boss> bosses = [];
  bool loading = true, busy = false;
  String? error;
  Map<String, dynamic> status = {};

  List<Boss> _readBosses(Map<String, dynamic> document) {
    if (document['schemaVersion'] != 1) {
      throw const FormatException('지원하지 않는 저장 형식입니다.');
    }
    final result = (document['bosses'] as List)
        .map((b) => Boss.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();
    if (result.isEmpty ||
        result.length > 100 ||
        result.map((b) => b.id).toSet().length != result.length) {
      throw const FormatException('DB 보스 목록이 올바르지 않습니다.');
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  Future<void> initialize() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      final stored = await platform.load();
      if (stored != null) {
        final document = jsonDecode(stored) as Map<String, dynamic>;
        bosses = _readBosses(document);
        _persisted = bosses;
        // Never publish old per-user schedules into the shared database.
        if (document['sharedVersion'] == 1) {
          _pending = (document['pendingChanges'] as Map? ?? {}).map((k, v) =>
              MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
        }
      }
      await _syncCloud();
      if (bosses.isEmpty) {
        throw StateError(cloudError ?? '최초 실행에는 공통 DB 연결이 필요합니다.');
      }
      await _applyPendingCuts();
      await _sync();
      if (_pending.isNotEmpty) await _syncCloud();
    } catch (e) {
      error = '설정을 불러오지 못했습니다. 다시 시도해 주세요. ($e)';
    } finally {
      loading = false;
      notifyListeners();
      _resumeRefresh();
    }
  }

  Future<void> _persist() async {
    await platform.save(jsonEncode({
      'schemaVersion': 1,
      'sharedVersion': 1,
      'bosses': bosses.map((b) => b.toJson()).toList(),
      'pendingChanges': _pending,
    }));
    _persisted = bosses;
  }

  Future<void> _save() async {
    final before = _pending;
    _pending = {
      for (final e in before.entries) e.key: {...e.value}
    };
    for (final boss in bosses) {
      final previous = _persisted.where((b) => b.id == boss.id);
      if (previous.isEmpty) continue;
      final old = previous.first.toJson(), updated = boss.toJson();
      for (final field in timeFields) {
        if (!mapEquals(
            {'v': jsonEncode(old[field])}, {'v': jsonEncode(updated[field])})) {
          (_pending['${boss.id}'] ??= {})[field] = updated[field];
        }
      }
    }
    try {
      await _persist();
    } catch (_) {
      _pending = before;
      rethrow;
    }
  }

  Future<void> _syncCloud() async {
    if (!cloud.configured) return;
    try {
      if (_pending.isNotEmpty) {
        await cloud
            .save({'changes': _pending}).timeout(const Duration(seconds: 8));
        final sent = _pending;
        _pending = {};
        try {
          await _persist();
        } catch (_) {
          _pending = sent;
          rethrow;
        }
      }
      final remote = await cloud.load().timeout(const Duration(seconds: 8));
      if (remote == null) throw StateError('공통 보스 시간표가 DB에 없습니다.');
      final restored = _readBosses(remote);
      final enabled = {for (final b in bosses) b.id: b.enabled};
      final before = bosses;
      bosses = restored
          .map((b) => b.update(enabled: enabled[b.id] ?? false))
          .toList();
      try {
        await _persist();
      } catch (_) {
        bosses = before;
        rethrow;
      }
      await _sync();
      cloudError = null;
    } catch (e) {
      cloudError = '$e';
      debugPrint('Shared Firestore sync failed: $e');
    }
  }

  void _resumeRefresh() {
    if (!_refreshRequested) return;
    _refreshRequested = false;
    Future.microtask(refresh);
  }

  Future<void> _applyPendingCuts() async {
    final cuts = await platform.pendingCuts();
    if (cuts.isEmpty) return;
    final before = bosses;
    final tokens = <String>[];
    var changed = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final cut in cuts) {
      final token = cut['token'];
      if (token is! String) continue;
      tokens.add(token);
      final id = cut['id'], at = cut['atMs'];
      if (id is! int || at is! int || at <= 0 || at > now) continue;
      bosses = bosses.map((boss) {
        if (boss.id != id ||
            boss.isFixed ||
            (boss.anchorMs != null && boss.anchorMs! >= at)) return boss;
        changed = true;
        return boss.update(anchorMs: at);
      }).toList();
    }
    if (changed) {
      try {
        await _save();
      } catch (_) {
        bosses = before;
        rethrow;
      }
    }
    // Remove native events only after both persistence and alarm scheduling succeed.
    _cutTokens = tokens;
  }

  Future<void> _sync() async {
    final now = DateTime.now().toUtc();
    final events = <Map<String, dynamic>>[];
    for (final boss in bosses.where((b) => b.enabled)) {
      var cursor = now;
      for (var i = 0; i < 65; i++) {
        final alarm = boss.nextAlarm(cursor);
        if (alarm == null) break;
        events.add({
          'id': boss.id,
          'name': boss.name,
          'canCut': !boss.isFixed,
          'fireMs': alarm.millisecondsSinceEpoch,
          'spawnMs':
              alarm.add(const Duration(minutes: 5)).millisecondsSinceEpoch
        });
        cursor = alarm;
      }
    }
    events.sort((a, b) {
      final order = (a['fireMs'] as int).compareTo(b['fireMs'] as int);
      return order != 0 ? order : (a['id'] as int).compareTo(b['id'] as int);
    });
    // 65th event marks the first uncovered instant, including simultaneous events.
    status = await platform.sync(events.take(64).toList(),
        events.length > 64 ? events[64]['fireMs'] as int : null);
    if (_cutTokens.isNotEmpty) {
      await platform.acknowledgeCuts(_cutTokens);
      _cutTokens = [];
    }
  }

  Future<void> refresh() async {
    if (busy || loading) {
      _refreshRequested = true;
      return;
    }
    if (bosses.isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      await _applyPendingCuts();
      await _sync();
      await _syncCloud();
      error = null;
    } catch (e) {
      error = '알림 예약에 실패했습니다. 다시 시도해 주세요. ($e)';
    } finally {
      busy = false;
      notifyListeners();
      _resumeRefresh();
    }
  }

  Future<void> change(Boss updated) async {
    await _changeAll(
        bosses.map((b) => b.id == updated.id ? updated : b).toList());
  }

  Future<void> setAllEnabled(bool enabled) async {
    await _changeAll(bosses.map((b) => b.update(enabled: enabled)).toList());
  }

  Future<void> resetAllTimes(DateTime reference) async {
    if (reference.isAfter(DateTime.now())) {
      error = '리셋 기준 시간은 현재보다 미래일 수 없습니다.';
      notifyListeners();
      return;
    }
    await _changeAll(
        bosses
            .map((b) => b.isFixed
                ? b
                : b.update(anchorMs: reference.millisecondsSinceEpoch))
            .toList(),
        applyPendingCutsFirst: true);
  }

  Future<void> _changeAll(List<Boss> updated,
      {bool applyPendingCutsFirst = false}) async {
    if (busy || loading || bosses.isEmpty) return;
    busy = true;
    error = null;
    notifyListeners();
    var before = bosses;
    try {
      if (applyPendingCutsFirst) {
        await _applyPendingCuts();
        // Finish earlier notification cuts before replacing their time basis.
        // Otherwise a failed reset sync could replay those cuts on restart.
        if (_cutTokens.isNotEmpty) await _sync();
        before = bosses;
      }
      bosses = updated;
      try {
        await _save();
      } catch (_) {
        bosses = before;
        rethrow;
      }
      if (!applyPendingCutsFirst) await _applyPendingCuts();
      await _sync();
      await _syncCloud();
    } catch (e) {
      error = '설정 저장 또는 알림 예약에 실패했습니다. 다시 시도해 주세요. ($e)';
    } finally {
      busy = false;
      notifyListeners();
      _resumeRefresh();
    }
  }

  Future<void> permissions() async {
    try {
      await platform.requestPermissions();
      await refresh();
    } catch (e) {
      error = '알림 권한을 확인하지 못했습니다. ($e)';
      notifyListeners();
    }
  }
}
