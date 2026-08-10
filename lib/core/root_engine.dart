import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'audit.dart';
import 'models.dart';

/// Root 引擎：探测 su（优先 SukiSU-Ultra / KernelSU 路径）并以 root 执行命令
/// 降级链：root su → sui su → shizuku → 本地 sh
class RootEngine {
  String? _suPath;
  String? _suiPath;
  String? _seLinux;
  bool _isRooted = false;
  bool _suiOk = false;

  /// Shizuku 执行器（由上层注入）
  Future<ExecResult> Function(String command, Duration timeout)?
      shizukuRunner;

  static const List<String> _suCandidates = [
    '/data/adb/ksu/bin/su', // SukiSU-Ultra / KernelSU
    '/data/adb/ap/bin/su', // APatch
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/su/bin/su',
    '/data/adb/magisk/busybox', // Magisk（最后兜底探测）
  ];

  static const String _suiBin = '/data/adb/sui/su'; // Sui

  bool get isRooted => _isRooted;
  bool get suiOk => _suiOk;
  String? get suPath => _suPath;
  String? get suiSuPath => _suiBin;

  RootStatus get status =>
      RootStatus(isRooted: _isRooted || _suiOk, suPath: _suPath ?? _suiPath, seLinux: _seLinux);

  /// 执行一次完整探测
  Future<RootStatus> check() async {
    _isRooted = false;
    _suPath = null;
    _suiOk = false;
    _seLinux = null;

    for (final cand in _suCandidates) {
      try {
        if (await File(cand).exists() && await _verify(cand)) {
          _suPath = cand;
          _isRooted = true;
          break;
        }
      } catch (_) {}
    }

    // 兜底：PATH 中的通用 su
    if (!_isRooted) {
      try {
        if (await _verify('su')) {
          _suPath = 'su';
          _isRooted = true;
        }
      } catch (_) {}
    }

    // Sui（/data/adb/sui/su）
    if (!_isRooted) {
      try {
        if (await File(_suiBin).exists() && await _verify(_suiBin)) {
          _suiOk = true;
        }
      } catch (_) {}
    }

    if (_isRooted || _suiOk) {
      try {
        final r = await run('getenforce',
            asRoot: true, timeout: const Duration(seconds: 8));
        _seLinux = r.stdout.trim();
      } catch (_) {}
    }
    return status;
  }

  Future<bool> _verify(String su) async {
    final r = await _runRaw(su, ['-c', 'id -u'], const Duration(seconds: 8));
    return r.exitCode == 0 && r.stdout.toString().trim() == '0';
  }

  Future<ProcessResult> _runRaw(String exe, List<String> args, Duration timeout) =>
      Process.run(exe, args).timeout(timeout);

  /// 执行 shell 命令；按降级链选择执行器
  /// asRoot=true：root su → sui su → shizuku → 失败提示
  Future<ExecResult> run(
    String command, {
    bool asRoot = true,
    Duration timeout = const Duration(seconds: 60),
    String? cwd,
  }) async {
    // 高危命令拦截（注入/破坏性命令，root 在手也不放行）
    final blocked = _guard(command);
    if (blocked != null) {
      await AuditLog.append(
        command: command,
        asRoot: asRoot,
        exitCode: -2,
        elapsedMs: 0,
        note: 'blocked: $blocked',
      );
      return ExecResult(
        exitCode: -2,
        stdout: '',
        stderr: '🚫 高危命令已拦截（$blocked）\n$command',
      );
    }

    final sw = Stopwatch()..start();
    var result = const ExecResult(exitCode: -1, stdout: '', stderr: '');
    try {
      if (asRoot) {
        if (_isRooted && _suPath != null) {
          result = await _exec(() => Process.run(_suPath!, ['-c', command],
              workingDirectory: cwd), timeout);
        } else if (_suiOk) {
          result = await _exec(() => Process.run(_suiBin, ['-c', command],
              workingDirectory: cwd), timeout);
        } else {
          final shizuku = shizukuRunner;
          if (shizuku != null) {
            result = await shizuku(command, timeout);
          } else {
            result = const ExecResult(
              exitCode: -1,
              stdout: '',
              stderr: '无可用权限：需要 root / sui / shizuku（设置页可开启）',
            );
          }
        }
      } else {
        result = await _exec(() => Process.run('sh', ['-c', command],
            workingDirectory: cwd), timeout);
      }
    } on TimeoutException {
      result = ExecResult(
        exitCode: -1,
        stdout: '',
        stderr: '⏱ 命令超时（${timeout.inSeconds}s）',
        timedOut: true,
      );
    } on ProcessException catch (e) {
      result = ExecResult(exitCode: -1, stdout: '', stderr: e.message);
    } finally {
      sw.stop();
      // 审计：每条执行命令落盘
      await AuditLog.append(
        command: command,
        asRoot: asRoot,
        exitCode: result.exitCode,
        elapsedMs: sw.elapsedMilliseconds,
        outLen: result.stdout.length,
        errLen: result.stderr.length,
        truncated: result.truncated,
      );
    }
    return result;
  }

