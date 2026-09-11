import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lordnine_boss_alarm/app/app.dart';
import 'package:lordnine_boss_alarm/core/services/alarm_platform.dart';
import 'package:lordnine_boss_alarm/core/services/boss_cloud_store.dart';
import 'package:lordnine_boss_alarm/features/boss_alarm/application/boss_controller.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/boss_catalog.json').readAsStringSync())
        as Map<String, dynamic>;

class FakeBossCloudStore implements BossCloudStore {
  Map<String, dynamic>? document = fixture();
  bool fail = false;
  int writes = 0;
  @override
  bool get configured => true;
  @override
  Future<Map<String, dynamic>?> load() async {
    if (fail) throw StateError('offline');
    return document == null
        ? null
        : jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (fail) throw StateError('offline');
    writes++;
    for (final entry in (value['changes'] as Map).entries) {
      final row = (document!['bosses'] as List)
          .firstWhere((b) => '${b['id']}' == entry.key) as Map;
      row.addAll(entry.value as Map);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? saved;
  Map<String, dynamic>? lastSync;
  List<Map<String, dynamic>> cuts = [];
  bool failSave = false, failSync = false;
  late FakeBossCloudStore cloud;
  setUp(() {
    saved = null;
    cuts = [];
    lastSync = null;
    failSave = failSync = false;
    cloud = FakeBossCloudStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AlarmPlatform.channel, (call) async {
      switch (call.method) {
        case 'load':
          return saved;
        case 'save':
          if (failSave) throw PlatformException(code: 'disk_full');
          saved = call.arguments as String;
          return null;
        case 'pendingCuts':
          return cuts;
        case 'acknowledgeCuts':
          cuts.removeWhere(
              (c) => (call.arguments as List).contains(c['token']));
          return null;
        case 'sync':
          if (failSync) throw PlatformException(code: 'schedule_failed');
          lastSync = Map<String, dynamic>.from(call.arguments as Map);
          return {'platform': 'android', 'allowed': true, 'exact': true};
        case 'requestPermissions':
          return null;
      }
      throw PlatformException(code: 'unknown');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AlarmPlatform.channel, null));

  test('첫 실행은 공통 DB를 읽고 서버에 기본값을 쓰지 않는다', () async {
    final at = DateTime.now().millisecondsSinceEpoch - 60000;
    cloud.document!['bosses'][0]['anchorMs'] = at;
    final c = BossController(cloud: cloud);
    await c.initialize();
    expect(c.bosses, hasLength(45));
    expect(c.bosses.first.anchorMs, at);
    expect(c.bosses.every((b) => !b.enabled), isTrue);
    expect(cloud.writes, 0);
    expect((jsonDecode(saved!) as Map)['sharedVersion'], 1);
  });

  test('이전 사용자별 시간표는 공유 DB를 덮어쓰지 않고 알림 선택만 보존한다', () async {
    final old = fixture();
    old['cloudPending'] = true;
    old['bosses'][0]['anchorMs'] = 123;
    old['bosses'][0]['enabled'] = true;
    saved = jsonEncode(old);
    final c = BossController(cloud: cloud);
    await c.initialize();
    expect(c.bosses.first.anchorMs, isNull);
    expect(c.bosses.first.enabled, isTrue);
    expect(cloud.writes, 0);
  });

  test('두 사용자가 공통 처치 시각을 공유하고 알림 선택은 공유하지 않는다', () async {
    final a = BossController(cloud: cloud);
    await a.initialize();
    saved = null;
    final b = BossController(cloud: cloud);
    await b.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    await a.change(a.bosses.first.update(anchorMs: at, enabled: true));
    await b.refresh();
    expect(b.bosses.first.anchorMs, at);
    expect(b.bosses.first.enabled, isFalse);
    expect(cloud.document!['bosses'][0]['enabled'], isFalse);
  });

  test('오래된 화면에서 다른 보스를 수정해도 먼저 저장한 보스 시간을 보존한다', () async {
    final a = BossController(cloud: cloud), b = BossController(cloud: cloud);
    await a.initialize();
    await b.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    await a.change(a.bosses[0].update(anchorMs: at));
    await b.change(b.bosses[2].update(anchorMs: at - 1000));
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
    expect(cloud.document!['bosses'][2]['anchorMs'], at - 1000);
  });

  test('같은 보스의 다른 시간 필드 변경도 병합한다', () async {
    final a = BossController(cloud: cloud), b = BossController(cloud: cloud);
    await a.initialize();
    await b.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    await a.change(a.bosses.first.update(anchorMs: at));
    await b.change(b.bosses.first.update(intervalMinutes: 300));
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
    expect(cloud.document!['bosses'][0]['intervalMinutes'], 300);
  });

  test('전체 알림 설정과 해제는 처치 시간 및 DB를 변경하지 않는다', () async {
    final at = DateTime.now().millisecondsSinceEpoch - 60000;
    cloud.document!['bosses'][0]['anchorMs'] = at;
    final c = BossController(cloud: cloud);
    await c.initialize();
    final before = jsonEncode(cloud.document), writes = cloud.writes;
    await c.setAllEnabled(true);
    expect(c.bosses.every((b) => b.enabled), isTrue);
    expect(c.bosses.first.anchorMs, at);
    expect(
        c.bosses
            .where((b) => !b.isFixed)
            .skip(1)
            .every((b) => b.anchorMs == null),
        isTrue);
    expect(jsonEncode(cloud.document), before);
    expect(cloud.writes, writes);
    expect((lastSync!['events'] as List).any((e) => e['id'] == 3), isFalse);
    await c.setAllEnabled(false);
    expect(jsonEncode(cloud.document), before);
    expect(cloud.writes, writes);
    expect(lastSync!['events'], isEmpty);
  });

  test('전체 리셋을 공유하되 고정 일정과 기기 알림 선택을 보존한다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    final fixed =
        c.bosses.where((b) => b.isFixed).map((b) => b.toJson()).toList();
    final at = DateTime.now().subtract(const Duration(hours: 1));
    await c.resetAllTimes(at);
    expect(
        c.bosses
            .where((b) => !b.isFixed)
            .every((b) => b.anchorMs == at.millisecondsSinceEpoch),
        isTrue);
    expect(c.bosses.where((b) => b.isFixed).map((b) => b.toJson()).toList(),
        fixed);
    expect(c.bosses.every((b) => !b.enabled), isTrue);
    final before = saved;
    await c.resetAllTimes(DateTime.now().add(const Duration(days: 1)));
    expect(saved, before);
    expect(c.error, contains('미래'));
  });

  test('DB 장애 동안 변경을 보관하고 재시작하면 변경한 필드만 전송한다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    cloud.fail = true;
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    await c.change(c.bosses.first.update(anchorMs: at));
    expect(c.cloudError, isNotNull);
    expect((jsonDecode(saved!) as Map)['pendingChanges'], isNotEmpty);
    cloud.document!['bosses'][2]['anchorMs'] = at - 1000;
    cloud.fail = false;
    final restored = BossController(cloud: cloud);
    await restored.initialize();
    expect(restored.bosses.first.anchorMs, at);
    expect(restored.bosses[2].anchorMs, at - 1000);
    expect((jsonDecode(saved!) as Map)['pendingChanges'], isEmpty);
  });

  test('로컬 저장 실패는 DB를 바꾸지 않고 이전 상태를 보존한다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    final before = saved;
    failSave = true;
    await c.change(c.bosses.first.update(anchorMs: 123456789));
    expect(saved, before);
    expect(c.bosses.first.anchorMs, isNull);
    expect(cloud.writes, 0);
    expect(c.error, isNotNull);
  });

