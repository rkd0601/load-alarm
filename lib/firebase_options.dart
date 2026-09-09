import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// Supply public Firebase app settings with --dart-define-from-file.
// No service account credentials belong in a mobile app.
class BossFirebaseOptions {
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static bool get configured => _projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (_apiKey.isEmpty || _appId.isEmpty || _senderId.isEmpty) {
      throw StateError('Firebase 앱 연결 설정이 누락되었습니다.');
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('Firebase 연결은 Android/iOS에서 지원합니다.');
    }
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      iosBundleId: 'com.lordnine.lordnineBossAlarm',
    );
  }
}