  Future<ExecResult> _exec(
      Future<ProcessResult> Function() fn, Duration timeout) async {
    final r = await fn().timeout(timeout);
    return ExecResult(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  /// 启动交互式 root shell（供内置 ADB 使用）；无 root/sui 时返回 null
  Future<Process?> startRootShell([String command = 'sh']) async {
    try {
      if (_isRooted && _suPath != null) {
        return await Process.start(_suPath!, ['-c', command]);
      }
      if (_suiOk) {
        return await Process.start(_suiBin, ['-c', command]);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 读文件（root 场景走 shell cat）
  Future<ExecResult> readFile(String path, {bool asRoot = true}) {
    return run('cat ${sq(path)}',
        asRoot: asRoot, timeout: const Duration(seconds: 15));
  }

  /// 写文件（root/sui 场景经 su 的 stdin 管道，避免命令行长度限制）
  Future<ExecResult> writeFile(
    String path,
    String content, {
    bool asRoot = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final String? su = asRoot
          ? (_isRooted && _suPath != null
              ? _suPath
              : (_suiOk ? _suiPath : null))
          : null;
      final Process p = su != null
          ? await Process.start(su, ['-c', 'cat > ${sq(path)}'])
          : await Process.start('sh', ['-c', 'cat > ${sq(path)}']);
      p.stdin.add(utf8.encode(content));
      await p.stdin.close();
      final stdout = await p.stdout.transform(utf8.decoder).join();
      final stderr = await p.stderr.transform(utf8.decoder).join();
      final code = await p.exitCode.timeout(timeout);
      return ExecResult(exitCode: code, stdout: stdout, stderr: stderr);
    } on TimeoutException {
      return ExecResult(
          exitCode: -1, stdout: '', stderr: '⏱ 写入超时', timedOut: true);
    } on ProcessException catch (e) {
      return ExecResult(exitCode: -1, stdout: '', stderr: e.message);
    }
  }

  /// 列目录（原始 ls 输出，兼容 toybox）
  Future<ExecResult> listDir(String path, {bool asRoot = true}) {
    return run('ls -la ${sq(path)}',
        asRoot: asRoot, timeout: const Duration(seconds: 15));
  }

  /// shell 单引号转义（公开，供 MCP 层复用）
  static String sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

  // ── 高危命令拦截 ──────────────────────────────────────────────
  // 命中任一规则直接拒绝执行（root 在手也不放行），并写入审计。
  // 规则匹配「命令边界」，避免误伤正常调试命令（如 rm /data/local/tmp/x）。
  static final List<(RegExp, String)> _guardRules = [
    // 1. 删除根目录 / 或 /*
    (RegExp(r'(^|[;&|\s])rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/(\s|$|\*)'),
        '禁止删除根目录'),
    // 2. 删除关键分区根目录（/data /system /vendor /cache /boot /etc /dev /proc /sys /product /apex）
    (RegExp(
            r'(^|[;&|\s])rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/(data|system|vendor|cache|boot|etc|dev|proc|sys|product|apex)(\s|$|\*)'),
        '禁止删除关键系统分区'),
    // 3. 块设备直写 / 分区重写（dd 写 /dev/block 等）
    (RegExp(r'(^|[;&|\s])dd\s+.*of=/dev/(sd|block|mmc|disk)\w*'),
        '禁止直接写入块设备'),
    (RegExp(r'(^|[;&|\s])[^>]{0,60}>\s*/dev/(sd|block|mmc|disk)'),
        '禁止重定向到块设备'),
    // 4. 格式化 / 分区工具
    (RegExp(r'(^|[;&|\s])(mkfs|mke2fs|mkfs\.\w+|fdisk|parted)\b'),
        '禁止格式化/分区操作'),
    (RegExp(r'(^|[;&|\s])format\b'), '禁止格式化操作'),
    // 5. fork 炸弹
    (RegExp(r':\(\)\s*\{\s*:\|:&\s*\};:'), '禁止 fork 炸弹'),
  ];

  /// 返回 null 表示放行；否则返回被拦截的原因
  static String? _guard(String command) {
    final c = command.trim();
    for (final (re, why) in _guardRules) {
      if (re.hasMatch(c)) return why;
    }
    return null;
  }
}
