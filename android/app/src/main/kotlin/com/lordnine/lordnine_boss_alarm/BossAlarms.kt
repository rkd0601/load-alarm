package com.lordnine.lordnine_boss_alarm

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

object BossAlarms {
    const val CHANNEL = "boss_spawn"
    const val CUT_ACTION = "com.lordnine.lordnine_boss_alarm.CUT"
    private const val LEAD = 300000L
    fun preferences(context: Context) = context.getSharedPreferences("boss_alarm", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private fun notifications(context: Context) = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun validate(document: String) {
        val root = JSONObject(document)
        require(root.getInt("schemaVersion") == 1)
        val bosses = root.getJSONArray("bosses")
        val ids = mutableSetOf<Int>()
        for (i in 0 until bosses.length()) {
            val boss = bosses.getJSONObject(i)
            require(boss.getInt("id") > 0 && ids.add(boss.getInt("id")))
            require(boss.getString("name").isNotBlank())
            val days = boss.getJSONArray("weekdays")
            require(days.length() > 0 || boss.getInt("intervalMinutes") > 5)
            for (j in 0 until days.length()) require(days.getInt(j) in 1..7)
            require(boss.getInt("minuteOfDay") in 0..1439)
        }
    }

    fun status(context: Context): Map<String, Any> {
        createChannel(context)
        val notificationManager = notifications(context)
        val allowed = (Build.VERSION.SDK_INT < 24 || notificationManager.areNotificationsEnabled()) &&
            (Build.VERSION.SDK_INT < 26 || notificationManager.getNotificationChannel(CHANNEL).importance != NotificationManager.IMPORTANCE_NONE)
        return mapOf("platform" to "android", "allowed" to allowed,
            "exact" to (Build.VERSION.SDK_INT < 31 || manager(context).canScheduleExactAlarms()))
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            notifications(context).createNotificationChannel(NotificationChannel(
                CHANNEL, "보스 젠 5분 전", NotificationManager.IMPORTANCE_HIGH))
        }
    }

