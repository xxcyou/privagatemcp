package com.sukishell.root_mcp

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.TrafficStats
import android.net.wifi.WifiManager
import android.nfc.NfcAdapter
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.core.content.ContextCompat
import android.telephony.TelephonyManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 设备工具：剪贴板/传感器/振动/流量/NFC/WiFi/蓝牙/电话 */
object DeviceTools {

    // ---------- 剪贴板 ----------

    fun clipboardGet(context: Context): String? {
        return try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString()
        } catch (_: Throwable) {
            null
        }
    }

    fun clipboardSet(context: Context, text: String): Boolean {
        return try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("rmcp", text))
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ---------- 传感器 ----------

    /** 读取一次传感器数据（加速度/光线/距离/陀螺仪等） */
    fun sensorRead(context: Context, type: String): Map<String, Any?>? {
        return try {
            val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val sensor = when (type) {
                "accelerometer" -> sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                "light" -> sm.getDefaultSensor(Sensor.TYPE_LIGHT)
                "proximity" -> sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)
                "gyroscope" -> sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
                "magnetic" -> sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                else -> sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            } ?: return null
            val latch = CountDownLatch(1)
            var values: FloatArray? = null
            val listener = object : SensorEventListener {
                override fun onSensorChanged(e: SensorEvent?) {
                    values = e?.values
                    latch.countDown()
                }
                override fun onAccuracyChanged(s: Sensor?, a: Int) {}
            }
            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            latch.await(2, TimeUnit.SECONDS)
            sm.unregisterListener(listener)
            values ?: return null
            val v = values!!
            mapOf(
                "sensor" to type,
                "values" to v.toList(),
                "timestamp" to System.currentTimeMillis(),
            )
        } catch (_: Throwable) {
            null
        }
    }

    // ---------- 振动 ----------

    fun vibrate(context: Context, ms: Int): Boolean {
        return try {
            val v = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createOneShot(ms.coerceIn(50, 10000).toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(ms.toLong())
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ---------- 流量统计 ----------

    /** 各应用流量（近 1 天，TrafficStats 从开机累计 → 返回累计值） */
    fun trafficStats(context: Context): List<Map<String, Any?>>? {
        return try {
            val pm = context.packageManager
            val apps = pm.getInstalledApplications(0)
            val out = mutableListOf<Map<String, Any?>>()
            for (app in apps) {
                try {
                    val rx = TrafficStats.getUidRxBytes(app.uid)
                    val tx = TrafficStats.getUidTxBytes(app.uid)
                    if (rx > 0 || tx > 0) {
                        out.add(mapOf(
                            "package" to app.packageName,
                            "rx_bytes" to rx,
                            "tx_bytes" to tx,
                        ))
                    }
                } catch (_: Throwable) {}
            }
            out.sortedByDescending { (it["rx_bytes"] as Long) + (it["tx_bytes"] as Long) }
                .take(20)
        } catch (_: Throwable) {
            null
        }
    }

    // ---------- NFC ----------

    fun nfcStatus(context: Context): Map<String, Any?> {
        val adapter = NfcAdapter.getDefaultAdapter(context)
        return mapOf(
            "available" to (adapter != null),
            "enabled" to (adapter?.isEnabled ?: false),
        )
    }

    // ---------- WiFi 扫描 ----------

    fun wifiScan(context: Context): List<Map<String, Any?>>? {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.NEARBY_WIFI_DEVICES)
                != PackageManager.PERMISSION_GRANTED) return null
        return try {
            val wm = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (!wm.isWifiEnabled) return emptyList()
            wm.startScan()
            Thread.sleep(800)
            wm.scanResults.map { r ->
                mapOf(
                    "ssid" to r.SSID,
                    "bssid" to r.BSSID,
                    "rssi" to r.level,
                    "frequency" to r.frequency,
                )
            }.sortedByDescending { it["rssi"] as Int }.take(30)
        } catch (_: Throwable) {
            null
        }
    }

    // ---------- 蓝牙扫描 ----------

    fun bluetoothScan(context: Context): List<Map<String, Any?>>? {
        if (Build.VERSION.SDK_INT >= 31 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN)
                != PackageManager.PERMISSION_GRANTED) return null
        return try {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return null
            if (!adapter.isEnabled) return emptyList()
            val results = mutableListOf<Map<String, Any?>>()
            val receiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(c: Context?, intent: Intent?) {
                    if (intent?.action == android.bluetooth.BluetoothDevice.ACTION_FOUND) {
                        val device = intent.getParcelableExtra<android.bluetooth.BluetoothDevice>(android.bluetooth.BluetoothDevice.EXTRA_DEVICE)
                        if (device != null) {
                            results.add(mapOf(
                                "name" to (device.name ?: "?"),
                                "address" to device.address,
                                "rssi" to intent.getShortExtra(android.bluetooth.BluetoothDevice.EXTRA_RSSI, 0),
                            ))
                        }
                    }
                }
            }
            context.registerReceiver(receiver, android.content.IntentFilter(android.bluetooth.BluetoothDevice.ACTION_FOUND))
            adapter.startDiscovery()
            Thread.sleep(4000)
            adapter.cancelDiscovery()
            context.unregisterReceiver(receiver)
            results.sortedByDescending { it["rssi"] as Short }.take(30)
        } catch (_: Throwable) {
            null
        }
    }

    // ---------- 电话 ----------

    fun phoneState(context: Context): Map<String, Any?>? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED) return null
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            mapOf(
                "network_type" to (if (Build.VERSION.SDK_INT >= 30) tm.dataNetworkType else tm.networkType),
                "sim_state" to tm.simState,
                "sim_operator" to tm.simOperatorName,
                "phone_type" to tm.phoneType,
                "is_roaming" to tm.isNetworkRoaming,
            )
        } catch (_: Throwable) {
            null
        }
    }

    /** 直接拨打电话（需要 CALL_PHONE 权限） */
    fun callDirect(context: Context, number: String): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED) return false
        return try {
            val intent = Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:$number"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 打开拨号界面（无需权限） */
    fun openDialer(context: Context, number: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:$number"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 电池信息（无需权限） */
    fun battery(context: Context): Map<String, Any?> {
        return try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            val level = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val status = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_STATUS)
            val charging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                status == android.os.BatteryManager.BATTERY_STATUS_FULL
            val statusLabel = when (status) {
                android.os.BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                android.os.BatteryManager.BATTERY_STATUS_FULL -> "full"
                android.os.BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
                android.os.BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not_charging"
                else -> "unknown"
            }
            mapOf(
                "level_percent" to level,
                "charging" to charging,
                "status" to statusLabel,
            )
        } catch (_: Throwable) {
            mapOf("error" to "battery unavailable")
        }
    }

    /** WiFi 状态（需 ACCESS_WIFI_STATE，SSID 需定位权限） */
    fun wifiStatus(context: Context): Map<String, Any?> {
        return try {
            val wm = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val info = wm.connectionInfo
            mapOf(
                "enabled" to wm.isWifiEnabled,
                "connected" to (info != null && info.networkId != -1),
                "ssid" to (info?.ssid?.removeSurrounding("\"") ?: ""),
                "bssid" to (info?.bssid ?: ""),
                "rssi_dbm" to (info?.rssi ?: -127),
                "link_speed_mbps" to (info?.linkSpeed ?: 0),
                "ip" to (if (info != null) android.text.format.Formatter.formatIpAddress(info.ipAddress) else ""),
            )
        } catch (_: Throwable) {
            mapOf("error" to "wifi unavailable")
        }
    }

    /** 蓝牙状态 + 已配对设备（需 BLUETOOTH_CONNECT） */
    fun bluetoothStatus(context: Context): Map<String, Any?> {
        return try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
                ?: return mapOf("supported" to false)
            val bonded = if (adapter.state == BluetoothAdapter.STATE_ON) {
                adapter.bondedDevices.map { mapOf("name" to (it.name ?: ""), "address" to it.address) }
            } else emptyList<Map<String, Any?>>()
            val stateLabel = when (adapter.state) {
                BluetoothAdapter.STATE_ON -> "on"
                BluetoothAdapter.STATE_TURNING_ON -> "turning_on"
                BluetoothAdapter.STATE_OFF -> "off"
                BluetoothAdapter.STATE_TURNING_OFF -> "turning_off"
                else -> "unknown"
            }
            mapOf(
                "supported" to true,
                "enabled" to (adapter.state == BluetoothAdapter.STATE_ON),
                "state" to stateLabel,
                "bonded_count" to bonded.size,
                "bonded" to bonded,
            )
        } catch (_: Throwable) {
            mapOf("error" to "bluetooth unavailable")
        }
    }
}
