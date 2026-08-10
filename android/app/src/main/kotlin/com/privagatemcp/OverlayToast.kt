package com.privagatemcp

import android.content.Context
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView

/** 悬浮窗：在屏幕上显示一行文字，N 秒后自动消失（需要悬浮窗权限） */
object OverlayToast {
    private var view: TextView? = null

    fun show(context: Context, text: String, seconds: Int): Boolean {
        if (!PermHelper.isOverlayGranted(context)) return false
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        hide(wm)
        val tv = TextView(context).apply {
            this.text = text
            setTextColor(android.graphics.Color.WHITE)
            textSize = 15f
            setPadding(48, 28, 48, 28)
            setBackgroundColor(0xCC10141F.toInt())
            alpha = 0.95f
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 240
        }
        return try {
            wm.addView(tv, params)
            view = tv
            Handler(Looper.getMainLooper()).postDelayed({
                hide(wm)
            }, (seconds.coerceAtLeast(1) * 1000).toLong())
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun hide(wm: WindowManager) {
        view?.let {
            try {
                wm.removeView(it)
            } catch (_: Throwable) {}
        }
        view = null
    }
}
