import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lordnine_boss_alarm/app/app.dart';
import 'package:lordnine_boss_alarm/core/services/alarm_platform.dart';
import 'package:lordnine_boss_alarm/core/services/boss_cloud_store.dart';
import 'package:lordnine_boss_alarm/features/boss_alarm/application/boss_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? saved;
  Map<String, dynamic>? lastSync;
  List<Map<String, dynamic>> cuts = [];
  bool failSave = false;
  bool failSync = false;
  setUp(() {
    saved = File('assets/bosses.json').readAsStringSync();
    lastSync = null;
    cuts = [];
    failSave = false;
    failSync = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AlarmPlatform.channel, (call) async {
      switch (call.method) {
        case 'pendingCuts':
          return cuts;
        case 'acknowledgeCuts':
          final tokens = List<String>.from(call.arguments as List);
          cuts.removeWhere((cut) => tokens.contains(cut['token']));
          return null;
        case 'load':
          return saved;
        case 'save':
          if (failSave) throw PlatformException(code: 'disk_full');
          saved = call.arguments as String;
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
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AlarmPlatform.channel, null);
  });

  testWidgets('기본 목록 표시, 검색과 처치 체크를 저장한다', (tester) async {
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    expect(find.text('로드나인 보스 알림'), findsOneWidget);
    expect(find.text('전체 45'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    expect(find.text('베나투스'), findsNWidgets(2));
    expect(find.text('처치 시간을 설정해 주세요'), findsOneWidget);
    await tester.tap(find.text('지금 처치 체크'));
    await tester.pumpAndSettle();
    final bosses = (jsonDecode(saved!) as Map)['bosses'] as List;
    expect((bosses.first as Map)['anchorMs'], isNotNull);
    expect(find.text('처치 시간을 설정해 주세요'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((lastSync!['events'] as List).length, 64);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('직접 입력한 한국 처치 시각을 저장하고 알림을 재예약한다', (tester) async {
    final root = jsonDecode(saved!) as Map<String, dynamic>;
    (root['bosses'] as List).first['enabled'] = true;
    saved = jsonEncode(root);
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.text('처치 시간 입력'));
    await tester.pumpAndSettle();
    final entered =
        DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final korea = entered.add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    await tester.enterText(find.byKey(const ValueKey('kill-date')),
        '${korea.year}-${two(korea.month)}-${two(korea.day)}');
    await tester.enterText(find.byKey(const ValueKey('kill-time')),
        '${two(korea.hour)}:${two(korea.minute)}:25');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    final expected = DateTime.utc(
            korea.year, korea.month, korea.day, korea.hour, korea.minute, 25)
        .subtract(const Duration(hours: 9));
    final boss = ((jsonDecode(saved!) as Map)['bosses'] as List).first as Map;
    expect(boss['anchorMs'], expected.millisecondsSinceEpoch);
    expect(boss['enabled'], isTrue);
    final event = (lastSync!['events'] as List).first as Map;
    expect(
        event['fireMs'],
        expected
            .add(const Duration(hours: 3, minutes: 55))
            .millisecondsSinceEpoch);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('잘못된 날짜와 미래 처치 시각을 거부하고 취소는 설정을 유지한다', (tester) async {
    final before = saved;
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.text('처치 시간 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('kill-date')), '2026-02-30');
    await tester.enterText(find.byKey(const ValueKey('kill-time')), '12:30');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('존재하는 날짜와 올바른 시각을 입력해 주세요.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('kill-date')), '9999-01-01');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('처치 시간은 현재보다 미래일 수 없습니다.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(saved, before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('첫 실행에서 실제 에셋의 기본 설정을 저장한다', (tester) async {
    saved = null;
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect((jsonDecode(saved!) as Map)['bosses'], hasLength(45));
    expect(find.text('전체 45'), findsOneWidget);
    expect(lastSync!['events'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('미설정 보스 알림을 켜면 시간 설정에서 활성화 상태로 저장한다', (tester) async {
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('베나투스 시간 설정'), findsOneWidget);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final first = ((jsonDecode(saved!) as Map)['bosses'] as List).first as Map;
    expect(first['enabled'], isTrue);
    expect(first['anchorMs'], isNotNull);
    expect(lastSync!['events'], isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('재시작 복구, 재체크 예약 교체, 비활성화 취소', () async {
    final controller = BossController();
    await controller.initialize();
    final boss = controller.bosses.first;
    final anchor = DateTime.now().millisecondsSinceEpoch;
    await controller.change(boss.update(enabled: true, anchorMs: anchor));
    final first =
        Map<String, dynamic>.from((lastSync!['events'] as List).first as Map);
    expect(first['spawnMs'], anchor + 240 * 60000);
    expect(first['fireMs'], anchor + 235 * 60000);
    expect((lastSync!['events'] as List).length, 64);
    expect(lastSync!['horizonMs'], anchor + (240 * 65 - 5) * 60000);
    final restored = BossController();
    await restored.initialize();
    expect(restored.bosses.first.anchorMs, anchor);
    await restored
        .change(restored.bosses.first.update(anchorMs: anchor - 60000));
    expect(((lastSync!['events'] as List).first as Map)['fireMs'],
        (first['fireMs'] as int) - 60000);
    await restored.change(restored.bosses.first.update(enabled: false));
    expect(lastSync!['events'], isEmpty);
    expect(lastSync!['horizonMs'], isNull);
  });

  test('저장 실패는 화면 상태를 되돌리고 재시도 가능하다', () async {
    final controller = BossController();
    await controller.initialize();
    failSave = true;
    await controller.change(controller.bosses.first.update(enabled: true));
    expect(controller.bosses.first.enabled, isFalse);
    expect(controller.error, isNotNull);
    expect(controller.busy, isFalse);
  });

  test('예약 실패도 저장된 처치 기준은 보존한다', () async {
    final controller = BossController();
    await controller.initialize();
    failSync = true;
    final anchor = DateTime.now().millisecondsSinceEpoch;
    await controller.change(
        controller.bosses.first.update(enabled: true, anchorMs: anchor));
    expect(controller.bosses.first.anchorMs, anchor);
    expect(controller.error, isNotNull);
    failSync = false;
    await controller.refresh();
    expect(controller.error, isNull);
    expect(lastSync!['events'], isNotEmpty);
  });

  testWidgets('전체 버튼은 검색과 관계없이 적용하고 예약을 취소한다', (tester) async {
    await tester.pumpWidget(const LordnineBossAlarmApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '베나투스');
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 설정'));
    await tester.pumpAndSettle();
    final bosses = (jsonDecode(saved!) as Map)['bosses'] as List;
    expect(bosses.where((b) => b['enabled'] == true), hasLength(23));
    expect(bosses.first['anchorMs'], isNull);
    expect(lastSync!['events'], isNotEmpty);
    await tester.tap(find.text('전체 해제'));
    await tester.pumpAndSettle();
    expect(
        ((jsonDecode(saved!) as Map)['bosses'] as List)
            .every((b) => b['enabled'] == false),
        isTrue);
    expect(lastSync!['events'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('전체 설정 저장 실패를 복구하고 처치 기준을 보존한다', () async {
    final controller = BossController();
    await controller.initialize();
    final anchor = DateTime.now().millisecondsSinceEpoch;
    await controller.change(controller.bosses.first.update(anchorMs: anchor));
    final before = saved;
    failSave = true;
    await controller.setAllEnabled(true);
    expect(saved, before);
    expect(controller.bosses.every((b) => !b.enabled), isTrue);
    expect(controller.error, isNotNull);
    failSave = false;
    await controller.setAllEnabled(true);
    expect(controller.bosses.where((b) => b.enabled), hasLength(24));
    await controller.setAllEnabled(false);
    expect(controller.bosses.first.anchorMs, anchor);
    final restored = BossController();
    await restored.initialize();
    expect(restored.bosses.first.anchorMs, anchor);
    expect(restored.bosses.every((b) => !b.enabled), isTrue);
    expect(lastSync!['events'], isEmpty);
  });

  test('기존 시간표를 DB로 이전하고 전체 설정을 한 번에 저장한다', () async {
    final cloud = FakeBossCloudStore();
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    expect(cloud.document!['bosses'], hasLength(45));
    expect((jsonDecode(saved!) as Map)['cloudPending'], isFalse);
    expect(cloud.writes, 1);
    await controller.setAllEnabled(true);
    expect(cloud.writes, 2);
    expect(
        (cloud.document!['bosses'] as List).where((b) => b['enabled'] == true),
        hasLength(23));
    expect(controller.cloudError, isNull);
  });

  test('DB 실패에도 로컬 저장과 알림을 유지하고 재시작 후 재전송한다', () async {
    final cloud = FakeBossCloudStore()..fail = true;
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    await controller.setAllEnabled(true);
    expect(controller.error, isNull);
    expect(controller.cloudError, isNotNull);
    expect(lastSync!['events'], isNotEmpty);
    expect((jsonDecode(saved!) as Map)['cloudPending'], isTrue);
    cloud.fail = false;
    final restored = BossController(cloud: cloud);
    await restored.initialize();
    expect((jsonDecode(saved!) as Map)['cloudPending'], isFalse);
    expect(
        (cloud.document!['bosses'] as List).where((b) => b['enabled'] == true),
        hasLength(23));
  });

  test('DB 변경을 불러와 알림을 갱신하고 손상된 DB는 거부한다', () async {
    final cloud = FakeBossCloudStore();
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    final anchor = DateTime.now().millisecondsSinceEpoch;
    final remote = (cloud.document!['bosses'] as List).first as Map;
    remote['anchorMs'] = anchor;
    remote['enabled'] = true;
    await controller.refresh();
    expect(controller.bosses.first.anchorMs, anchor);
    expect(lastSync!['events'], isNotEmpty);
    final before = saved;
    cloud.document = {'schemaVersion': 1, 'bosses': []};
    await controller.refresh();
    expect(controller.cloudError, isNotNull);
    expect(saved, before);
    expect(controller.bosses.first.anchorMs, anchor);
  });

  test('로컬 저장 실패 시 DB를 변경하지 않는다', () async {
    final cloud = FakeBossCloudStore();
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    failSave = true;
    await controller.setAllEnabled(true);
    expect(cloud.writes, 1);
    expect(controller.bosses.every((b) => !b.enabled), isTrue);
  });

  test('알림 컷으로 앱을 시작하면 누른 시각으로 저장하고 DB와 알림을 갱신한다', () async {
    final root = jsonDecode(saved!) as Map<String, dynamic>;
    root['bosses'][0]['enabled'] = true;
    saved = jsonEncode(root);
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    cuts.add({'id': 1, 'token': 'notification-1', 'atMs': at});
    final cloud = FakeBossCloudStore();
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    expect(controller.bosses.first.anchorMs, at);
    expect(controller.bosses.first.enabled, isTrue);
    expect(cuts, isEmpty);
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
    expect(lastSync!['events'][0]['fireMs'], at + 235 * 60000);
    expect(lastSync!['events'][0]['canCut'], isTrue);
  });

  test('복귀 시 여러 컷을 반영하고 고정 보스와 오래된 컷은 무시한다', () async {
    final controller = BossController();
    await controller.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    final fixed = controller.bosses.firstWhere((b) => b.isFixed);
    final second = controller.bosses.where((b) => !b.isFixed).skip(1).first;
    await controller.change(controller.bosses.first.update(anchorMs: at));
    cuts.addAll([
      {'id': 1, 'token': 'old', 'atMs': at - 60000},
      {'id': second.id, 'token': 'new', 'atMs': at},
      {'id': fixed.id, 'token': 'fixed', 'atMs': at},
      {'id': -1, 'token': 'missing', 'atMs': at},
      {'id': 1, 'token': 'future', 'atMs': at + 60000},
    ]);
    await controller.refresh();
    expect(controller.bosses.first.anchorMs, at);
    expect(controller.bosses.firstWhere((b) => b.id == second.id).anchorMs, at);
    expect(controller.bosses.firstWhere((b) => b.id == second.id).enabled,
        isFalse);
    expect(controller.bosses.firstWhere((b) => b.id == fixed.id).anchorMs,
        fixed.anchorMs);
    expect(cuts, isEmpty);
    await controller.setAllEnabled(true);
    final fixedEvents = (lastSync!['events'] as List).where(
        (e) => controller.bosses.firstWhere((b) => b.id == e['id']).isFixed);
    expect(fixedEvents, isNotEmpty);
    expect(fixedEvents.every((e) => e['canCut'] == false), isTrue);
  });

  test('컷 저장 실패 시 이벤트를 유지하고 재시도한다', () async {
    final controller = BossController();
    await controller.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    cuts.add({'id': 1, 'token': 'retry', 'atMs': at});
    failSave = true;
    await controller.refresh();
    expect(controller.bosses.first.anchorMs, isNull);
    expect(cuts, hasLength(1));
    expect(controller.error, isNotNull);
    failSave = false;
    await controller.refresh();
    expect(controller.bosses.first.anchorMs, at);
    expect(cuts, isEmpty);
  });

  test('컷 예약 실패 후 재처리해도 처치 시각이 밀리지 않는다', () async {
    final controller = BossController();
    await controller.initialize();
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    cuts.add({'id': 1, 'token': 'retry-alarm', 'atMs': at});
    failSync = true;
    await controller.refresh();
    expect(controller.bosses.first.anchorMs, at);
    expect(cuts, hasLength(1));
    failSync = false;
    final restored = BossController();
    await restored.initialize();
    expect(restored.bosses.first.anchorMs, at);
    expect(cuts, isEmpty);
  });

  test('컷 DB 전송 실패에도 로컬 처치 기준은 남고 재전송된다', () async {
    final cloud = FakeBossCloudStore();
    final controller = BossController(cloud: cloud);
    await controller.initialize();
    cloud.fail = true;
    final at = DateTime.now().millisecondsSinceEpoch - 1000;
    cuts.add({'id': 1, 'token': 'offline-cut', 'atMs': at});
    await controller.refresh();
    expect(cuts, isEmpty);
    expect(controller.bosses.first.anchorMs, at);
    expect(controller.cloudError, isNotNull);
    cloud.fail = false;
    await controller.refresh();
    expect(cloud.document!['bosses'][0]['anchorMs'], at);
  });

  test('손상된 저장 데이터를 기본값으로 덮어쓰지 않는다', () async {
    saved = '{invalid';
    final controller = BossController();
    await controller.initialize();
    expect(controller.error, isNotNull);
    expect(saved, '{invalid');
  });
}

class FakeBossCloudStore implements BossCloudStore {
  Map<String, dynamic>? document;
  bool fail = false;
  int writes = 0;
  @override
  bool get configured => true;
  @override
  Future<Map<String, dynamic>?> load() async {
    if (fail) throw StateError('offline');
    return document;
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (fail) throw StateError('offline');
    writes++;
    document = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}