  test('첫 실행 DB 장애는 임의 시간표를 생성하지 않고 재시도한다', () async {
    cloud.fail = true;
    final c = BossController(cloud: cloud);
    await c.initialize();
    expect(c.error, isNotNull);
    expect(saved, isNull);
    expect(c.bosses, isEmpty);
    cloud.fail = false;
    await c.initialize();
    expect(c.bosses, hasLength(45));
    expect(c.error, isNull);
  });

  test('DB가 없거나 손상되어도 캐시를 덮어쓰지 않는다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    final before = saved;
    cloud.document = {'schemaVersion': 1, 'bosses': []};
    await c.refresh();
    expect(c.cloudError, isNotNull);
    expect(saved, before);
    cloud.document = null;
    await c.refresh();
    expect(c.cloudError, isNotNull);
    expect(saved, before);
  });

  test('알림 처치 체크는 공통 DB와 다음 예약에 반영한다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    await c.change(c.bosses.first.update(enabled: true));
    cuts.add({'id': 1, 'atMs': at, 'token': 'cut-1'});
    await c.refresh();
    expect(cuts, isEmpty);
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
    expect(lastSync!['events'][0]['fireMs'], at + 235 * 60000);
  });

  test('컷 미확인 5분 경과 후 출몰 시각을 자동 컷으로 공유한다', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final anchor = now - 246 * 60000;
    final spawn = anchor + 240 * 60000;
    cloud.document!['bosses'][0]['anchorMs'] = anchor;
    final c = BossController(cloud: cloud);
    await c.initialize();
    expect(c.bosses.first.anchorMs, spawn);
    expect(cloud.document!['bosses'][0]['anchorMs'], spawn);
  });

  test('알림 예약 실패 후에도 처치 변경은 보존되어 재전송된다', () async {
    final c = BossController(cloud: cloud);
    await c.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    failSync = true;
    await c.change(c.bosses.first.update(anchorMs: at, enabled: true));
    expect(c.bosses.first.anchorMs, at);
    expect(c.error, isNotNull);
    failSync = false;
    await c.refresh();
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
    expect(lastSync!['events'], isNotEmpty);
  });

  test('손상된 로컬 기록을 DB 기본값으로 덮어쓰지 않는다', () async {
    saved = '{invalid';
    final c = BossController(cloud: cloud);
    await c.initialize();
    expect(c.error, isNotNull);
    expect(saved, '{invalid');
  });

  testWidgets('검색 중 전체 알림 설정은 입력 창 없이 전체 보스에 적용한다', (tester) async {
    await tester.pumpWidget(
        LordnineBossAlarmApp(controller: BossController(cloud: cloud)));
    await tester.pumpAndSettle();
    expect(find.text('전체 45'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 설정'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(cloud.writes, 0);
    expect(
        ((jsonDecode(saved!) as Map)['bosses'] as List)
            .where((b) => (b['weekdays'] as List).isEmpty)
            .every((b) => b['anchorMs'] == null),
        isTrue);
    expect(
        ((jsonDecode(saved!) as Map)['bosses'] as List)
            .every((b) => b['enabled'] == true),
        isTrue);
    await tester.tap(find.text('전체 해제'));
    await tester.pumpAndSettle();
    expect(lastSync!['events'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('처치 시간 입력 검증과 취소는 DB를 변경하지 않는다', (tester) async {
    await tester.pumpWidget(
        LordnineBossAlarmApp(controller: BossController(cloud: cloud)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.text('처치 시간 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('kill-date')), '2026-02-30');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('존재하는 날짜와 올바른 시각을 입력해 주세요.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(cloud.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('배포 JSON에는 시간 데이터가 없다', () {
    final metadata =
        jsonDecode(File('assets/bosses.json').readAsStringSync()) as Map;
    for (final boss in metadata['bosses'] as List) {
      expect((boss as Map).keys, isNot(contains('anchorMs')));
      for (final key in BossController.timeFields) {
        expect(boss.containsKey(key), isFalse);
      }
    }
  });
}
