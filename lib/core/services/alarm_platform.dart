import 'package:flutter/services.dart';

class AlarmPlatform {
  static const channel = MethodChannel('lordnine/boss_alarm');

  Future<String?> load() => channel.invokeMethod<String>('load');
  Future<void> save(String json) => channel.invokeMethod<void>('save', json);
  Future<Map<String, dynamic>> sync(
      List<Map<String, dynamic>> events, int? horizonMs) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
        'sync', {'events': events, 'horizonMs': horizonMs});
    return result ?? {};
  }

  Future<void> requestPermissions() =>
      channel.invokeMethod<void>('requestPermissions');
}
