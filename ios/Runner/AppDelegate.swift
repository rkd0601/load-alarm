import UIKit
import Flutter
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let center = UNUserNotificationCenter.current()
  private var alarmChannel: FlutterMethodChannel?
  private let cutAction = "BOSS_CUT"
  private let cutCategory = "BOSS_FIELD"
  private let cutsKey = "boss_pending_cuts"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    center.delegate = self
    let cut = UNNotificationAction(identifier: cutAction, title: "컷", options: [.foreground])
    center.setNotificationCategories([UNNotificationCategory(identifier: cutCategory,
      actions: [cut], intentIdentifiers: [], options: [])])
    if let controller = window?.rootViewController as? FlutterViewController {
      alarmChannel = FlutterMethodChannel(name: "lordnine/boss_alarm", binaryMessenger: controller.binaryMessenger)
      alarmChannel?.setMethodCallHandler { [weak self] call, result in
          guard let self = self else { return }
          switch call.method {
          case "pendingCuts":
            result(UserDefaults.standard.array(forKey: self.cutsKey) ?? [])
          case "acknowledgeCuts":
            let tokens = Set(call.arguments as? [String] ?? [])
            let cuts = UserDefaults.standard.array(forKey: self.cutsKey) as? [[String: Any]] ?? []
            let handled = UserDefaults.standard.stringArray(forKey: "boss_handled_cuts") ?? []
            UserDefaults.standard.set(Array((handled + Array(tokens)).suffix(128)), forKey: "boss_handled_cuts")
            UserDefaults.standard.set(cuts.filter { !tokens.contains($0["token"] as? String ?? "") }, forKey: self.cutsKey)
            result(nil)
          case "load":
            result(UserDefaults.standard.string(forKey: "boss_document"))
          case "save":
            guard let document = call.arguments as? String,
              let data = document.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schemaVersion"] as? Int == 1,
              root["bosses"] is [[String: Any]] else {
              result(FlutterError(code: "invalid_document", message: "잘못된 보스 설정입니다.", details: nil))
              return
            }
            UserDefaults.standard.set(document, forKey: "boss_document")
            // Invalidate previous checks immediately; sync installs the replacement.
            self.center.removeAllPendingNotificationRequests()
            result(nil)
          case "sync":
            self.schedule(call.arguments as? [String: Any] ?? [:], result: result)
          case "requestPermissions":
            self.center.getNotificationSettings { settings in
              if settings.authorizationStatus == .denied {
                DispatchQueue.main.async {
                  if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                  }
                  result(nil)
                }
              } else {
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                  DispatchQueue.main.async {
                    if let error = error {
                      result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
                    } else { result(nil) }
                  }
                }
              }
            }
          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func schedule(_ arguments: [String: Any], result: @escaping FlutterResult) {
    let events = arguments["events"] as? [[String: Any]] ?? []
    let horizon = arguments["horizonMs"] as? NSNumber
    center.removeAllPendingNotificationRequests()
    let group = DispatchGroup()
    let lock = NSLock()
    var failure: Error?
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "M/d HH:mm"
    for event in events.prefix(64) {
      guard let id = event["id"] as? Int, let name = event["name"] as? String,
        let fire = event["fireMs"] as? NSNumber, let spawn = event["spawnMs"] as? NSNumber else { continue }
      let fireDate = Date(timeIntervalSince1970: fire.doubleValue / 1000)
      guard fireDate > Date() else { continue }
      let content = UNMutableNotificationContent()
      content.title = "\(name) 젠 5분 전"
      content.body = "\(formatter.string(from: Date(timeIntervalSince1970: spawn.doubleValue / 1000))) (한국 시간) 젠 예정"
      content.sound = .default
      if event["canCut"] as? Bool == true {
        content.categoryIdentifier = cutCategory
        content.userInfo = ["bossId": id]
      }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
      components.timeZone = calendar.timeZone
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let request = UNNotificationRequest(identifier: "boss_\(id)_\(fire.int64Value)", content: content, trigger: trigger)
      group.enter()
      center.add(request) { error in
        if let error = error { lock.lock(); failure = error; lock.unlock() }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if let failure = failure {
        result(FlutterError(code: "schedule_error", message: failure.localizedDescription, details: nil))
        return
      }
      self.center.getNotificationSettings { settings in
        let allowed = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional
        DispatchQueue.main.async {
          result(["platform": "ios", "allowed": allowed, "exact": true,
                  "horizonMs": horizon as Any? ?? NSNull()])
        }
      }
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    guard response.actionIdentifier == cutAction,
      let id = response.notification.request.content.userInfo["bossId"] as? Int else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
      return
    }
    let at = Int64(Date().timeIntervalSince1970 * 1000)
    let token = response.notification.request.identifier
    DispatchQueue.main.async {
      var cuts = UserDefaults.standard.array(forKey: self.cutsKey) as? [[String: Any]] ?? []
      let handled = UserDefaults.standard.stringArray(forKey: "boss_handled_cuts") ?? []
      if !handled.contains(token) && !cuts.contains(where: { $0["token"] as? String == token }) {
        cuts.append(["id": id, "token": token, "atMs": at])
        UserDefaults.standard.set(cuts, forKey: self.cutsKey)
      }
      center.removeDeliveredNotifications(withIdentifiers: [token])
      self.alarmChannel?.invokeMethod("cutPending", arguments: nil)
      completionHandler()
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .sound])
  }
}
