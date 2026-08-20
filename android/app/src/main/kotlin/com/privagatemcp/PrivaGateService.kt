package com.privagatemcp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/** 前台服务：保持 App 进程存活 + MediaProjection 会话要求 */
class PrivaGateService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val isCapture = intent?.getBooleanExtra("media_projection", false) == true
        // 尽早调用 startForeground()：服务被 startForegroundService() 启动后，系统要求
        // 在数秒内必须调用 startForeground()，否则抛
        // ForegroundServiceDidNotStartInTimeException（Android 13 上常见，MIUI 更严格）。
        try {
            startForegroundCompat(isCapture)
        } catch (e: Throwable) {
            // 任何 FGS 类型/权限校验失败：先退到最不严格的类型（type=0，仅 API<34 有效）再试一次；
            // 仍失败就 stopSelf，但保证 startForeground 一定被调用过，避免系统判定超时崩溃。
            try {
                ServiceCompat.startForeground(this, 1, buildNotification(isCapture), 0)
            } catch (_: Throwable) {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // 不自动重启：进程被杀后 Dart isolate 已销毁，避免“假在线”
        return START_NOT_STICKY
    }

    private fun startForegroundCompat(isCapture: Boolean) {
        val type = foregroundType(isCapture)
        if (Build.VERSION.SDK_INT >= 29) {
            // 类型必须在 manifest 的 foregroundServiceType 声明范围内，否则抛 SecurityException。
            ServiceCompat.startForeground(this, 1, buildNotification(isCapture), type)
        } else {
            startForeground(1, buildNotification(isCapture))
        }
    }

    private fun foregroundType(isCapture: Boolean): Int {
        return if (isCapture) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        } else if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+：常驻服务器用 specialUse，避免 dataSync 的 6 小时超时
            // （Android 15+ 的 dataSync FGS 超时未停止会抛
            //   ForegroundServiceDidNotStopInTimeException 直接崩溃）
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            // API < 34 无 specialUse 类型，dataSync 也无超时限制，可安全使用。
            // 注意：dataSync 必须同步声明在 manifest foregroundServiceType 中。
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
    }

    /**
     * Android 15+ 的 FGS 超时兑底：系统在超时前会回调此方法。
     * specialUse 无超时限制，但 mediaProjection 等类型可能触发；
     * 这里优雅停止而非让系统抛 ForegroundServiceDidNotStopInTimeException。
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        super.onTimeout(startId, fgsType)
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    private fun buildNotification(isCapture: Boolean): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                "mcp_server", "RootMCP", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持 MCP 服务器运行"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "mcp_server")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle(if (isCapture) "RootMCP 屏幕捕获中" else "RootMCP 正在运行")
            .setContentText(if (isCapture) "MediaProjection 会话进行中" else "MCP 服务器监听中 · 点击回到应用")
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }
}
