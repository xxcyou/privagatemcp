package com.sukishell.root_mcp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** MediaProjection 屏幕捕获：单帧 PNG 截图（需先授权） */
object ScreenCapture {
    var projection: MediaProjection? = null
        private set

    private var appContext: Context? = null
    private val handler = Handler(Looper.getMainLooper())

    fun start(context: Context, resultData: Intent) {
        stop()
        appContext = context.applicationContext
        val mgr = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        projection = mgr.getMediaProjection(Activity.RESULT_OK, resultData)?.apply {
            // Android 14+ 要求：createVirtualDisplay 前必须注册 callback
            registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    projection = null
                }
            }, handler)
        }
    }

    fun stop() {
        try {
            projection?.stop()
        } catch (_: Throwable) {}
        projection = null
    }

    /** 捕获一帧并编码为 PNG；失败返回 null */
    fun capture(): ByteArray? {
        val proj = projection ?: return null
        val ctx = appContext ?: return null
        return try {
            val metrics = DisplayMetrics()
            val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
            wm.defaultDisplay.getRealMetrics(metrics)
            val width = metrics.widthPixels
            val height = metrics.heightPixels
            val density = metrics.densityDpi

            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            val vd = proj.createVirtualDisplay(
                "rmcp-capture",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, handler
            ) ?: return null

            val latch = CountDownLatch(1)
            var image: Image? = null
            handler.post {
                image = try {
                    reader.acquireLatestImage()
                } catch (_: Throwable) {
                    null
                }
                latch.countDown()
            }
            val got = latch.await(800, TimeUnit.MILLISECONDS)
            var result: ByteArray? = null
            val img = if (got) image else null
            if (img != null) {
                try {
                    val planes = img.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * width
                    val bmp = Bitmap.createBitmap(
                        width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888
                    )
                    bmp.copyPixelsFromBuffer(buffer)
                    val cropped = Bitmap.createBitmap(bmp, 0, 0, width, height)
                    val out = ByteArrayOutputStream()
                    cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
                    result = out.toByteArray()
                    cropped.recycle()
                    bmp.recycle()
                } finally {
                    img.close()
                }
            }
            try {
                vd.release()
            } catch (_: Throwable) {}
            try {
                reader.close()
            } catch (_: Throwable) {}
            result
        } catch (e: Throwable) {
            null
        }
    }
}
