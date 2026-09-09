package com.lordnine.lordnine_boss_alarm

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarmChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        intent?.let { BossAlarms.queueCut(this, it) }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (BossAlarms.queueCut(this, intent)) {
            alarmChannel?.invokeMethod("cutPending", null)
        }
    }

    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        alarmChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lordnine/boss_alarm")
        alarmChannel!!.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "pendingCuts" -> result.success(BossAlarms.pendingCuts(this))
                        "acknowledgeCuts" -> {
                            BossAlarms.acknowledgeCuts(this, (call.arguments as List<*>).filterIsInstance<String>())
                            result.success(null)
                        }
                        "load" -> result.success(BossAlarms.preferences(this).getString("document", null))
                        "save" -> {
                            val json = call.arguments as String
                            BossAlarms.validate(json)
                            check(BossAlarms.preferences(this).edit().putString("document", json).commit())
                            // Persist and reconcile here as well, so process death between
                            // Flutter's save and sync cannot leave the old schedule active.
                            runCatching { BossAlarms.schedule(this) }
                            result.success(null)
                        }
                        "sync" -> {
                            BossAlarms.schedule(this)
                            result.success(BossAlarms.status(this))
                        }
                        "requestPermissions" -> {
                            if (permissionResult != null) {
                                result.error("busy", "권한 요청이 진행 중입니다.", null)
                            } else if (Build.VERSION.SDK_INT >= 33 &&
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                permissionResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                            } else {
                                openSettings()
                                result.success(null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("alarm_error", e.message, null)
                }
            }
    }

    private fun openSettings() {
        val alarms = getSystemService(ALARM_SERVICE) as AlarmManager
        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) {
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:$packageName")))
        } else if (Build.VERSION.SDK_INT >= 26 &&
            (!notifications.areNotificationsEnabled() ||
             notifications.getNotificationChannel(BossAlarms.CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE)) {
            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        } else if (Build.VERSION.SDK_INT >= 24 && !notifications.areNotificationsEnabled()) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 100) {
            val result = permissionResult
            permissionResult = null
            try {
                openSettings()
                result?.success(null)
            } catch (e: Exception) {
                result?.error("permission_error", e.message, null)
            }
        }
    }
}
