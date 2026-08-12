import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audit.dart';
import '../core/foreground_service.dart';
import '../core/models.dart';
import '../core/native_bridge.dart';
import '../core/permissions.dart';
import '../core/root_engine.dart';
import '../mcp/mcp_service.dart';

/// 全局应用状态
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  static const _kPort = 'port';
  static const _kToken = 'token';
  static const _kAutoStart = 'auto_start';
  static const _kThemeMode = 'theme_mode';
  static const _kThemeIndex = 'theme_index';
  static const _kDangerPolicy = 'danger_policy';
  static const _kAdbMemory = 'adb_memory';
  static const _kAdbWasEnabled = 'adb_was_enabled';

  final RootEngine engine = RootEngine();
  late final McpService mcp;

  SharedPreferences? _prefs;

  int port = 8787;
  String token = '';
  bool autoStart = false;

  /// 亮度模式：跟随系统 / 手动亮 / 手动暗
  ThemeMode themeMode = ThemeMode.dark;

  /// 配色方案下标（appThemeDefs）
  int themeIndex = 0;

  /// 危险命令执行策略（默认严格拦截）
  DangerPolicy dangerPolicy = DangerPolicy.strict;

  /// ADB 记忆开关：开启后下次启动 App 自动恢复 ADB 状态
  bool adbMemory = false;

  /// 上次 ADB 是否处于开启状态（配合 adbMemory 使用）
  bool adbWasEnabled = false;

  RootStatus? rootStatus;
  Permissions permissions = Permissions();
  bool checkingRoot = false;
  bool checkingPerms = false;
  bool serverStarting = false;
  bool adbEnabled = false;
  String adbStatusText = '未知';

  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => List.unmodifiable(_logs);

  AppState() {
    // Shizuku 执行器注入 Root 引擎（降级链第三级）
    engine.shizukuRunner = (cmd, timeout) =>
        NativeBridge.shizukuRun(cmd, timeout: timeout);
    mcp = McpService(
      engine: engine,
      getToken: () => token,
      onLog: addLog,
      onStatusChanged: notifyListeners,
      getPermissions: () => permissions,
      adbRunner: adbService,
    );
  }

  Future<void> init() async {
    await AuditLog.init();
    _prefs = await SharedPreferences.getInstance();
    port = _prefs!.getInt(_kPort) ?? 8787;
    token = _prefs!.getString(_kToken) ?? '';
    autoStart = _prefs!.getBool(_kAutoStart) ?? false;
    final tm = _prefs!.getString(_kThemeMode);
    themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    themeIndex = _prefs!.getInt(_kThemeIndex) ?? 0;
    dangerPolicy = DangerPolicy.values[(_prefs!.getInt(_kDangerPolicy) ?? 0)
        .clamp(0, DangerPolicy.values.length - 1)];
    engine.dangerPolicy = dangerPolicy;
    adbMemory = _prefs!.getBool(_kAdbMemory) ?? false;
    adbWasEnabled = _prefs!.getBool(_kAdbWasEnabled) ?? false;

    if (token.isEmpty) {
      token = _generateToken();
      await _prefs!.setString(_kToken, token);
    }

    addLog(LogEntry.info('App 初始化完成'));
    notifyListeners();

    if (autoStart) {
      await startServer();
    }

    // 启动自动检查权限（无需手动点检测）
    await refreshPermissions();
    await refreshAdbStatus();

    // ADB 记忆：开关打开且上次是开启状态 → 自动恢复（重启后 setprop 会丢失）
    if (adbMemory && adbWasEnabled && !adbEnabled) {
      addLog(LogEntry.info('ADB 记忆：自动恢复开启（上次为开启状态）'));
      await adbService('start');
    }

    // 监听生命周期：从后台/系统设置页/授权弹窗返回时自动刷新权限
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从系统设置页/授权弹窗返回 → 立即同步权限与 ADB 状态
      refreshPermissions();
      refreshAdbStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------- 权限 ----------------

  /// 检测全部权限：root / sui / shizuku / 无障碍 / 截屏
  Future<void> refreshPermissions() async {
    checkingPerms = true;
    notifyListeners();
    final rs = await engine.check();
    rootStatus = rs;
    final shizuku = await NativeBridge.shizukuAvailable();
    final shizukuGranted = await NativeBridge.shizukuGranted();
    final a11y = await NativeBridge.a11yEnabled();
    final capture = await NativeBridge.captureGranted();
    final extras = await NativeBridge.permsCheckAll();
    permissions = Permissions(
      root: engine.isRooted,
      sui: engine.suiOk,
      shizuku: shizuku && shizukuGranted,
      accessibility: a11y,
      capture: capture,
      fileAccess: extras['file_access'] == true,
      location: extras['location'] == true,
      overlay: extras['overlay'] == true,
      notifications: extras['notifications'] == true,
      camera: extras['camera'] == true,
      microphone: extras['microphone'] == true,
      sms: extras['sms'] == true,
      contacts: extras['contacts'] == true,
      callLog: extras['call_log'] == true,
      calendar: extras['calendar'] == true,
      usageStats: extras['usage_stats'] == true,
      ignoreBattery: extras['ignore_battery'] == true,
      allApps: extras['all_apps'] == true,
      phone: extras['phone'] == true,
      wifi: extras['wifi'] == true,
      bluetooth: extras['bluetooth'] == true,
      suPath: engine.suPath,
      suiPath: engine.suiSuPath,
    );
    checkingPerms = false;
    addLog(LogEntry.info(
        '权限检测完成：${permissions.shellLevel.label} · 扩展 ${permissions.extraCount} 项'));
    notifyListeners();
  }

  Future<void> requestShizuku() async {
    await NativeBridge.shizukuRequest();
    addLog(LogEntry.info('Shizuku 授权：请在系统弹窗确认'));
    // 轮询等待用户完成授权（弹窗异步）
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await NativeBridge.shizukuGranted()) break;
    }
    await refreshPermissions();
  }

  Future<void> openAccessibilitySettings() async {
    await NativeBridge.a11yOpenSettings();
    addLog(LogEntry.info('已打开无障碍设置页，开启 PrivaGate MCP 后返回并点“检测”'));
  }

  Future<void> requestScreenCapture() async {
    await NativeBridge.captureRequest();
    addLog(LogEntry.info('屏幕捕获：请在系统弹窗允许'));
    // 轮询等待用户完成授权
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await NativeBridge.captureGranted()) break;
    }
    await refreshPermissions();
  }

  // ---------------- ADB 服务（内置，root 模式） ----------------

  /// 查询 adb 状态并缓存到 UI
  Future<void> refreshAdbStatus() async {
    final r = await engine.run(
        'echo PORT=\$(getprop service.adb.tcp.port); '
        'echo ADBD=\$(ps -A | grep -c adbd)',
        asRoot: true,
        timeout: const Duration(seconds: 10));
    final out = r.stdout;
    final port = RegExp(r'PORT=(\d+)').firstMatch(out)?.group(1) ?? '0';
    final adbd = RegExp(r'ADBD=(\d+)').firstMatch(out)?.group(1) ?? '0';
    adbEnabled = port != '0' && adbd != '0';
    adbStatusText = '端口 $port · adbd ×$adbd';
    notifyListeners();
  }

  /// 控制系统 adbd：start=开启无线 adb（端口 5555），stop=关闭，status=查询
  /// 注意：开启会断开当前无线调试连接（电脑端需 adb connect 新端口）
  Future<ExecResult> adbService(String action) async {
    final cmd = switch (action) {
      'start' => 'setprop service.adb.tcp.port 5555; stop adbd; '
          'sleep 1; start adbd; sleep 2; '
          'echo PORT=\$(getprop service.adb.tcp.port); '
          'echo ADBD=\$(ps -A | grep -c adbd)',
      'stop' => 'setprop service.adb.tcp.port 0; stop adbd; '
          'sleep 1; start adbd; sleep 1; '
          'echo PORT=\$(getprop service.adb.tcp.port)',
      _ => 'getprop service.adb.tcp.port; '
          'echo ADBD=\$(ps -A | grep -c adbd)',
    };
    addLog(LogEntry.info('ADB 服务: $action'));
    final r = await engine.run(cmd,
        asRoot: true, timeout: const Duration(seconds: 30));
    addLog(r.isOk
        ? LogEntry.success('ADB $action 完成', detail: r.stdout.trim())
        : LogEntry.error('ADB $action 失败', detail: r.stderr.trim()));
    await refreshAdbStatus();
    // 记忆上次开关状态（配合「ADB 记忆」开关实现重启自动恢复）
    if (r.isOk && (action == 'start' || action == 'stop')) {
      adbWasEnabled = action == 'start';
      await _prefs?.setBool(_kAdbWasEnabled, adbWasEnabled);
    }
    return r;
  }

  /// ADB 记忆开关：开启后下次启动 App 自动恢复 ADB 状态
  Future<void> setAdbMemory(bool v) async {
    adbMemory = v;
    await _prefs?.setBool(_kAdbMemory, v);
    notifyListeners();
  }

  Future<void> requestLocationPerm() async {
    await NativeBridge.requestLocation();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  Future<void> requestAllFilesPerm() async {
    await NativeBridge.requestAllFiles();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  Future<void> requestOverlayPerm() async {
    await NativeBridge.requestOverlay();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  Future<void> requestNotificationAccessPerm() async {
    await NativeBridge.requestNotificationAccess();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  /// 批量请求运行时权限（系统弹窗）
  Future<void> requestRuntimePerms(List<String> perms) async {
    await NativeBridge.requestRuntime(perms);
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  /// 按工具 requires 键请求对应权限（工具页灰色卡片点击引导）
  Future<void> requestByRequires(String? requires) async {
    switch (requires) {
      case 'accessibility':
        await openAccessibilitySettings();
      case 'capture':
        await requestScreenCapture();
      case 'location':
        await requestLocationPerm();
      case 'notifications':
        await requestNotificationAccessPerm();
      case 'overlay':
        await requestOverlayPerm();
      case 'camera':
        await requestRuntimePerms(['android.permission.CAMERA']);
      case 'microphone':
        await requestRuntimePerms(['android.permission.RECORD_AUDIO']);
      case 'sms':
        await requestRuntimePerms(
            ['android.permission.READ_SMS', 'android.permission.SEND_SMS']);
      case 'contacts':
        await requestRuntimePerms(['android.permission.READ_CONTACTS']);
      case 'call_log':
        await requestRuntimePerms(['android.permission.READ_CALL_LOG']);
      case 'calendar':
        await requestRuntimePerms(['android.permission.READ_CALENDAR']);
      case 'usage_stats':
        await requestUsageStatsPerm();
      case 'phone':
        await requestRuntimePerms([
          'android.permission.CALL_PHONE',
          'android.permission.READ_PHONE_STATE',
        ]);
      case 'wifi':
        await requestRuntimePerms(['android.permission.NEARBY_WIFI_DEVICES']);
      case 'bluetooth':
        await requestRuntimePerms([
          'android.permission.BLUETOOTH_SCAN',
          'android.permission.BLUETOOTH_CONNECT',
        ]);
      default:
        break;
    }
  }

  Future<void> requestUsageStatsPerm() async {
    await NativeBridge.requestUsageStats();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  Future<void> requestIgnoreBatteryPerm() async {
    await NativeBridge.requestIgnoreBattery();
    await Future.delayed(const Duration(seconds: 1));
    await refreshPermissions();
  }

  // ---------------- Root ----------------

  Future<void> refreshRoot() async {
    checkingRoot = true;
    notifyListeners();
    rootStatus = await engine.check();
    checkingRoot = false;
    addLog(rootStatus!.isRooted
        ? LogEntry.success('Root 检测通过', detail: 'su: ${engine.suPath}')
        : LogEntry.error('未检测到 Root', detail: '请确认已刷 SukiSU-Ultra 并授权'));
    notifyListeners();
  }

  // ---------------- MCP Server ----------------

  Future<void> startServer() async {
    if (mcp.running || serverStarting) return;
    serverStarting = true;
    notifyListeners();
    try {
      if (rootStatus == null) {
        await refreshRoot();
      }
      await mcp.start(port);
      await ForegroundService.start();
    } catch (e) {
      addLog(LogEntry.error('启动服务器失败: $e'));
    } finally {
      serverStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    if (!mcp.running) return;
    await mcp.stop();
    await ForegroundService.stop();
    notifyListeners();
  }

  Future<void> setPort(int p) async {
    port = p;
    await _prefs?.setInt(_kPort, p);
    notifyListeners();
  }

  Future<void> setAutoStart(bool v) async {
    autoStart = v;
    await _prefs?.setBool(_kAutoStart, v);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs?.setString(_kThemeMode, m.name);
    notifyListeners();
  }

  Future<void> setThemeIndex(int i) async {
    themeIndex = i;
    await _prefs?.setInt(_kThemeIndex, i);
    notifyListeners();
  }

  Future<void> setDangerPolicy(DangerPolicy p) async {
    dangerPolicy = p;
    engine.dangerPolicy = p;
    await _prefs?.setInt(_kDangerPolicy, p.index);
    notifyListeners();
  }

  Future<void> regenerateToken() async {
    token = _generateToken();
    await _prefs?.setString(_kToken, token);
    addLog(LogEntry.info('Token 已重新生成'));
    notifyListeners();
  }

  // ---------------- 日志 ----------------

  void addLog(LogEntry entry) {
    _logs.insert(0, entry);
    if (_logs.length > 300) _logs.removeRange(300, _logs.length);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  static String _generateToken() {
    final rand = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
