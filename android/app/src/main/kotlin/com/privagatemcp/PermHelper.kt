package com.privagatemcp

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/** 扩展权限辅助：文件访问/定位/悬浮窗/通知读取 */
object PermHelper {

    // ---------- 检查 ----------

    fun checkAll(context: Context): Map<String, Any> {
        fun granted(vararg perms: String): Boolean {
            val r = perms.any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
            return r
        }
        val result = mapOf(
            "file_access" to isAllFilesGranted(context),
            "location" to isLocationGranted(context),
            "overlay" to isOverlayGranted(context),
            "notifications" to isNotificationAccessGranted(context),
            "camera" to granted(Manifest.permission.CAMERA),
            "microphone" to granted(Manifest.permission.RECORD_AUDIO),
            "sms" to granted(Manifest.permission.READ_SMS),
            "contacts" to granted(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS),
            "call_log" to granted(Manifest.permission.READ_CALL_LOG, Manifest.permission.WRITE_CALL_LOG),
            "calendar" to granted(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            "usage_stats" to isUsageStatsGranted(context),
            "ignore_battery" to isIgnoreBatteryGranted(context),
            "all_apps" to true,
            "phone" to granted(Manifest.permission.CALL_PHONE, Manifest.permission.READ_PHONE_STATE),
            "wifi" to granted(Manifest.permission.NEARBY_WIFI_DEVICES, Manifest.permission.ACCESS_WIFI_STATE),
            "bluetooth" to granted(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
        )
        return result
    }

    fun isUsageStatsGranted(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                appOps.unsafeCheckOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), context.packageName
                )
            }
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }

    fun isIgnoreBatteryGranted(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Throwable) {
            false
        }
    }

    fun isAllFilesGranted(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 30) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun isLocationGranted(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
    }

    fun isOverlayGranted(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun isNotificationAccessGranted(context: Context): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return flat.split(':').any { it.contains("PrivaGateNotificationListener") }
    }

    /** 无障碍服务是否在系统侧启用（查设置，不依赖进程内 instance） */
    fun isAccessibilityEnabled(context: Context): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return flat.split(':').any { it.contains("PrivaGateAccessibilityService") }
    }

    fun isPostNotificationsGranted(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else true
    }

    // ---------- 请求 ----------

    fun requestLocation(activity: MainActivity) {
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            MainActivity.REQ_LOCATION
        )
    }

    fun openAllFilesSettings(activity: MainActivity) {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:${activity.packageName}")))
            } else {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } catch (_: Throwable) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    fun openOverlaySettings(activity: MainActivity) {
        try {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")))
        } catch (_: Throwable) {}
    }

    fun openNotificationAccessSettings(activity: MainActivity) {
        try {
            activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        } catch (_: Throwable) {}
    }

    fun requestRuntime(activity: MainActivity, vararg perms: String) {
        ActivityCompat.requestPermissions(activity, perms, MainActivity.REQ_RUNTIME)
    }

    fun openUsageStatsSettings(activity: MainActivity) {
        try {
            activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        } catch (_: Throwable) {}
    }

    fun openIgnoreBatterySettings(activity: MainActivity) {
        try {
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}"))
            )
        } catch (_: Throwable) {
            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    fun requestPostNotifications(activity: MainActivity) {
        if (Build.VERSION.SDK_INT >= 33) {
            ActivityCompat.requestPermissions(
                activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), MainActivity.REQ_NOTIFICATION
            )
        }
    }

    // ---------- 定位 ----------

    /** 获取当前位置（优先最新已知位置，必要时单次更新） */
    fun getLocation(context: Context): Map<String, Any?>? {
        if (!isLocationGranted(context)) return null
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        var best: Location? = null
        for (p in providers) {
            try {
                val l = lm.getLastKnownLocation(p)
                if (l != null && (best == null || l.time > best.time)) best = l
            } catch (_: Throwable) {}
        }
        if (best == null) {
            // 单次请求（最多等 ~3s）
            val latch = java.util.concurrent.CountDownLatch(1)
            var loc: Location? = null
            val listener = android.location.LocationListener {
                loc = it
                latch.countDown()
            }
            try {
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, listener, null)
                } else if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestSingleUpdate(LocationManager.GPS_PROVIDER, listener, null)
                }
                latch.await(3, java.util.concurrent.TimeUnit.SECONDS)
            } catch (_: Throwable) {}
            try { lm.removeUpdates(listener) } catch (_: Throwable) {}
            best = loc
        }
        return best?.let {
            mapOf(
                "lat" to it.latitude,
                "lng" to it.longitude,
                "accuracy" to it.accuracy,
                "provider" to it.provider,
                "time" to it.time,
            )
        }
    }
}
