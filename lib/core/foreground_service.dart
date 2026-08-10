import 'package:flutter/services.dart';

/// 与原生前台服务通信（保持进程存活）
class ForegroundService {
  static const _channel = MethodChannel('root_mcp/foreground');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      // 非 Android 环境或通道不可用时静默降级
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
