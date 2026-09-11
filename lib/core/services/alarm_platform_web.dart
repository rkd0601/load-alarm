import 'dart:async';
// Selected only by dart.library.html; native builds use the method channel.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Browser alarms run only while the page is alive; this is not server push.
class AlarmPlatform {
  static const storageKey = 'lordnine.bossAlarm.v1';
  Timer? _timer;
  StreamSubscription<html.Event>? _visibility;
  Future<void> Function()? _refresh;
  List<Map<String, dynamic>> _events = [];
  html.ServiceWorkerRegistration? _worker;

  bool get _supported =>
      html.window.isSecureContext == true &&
      html.Notification.supported &&
      html.window.navigator.serviceWorker != null;

  void setCutHandler(Future<void> Function()? handler) {
    _refresh = handler;
    _visibility?.cancel();
    if (handler == null) {
      _timer?.cancel();
      return;
    }
    _visibility = html.document.onVisibilityChange.listen((_) {
      if (html.document.visibilityState == 'visible') _refresh?.call();
    });
  }

  Future<List<Map<String, dynamic>>> pendingCuts() async => [];
  Future<void> acknowledgeCuts(List<String> tokens) async {}
  Future<String?> load() async => html.window.localStorage[storageKey];
  Future<void> save(String json) async {
    html.window.localStorage[storageKey] = json;
  }

  Future<void> _connectWorker() async {
    if (!_supported || _worker != null) return;
    await html.window.navigator.serviceWorker!.register('boss-alarm-sw.js');
    _worker = await html.window.navigator.serviceWorker!.ready;
  }

  Future<Map<String, dynamic>> sync(
      List<Map<String, dynamic>> events, int? horizonMs) async {
    _timer?.cancel();
    _events = events.map((e) => Map<String, dynamic>.from(e)).toList();
    final allowed = _supported && html.Notification.permission == 'granted';
    if (allowed && _events.isNotEmpty) {
      await _connectWorker();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    return {
      'platform': 'web',
      'supported': _supported,
      'allowed': allowed,
      // No separate exact-alarm permission exists on the web.
      'exact': true,
      'horizonMs': horizonMs,
    };
  }

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = _events.where((e) => (e['fireMs'] as int) <= now).toList();
    _events.removeWhere((e) => (e['fireMs'] as int) <= now);
    for (final event in due) {
      // A suspended tab must not issue stale "five minutes before" alarms.
      if (now - (event['fireMs'] as int) > 60000) continue;
      _worker?.showNotification('${event['name']} · 젠 5분 전', {
        'body': '보스 출현 시간을 확인해 주세요.',
        'tag': 'boss-${event['id']}-${event['spawnMs']}',
      }).catchError((Object error) {
        html.window.console.warn('보스 알림 표시 실패: $error');
      });
    }
    if (_events.isEmpty) {
      _timer?.cancel();
      _refresh?.call();
    }
  }

  Future<void> requestPermissions() async {
    if (!_supported) return;
    // Keep permission request directly in the user's button-click call stack.
    await html.Notification.requestPermission();
    if (html.Notification.permission == 'granted') await _connectWorker();
  }
}
