import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lordnine_boss_alarm/features/boss_alarm/domain/boss.dart';

Boss field({int? anchor, int minutes = 240}) => Boss(
    id: 1,
    name: '베나투스',
    region: '',
    location: '',
    intervalMinutes: minutes,
    weekdays: const [],
    minuteOfDay: 0,
    anchorMs: anchor);

void main() {
  final anchor = DateTime.utc(2026, 9, 8, 1);
  test('시트 원본의 45종과 대표 주기를 가져온다', () {
    final root =
        jsonDecode(File('test/fixtures/boss_catalog.json').readAsStringSync()) as Map;
    final bosses = (root['bosses'] as List)
        .map((j) => Boss.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    expect(bosses.length, 45);
    expect(bosses.where((b) => b.isFixed).length, 23);
    expect(bosses.where((b) => !b.isFixed).length, 22);
    expect(bosses.every((b) => !b.enabled && b.anchorMs == null), isTrue);
    expect(bosses.singleWhere((b) => b.name == '베나투스').intervalMinutes, 240);
    expect(bosses.singleWhere((b) => b.name == '슈라이어').intervalMinutes, 1560);
    expect(bosses.singleWhere((b) => b.name == '세크레타').intervalMinutes, 2760);
    expect(bosses.singleWhere((b) => b.name == '아우라크').weekdays, [4, 5]);
  });
  test('처치 기록 없이는 필드 젠과 알림을 추정하지 않는다', () {
    expect(field().nextSpawn(anchor), isNull);
    expect(field().nextAlarm(anchor), isNull);
  });
  test('처치 시각 + 주기, 5분 전 알림', () {
    final boss = field(anchor: anchor.millisecondsSinceEpoch);
    expect(boss.nextSpawn(anchor), anchor.add(const Duration(hours: 4)));
    expect(boss.nextAlarm(anchor),
        anchor.add(const Duration(hours: 3, minutes: 55)));
  });
  test('여러 번 미체크해도 최초 기준에서 누적하며 드리프트하지 않는다', () {
    final boss = field(anchor: anchor.millisecondsSinceEpoch);
    expect(boss.nextSpawn(anchor.add(const Duration(hours: 49, minutes: 13))),
        anchor.add(const Duration(hours: 52)));
  });
  test('젠 시각과 정확히 같으면 다음 주기로 넘긴다', () {
    final boss = field(anchor: anchor.millisecondsSinceEpoch);
    expect(boss.nextSpawn(anchor.add(const Duration(hours: 4))),
        anchor.add(const Duration(hours: 8)));
  });
  test('필드 젠 직후 5분 동안 컷 미확인 상태로 남긴다', () {
    final boss = field(anchor: anchor.millisecondsSinceEpoch);
    final spawned = anchor.add(const Duration(hours: 4));
    expect(boss.unconfirmedSpawn(spawned), spawned);
    expect(boss.unconfirmedSpawn(spawned.add(const Duration(minutes: 4))),
        spawned);
    expect(boss.autoCutSpawn(spawned.add(const Duration(minutes: 4))),
        isNull);
    expect(boss.unconfirmedSpawn(spawned.add(const Duration(minutes: 5))),
        isNull);
    expect(boss.autoCutSpawn(spawned.add(const Duration(minutes: 5))),
        spawned);
  });
  test('수동 컷 시각 자체는 컷 미확인으로 보지 않는다', () {
    final checked = anchor.add(const Duration(minutes: 2));
    final boss = field(anchor: checked.millisecondsSinceEpoch);
    expect(boss.unconfirmedSpawn(checked), isNull);
    expect(boss.autoCutSpawn(checked.add(const Duration(minutes: 5))), isNull);
  });
  test('이미 지난 경고를 보내지 않고 다음 알림을 찾는다', () {
    final boss = field(anchor: anchor.millisecondsSinceEpoch);
    expect(boss.nextAlarm(anchor.add(const Duration(hours: 3, minutes: 56))),
        anchor.add(const Duration(hours: 7, minutes: 55)));
    expect(boss.nextAlarm(anchor.add(const Duration(hours: 3, minutes: 55))),
        anchor.add(const Duration(hours: 7, minutes: 55)));
  });
  test('새 처치 체크로 기준을 재설정한다', () {
    final checked = anchor.add(const Duration(hours: 5, minutes: 20));
    final boss = field(anchor: anchor.millisecondsSinceEpoch)
        .update(anchorMs: checked.millisecondsSinceEpoch);
    expect(boss.nextSpawn(checked), checked.add(const Duration(hours: 4)));
  });
  test('26시간과 46시간 주기는 자정을 넘어도 유지한다', () {
    for (final hours in [26, 46]) {
      final boss =
          field(anchor: anchor.millisecondsSinceEpoch, minutes: hours * 60);
      expect(boss.nextSpawn(anchor.add(Duration(hours: hours * 7))),
          anchor.add(Duration(hours: hours * 8)));
    }
  });
  test('한국 월·금 12:30 고정 젠과 주간 순환', () {
    const boss = Boss(
        id: 2,
        name: '클레멘티스',
        region: '',
        location: '',
        intervalMinutes: 0,
        weekdays: [1, 5],
        minuteOfDay: 750);
    expect(boss.nextSpawn(DateTime.utc(2026, 9, 7, 3, 29)),
        DateTime.utc(2026, 9, 7, 3, 30));
    expect(boss.nextSpawn(DateTime.utc(2026, 9, 7, 3, 30)),
        DateTime.utc(2026, 9, 11, 3, 30));
    expect(boss.nextSpawn(DateTime.utc(2026, 9, 11, 3, 30)),
        DateTime.utc(2026, 9, 14, 3, 30));
  });
  test('월요일 자정 고정 젠의 알림은 일요일 23:55이다', () {
    const boss = Boss(
        id: 2,
        name: '테스트',
        region: '',
        location: '',
        intervalMinutes: 0,
        weekdays: [1],
        minuteOfDay: 0);
    expect(boss.nextAlarm(DateTime.utc(2026, 9, 6, 14)),
        DateTime.utc(2026, 9, 6, 14, 55));
  });
  test('설정 저장 왕복', () {
    final boss =
        field(anchor: anchor.millisecondsSinceEpoch).update(enabled: true);
    expect(
        Boss.fromJson(
                jsonDecode(jsonEncode(boss.toJson())) as Map<String, dynamic>)
            .toJson(),
        boss.toJson());
  });
  test('잘못된 주기 및 요일 거부', () {
    expect(() => Boss.fromJson({...field().toJson(), 'intervalMinutes': 0}),
        throwsFormatException);
    expect(
        () => Boss.fromJson({
              ...field().toJson(),
              'weekdays': [8]
            }),
        throwsFormatException);
  });
}
