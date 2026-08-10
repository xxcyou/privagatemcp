import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 命令审计日志：每次 shell/root 执行落盘，便于排查 AI 到底执行了什么。
///
/// 文件：<应用支持目录>/audit.log，每行一条 JSON。
/// 超过 [maxBytes] 自动轮转到 audit.log.1 并清空主文件。
class AuditLog {
  static File? _file;
  static const int maxBytes = 1024 * 1024; // 1MB

  /// 初始化（需在 runApp 前或 AppState.init 调用）
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/audit.log');
    } catch (_) {
      // 非 Android / 异常时降级到系统临时目录，保证不崩
      _file = File('${Directory.systemTemp.path}/priva_audit.log');
    }
  }

  /// 追加一条审计记录（JSON 单行）
  static Future<void> append({
    required String command,
    required bool asRoot,
    required int exitCode,
    required int elapsedMs,
    int outLen = 0,
    int errLen = 0,
    bool truncated = false,
    String? note,
  }) async {
    final f = _file;
    if (f == null) return;
    try {
      final entry = jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'as_root': asRoot,
        'cmd': command,
        'exit': exitCode,
        'ms': elapsedMs,
        'out_len': outLen,
        'err_len': errLen,
        'truncated': truncated,
        'note': ?note,
      });
      await f.writeAsString('$entry\n', mode: FileMode.append);
      // 轮转：超限时把当前内容挪到 .1，主文件清空
      if (await f.length() > maxBytes) {
        final bak = File('${f.path}.1');
        await bak.writeAsString(await f.readAsString());
        await f.writeAsString('');
      }
    } catch (_) {
      // 审计失败不影响主流程
    }
  }

  /// 读取最近 [tail] 条审计记录
  static Future<String> read({int tail = 50}) async {
    final f = _file;
    if (f == null || !await f.exists()) return '(审计日志为空)';
    try {
      final lines =
          (await f.readAsString()).trimRight().split('\n').where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) return '(审计日志为空)';
      if (lines.length <= tail) return lines.join('\n');
      return '...[共 ${lines.length} 条，显示最近 $tail 条]\n'
          '${lines.sublist(lines.length - tail).join('\n')}';
    } catch (_) {
      return '(读取审计日志失败)';
    }
  }

  static String? get path => _file?.path;
}
