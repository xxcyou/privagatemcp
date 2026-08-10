package com.privagatemcp

import android.app.Notification
import android.app.PendingIntent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** 通知读取服务：缓存活动通知，供 MCP 工具查询/操作 */
class PrivaGateNotificationListener : NotificationListenerService() {

    companion object {
        @Volatile
        var connected = false

        /** 当前活动通知快照（包名/标题/文本/时间/id） */
        @Volatile
        var snapshot: List<Map<String, Any?>> = emptyList()
    }

    override fun onListenerConnected() {
        connected = true
        refresh()
    }

    override fun onListenerDisconnected() {
        connected = false
        snapshot = emptyList()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        refresh()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        refresh()
    }


    private fun refresh() {
        try {
            val list = activeNotifications ?: return
            snapshot = list.mapNotNull { sbn ->
                try {
                    val n = sbn.notification
                    mapOf(
                        "key" to sbn.key,
                        "package" to sbn.packageName,
                        "id" to sbn.id,
                        "when" to sbn.postTime,
                        "title" to (n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""),
                        "text" to (n.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""),
                        "ticker" to (n.tickerText?.toString() ?: ""),
                    )
                } catch (_: Throwable) {
                    null
                }
            }
        } catch (_: Throwable) {}
    }

    /** 触发通知的点击意图（打开对应应用/界面） */
    fun openNotification(key: String): Boolean {
        val sbn = activeNotifications?.firstOrNull { it.key == key } ?: return false
        val pi: PendingIntent? = sbn.notification.contentIntent
        return try {
            pi?.send() != null
        } catch (_: Throwable) {
            false
        }
    }

    fun clearNotification(key: String): Boolean {
        return try {
            cancelNotification(key)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun clearAll(): Boolean {
        return try {
            cancelAllNotifications()
            true
        } catch (_: Throwable) {
            false
        }
    }
}
