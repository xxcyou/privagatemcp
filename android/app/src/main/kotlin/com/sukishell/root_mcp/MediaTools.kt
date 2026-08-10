package com.sukishell.root_mcp

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaRecorder
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File

/** 媒体工具：拍照 / 录音（base64 返回） */
object MediaTools {

    /** 录音 N 秒 → m4a base64（需要麦克风权限） */
    fun record(context: Context, seconds: Int): Map<String, Any?>? {
        if (!(PermHelper.checkAll(context)["microphone"] as Boolean)) return null
        val file = File(context.cacheDir, "rmcp_rec_${System.currentTimeMillis()}.m4a")
        val recorder = MediaRecorder()
        return try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            Thread.sleep((seconds.coerceIn(1, 60) * 1000).toLong())
            recorder.stop()
            val bytes = file.readBytes()
            file.delete()
            mapOf(
                "format" to "m4a",
                "duration_s" to seconds,
                "size_bytes" to bytes.size,
                "base64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
            )
        } catch (e: Throwable) {
            try { recorder.release() } catch (_: Throwable) {}
            file.delete()
            null
        } finally {
            try { recorder.release() } catch (_: Throwable) {}
        }
    }

    /** Bitmap → PNG base64 */
    fun bitmapToPngBase64(bmp: Bitmap): String {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}
