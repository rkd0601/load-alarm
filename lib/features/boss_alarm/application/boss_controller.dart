import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/services/alarm_platform.dart';
import '../../../core/services/boss_cloud_store.dart';
import '../domain/boss.dart';

class BossController extends ChangeNotifier {
  BossController({AlarmPlatform? platform, BossCloudStore? cloud})
      : platform = platform ?? AlarmPlatform(),
        cloud = cloud ?? FirestoreBossCloudStore();
  final AlarmPlatform platform;
  final BossCloudStore cloud;
  bool _cloudPending = false;
  bool _refreshRequested = false;
  List<String> _cutTokens = [];
  String? cloudError;
  String get cloudStatus => !cloud.configured
      ? 'Firebase 연결 설정 필요 · 기기에 저장 중'
      : cloudError != null
          ? '기기에 저장됨 · 동기화 실패, 새로고침으로 재시도'
          : _cloudPending
              ? 'DB 동기화 대기 중'
              : 'Firestore 동기화 완료';
  List<Boss> bosses = [];
  bool loading = true, busy = false;
  String? error;
  Map<String, dynamic> status = {};

  Future<void> initialize() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      final stored = await platform.load();
      final Map<String, dynamic> document = jsonDecode(
              stored ?? await rootBundle.loadString('assets/bosses.json'))
          as Map<String, dynamic>;
      _cloudPending = document['cloudPending'] as bool? ?? true;
      if (document['schemaVersion'] != 1) {
        throw const FormatException('지원하지 않는 저장 형식입니다.');
      }
      bosses = (document['bosses'] as List)
          .map((b) => Boss.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList();
      if (bosses.map((b) => b.id).toSet().length != bosses.length) {
        throw const FormatException('중복된 보스 식별자입니다.');
      }
      if (stored == null) {
        try {
          await _save();
        } catch (_) {
          bosses = [];
          rethrow;
        }
      }
      await _applyPendingCuts();
      await _sync();
      await _syncCloud();
    } catch (e) {
      error = '설정을 불러오지 못했습니다. 다시 시도해 주세요. ($e)';
    } finally {
      loading = false;
      notifyListeners();
      _resumeRefresh();
    }
  }

  Map<String, dynamic> get _document => {
        'schemaVersion': 1,
        'bosses': bosses.map((b) => b.toJson()).toList(),
      };

  Future<void> _persist() => platform.save(jsonEncode({
        ..._document,
        'cloudPending': _cloudPending,
      }));

  Future<void> _save() async {
    final before = _cloudPending;
    _cloudPending = true;
    try {
      await _persist();
    } catch (_) {
      _cloudPending = before;
      rethrow;
    }
  }

  Future<void> _syncCloud() async {
    if (!cloud.configured) return;
    try {
      if (_cloudPending) {
        await cloud.save(_document).timeout(const Duration(seconds: 8));
        _cloudPending = false;
        try {
          await _persist();
        } catch (_) {
          _cloudPending = true;
          rethrow;
        }
      } else {
        final remote = await cloud.load().timeout(const Duration(seconds: 8));
        if (remote == null) {
          await _save();
          await cloud.save(_document).timeout(const Duration(seconds: 8));
          _cloudPending = false;
          try {
            await _persist();
          } catch (_) {
            _cloudPending = true;
            rethrow;
          }
        } else {
          if (remote['schemaVersion'] != 1) {
            throw const FormatException('지원하지 않는 DB 저장 형식입니다.');
          }
          final restored = (remote['bosses'] as List)
              .map((b) => Boss.fromJson(Map<String, dynamic>.from(b as Map)))
              .toList();
          if (restored.isEmpty ||
              restored.length > 100 ||
              restored.map((b) => b.id).toSet().length != restored.length) {
            throw const FormatException('DB 보스 목록이 올바르지 않습니다.');
          }
          final before = bosses;
          bosses = restored;
          try {
            await _persist();
          } catch (_) {
            bosses = before;
            rethrow;
          }
          await _sync();
        }
      }
      cloudError = null;
    } catch (e) {
      cloudError = '$e';
      debugPrint('Firestore sync failed: $e');
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
    await _changeAll(bosses
        .map((b) =>
            b.update(enabled: enabled && (b.isFixed || b.anchorMs != null)))
        .toList());
  }

  Future<void> _changeAll(List<Boss> updated) async {
    if (busy || loading || bosses.isEmpty) return;
    busy = true;
    error = null;
    notifyListeners();
    final before = bosses;
    try {
      bosses = updated;
      try {
        await _save();
      } catch (_) {
        bosses = before;
        rethrow;
      }
      await _applyPendingCuts();
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
