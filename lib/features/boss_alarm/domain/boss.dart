class Boss {
  const Boss({
    required this.id,
    required this.name,
    required this.region,
    required this.location,
    required this.intervalMinutes,
    required this.weekdays,
    required this.minuteOfDay,
    this.catalogVersion = 0,
    this.ability = '',
    this.loot = '',
    this.enabled = false,
    this.anchorMs,
  });

  final int id;
  final int catalogVersion;
  final String name, region, location, ability, loot;
  final int intervalMinutes, minuteOfDay;
  final List<int> weekdays;
  final bool enabled;
  final int? anchorMs;
  bool get isFixed => weekdays.isNotEmpty;

  factory Boss.fromJson(Map<String, dynamic> json) {
    final boss = Boss(
      id: json['id'] as int,
      catalogVersion: json['catalogVersion'] as int? ?? 0,
      name: json['name'] as String,
      region: json['region'] as String,
      location: json['location'] as String,
      intervalMinutes: json['intervalMinutes'] as int,
      weekdays: List<int>.from(json['weekdays'] as List),
      minuteOfDay: json['minuteOfDay'] as int,
      ability: json['ability'] as String? ?? '',
      loot: json['loot'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      anchorMs: json['anchorMs'] as int?,
    );
    if (boss.id <= 0 ||
        boss.name.trim().isEmpty ||
        (!boss.isFixed && boss.intervalMinutes <= 5) ||
        boss.weekdays.any((d) => d < 1 || d > 7) ||
        boss.minuteOfDay < 0 ||
        boss.minuteOfDay >= 1440) {
      throw const FormatException('보스 설정 형식이 올바르지 않습니다.');
    }
    return boss;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'catalogVersion': catalogVersion,
        'name': name,
        'region': region,
        'location': location,
        'intervalMinutes': intervalMinutes,
        'weekdays': weekdays,
        'minuteOfDay': minuteOfDay,
        'ability': ability,
        'loot': loot,
        'enabled': enabled,
        'anchorMs': anchorMs,
      };

  Boss update(
          {bool? enabled,
          int? anchorMs,
          int? intervalMinutes,
          List<int>? weekdays,
          int? minuteOfDay}) =>
      Boss.fromJson({
        ...toJson(),
        'enabled': enabled ?? this.enabled,
        'anchorMs': anchorMs ?? this.anchorMs,
        'intervalMinutes': intervalMinutes ?? this.intervalMinutes,
        'weekdays': weekdays ?? this.weekdays,
        'minuteOfDay': minuteOfDay ?? this.minuteOfDay,
      });

  /// First spawn strictly after the supplied instant. Anchors never drift.
  DateTime? nextSpawn(DateTime after) {
    if (!isFixed) {
      if (anchorMs == null) return null;
      final period = intervalMinutes * 60000;
      final elapsed = after.millisecondsSinceEpoch - anchorMs!;
      final count = elapsed < period ? 1 : elapsed ~/ period + 1;
      return DateTime.fromMillisecondsSinceEpoch(anchorMs! + count * period,
          isUtc: true);
    }
    final korea = after.toUtc().add(const Duration(hours: 9));
    final day = DateTime.utc(korea.year, korea.month, korea.day);
    for (var offset = 0; offset <= 7; offset++) {
      final local = day.add(Duration(days: offset, minutes: minuteOfDay));
      final candidate = local.subtract(const Duration(hours: 9));
      if (weekdays.contains(local.weekday) && candidate.isAfter(after)) {
        return candidate;
      }
    }
    throw StateError('고정 시간 계산 실패');
  }

  DateTime? nextAlarm(DateTime after) =>
      nextSpawn(after.add(const Duration(minutes: 5)))
          ?.subtract(const Duration(minutes: 5));

  DateTime? lastSpawnAtOrBefore(DateTime time) {
    if (isFixed || anchorMs == null) return null;
    final period = intervalMinutes * 60000;
    final elapsed = time.millisecondsSinceEpoch - anchorMs!;
    if (elapsed < period) return null;
    final count = elapsed ~/ period;
    return DateTime.fromMillisecondsSinceEpoch(anchorMs! + count * period,
        isUtc: true);
  }

  DateTime? unconfirmedSpawn(DateTime time) {
    final spawn = lastSpawnAtOrBefore(time);
    if (spawn == null) return null;
    final elapsed = time.difference(spawn);
    if (elapsed.isNegative || elapsed >= const Duration(minutes: 5)) {
      return null;
    }
    return spawn;
  }

  DateTime? autoCutSpawn(DateTime time) {
    final spawn = lastSpawnAtOrBefore(time);
    if (spawn == null) return null;
    return time.difference(spawn) >= const Duration(minutes: 5) ? spawn : null;
  }

  String get scheduleLabel {
    if (!isFixed) {
      final hours = intervalMinutes ~/ 60;
      final minutes = intervalMinutes % 60;
      return '${hours > 0 ? '$hours시간 ' : ''}${minutes > 0 ? '$minutes분 ' : ''}주기';
    }
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${weekdays.map((d) => days[d - 1]).join(', ')} ${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')} (한국 시간)';
  }
}

String koreaTime(DateTime time) {
  final k = time.toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${k.month}/${k.day} ${two(k.hour)}:${two(k.minute)}';
}
