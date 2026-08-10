import 'package:flutter/material.dart';

/// Root 状态快照
class RootStatus {
  final bool isRooted;
  final String? suPath;
  final String? seLinux;

  const RootStatus({
    required this.isRooted,
    this.suPath,
    this.seLinux,
  });

  Map<String, dynamic> toJson() => {
        'is_rooted': isRooted,
        'su_path': suPath,
        'se_linux': seLinux,
      };
}

/// 命令执行结果
class ExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool truncated;

  const ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.truncated = false,
  });

  bool get isOk => exitCode == 0 && !timedOut;

  Map<String, dynamic> toJson() => {
        'exit_code': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'timed_out': timedOut,
        'truncated': truncated,
      };
}

/// 日志条目（UI 日志页用）
class LogEntry {
  final DateTime time;
  final String level; // info / success / error
  final String message;
  final String? detail;

  LogEntry(this.level, this.message, {this.detail, DateTime? time})
      : time = time ?? DateTime.now();

  factory LogEntry.info(String m, {String? detail}) =>
      LogEntry('info', m, detail: detail);
  factory LogEntry.success(String m, {String? detail}) =>
      LogEntry('success', m, detail: detail);
  factory LogEntry.error(String m, {String? detail}) =>
      LogEntry('error', m, detail: detail);
}

/// MCP 工具总数（首页/工具页展示用，实际按权限动态注册）
const int kToolCount = 74;

/// MCP 工具元信息（工具页展示用）
class McpToolInfo {
  final String name;
  final String description;
  final String example;
  final IconData icon;
  final Color color;
  final List<String> params;

  /// 需要的特殊权限：null=shell 工具、'accessibility'=无障碍、'capture'=屏幕捕获
  final String? requires;

  /// 最低 shell 权限级别：null=任意、'shizuku'=至少 shizuku、'root'=root/sui
  final String? minShell;

  const McpToolInfo({
    required this.name,
    required this.description,
    required this.example,
    required this.icon,
    required this.color,
    required this.params,
    this.requires,
    this.minShell,
  });
}
