package com.privagatemcp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val REQ_NOTIFICATION = 1001
        const val REQ_SHIZUKU = 1002
        const val REQ_CAPTURE = 1003
        const val REQ_LOCATION = 1004
        const val REQ_RUNTIME = 1005
        const val REQ_PHOTO = 1006
        lateinit var instance: MainActivity
            private set
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/foreground")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        maybeRequestNotificationPermission()
                        try {
                            val intent = Intent(this, PrivaGateService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Throwable) {
                            result.error("FGS", e.message ?: "fgs failed", null)
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, PrivaGateService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/shizuku")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(Shizuku.pingBinder())
                    "isGranted" -> result.success(Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED)
                    "requestPermission" -> {
                        if (Shizuku.shouldShowRequestPermissionRationale()) {
                            result.success(false)
                        } else {
                            Shizuku.requestPermission(REQ_SHIZUKU)
                            result.success(true)
                        }
                    }
                    "runCommand" -> {
                        val cmd = call.argument<String>("command") ?: ""
                        if (!Shizuku.pingBinder()) {
                            result.error("NO_SHIZUKU", "Shizuku 未运行", null)
                        } else if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                            result.error("NO_PERMISSION", "未授权 Shizuku", null)
                        } else {
                            Thread {
                                try {
                                    val p = Shizuku.newProcess(
                                        arrayOf("/system/bin/sh", "-c", cmd),
                                        null, null,
                                    )
                                    val stdout = p.inputStream.bufferedReader().readText()
                                    val stderr = p.errorStream.bufferedReader().readText()
                                    val code = p.waitFor()
                                    result.success(
                                        mapOf(
                                            "exit_code" to code,
                                            "stdout" to stdout,
                                            "stderr" to stderr,
                                        )
                                    )
                                } catch (e: Throwable) {
                                    result.error("EXEC", e.message ?: "exec failed", null)
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/a11y")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(PermHelper.isAccessibilityEnabled(this))
                    "dump" -> result.success(PrivaGateAccessibilityService.dump())
                    "click" -> result.success(
                        PrivaGateAccessibilityService.clickNode(
                            call.argument<String>("text"), call.argument<Double>("x")?.toFloat(), call.argument<Double>("y")?.toFloat()
                        )
                    )
                    "longClick" -> result.success(
                        PrivaGateAccessibilityService.clickNode(
                            call.argument<String>("text"), call.argument<Double>("x")?.toFloat(), call.argument<Double>("y")?.toFloat(), longClick = true
                        )
                    )
                    "setText" -> result.success(
                        PrivaGateAccessibilityService.setText(call.argument<String>("text") ?: "")
                    )
                    "global" -> result.success(
                        PrivaGateAccessibilityService.globalAction(call.argument<String>("action") ?: "")
                    )
                    "scroll" -> result.success(
                        PrivaGateAccessibilityService.scroll(call.argument<String>("direction") ?: "forward")
                    )
                    "swipe" -> result.success(
                        PrivaGateAccessibilityService.swipe(
                            call.argument<Double>("x1")?.toFloat() ?: 0f,
                            call.argument<Double>("y1")?.toFloat() ?: 0f,
                            call.argument<Double>("x2")?.toFloat() ?: 0f,
                            call.argument<Double>("y2")?.toFloat() ?: 0f,
                            call.argument<Double>("duration")?.toLong() ?: 200L,
                        )
                    )
                    "openSettings" -> {
                        startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAll" -> result.success(PermHelper.checkAll(this))
                    "requestLocation" -> {
                        PermHelper.requestLocation(this)
                        result.success(true)
                    }
                    "requestAllFiles" -> {
                        PermHelper.openAllFilesSettings(this)
                        result.success(true)
                    }
                    "requestOverlay" -> {
                        PermHelper.openOverlaySettings(this)
                        result.success(true)
                    }
                    "requestNotificationAccess" -> {
                        PermHelper.openNotificationAccessSettings(this)
                        result.success(true)
                    }
                    "requestRuntime" -> {
                        val perms = call.argument<List<String>>("permissions") ?: emptyList()
                        PermHelper.requestRuntime(this, *perms.toTypedArray())
                        result.success(true)
                    }
                    "requestUsageStats" -> {
                        PermHelper.openUsageStatsSettings(this)
                        result.success(true)
                    }
                    "requestIgnoreBattery" -> {
                        PermHelper.openIgnoreBatterySettings(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/location")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> {
                        val loc = PermHelper.getLocation(this)
                        if (loc == null) {
                            result.error("NO_LOCATION", "定位失败或未授权", null)
                        } else {
                            result.success(loc)
                        }
                    }
                    "watch" -> {
                        // 连续采样：轮询 GPS/网络最后已知位置，取精度最优
                        Thread {
                            val samples = mutableListOf<Map<String, Any?>>()
                            try {
                                val lm = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
                                val n = call.argument<Number>("count")?.toInt() ?: 5
                                val intervalMs = call.argument<Number>("intervalMs")?.toLong() ?: 1000L
                                for (i in 0 until n) {
                                    try {
                                        val gps = lm.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                                        val net = lm.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
                                        val loc = gps ?: net
                                        if (loc != null) {
                                            samples.add(mapOf(
                                                "lat" to loc.latitude,
                                                "lon" to loc.longitude,
                                                "accuracy_m" to loc.accuracy,
                                                "provider" to (loc.provider ?: ""),
                                                "time" to loc.time,
                                            ))
                                        }
                                    } catch (_: Throwable) {}
                                    if (i < n - 1) Thread.sleep(intervalMs.coerceIn(100, 5000))
                                }
                            } catch (_: Throwable) {}
                            runOnUiThread {
                                if (samples.isEmpty()) {
                                    result.error("NO_LOCATION", "定位失败或未授权", null)
                                } else {
                                    val best = samples.minByOrNull { (it["accuracy_m"] as? Float) ?: Float.MAX_VALUE }
                                    result.success(mapOf("samples" to samples.size, "best" to best, "all" to samples))
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConnected" -> result.success(PrivaGateNotificationListener.connected)
                    "list" -> result.success(PrivaGateNotificationListener.snapshot)
                    "open" -> result.success(
                        PrivaGateNotificationListener().openNotification(call.argument<String>("key") ?: "")
                    )
                    "clear" -> result.success(
                        PrivaGateNotificationListener().clearNotification(call.argument<String>("key") ?: "")
                    )
                    "clearAll" -> result.success(PrivaGateNotificationListener().clearAll())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "photo" -> {
                        if (!(PermHelper.checkAll(this)["camera"] as Boolean)) {
                            result.error("NO_PERMISSION", "未授权相机", null)
                        } else {
                            pendingPhotoResult = result
                            try {
                                val intent = android.content.Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
                                startActivityForResult(intent, REQ_PHOTO)
                            } catch (e: Throwable) {
                                pendingPhotoResult = null
                                result.error("NO_CAMERA", "没有可用相机应用", null)
                            }
                        }
                    }
                    "record" -> {
                        val seconds = call.argument<Int>("seconds") ?: 5
                        Thread {
                            val r = MediaTools.record(this, seconds)
                            if (r == null) {
                                runOnUiThread { result.error("NO_PERMISSION", "录音失败或未授权", null) }
                            } else {
                                runOnUiThread { result.success(r) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/overlay")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val text = call.argument<String>("text") ?: ""
                        val seconds = call.argument<Int>("seconds") ?: 3
                        result.success(OverlayToast.show(this, text, seconds))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/data")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "smsList" -> {
                        val r = DataTools.smsList(this, call.argument<Int>("limit") ?: 50)
                        if (r == null) result.error("NO_PERMISSION", "未授权短信", null) else result.success(r)
                    }
                    "smsSend" -> {
                        val ok = DataTools.smsSend(
                            call.argument<String>("number") ?: "", call.argument<String>("text") ?: ""
                        )
                        result.success(ok)
                    }
                    "contacts" -> {
                        val r = DataTools.contacts(this, call.argument<Int>("limit") ?: 200)
                        if (r == null) result.error("NO_PERMISSION", "未授权通讯录", null) else result.success(r)
                    }
                    "callLog" -> {
                        val r = DataTools.callLog(this, call.argument<Int>("limit") ?: 100)
                        if (r == null) result.error("NO_PERMISSION", "未授权通话记录", null) else result.success(r)
                    }
                    "calendar" -> {
                        val r = DataTools.calendar(this, call.argument<Int>("limit") ?: 50)
                        if (r == null) result.error("NO_PERMISSION", "未授权日历", null) else result.success(r)
                    }
                    "usage" -> {
                        val r = DataTools.usage(this, call.argument<Int>("days") ?: 1)
                        if (r == null) result.error("NO_PERMISSION", "未授权使用统计", null) else result.success(r)
                    }
                    "smsThreads" -> {
                        val r = DataTools.smsThreads(this, call.argument<Int>("limit") ?: 50)
                        if (r == null) result.error("NO_PERMISSION", "未授权短信", null) else result.success(r)
                    }
                    "smsDelete" -> {
                        val ok = DataTools.smsDelete(
                            this,
                            call.argument<Number>("id")?.toLong(), call.argument<String>("number")
                        )
                        if (!ok && PermHelper.checkAll(this)["sms"] == false) {
                            result.error("NO_PERMISSION", "未授权短信", null)
                        } else result.success(ok)
                    }
                    "smsMarkRead" -> {
                        val ok = DataTools.smsMarkRead(this, call.argument<Number>("id")?.toLong())
                        if (!ok && PermHelper.checkAll(this)["sms"] == false) {
                            result.error("NO_PERMISSION", "未授权短信", null)
                        } else result.success(ok)
                    }
                    "contactAdd" -> {
                        val ok = DataTools.contactAdd(
                            this,
                            call.argument<String>("name") ?: "", call.argument<String>("number") ?: ""
                        )
                        result.success(ok)
                    }
                    "contactUpdate" -> {
                        val ok = DataTools.contactUpdate(
                            this,
                            call.argument<Number>("contactId")?.toLong() ?: -1L,
                            call.argument<String>("name"), call.argument<String>("number")
                        )
                        result.success(ok)
                    }
                    "contactDelete" -> {
                        val ok = DataTools.contactDelete(this, call.argument<Number>("contactId")?.toLong() ?: -1L)
                        result.success(ok)
                    }
                    "callLogDelete" -> {
                        val ok = DataTools.callLogDelete(
                            this,
                            call.argument<Number>("id")?.toLong(), call.argument<String>("number"),
                            call.argument<Boolean>("all") ?: false
                        )
                        result.success(ok)
                    }
                    "calendarAdd" -> {
                        val ok = DataTools.calendarAdd(
                            this,
                            call.argument<String>("title") ?: "",
                            call.argument<Number>("startMs")?.toLong() ?: System.currentTimeMillis(),
                            call.argument<Number>("endMs")?.toLong() ?: (System.currentTimeMillis() + 3600000L),
                            call.argument<String>("description")
                        )
                        result.success(ok)
                    }
                    "calendarDelete" -> {
                        val ok = DataTools.calendarDelete(this, call.argument<Number>("id")?.toLong() ?: -1L)
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "clipboardGet" -> result.success(DeviceTools.clipboardGet(this))
                    "clipboardSet" -> result.success(
                        DeviceTools.clipboardSet(this, call.argument<String>("text") ?: "")
                    )
                    "sensorRead" -> result.success(
                        DeviceTools.sensorRead(this, call.argument<String>("type") ?: "accelerometer")
                    )
                    "vibrate" -> result.success(
                        DeviceTools.vibrate(this, call.argument<Int>("ms") ?: 300)
                    )
                    "traffic" -> result.success(DeviceTools.trafficStats(this))
                    "nfcStatus" -> result.success(DeviceTools.nfcStatus(this))
                    "wifiScan" -> result.success(DeviceTools.wifiScan(this))
                    "bluetoothScan" -> result.success(DeviceTools.bluetoothScan(this))
                    "phoneState" -> result.success(DeviceTools.phoneState(this))
                    "callDirect" -> result.success(
                        DeviceTools.callDirect(this, call.argument<String>("number") ?: "")
                    )
                    "openDialer" -> result.success(
                        DeviceTools.openDialer(this, call.argument<String>("number") ?: "")
                    )
                    "battery" -> result.success(DeviceTools.battery(this))
                    "wifiStatus" -> result.success(DeviceTools.wifiStatus(this))
                    "bluetoothStatus" -> result.success(DeviceTools.bluetoothStatus(this))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privagate/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
                        // Android 14+ 要求：getMediaProjection 前必须运行 mediaProjection 类型 FGS
                        startCaptureFgs()
                        startActivityForResult(mgr.createScreenCaptureIntent(), REQ_CAPTURE)
                        result.success(true)
                    }
                    "isGranted" -> result.success(ScreenCapture.projection != null)
                    "capture" -> {
                        val png = ScreenCapture.capture()
                        if (png == null) {
                            result.error("NO_PROJECTION", "未授权屏幕捕获", null)
                        } else {
                            result.success(mapOf("png_base64" to android.util.Base64.encodeToString(png, android.util.Base64.NO_WRAP)))
                        }
                    }
                    "stop" -> {
                        ScreenCapture.stop()
                        stopService(Intent(this, PrivaGateService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var pendingPhotoResult: io.flutter.plugin.common.MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PHOTO) {
            val res = pendingPhotoResult
            pendingPhotoResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    val bmp = data.extras?.getParcelable<android.graphics.Bitmap>("data")
                    if (bmp != null) {
                        res?.success(mapOf(
                            "format" to "jpg",
                            "base64" to MediaTools.bitmapToPngBase64(bmp),
                        ))
                    } else {
                        res?.error("NO_IMAGE", "相机未返回图像", null)
                    }
                } catch (e: Throwable) {
                    res?.error("ERR", e.message ?: "拍照失败", null)
                }
            } else {
                res?.error("CANCELLED", "用户取消拍照", null)
            }
            return
        }
        if (requestCode == REQ_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                ScreenCapture.start(this, data)
            } else {
                // 用户拒绝授权 → 停掉 mediaProjection FGS
                stopService(Intent(this, PrivaGateService::class.java))
            }
        }
    }

    private fun startCaptureFgs() {
        val intent = Intent(this, PrivaGateService::class.java)
            .putExtra("media_projection", true)
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_SHIZUKU && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            // 已授权，无需额外处理
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
    }

    private fun maybeRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATION
                )
            }
        }
    }
}
