import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';

/// 原生能力桥：Shizuku / 无障碍 / 屏幕捕获
class NativeBridge {
  static const _shizuku = MethodChannel('privagate/shizuku');
  static const _a11y = MethodChannel('privagate/a11y');
  static const _capture = MethodChannel('privagate/capture');
  static const _perms = MethodChannel('privagate/permissions');
  static const _location = MethodChannel('privagate/location');
  static const _notifications = MethodChannel('privagate/notifications');
  static const _overlay = MethodChannel('privagate/overlay');
  static const _media = MethodChannel('privagate/media');
  static const _data = MethodChannel('privagate/data');
  static const _device = MethodChannel('privagate/device');

  // ---------- Shizuku ----------

  static Future<bool> shizukuAvailable() async {
    try {
      return await _shizuku.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> shizukuGranted() async {
    try {
      return await _shizuku.invokeMethod<bool>('isGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 弹出 Shizuku 授权框（系统对话框）
  static Future<bool> shizukuRequest() async {
    try {
      return await _shizuku.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 经 Shizuku 执行命令（shell uid）
  static Future<ExecResult> shizukuRun(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final r = await _shizuku
          .invokeMethod<Map<dynamic, dynamic>>(
              'runCommand', {'command': command})
          .timeout(timeout);
      if (r == null) {
        return const ExecResult(exitCode: -1, stdout: '', stderr: 'Shizuku 无响应');
      }
      return ExecResult(
        exitCode: (r['exit_code'] as num?)?.toInt() ?? -1,
        stdout: (r['stdout'] as String?) ?? '',
        stderr: (r['stderr'] as String?) ?? '',
      );
    } on TimeoutException {
      return ExecResult(
          exitCode: -1, stdout: '', stderr: '⏱ Shizuku 命令超时', timedOut: true);
    } on PlatformException catch (e) {
      return ExecResult(exitCode: -1, stdout: '', stderr: e.message ?? 'Shizuku 错误');
    }
  }

  // ---------- 无障碍 ----------

  static Future<bool> a11yEnabled() async {
    try {
      return await _a11y.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> a11yDump() async {
    try {
      return await _a11y.invokeMethod<String>('dump') ?? '{"error":"无响应"}';
    } catch (e) {
      return '{"error":"$e"}';
    }
  }

  static Future<bool> a11yClick({
    String? text,
    double? x,
    double? y,
    bool longClick = false,
  }) async {
    try {
      return await _a11y.invokeMethod<bool>('click', {
            'text': ?text,
            'x': ?x,
            'y': ?y,
            'long': longClick,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> a11ySetText(String text) async {
    try {
      return await _a11y.invokeMethod<bool>('setText', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> a11yGlobal(String action) async {
    try {
      return await _a11y.invokeMethod<bool>('global', {'action': action}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> a11yScroll(String direction) async {
    try {
      return await _a11y.invokeMethod<bool>('scroll', {'direction': direction}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> a11ySwipe(
      double x1, double y1, double x2, double y2, int duration) async {
    try {
      return await _a11y.invokeMethod<bool>('swipe', {
            'x1': x1,
            'y1': y1,
            'x2': x2,
            'y2': y2,
            'duration': duration,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> a11yOpenSettings() async {
    try {
      return await _a11y.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- 屏幕捕获 ----------

  static Future<bool> captureRequest() async {
    try {
      return await _capture.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> captureGranted() async {
    try {
      return await _capture.invokeMethod<bool>('isGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 捕获一帧，返回 PNG base64；失败返回 null
  static Future<String?> capturePng() async {
    try {
      final r = await _capture
          .invokeMethod<Map<dynamic, dynamic>>('capture')
          .timeout(const Duration(seconds: 10));
      return r?['png_base64'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> captureStop() async {
    try {
      await _capture.invokeMethod('stop');
    } catch (_) {}
  }
  // ---------- 扩展权限（文件/定位/悬浮窗/通知） ----------

  static Future<Map<String, dynamic>> permsCheckAll() async {
    try {
      final r = await _perms.invokeMethod<Map<dynamic, dynamic>>('checkAll');
      return (r ?? {}).map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) {
      return {};
    }
  }

  static Future<void> requestLocation() async {
    try { await _perms.invokeMethod('requestLocation'); } catch (_) {}
  }

  static Future<void> requestAllFiles() async {
    try { await _perms.invokeMethod('requestAllFiles'); } catch (_) {}
  }

  static Future<void> requestOverlay() async {
    try { await _perms.invokeMethod('requestOverlay'); } catch (_) {}
  }

  static Future<void> requestNotificationAccess() async {
    try { await _perms.invokeMethod('requestNotificationAccess'); } catch (_) {}
  }

  // ---------- 定位 ----------

  static Future<Map<String, dynamic>?> locationGet() async {
    try {
      final r = await _location.invokeMethod<Map<dynamic, dynamic>>('get');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) {
      return null;
    }
  }

  // ---------- 通知读取 ----------

  static Future<bool> notificationsConnected() async {
    try {
      return await _notifications.invokeMethod<bool>('isConnected') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> notificationsList() async {
    try {
      final r = await _notifications.invokeMethod<List<dynamic>>('list');
      return (r ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v as dynamic)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> notificationOpen(String key) async {
    try {
      return await _notifications.invokeMethod<bool>('open', {'key': key}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> notificationClear(String key) async {
    try {
      return await _notifications.invokeMethod<bool>('clear', {'key': key}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> notificationClearAll() async {
    try {
      return await _notifications.invokeMethod<bool>('clearAll') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- 悬浮窗 ----------

  static Future<bool> overlayShow(String text, int seconds) async {
    try {
      return await _overlay.invokeMethod<bool>('show', {'text': text, 'seconds': seconds}) ?? false;
    } catch (_) {
      return false;
    }
  }
  // ---------- 媒体（相机/麦克风） ----------

  static Future<Map<String, dynamic>?> cameraPhoto() async {
    try {
      final r = await _media.invokeMethod<Map<dynamic, dynamic>>('photo');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> audioRecord(int seconds) async {
    try {
      final r = await _media
          .invokeMethod<Map<dynamic, dynamic>>('record', {'seconds': seconds});
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) {
      return null;
    }
  }

  // ---------- 数据（短信/通讯录/通话/日历/使用统计） ----------

  static Future<List<Map<String, dynamic>>?> dataCall(String method, Map<String, dynamic> args) async {
    try {
      final r = await _data.invokeMethod<List<dynamic>>(method, args);
      return (r ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v as dynamic)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> smsSend(String number, String text) async {
    try {
      return await _data.invokeMethod<bool>('smsSend', {'number': number, 'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>?> smsThreads(int limit) =>
      dataCall('smsThreads', {'limit': limit});

  static Future<bool> smsDelete({int? id, String? number}) async {
    try {
      return await _data.invokeMethod<bool>('smsDelete', {'id': id, 'number': number}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> smsMarkRead({int? id}) async {
    try {
      return await _data.invokeMethod<bool>('smsMarkRead', {'id': id}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> contactAdd(String name, String number) async {
    try {
      return await _data.invokeMethod<bool>('contactAdd', {'name': name, 'number': number}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> contactUpdate(int contactId, {String? name, String? number}) async {
    try {
      return await _data.invokeMethod<bool>(
              'contactUpdate', {'contactId': contactId, 'name': name, 'number': number}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> contactDelete(int contactId) async {
    try {
      return await _data.invokeMethod<bool>('contactDelete', {'contactId': contactId}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> callLogDelete({int? id, String? number, bool all = false}) async {
    try {
      return await _data.invokeMethod<bool>(
              'callLogDelete', {'id': id, 'number': number, 'all': all}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> calendarAdd({
    required String title,
    required int startMs,
    required int endMs,
    String? description,
  }) async {
    try {
      return await _data.invokeMethod<bool>('calendarAdd', {
        'title': title,
        'startMs': startMs,
        'endMs': endMs,
        'description': description,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> calendarDelete(int id) async {
    try {
      return await _data.invokeMethod<bool>('calendarDelete', {'id': id}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- 扩展权限请求 ----------

  static Future<void> requestRuntime(List<String> perms) async {
    try { await _perms.invokeMethod('requestRuntime', {'permissions': perms}); } catch (_) {}
  }

  static Future<void> requestUsageStats() async {
    try { await _perms.invokeMethod('requestUsageStats'); } catch (_) {}
  }

  static Future<void> requestIgnoreBattery() async {
    try { await _perms.invokeMethod('requestIgnoreBattery'); } catch (_) {}
  }
  // ---------- 设备（剪贴板/传感器/振动/流量/NFC/WiFi/蓝牙/电话） ----------

  static Future<String?> clipboardGet() async {
    try { return await _device.invokeMethod<String>('clipboardGet'); } catch (_) { return null; }
  }

  static Future<bool> clipboardSet(String text) async {
    try { return await _device.invokeMethod<bool>('clipboardSet', {'text': text}) ?? false; } catch (_) { return false; }
  }

  static Future<Map<String, dynamic>?> sensorRead(String type) async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('sensorRead', {'type': type});
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<bool> vibrate(int ms) async {
    try { return await _device.invokeMethod<bool>('vibrate', {'ms': ms}) ?? false; } catch (_) { return false; }
  }

  static Future<List<Map<String, dynamic>>?> trafficStats() async {
    try {
      final r = await _device.invokeMethod<List<dynamic>>('traffic');
      return (r ?? []).whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v as dynamic))).toList();
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> nfcStatus() async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('nfcStatus');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> batteryStatus() async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('battery');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> wifiStatus() async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('wifiStatus');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> bluetoothStatus() async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('bluetoothStatus');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  /// 连续定位采样：count 次间隔 intervalMs，返回全部采样 + 精度最优值
  static Future<Map<String, dynamic>?> locationWatch({int count = 5, int intervalMs = 1000}) async {
    try {
      final r = await _location.invokeMethod<Map<dynamic, dynamic>>(
          'watch', {'count': count, 'intervalMs': intervalMs});
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<List<Map<String, dynamic>>?> wifiScan() async {
    try {
      final r = await _device.invokeMethod<List<dynamic>>('wifiScan');
      return (r ?? []).whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v as dynamic))).toList();
    } catch (_) { return null; }
  }

  static Future<List<Map<String, dynamic>>?> bluetoothScan() async {
    try {
      final r = await _device.invokeMethod<List<dynamic>>('bluetoothScan');
      return (r ?? []).whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v as dynamic))).toList();
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> phoneState() async {
    try {
      final r = await _device.invokeMethod<Map<dynamic, dynamic>>('phoneState');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v as dynamic));
    } catch (_) { return null; }
  }

  static Future<bool> callDirect(String number) async {
    try { return await _device.invokeMethod<bool>('callDirect', {'number': number}) ?? false; } catch (_) { return false; }
  }

  static Future<bool> openDialer(String number) async {
    try { return await _device.invokeMethod<bool>('openDialer', {'number': number}) ?? false; } catch (_) { return false; }
  }
}

