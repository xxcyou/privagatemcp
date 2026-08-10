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
        val type = if (isCapture) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                ServiceCompat.startForeground(this, 1, buildNotification(isCapture), type)
            } else {
                startForeground(1, buildNotification(isCapture))
            }
        } catch (e: Throwable) {
            // FGS 类型权限校验失败时兜底，避免进程崩溃
            stopSelf()
            return START_NOT_STICKY
        }
        // 不自动重启：进程被杀后 Dart isolate 已销毁，避免“假在线”
        return START_NOT_STICKY
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
