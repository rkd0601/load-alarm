import 'package:flutter/services.dart';

class AlarmPlatform {
  static const channel = MethodChannel('lordnine/boss_alarm');

  void setCutHandler(Future<void> Function()? handler) {
    channel.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method == 'cutPending') await handler();
          });
  }

  Future<List<Map<String, dynamic>>> pendingCuts() async {
    final result = await channel.invokeListMethod<dynamic>('pendingCuts');
    return (result ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> acknowledgeCuts(List<String> tokens) =>
      channel.invokeMethod<void>('acknowledgeCuts', tokens);

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
