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

  /// 危险命令执行策略（由上层 AppState 同步；默认严格）
  DangerPolicy dangerPolicy = DangerPolicy.strict;

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
    // 高危命令拦截（可配置策略；绝对红线任何模式都拦）
    final danger = _guard(command);
    if (danger != null) {
      final blocked = danger.isAbsolute || dangerPolicy == DangerPolicy.strict;
      await AuditLog.append(
        command: command,
        asRoot: asRoot,
        exitCode: blocked ? -2 : 0,
        elapsedMs: 0,
        note: blocked
            ? 'blocked: ${danger.reason}'
            : 'danger-executed: ${danger.reason} (policy=${dangerPolicy.name})',
      );
      if (blocked) {
        return ExecResult(
          exitCode: -2,
          stdout: '',
          stderr: '🚫 高危命令已拦截（${danger.reason}）\n'
              '$command\n'
              '如需执行刷机/分区等操作，可在设置页将「危险命令策略」切为警告/关闭',
        );
      }
      // warn/off：放行，但结果头部加提示
      final r = await _runGuarded(command, asRoot: asRoot, timeout: timeout, cwd: cwd);
      return ExecResult(
        exitCode: r.exitCode,
        stdout: '⚠ 危险命令已放行（${danger.reason}，策略=${dangerPolicy.label}）\n'
            '${r.stdout}',
        stderr: r.stderr,
        timedOut: r.timedOut,
        truncated: r.truncated,
        originalLen: r.originalLen,
      );
    }
    return _runGuarded(command, asRoot: asRoot, timeout: timeout, cwd: cwd);
  }

  /// 实际执行（含审计），拦截检查通过后调用
  Future<ExecResult> _runGuarded(
    String command, {
    required bool asRoot,
    required Duration timeout,
    String? cwd,
  }) async {
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
  // 命中规则返回 (reason, isAbsolute)；
  //   isAbsolute=true  → 绝对红线，任何策略都拦截（删根目录/fork炸弹）
  //   isAbsolute=false → 可配置：strict 拦截，warn/off 放行但审计标记
  // 规则匹配「命令边界」，避免误伤正常命令（如 rm -rf /data/病毒目录）。
  static final List<(RegExp, String, bool)> _guardRules = [
    // 绝对红线
    (RegExp(r'(^|[;&|\s])rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/(\s|$|\*)'),
        '禁止删除根目录 /', true),
    (RegExp(r':\(\)\s*\{\s*:\|:&\s*\};:'), '禁止 fork 炸弹', true),
    // 可配置：关键分区根级删除（/data/具体路径不受限，可清病毒）
    (RegExp(
            r'(^|[;&|\s])rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/(data|system|vendor|cache|boot|etc|dev|proc|sys|product|apex)(\s|$|\*)'),
        '删除关键系统分区根目录', false),
    // 可配置：块设备直写 / 分区重写（刷机场景需要）
    (RegExp(r'(^|[;&|\s])dd\s+.*of=/dev/(sd|block|mmc|disk)\w*'),
        'dd 直接写入块设备', false),
    (RegExp(r'(^|[;&|\s])[^>]{0,60}>\s*/dev/(sd|block|mmc|disk)'),
        '重定向到块设备', false),
    // 可配置：格式化 / 分区工具
    (RegExp(r'(^|[;&|\s])(mkfs|mke2fs|mkfs\.\w+|fdisk|parted)\b'),
        '格式化/分区操作', false),
    (RegExp(r'(^|[;&|\s])format\b'), '格式化操作', false),
  ];

  /// 返回 null 表示放行；否则返回拦截信息
  static ({String reason, bool isAbsolute})? _guard(String command) {
    final c = command.trim();
    for (final (re, why, abs) in _guardRules) {
      if (re.hasMatch(c)) return (reason: why, isAbsolute: abs);
    }
    return null;
  }
}
