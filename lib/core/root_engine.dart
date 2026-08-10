import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    try {
      if (asRoot) {
        if (_isRooted && _suPath != null) {
          return _exec(() => Process.run(_suPath!, ['-c', command],
              workingDirectory: cwd), timeout);
        }
        if (_suiOk) {
          return _exec(() => Process.run(_suiBin, ['-c', command],
              workingDirectory: cwd), timeout);
        }
        final shizuku = shizukuRunner;
        if (shizuku != null) {
          return await shizuku(command, timeout);
        }
        return const ExecResult(
          exitCode: -1,
          stdout: '',
          stderr: '无可用权限：需要 root / sui / shizuku（设置页可开启）',
        );
      }
      return _exec(() => Process.run('sh', ['-c', command],
          workingDirectory: cwd), timeout);
    } on TimeoutException {
      return ExecResult(
        exitCode: -1,
        stdout: '',
        stderr: '⏱ 命令超时（${timeout.inSeconds}s）',
        timedOut: true,
      );
    } on ProcessException catch (e) {
      return ExecResult(exitCode: -1, stdout: '', stderr: e.message);
    }
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
}
