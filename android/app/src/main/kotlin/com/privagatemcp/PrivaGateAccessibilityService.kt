package com.privagatemcp

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

/** 无障碍服务：读取 UI 结构 + 全局操作 + 模拟点击/滑动 */
class PrivaGateAccessibilityService : AccessibilityService() {

    companion object {
        var instance: PrivaGateAccessibilityService? = null
            private set

        private const val MAX_NODES = 400
        private val mainHandler = Handler(Looper.getMainLooper())

        fun dump(): String {
            val svc = instance ?: return """{"error":"无障碍服务未启用"}"""
            return try {
                val root = svc.rootInActiveWindow ?: return """{"error":"无法获取窗口内容"}"""
                val obj = JSONObject()
                nodeToJson(root, obj, 0)
                obj.toString()
            } catch (e: Throwable) {
                """{"error":"${e.message}"}"""
            }
        }

        private fun nodeToJson(node: AccessibilityNodeInfo, obj: JSONObject, depth: Int) {
            if (depth > 20) return
            obj.put("text", node.text?.toString())
            obj.put("desc", node.contentDescription?.toString())
            obj.put("cls", node.className?.toString()?.substringAfterLast('.') ?: "")
            obj.put("pkg", node.packageName?.toString())
            val b = Rect()
            node.getBoundsInScreen(b)
            obj.put("bounds", JSONArray(listOf(b.left, b.top, b.right, b.bottom)))
            obj.put("clickable", node.isClickable)
            obj.put("long_clickable", node.isLongClickable)
            obj.put("scrollable", node.isScrollable)
            obj.put("editable", node.isEditable)
            obj.put("checked", node.isChecked)
            obj.put("selected", node.isSelected)
            obj.put("focused", node.isFocused)
            obj.put("enabled", node.isEnabled)

            if (depth < 20) {
                val children = JSONArray()
                var count = 0
                for (i in 0 until node.childCount) {
                    val child = node.getChild(i) ?: continue
                    if (count >= MAX_NODES) break
                    val c = JSONObject()
                    nodeToJson(child, c, depth + 1)
                    children.put(c)
                    count++
                }
                if (children.length() > 0) obj.put("children", children)
            }
        }

        fun clickNode(text: String?, x: Float?, y: Float?, longClick: Boolean = false): Boolean {
            val svc = instance ?: return false
            return try {
                if (x != null && y != null) {
                    dispatchTap(svc, x, y, longClick)
                    true
                } else if (text != null) {
                    val root = svc.rootInActiveWindow ?: return false
                    val target = findNodeByText(root, text)
                    if (target != null) {
                        val rect = Rect()
                        target.getBoundsInScreen(rect)
                        target.recycle()
                        dispatchTap(svc, rect.centerX().toFloat(), rect.centerY().toFloat(), longClick)
                        true
                    } else {
                        // 文本不可点击时尝试父节点
                        val node = findNodeByText(root, text)
                        var n = node
                        var clicked = false
                        while (n != null && !clicked) {
                            if (n.isClickable) {
                                val r = Rect()
                                n.getBoundsInScreen(r)
                                dispatchTap(svc, r.centerX().toFloat(), r.centerY().toFloat(), longClick)
                                clicked = true
                            }
                            n = n.parent
                        }
                        node?.recycle()
                        clicked
                    }
                } else false
            } catch (e: Throwable) {
                false
            }
        }

        fun setText(text: String): Boolean {
            val svc = instance ?: return false
            return try {
                val root = svc.rootInActiveWindow ?: return false
                var node: AccessibilityNodeInfo? = null
                // 找已聚焦或可编辑节点
                node = findFocusedEditable(root)
                if (node == null) {
                    node = findFirstEditable(root)
                }
                if (node == null) return false
                val bundle = android.os.Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
                }
                val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, bundle)
                node.recycle()
                ok
            } catch (e: Throwable) {
                false
            }
        }

        fun globalAction(action: String): Boolean {
            val svc = instance ?: return false
            val map = mapOf(
                "back" to GLOBAL_ACTION_BACK,
                "home" to GLOBAL_ACTION_HOME,
                "recents" to GLOBAL_ACTION_RECENTS,
                "notifications" to GLOBAL_ACTION_NOTIFICATIONS,
                "quick_settings" to GLOBAL_ACTION_QUICK_SETTINGS,
                "power_dialog" to GLOBAL_ACTION_POWER_DIALOG,
            )
            val id = map[action] ?: return false
            return svc.performGlobalAction(id)
        }

        fun scroll(direction: String): Boolean {
            val svc = instance ?: return false
            val root = svc.rootInActiveWindow ?: return false
            var node = findScrollable(root)
            if (node == null) return false
            val action = if (direction == "backward") {
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            } else {
                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            }
            val ok = node.performAction(action)
            node.recycle()
            return ok
        }

        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, duration: Long): Boolean {
            val svc = instance ?: return false
            return try {
                val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
                val stroke = GestureDescription.StrokeDescription(path, 0, duration)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                svc.dispatchGesture(gesture, null, null)
                true
            } catch (e: Throwable) {
                false
            }
        }

        private fun dispatchTap(svc: AccessibilityService, x: Float, y: Float, longClick: Boolean) {
            val path = Path().apply { moveTo(x, y); lineTo(x + 0.5f, y + 0.5f) }
            val duration = if (longClick) 800L else 60L
            val stroke = GestureDescription.StrokeDescription(path, 0, duration)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            svc.dispatchGesture(gesture, null, null)
        }

        private fun findNodeByText(node: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
            val t = node.text?.toString() ?: ""
            val d = node.contentDescription?.toString() ?: ""
            if (t.contains(text, ignoreCase = true) || d.contains(text, ignoreCase = true)) {
                return AccessibilityNodeInfo.obtain(node)
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                val found = findNodeByText(child, text)
                if (found != null) return found
            }
            return null
        }

        private fun findFocusedEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.isFocused && node.isEditable) return AccessibilityNodeInfo.obtain(node)
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                val found = findFocusedEditable(child)
                if (found != null) return found
            }
            return null
        }

        private fun findFirstEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.isEditable) return AccessibilityNodeInfo.obtain(node)
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                val found = findFirstEditable(child)
                if (found != null) return found
            }
            return null
        }

        private fun findScrollable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.isScrollable) return AccessibilityNodeInfo.obtain(node)
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                val found = findScrollable(child)
                if (found != null) return found
            }
            return null
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}
}
