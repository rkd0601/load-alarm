# 로드나인 보스 알림

Flutter Android/iOS 앱. 보스별 처치 시각, 젠 주기 또는 고정 요일을 저장하고 젠 5분 전에 **기기 로컬 알림**을 예약합니다. Firebase 설정 시 Firestore에 사용자별 시간표를 동기화합니다. FCM/APNs 원격 푸시와 여러 기기에서 사용할 계정 로그인은 포함하지 않습니다.

## 기본 데이터

[사용자 제공 스프레드시트](https://docs.google.com/spreadsheets/d/1b8pYSKejoEAAlao9H0KyKWhfpHKaFdg-XEiCXEXf7Jo)의 두 번째 시트 `보스탐체크`와 세 번째 시트 `보스List`를 2026-09-08에 내려받아 교차 검증했습니다.

- 필드 22종, 고정 23종. 이름·지역·상세 위치·젠 규칙은 3번 시트, 어빌/드롭 정보는 2번 시트를 사용합니다.
- Excel의 숫자 시간은 일 단위이므로 1440을 곱해 분으로 변환합니다. 베나투스/비오렌트 4시간, 슈라이어/라르바/카테나 26시간, 세크레타/오르도/아스타/수포르 46시간 등이 포함됩니다.
- 두 시트의 45종 젠 규칙이 모두 일치합니다. 기존 시트의 과거 처치 시각은 복사하지 않습니다.
- `assets/bosses.json`에 기본 데이터를 보관합니다. 첫 실행은 알림 OFF이며 필드 보스는 처치 시간 미설정 상태입니다.
- 원본 시트의 장소 표기는 그대로 유지합니다. 기본 데이터 변경은 기존 사용자의 수정된 설정에 자동 덮어쓰지 않습니다.

재생성:

```powershell
Invoke-WebRequest -Uri 'https://docs.google.com/spreadsheets/d/1b8pYSKejoEAAlao9H0KyKWhfpHKaFdg-XEiCXEXf7Jo/export?format=xlsx' -OutFile boss-source.xlsx
python tools/import_bosses.py boss-source.xlsx
```

가져오기 스크립트는 Python 표준 라이브러리만 사용합니다. 두 시트의 주기가 다르거나 예상 보스 수가 달라지면 실패하므로 원본 변경을 확인한 후 갱신해야 합니다.

## 사용 방법과 계산 규칙

1. 보스명/지역으로 검색합니다.
2. 필드 보스의 `지금 처치 체크`를 누르거나 `처치 시간 입력`에서 실제 날짜(YYYY-MM-DD)와 시각(HH:mm 또는 HH:mm:ss)을 직접 입력합니다. 모든 입력은 한국 시간이며 미래 시각은 허용하지 않습니다. 주기는 `시간 설정`에서 수정합니다.
3. 알림 스위치를 켭니다. 미설정 필드 보스는 시간 설정 창이 열립니다.
4. 권한 안내에서 기기 알림 및 Android 정확한 알람 권한을 허용합니다.

모든 표시 및 고정 일정은 한국 시간(UTC+9)입니다. 필드는 `처치 기준 + n × 주기`로 계산하므로 체크를 여러 번 놓쳐도 시각이 밀리지 않습니다. 새 처치 체크 시 기준이 바뀌고 이전 예약을 교체합니다. 체크는 기존 알림 ON/OFF 선택을 유지합니다.

고정 보스는 처치 기준으로 이동하지 않고 선택한 요일·시간을 반복합니다. 고정 요일과 젠 시각도 수정할 수 있습니다. 젠 시각과 현재 시각이 같으면 다음 주기로 이동합니다. 5분 전 시각이 이미 지난 젠은 즉시 소급 알림을 보내지 않고 다음 주기 알림을 예약합니다.

예: 10:00 처치, 4시간 주기 → 13:55 알림 / 14:00 젠. 체크하지 않으면 17:55 / 18:00으로 이어집니다. 14:10에 체크하면 18:05 / 18:10으로 변경됩니다.

## 플랫폼 동작과 한계

### Android

네이티브 `AlarmManager`와 `BroadcastReceiver`를 사용합니다. 동일 시각의 보스들은 한 번의 깨우기로 처리하며, 알림을 처리한 뒤 다음 가장 빠른 알림을 예약합니다. Flutter 타이머는 화면 갱신에만 사용합니다.

- 설정은 SharedPreferences에 보관합니다.
- 일반적인 앱 종료 이후에도 예약은 유지됩니다. 재부팅·앱 업데이트·시계 변경·정확한 알람 권한 허용 시 저장된 설정으로 다시 예약합니다.
- 알림 OFF 또는 처치/주기 변경 시 기존 예약을 취소하고 다시 계산합니다.
- 정확한 알람 권한이 없으면 부정확한 예약으로 대체하지 않고 화면에 권한 안내를 표시합니다.
- 기기 강제 중지 후에는 앱을 다시 열어야 합니다. 제조사 절전 정책과 Android Doze의 알람 빈도 제한으로 짧은 간격의 알림은 지연될 수 있습니다. 이미 젠 시간이 지난 경고는 보내지 않습니다.
- 앱 데이터 삭제 시 설정도 삭제됩니다.

Android 동작 참고: [공식 AlarmManager 안내](https://developer.android.com/develop/background-work/services/alarms).

### iOS

`UNUserNotificationCenter`와 UserDefaults를 사용합니다. 가까운 순서의 최대 64건을 OS에 예약하고 앱 실행/복귀/설정 변경 시 갱신합니다. 화면의 예약 범위는 **첫 번째 미예약 알림 시각 직전까지**이며, 그 전에 앱을 열어야 합니다. 여러 보스가 같은 시각에 몰리는 경우에도 이 경계 이전의 모든 활성 알림이 포함되도록 계산합니다.

앱을 장기간 열지 않아도 무기한 반복하는 동작은 iOS 버전에 구현되어 있지 않습니다. 이 요구까지 충족하려면 서버 스케줄러와 APNs 원격 푸시를 추가해야 합니다. 이 저장소에는 해당 서버가 없습니다.

iOS 동작 참고: [Apple 로컬 알림 예약 안내](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html).

## 개발 / 검증

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

현재 작업 환경은 Flutter 3.13.3 / Dart 3.1.1입니다. 해당 구형 SDK에서 Windows 상대 경로가 잘못 해석되면 다음처럼 진입 파일을 절대 경로로 지정합니다.

```powershell
flutter build apk --debug --target D:/dev/workspace/vscode/sg/alarm/lib/main.dart
```

테스트는 기본 데이터 개수, 장시간 미체크, 젠/알림 경계, 26/46시간 주기, 한국 고정 요일과 자정, 처치 후 재예약, 설정 복구·손상·저장 실패, 알림 취소와 화면 흐름을 검증합니다. 플랫폼 채널은 Flutter 테스트에서 모킹되므로 실제 푸시 수신 검증을 대체하지 않습니다.

실기기 확인:

- 권한을 허용한 뒤 6분 주기로 설정하고 지금 처치 체크하여 약 1분 뒤 알림을 확인합니다.
- 앱을 닫고 다음 주기 알림, 재체크 후 이전 예약 취소, 알림 OFF를 확인합니다.
- Android에서 재부팅 후 복구, 권한 거절/재허용, 절전 상태를 확인합니다.
- iOS는 macOS/Xcode에서 별도 빌드하고 권한/백그라운드 수신/예약 갱신을 확인합니다.

## 주요 파일

- `assets/bosses.json`: 기본 보스 설정
- `tools/import_bosses.py`: 시트 변환 및 교차 검증
- `lib/features/boss_alarm/domain/boss.dart`: 젠·알림 시각 계산
- `lib/features/boss_alarm/application/boss_controller.dart`: 설정 저장, 예약 조정
- `lib/features/boss_alarm/presentation/boss_alarm_page.dart`: 목록 및 설정 화면
- `android/.../BossAlarms.kt`: Android 알림과 재부팅 복구
- `ios/Runner/AppDelegate.swift`: iOS 알림 예약과 권한

## 전체 알림 설정/해제

목록 위의 `전체 설정`과 `전체 해제`는 검색 및 필터와 관계없이 전체 보스에 적용됩니다. 전체 설정은 고정 보스와 처치 시간이 입력된 필드 보스의 알림을 켭니다. 처치 시간이 없는 필드 보스는 제외됩니다. 전체 해제는 모든 알림을 끄고 예약을 취소하며, 처치 시간과 젠 주기는 유지합니다. 변경 사항은 한 번에 저장하고 알림을 다시 예약합니다.

## Firebase Firestore 연결

현재 Flutter 3.13.3 / Dart 3.1.1에 맞춰 firebase_core 2.24.2, firebase_auth 4.15.3, cloud_firestore 4.14.0을 고정합니다. Firebase 연결 설정 없이 빌드하면 기존 기기 저장 방식으로 동작합니다.

1. Firebase 콘솔에서 사용할 프로젝트를 선택하고 무료 Spark 플랜을 유지합니다.
2. Firestore Database를 **Standard edition / (default)**로 생성합니다. 한국 사용자 중심이면 제공 지역에서 서울(asia-northeast3)을 선택합니다.
3. Authentication의 로그인 방법에서 **익명(Anonymous)**을 활성화합니다.
4. Android 앱 ID `com.lordnine.lordnine_boss_alarm`, iOS 번들 ID `com.lordnine.lordnineBossAlarm`로 앱을 등록합니다.
5. `config/firebase.example.json`을 `config/firebase.android.json` 또는 `config/firebase.ios.json`으로 복사하고 각 플랫폼의 Firebase 앱 설정을 입력합니다. 프로젝트 ID, API 키, 앱 ID, 메시지 발신자 ID는 Firebase 클라이언트 설정값입니다. 서비스 계정 키는 사용하지 않습니다.
6. 아래 규칙을 적용합니다. **기존 프로젝트의 규칙이 있다면 이 파일의 match 블록을 기존 규칙에 합쳐야 합니다. 전체 규칙을 덮어쓰면 다른 앱에 영향을 줄 수 있습니다.**

```powershell
firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
flutter run --dart-define-from-file=config/firebase.android.json
```

iOS에서는 `config/firebase.ios.json`을 사용하고 macOS/Xcode에서 빌드합니다. Dart의 FirebaseOptions로 초기화하므로 이 구성에는 google-services Gradle 플러그인이 필요하지 않습니다.

저장 경로는 `bossAlarmUsers/{익명 UID}/schedules/current`입니다. 보스 45종과 처치 시간, 알림 선택을 문서 하나로 저장합니다. 자기 UID의 시간표만 읽고 쓸 수 있으며 공용 시간표는 아닙니다. 익명 계정이 사라지는 앱 데이터 삭제/재설치 후에는 기존 DB 기록을 복구할 수 없습니다. 다른 기기와 공유하려면 계정 로그인 또는 길드 권한 모델을 추가해야 합니다.

기존 기기 저장 데이터는 최초 연결 시 우선 업로드합니다. 처치 체크, 시간 수정, 전체 설정/해제는 기기에 먼저 저장하고 알림을 예약한 뒤 DB에 전송합니다. 전송 실패 시 미전송 상태도 기기에 남기며 다음 실행, 앱 복귀 또는 새로고침에서 재시도합니다. 동기화된 상태에서는 DB 문서를 다시 읽어 로컬 시간표와 알림을 갱신합니다. DB에서 잘못된 데이터가 내려오면 기존 기기 시간표를 유지합니다. 원격 연결 대기는 호출당 8초로 제한합니다.

초 단위 카운트다운은 DB에 접근하지 않습니다. 화면 상단에서 DB 동기화 상태를 확인할 수 있습니다. 앱이 종료되어 있는 동안에는 DB 변경을 실시간으로 수신하지 않으며, 기기에 이미 예약된 알림을 사용합니다.

공식 문서: [Flutter 연결](https://firebase.google.com/docs/flutter/setup), [익명 인증](https://firebase.google.com/docs/auth/flutter/anonymous-auth), [접근 규칙](https://firebase.google.com/docs/firestore/security/rules-conditions).

### 연결된 프로젝트

- 프로젝트: `osle-sg`
- Firestore: `(default)`, Standard, 서울 `asia-northeast3`, 무료 DB 확인
- Android/iOS 등록 및 로컬 `config/firebase.android.json`, `config/firebase.ios.json` 생성 완료
- VS Code 실행 구성에서 `Boss Alarm (Firebase Android)` 또는 iOS 구성을 선택합니다.
- 2026-09-09: 사용자별 Firestore 규칙 배포 완료. 기존 규칙은 2023-12-02에 만료된 테스트 규칙이었고 `.firebase/setup-backup/`에 백업했습니다. CLI 배포는 프로젝트의 Service Usage API 비활성화로 실패하여 공식 Rules API로 배포했습니다.
- Authentication 익명 로그인 활성화 완료. 실제 서버에서 보스 45종 저장/조회, 비로그인 및 타 사용자 접근 차단, 잘못된 데이터 차단을 검증했습니다. 테스트 계정과 문서는 검증 후 삭제했습니다.

```powershell
flutter run --dart-define-from-file=config/firebase.android.json
flutter build apk --debug --target D:/dev/workspace/vscode/sg/alarm/lib/main.dart --dart-define-from-file=config/firebase.android.json
node tools/firebase_smoke.cjs config/firebase.android.json
```

연결 검증 스크립트는 임시 익명 사용자 2명을 만들어 시간표 저장/조회, 다른 사용자 접근 거부 및 잘못된 데이터 거부를 확인한 후 테스트 문서와 계정을 삭제합니다. 문서 정리를 위해 로그인된 Firebase CLI를 사용하며, 인증 토큰은 출력하거나 파일로 저장하지 않습니다.

## iPhone 설치용 IPA 빌드

현재 Windows 작업 환경에서는 IPA를 생성할 수 없습니다. Mac의 Xcode, Flutter, CocoaPods와 Apple 서명 설정이 필요합니다. `ios/Podfile` 및 CocoaPods 빌드 설정을 준비했으며, 실제 macOS 컴파일과 서명 검증은 아직 수행하지 않았습니다.

1. 프로젝트와 `config/firebase.ios.json`을 Mac으로 복사합니다. 이 JSON은 Git에서 제외되어 있으므로 별도로 옮겨야 합니다. `build/`, `.dart_tool/`, `ios/Flutter/Generated.xcconfig`, `ios/Flutter/flutter_export_environment.sh` 같은 Windows 생성 파일은 복사하지 않습니다.
2. Mac에서 `flutter pub get`과 `cd ios && pod install`을 실행합니다.
3. `ios/Runner.xcworkspace`를 Xcode로 열고 Runner → Signing & Capabilities에서 Automatically manage signing 및 본인의 Team을 설정합니다. 번들 ID는 Firebase에 등록된 `com.lordnine.lordnineBossAlarm`입니다.
4. 직접 설치할 기기를 개발자 계정에 등록하고 해당 기기를 포함하는 인증서/프로비저닝 프로파일을 준비합니다.
5. 프로젝트 루트에서 실행합니다.

```bash
bash tools/build_ios.sh ad-hoc
```

성공하면 `build/ios/ipa/`에 서명된 IPA가 생성됩니다. 스크립트는 Firebase iOS 설정을 포함하며 macOS, 필수 도구, 서명 팀, IPA 생성 결과를 확인합니다. Ad Hoc 배포에는 Apple Developer Program과 등록된 기기가 필요합니다. 무료 Apple 계정으로 개인 기기에 테스트하려면 Mac에서 iPhone을 연결하고 Xcode/`flutter run --dart-define-from-file=config/firebase.ios.json`을 사용합니다. 이는 배포용 IPA 제공과 다릅니다.

TestFlight 배포용 아카이브는 `bash tools/build_ios.sh app-store`로 빌드하며, App Store Connect 등록과 업로드는 별도입니다. 이 스크립트는 업로드하지 않습니다. 프로젝트의 Flutter 3.13.3과 설치할 Xcode 조합은 Mac에서 확인해야 합니다.

공식 안내: [Flutter iOS 빌드](https://docs.flutter.dev/deployment/ios), [Apple 등록 기기 배포](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