    private fun pending(context: Context, token: String = ""): PendingIntent =
        PendingIntent.getBroadcast(context, 1,
            Intent(context, BossAlarmReceiver::class.java).putExtra("token", token),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    // Match Dart's UTC-anchored interval / Asia-Seoul weekly schedule exactly.
    internal fun nextSpawn(boss: JSONObject, after: Long): Long? {
        val days = boss.getJSONArray("weekdays")
        if (days.length() == 0) {
            if (boss.isNull("anchorMs")) return null
            val anchor = boss.getLong("anchorMs")
            val period = boss.getLong("intervalMinutes") * 60000L
            val count = if (after - anchor < period) 1L else (after - anchor) / period + 1
            return anchor + count * period
        }
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Seoul"))
        calendar.timeInMillis = after
        calendar.set(Calendar.HOUR_OF_DAY, boss.getInt("minuteOfDay") / 60)
        calendar.set(Calendar.MINUTE, boss.getInt("minuteOfDay") % 60)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val weekdays = (0 until days.length()).map { days.getInt(it) }
        for (offset in 0..7) {
            val weekday = (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            if (weekday in weekdays && calendar.timeInMillis > after) return calendar.timeInMillis
            calendar.add(Calendar.DAY_OF_MONTH, 1)
        }
        return null
    }

    @Synchronized fun schedule(context: Context, now: Long = System.currentTimeMillis()) {
        val prefs = preferences(context)
        val document = prefs.getString("document", null) ?: return
        val bosses = JSONObject(document).getJSONArray("bosses")
        val events = mutableListOf<JSONObject>()
        for (i in 0 until bosses.length()) {
            val boss = bosses.getJSONObject(i)
            if (!boss.optBoolean("enabled")) continue
            val spawn = nextSpawn(boss, now + LEAD) ?: continue
            events.add(JSONObject().put("id", boss.getInt("id"))
                .put("name", boss.getString("name")).put("canCut", boss.getJSONArray("weekdays").length() == 0).put("spawnMs", spawn).put("fireMs", spawn - LEAD))
        }
        val alarmManager = manager(context)
        alarmManager.cancel(pending(context))
        val token = UUID.randomUUID().toString()
        val first = events.minOfOrNull { it.getLong("fireMs") }
        val due = JSONArray()
        events.filter { it.getLong("fireMs") == first }.forEach { due.put(it) }
        check(prefs.edit().putString("token", token).putString("due", due.toString()).commit())
        if (first == null) return
        // Never silently substitute an inexact alarm for a requested five-minute warning.
        if (Build.VERSION.SDK_INT >= 31 && !alarmManager.canScheduleExactAlarms()) return
        if (Build.VERSION.SDK_INT >= 23) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, first, pending(context, token))
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, first, pending(context, token))
        }
    }

    @Synchronized fun queueCut(context: Context, intent: Intent): Boolean {
        if (intent.action != CUT_ACTION) return false
        val id = intent.getIntExtra("cutId", -1)
        val token = intent.getStringExtra("cutToken") ?: return false
        val prefs = preferences(context)
        // Only accept a token issued by this app's immutable notification action.
        if (token != prefs.getString("cut_token_$id", null)) return false
        val cuts = JSONArray(prefs.getString("pending_cuts", "[]"))
        cuts.put(JSONObject().put("id", id).put("token", token)
            .put("atMs", System.currentTimeMillis()))
        check(prefs.edit().putString("pending_cuts", cuts.toString())
            .remove("cut_token_$id").commit())
        notifications(context).cancel(id)
        intent.removeExtra("cutToken")
        return true
    }

    @Synchronized fun pendingCuts(context: Context): List<Map<String, Any>> {
        val cuts = JSONArray(preferences(context).getString("pending_cuts", "[]"))
        return (0 until cuts.length()).map {
            val cut = cuts.getJSONObject(it)
            mapOf("id" to cut.getInt("id"), "token" to cut.getString("token"), "atMs" to cut.getLong("atMs"))
        }
    }

    @Synchronized fun acknowledgeCuts(context: Context, tokens: List<String>) {
        val prefs = preferences(context)
        val cuts = JSONArray(prefs.getString("pending_cuts", "[]"))
        val remaining = JSONArray()
        for (i in 0 until cuts.length()) {
            val cut = cuts.getJSONObject(i)
            if (cut.getString("token") !in tokens) remaining.put(cut)
        }
        check(prefs.edit().putString("pending_cuts", remaining.toString()).commit())
    }

    @Synchronized fun fire(context: Context, token: String?) {
        val prefs = preferences(context)
        if (token == null || token != prefs.getString("token", null)) return
        val now = System.currentTimeMillis()
        val due = JSONArray(prefs.getString("due", "[]"))
        val canNotify = status(context)["allowed"] == true
        val format = SimpleDateFormat("M/d HH:mm", Locale.KOREAN)
        format.timeZone = TimeZone.getTimeZone("Asia/Seoul")
        try {
            for (i in 0 until due.length()) {
                val event = due.getJSONObject(i)
                val spawn = event.getLong("spawnMs")
                // Do not send stale warnings after reboot, sleep or a clock change.
                if (!canNotify || spawn <= now || event.getLong("fireMs") > now + 1000) continue
                val tap = PendingIntent.getActivity(context, 0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
                    else Notification.Builder(context)
                if (event.optBoolean("canCut")) {
                    val id = event.getInt("id")
                    val cutToken = UUID.randomUUID().toString()
                    check(prefs.edit().putString("cut_token_$id", cutToken).commit())
                    val cut = PendingIntent.getActivity(context, id,
                        Intent(context, MainActivity::class.java).setAction(CUT_ACTION)
                            .setData(Uri.parse("boss-cut://$id/$cutToken"))
                            .putExtra("cutId", id).putExtra("cutToken", cutToken)
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT)
                    builder.addAction(Notification.Action.Builder(R.drawable.ic_boss_notification, "컷", cut).build())
                }
                val title = if (now - event.getLong("fireMs") < 60000) "${event.getString("name")} 젠 5분 전"
                    else "${event.getString("name")} 곧 젠"
                notifications(context).notify(event.getInt("id"), builder
                    .setSmallIcon(R.drawable.ic_boss_notification)
                    .setContentTitle(title)
                    .setContentText("${format.format(Date(spawn))} (한국 시간) 젠 예정")
                    .setContentIntent(tap).setAutoCancel(true)
                    .setCategory(Notification.CATEGORY_REMINDER)
                    .setPriority(Notification.PRIORITY_HIGH).build())
            }
        } finally {
            schedule(context, now + 1)
        }
    }
}

class BossAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BossAlarms.fire(context, intent.getStringExtra("token"))
    }
}

class BossAlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) {
            BossAlarms.schedule(context)
        }
    }
}
