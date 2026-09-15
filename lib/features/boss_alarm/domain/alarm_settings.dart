class AlarmSettings {
  const AlarmSettings({
    this.quietEnabled = false,
    this.quietStartMinute = 0,
    this.quietEndMinute = 0,
  });

  final bool quietEnabled;
  final int quietStartMinute;
  final int quietEndMinute;

  factory AlarmSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlarmSettings();
    return AlarmSettings(
      quietEnabled: json['quietEnabled'] as bool? ?? false,
      quietStartMinute: _minute(json['quietStartMinute']),
      quietEndMinute: _minute(json['quietEndMinute']),
    );
  }

  static int _minute(Object? value) {
    if (value is! int) return 0;
    if (value < 0) return 0;
    if (value >= 1440) return 1439;
    return value;
  }

  Map<String, dynamic> toJson() => {
        'quietEnabled': quietEnabled,
        'quietStartMinute': quietStartMinute,
        'quietEndMinute': quietEndMinute,
      };

  AlarmSettings update({
    bool? quietEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
  }) =>
      AlarmSettings(
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStartMinute: quietStartMinute ?? this.quietStartMinute,
        quietEndMinute: quietEndMinute ?? this.quietEndMinute,
      );

  bool mutedAt(DateTime utc) {
    if (!quietEnabled || quietStartMinute == quietEndMinute) return false;
    final korea = utc.toUtc().add(const Duration(hours: 9));
    final minute = korea.hour * 60 + korea.minute;
    if (quietStartMinute < quietEndMinute) {
      return minute >= quietStartMinute && minute < quietEndMinute;
    }
    return minute >= quietStartMinute || minute < quietEndMinute;
  }
}

String minuteOfDayLabel(int minuteOfDay) {
  final clamped = minuteOfDay.clamp(0, 1439);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(hour)}:${two(minute)}';
}
