package com.privagatemcp

import android.util.Log
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * 局域网广播发现：周期性向 255.255.255.255:53001 广播 MCP 连接信息
 * （IP/端口/token），让 NAS 端监听脚本自动发现，无需手动报地址。
 *
 * - 广播包不含敏感扩展信息之外的字段，token 是局域网内可控暴露（设置可关）
 * - 收到 NAS 的发现请求（REQ_MAGIC）→ 立即单播完整信息回源地址
 * - IP 变化时由 Dart 层调用 update()，立即重播
 */
object McpDiscovery {
    private const val TAG = "McpDiscovery"
    private const val PORT = 53001
    private const val MAGIC = "PRIVAGATE_MCP"
    private const val REQ_MAGIC = "PRIVAGATE_MCP_REQ"
    private const val BROADCAST_INTERVAL_MS = 15_000L
    private const val RECV_TIMEOUT_MS = 1_000

    private val lock = Any()
    private var thread: Thread? = null
    private var socket: DatagramSocket? = null
    @Volatile
    private var enabled = false
    @Volatile
    private var infoJson: String? = null
    @Volatile
    private var running = false

    /** 开启广播。info 为 JSON 字符串：{ip, port, token, version, name} */
    fun start(info: String) {
        synchronized(lock) {
            infoJson = info
            enabled = true
            if (running) {
                // 已运行：立即重播一次
                broadcastOnce()
                return
            }
            running = true
            thread = Thread({
                runLoop()
            }, "mcp-discovery").apply { isDaemon = true }
            thread?.start()
        }
    }

    /** 更新信息（如 IP 变化）并立即重播 */
    fun update(info: String) {
        synchronized(lock) {
            infoJson = info
            if (running) broadcastOnce()
        }
    }

    /** 停止广播 */
    fun stop() {
        synchronized(lock) {
            enabled = false
            running = false
            try {
                socket?.close()
            } catch (_: Throwable) {
            }
            socket = null
            thread?.interrupt()
            thread = null
        }
    }

    private fun runLoop() {
        var sock: DatagramSocket? = null
        try {
            // 必须 bind 53001 才能收到 NAS 的发现请求（REQ 目标端口 53001）
            sock = DatagramSocket(null)
            sock.reuseAddress = true
            sock.broadcast = true
            sock.soTimeout = RECV_TIMEOUT_MS
            sock.bind(java.net.InetSocketAddress("0.0.0.0", PORT))
            synchronized(lock) { socket = sock }
            var lastBroadcast = 0L
            while (running && enabled) {
                val now = System.currentTimeMillis()
                if (now - lastBroadcast >= BROADCAST_INTERVAL_MS) {
                    lastBroadcast = now
                    broadcastOnce()
                }
                // 监听发现请求（阻塞最多 1s，以便检查退出标志）
                try {
                    val buf = ByteArray(1024)
                    val pkt = DatagramPacket(buf, buf.size)
                    sock.receive(pkt)
                    val text = String(pkt.data, 0, pkt.length, Charsets.UTF_8)
                    if (text.contains(REQ_MAGIC)) {
                        replyTo(pkt.address, pkt.port)
                    }
                } catch (e: java.net.SocketTimeoutException) {
                    // 正常：继续循环
                } catch (e: Exception) {
                    if (running) {
                        Log.w(TAG, "recv error: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "discovery loop error: ${e.message}")
        } finally {
            try {
                sock?.close()
            } catch (_: Throwable) {
            }
            synchronized(lock) { socket = null }
        }
    }

    private fun broadcastOnce() {
        val info = infoJson ?: return
        try {
            val s = socket
            if (s == null || s.isClosed) return
            val data = info.toByteArray(Charsets.UTF_8)
            s.send(DatagramPacket(
                data, data.size,
                InetAddress.getByName("255.255.255.255"), PORT))
        } catch (e: Exception) {
            Log.d(TAG, "broadcast error: ${e.message}")
        }
    }

    /** 收到 NAS 请求 → 单播完整信息给请求方 */
    private fun replyTo(addr: InetAddress, port: Int) {
        val info = infoJson ?: return
        try {
            val s = socket ?: return
            val data = info.toByteArray(Charsets.UTF_8)
            s.send(DatagramPacket(data, data.size, addr, port))
        } catch (e: Exception) {
            Log.d(TAG, "reply error: ${e.message}")
        }
    }

    /** 组装广播 JSON */
    fun buildInfo(ip: String, port: Int, token: String, version: String): String {
        val obj = JSONObject()
        obj.put("magic", MAGIC)
        obj.put("name", "PrivaGate-MCP")
        obj.put("ip", ip)
        obj.put("port", port)
        obj.put("token", token)
        obj.put("version", version)
        obj.put("ts", System.currentTimeMillis() / 1000)
        return obj.toString()
    }
}
