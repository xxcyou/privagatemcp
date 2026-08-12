import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mcp_dart/mcp_dart.dart';

import '../core/audit.dart';
import '../core/models.dart';
import '../core/native_bridge.dart';
import '../core/permissions.dart';
import '../core/root_engine.dart';

class _McpSession {
  final McpServer server;
  final StreamableHTTPServerTransport transport;

  _McpSession(this.server, this.transport);
}

/// MCP 服务器：Streamable HTTP + Bearer Token 鉴权 + root 工具
class McpService {
  final RootEngine engine;
  final String Function() getToken;
  final void Function(LogEntry) onLog;
  final void Function() onStatusChanged;
  final Permissions Function() getPermissions;

  /// ADB 服务执行器（由上层注入，执行后自动同步 UI 状态）
  final Future<ExecResult> Function(String action)? adbRunner;

  HttpServer? _httpServer;
  final Map<String, _McpSession> _sessions = {};
  final List<StreamSubscription> _subs = [];

  bool _running = false;
  int _port = 8787;
  String? _lanIp;
  List<String> _lanIps = [];
  int _callCount = 0;

  /// 局域网 IP 定时刷新（IP 变更实时同步到 UI / allowedHosts）
  Timer? _ipTimer;

  McpService({
    required this.engine,
    required this.getToken,
    required this.onLog,
    required this.onStatusChanged,
    required this.getPermissions,
    this.adbRunner,
  });

  bool get running => _running;
  int get port => _port;
  String? get lanIp => _lanIp;
  int get callCount => _callCount;

  Set<String> get _allowedHosts =>
      {..._lanIps, 'localhost', '127.0.0.1', '::1'};

  Future<void> start(int port) async {
    if (_running) return;
    _port = port;
    await _collectIps();

    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _subs.add(_httpServer!.listen(_handleRequest));
    _running = true;
    // 每 5 秒刷新一次局域网 IP：WiFi/蜂窝切换、DHCP 变更时实时更新
    _ipTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => refreshIps());
    onLog(LogEntry.success('MCP 服务器已启动', detail: '端口 $port · IP ${_lanIp ?? '-'}'));
    onStatusChanged();
  }

  Future<void> stop() async {
    if (!_running) return;
    _ipTimer?.cancel();
    _ipTimer = null;
    for (final s in _sessions.values) {
      try {
        await s.transport.close();
      } catch (_) {}
      try {
        await s.server.close();
      } catch (_) {}
    }
    _sessions.clear();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _httpServer?.close(force: true);
    } catch (_) {}
    _httpServer = null;
    _running = false;
    onLog(LogEntry.info('MCP 服务器已停止'));
    onStatusChanged();
  }

  /// 重新收集局域网 IP；发生变化时通知 UI 刷新
  Future<void> refreshIps() async {
    final before = _lanIp;
    await _collectIps();
    if (before != _lanIp) {
      onLog(LogEntry.info('局域网 IP 变更: ${before ?? '-'} → ${_lanIp ?? '-'}'));
      onStatusChanged();
    }
  }

  Future<void> _collectIps() async {
    final ips = <String, String>{}; // ip -> 接口名
    try {
      final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final i in ifs) {
        final name = i.name.toLowerCase();
        // 跳过虚拟隧道/拨号接口，避免把 VPN 等地址当成局域网 IP
        if (name.contains('tun') || name.contains('ppp') ||
            name.contains('vpn') || name.contains('dummy')) {
          continue;
        }
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          ips[ip] = name;
        }
      }
    } catch (_) {}
    final sorted = ips.keys.toList()
      ..sort((a, b) =>
          _ipScore(a, ips[a]!).compareTo(_ipScore(b, ips[b]!)));
    _lanIps = sorted;
    _lanIp = sorted.isNotEmpty ? sorted.first : null;
  }

  /// IP 展示优先级：wlan/eth 等实体接口 + 局域网私有地址 最优先，
  /// 其次私有地址，再其次实体接口，最后其余地址
  int _ipScore(String ip, String name) {
    final isWifiEth = name.startsWith('wlan') || name.startsWith('eth') ||
        name.startsWith('en') || name.startsWith('ra') ||
        name.startsWith('bond') || name.startsWith('ccmni') ||
        name.startsWith('ap');
    final parts = ip.split('.');
    final seg2 = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final isPrivate = ip.startsWith('192.168.') || ip.startsWith('10.') ||
        (ip.startsWith('172.') && seg2 >= 16 && seg2 <= 31);
    if (isWifiEth && isPrivate) return 0;
    if (isPrivate) return 1;
    if (isWifiEth) return 2;
    return 3;
  }

  // ---------------- HTTP 层 ----------------

  Future<void> _handleRequest(HttpRequest req) async {
    debugPrint('REQ-IN ${req.method} ${req.uri.path} from ${req.connectionInfo?.remoteAddress.address}');
    // CORS（兼容网页端 MCP 客户端）
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers',
          'Authorization, Content-Type, MCP-Protocol-Version, MCP-Session-Id, Last-Event-ID')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return;
    }

    if (req.uri.path != '/mcp') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    // Bearer Token 鉴权
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth == null || !auth.startsWith('Bearer ')) {
      await _reject401(req);
      return;
    }
    final presented = auth.substring(7).trim();
    if (presented.isEmpty || presented != getToken()) {
      onLog(LogEntry.error('鉴权失败 401 ← ${req.connectionInfo?.remoteAddress.address}'));
      await _reject401(req);
      return;
    }
    debugPrint('REQ-AUTHED ${req.method}');

    try {
      final bodyBytes = await _collectBody(req);
      debugPrint('BODY-OK len=${bodyBytes.length}');
      dynamic body;
      if (bodyBytes.isNotEmpty) {
        body = jsonDecode(utf8.decode(bodyBytes));
      }
      debugPrint('PARSE-OK isInit=${_isInitialize(body)}');

      final sessionId = req.headers.value('mcp-session-id');
      StreamableHTTPServerTransport? transport;

      if (sessionId != null) {
        final s = _sessions[sessionId];
        if (s == null) {
          // 会话不存在（服务器重启或会话过期）→ 客户端需重新 initialize
          req.response.statusCode = HttpStatus.notFound;
          req.response.headers.set(
              HttpHeaders.contentTypeHeader, 'application/json');
          req.response.write(jsonEncode({'error': 'session not found'}));
          await req.response.close();
          return;
        }
        transport = s.transport;
      } else if (_isInitialize(body)) {
        // 每个会话一个独立 McpServer（mcp_dart 单连接限制）
        debugPrint('NEW-SERVER start');
        final server = _newServer();
        debugPrint('NEW-SERVER ok');
        StreamableHTTPServerTransport? holder;
        final t = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => generateUUID(),
            allowedHosts: _allowedHosts,
            onsessioninitialized: (sid) {
              _sessions[sid] = _McpSession(server, holder!);
              onLog(LogEntry.info('MCP 会话建立 $sid'));
            },
          ),
        );
        holder = t;
        t.onclose = () {
          final sid = t.sessionId;
          if (sid != null) {
            final gone = _sessions.remove(sid);
            gone?.server.close();
            onLog(LogEntry.info('MCP 会话关闭 $sid'));
          }
        };
        await server.connect(t);
        transport = t;
      }

      if (transport == null) {
        req.response.statusCode = HttpStatus.badRequest;
        req.response.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        req.response.write(jsonEncode({'error': 'session required'}));
        await req.response.close();
        return;
      }

      debugPrint('HANDLE start');
      await transport.handleRequest(req, body);
      debugPrint('HANDLE done');
    } catch (e, st) {
      onLog(LogEntry.error('MCP 请求处理异常: $e\n$st'));
      debugPrint('MCP REQ ERROR: $e\n$st');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        req.response.write(jsonEncode({'error': '$e', 'stack': '$st'}));
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _reject401(HttpRequest req) async {
    try {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.headers.set(
          HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.response.write(
          jsonEncode({'error': 'unauthorized', 'hint': '需要 Authorization: Bearer <token>'}));
      await req.response.close();
    } catch (_) {}
  }

  static bool _isInitialize(dynamic body) =>
      body is Map && body['method'] == Method.initialize;

  Future<Uint8List> _collectBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > 16 * 1024 * 1024) {
        throw const HttpException('request body too large');
      }
    }
    return Uint8List.fromList(bytes);
  }

  // ---------------- 工具注册 ----------------

  McpServer _newServer() {
    final s = McpServer(
      const Implementation(name: 'priva-gate-mcp', version: '1.7.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    _registerTools(s, getPermissions());
    return s;
  }

  void _registerTools(McpServer server, Permissions perm) {
    server.registerTool(
      'get_permissions',
      description: '查询全部权限状态：root/sui/shizuku/无障碍/屏幕捕获 及当前生效级别',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        return CallToolResult.fromStructuredContent(perm.toJson());
      },
    );

    if (perm.hasShell) {
    server.registerTool(
      'get_root_status',
      description: '查询设备 root 状态（是否已授权、su 路径、SELinux 状态）',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        onLog(LogEntry.info('调用 get_root_status'));
        return CallToolResult.fromStructuredContent(engine.status.toJson());
      },
    );

    server.registerTool(
      'exec',
      description: '在设备上执行 shell 命令（默认以 root 执行，首次触发 SukiSU 授权）',
      inputSchema: JsonSchema.object(
        properties: {
          'command': JsonSchema.string(description: '要执行的 shell 命令'),
          'as_root': JsonSchema.boolean(
              description: '是否以 root 执行（默认 true）', defaultValue: true),
          'timeout_s': JsonSchema.integer(
              description: '超时秒数（默认 60，最大 600）',
              minimum: 1,
              maximum: 600,
              defaultValue: 60),
          'cwd': JsonSchema.string(description: '工作目录（可选）'),
        },
        required: ['command'],
      ),
      callback: (args, extra) async {
        _bump();
        final command = (args['command'] as String?)?.trim();
        if (command == null || command.isEmpty) {
          return _err('参数 command 不能为空');
        }
        final asRoot = args['as_root'] as bool? ?? true;
        final timeoutSec =
            ((args['timeout_s'] as num?)?.toInt() ?? 60).clamp(1, 600);
        final cwd = args['cwd'] as String?;
        onLog(LogEntry.info('exec${asRoot ? "(root)" : ""}: $command'));
        final r = await engine.run(
          command,
          asRoot: asRoot,
          timeout: Duration(seconds: timeoutSec),
          cwd: cwd,
        );
        final capped = _cap(r);
        onLog(r.isOk
            ? LogEntry.success('✓ exec 完成 (${r.exitCode})', detail: command)
            : LogEntry.error('✗ exec 失败 (${r.exitCode})', detail: command));
        return CallToolResult.fromStructuredContent({
          ...capped.toJson(),
          'elevated_as': _elevation(asRoot),
          'danger_policy': engine.dangerPolicy.name,
        });
      },
    );

    server.registerTool(
      'read_file',
      description: '读取文件内容（默认 root 权限，可读 /data 等敏感目录）',
      inputSchema: JsonSchema.object(
        properties: {
          'path': JsonSchema.string(description: '文件绝对路径'),
          'as_root': JsonSchema.boolean(defaultValue: true),
        },
        required: ['path'],
      ),
      callback: (args, extra) async {
        _bump();
        final path = (args['path'] as String?)?.trim();
        if (path == null || path.isEmpty) return _err('参数 path 不能为空');
        final asRoot = args['as_root'] as bool? ?? true;
        onLog(LogEntry.info('read_file: $path'));
        final r = await engine.readFile(path, asRoot: asRoot);
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'write_file',
      description: '写入文件内容（默认 root 权限，自动覆盖）',
      inputSchema: JsonSchema.object(
        properties: {
          'path': JsonSchema.string(description: '文件绝对路径'),
          'content': JsonSchema.string(description: '文件内容'),
          'as_root': JsonSchema.boolean(defaultValue: true),
        },
        required: ['path', 'content'],
      ),
      callback: (args, extra) async {
        _bump();
        final path = (args['path'] as String?)?.trim();
        final content = args['content'] as String? ?? '';
        if (path == null || path.isEmpty) return _err('参数 path 不能为空');
        final asRoot = args['as_root'] as bool? ?? true;
        onLog(LogEntry.info('write_file: $path (${content.length} bytes)'));
        final r = await engine.writeFile(path, content, asRoot: asRoot);
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'list_dir',
      description: '列出目录内容（ls -la 原始输出）',
      inputSchema: JsonSchema.object(
        properties: {
          'path': JsonSchema.string(description: '目录绝对路径'),
          'as_root': JsonSchema.boolean(defaultValue: true),
        },
        required: ['path'],
      ),
      callback: (args, extra) async {
        _bump();
        final path = (args['path'] as String?)?.trim();
        if (path == null || path.isEmpty) return _err('参数 path 不能为空');
        final asRoot = args['as_root'] as bool? ?? true;
        onLog(LogEntry.info('list_dir: $path'));
        final r = await engine.listDir(path, asRoot: asRoot);
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    // ================= v1.1 实用工具集 =================

    server.registerTool(
      'device_info',
      description: '一键汇总设备信息：型号/系统版本/内核/ABI/CPU核心/内存/存储/电量/开机时长',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        onLog(LogEntry.info('调用 device_info'));
        final r = await engine.run(
          'echo model=\$(getprop ro.product.model);'
          'echo brand=\$(getprop ro.product.brand);'
          'echo android=\$(getprop ro.build.version.release);'
          'echo sdk=\$(getprop ro.build.version.sdk);'
          'echo kernel=\$(uname -r);'
          'echo abi=\$(getprop ro.product.cpu.abi);'
          'echo cores=\$(nproc);'
          'echo memraw=\$(grep MemTotal /proc/meminfo);'
          'echo storageraw=\$(df -h /data | tail -1);'
          'echo batteryraw=\$(dumpsys battery | grep -E level);'
          'echo uptimeraw=\$(cat /proc/uptime);'
          'echo selinux=\$(getenforce)',
          asRoot: true,
          timeout: const Duration(seconds: 20),
        );
        final info = <String, dynamic>{};
        for (final line in r.stdout.split('\n')) {
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          final key = line.substring(0, idx);
          var val = line.substring(idx + 1);
          switch (key) {
            case 'memraw':
              final parts = val.split(RegExp(r'\s+'));
              if (parts.length >= 2) {
                info['mem_mb'] = (int.tryParse(parts[1]) ?? 0) ~/ 1024;
              }
            case 'storageraw':
              final parts = val.split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                info['storage_total'] = parts[1];
                info['storage_used'] = parts[2];
                info['storage_free'] = parts[3];
              }
            case 'batteryraw':
              final m = RegExp(r'level:\s*(\d+)').firstMatch(val);
              info['battery'] = m != null ? '${m.group(1)}%' : val;
            case 'uptimeraw':
              final secs = double.tryParse(val.split(' ').first) ?? 0;
              info['uptime_hours'] =
                  (secs / 3600).toStringAsFixed(1);
            default:
              info[key] = val;
          }
        }
        return _structured(info);
      },
    );

    server.registerTool(
      'app_list',
      description: '列出已安装应用（含版本号），可按范围过滤：third(用户应用)/system/all',
      inputSchema: JsonSchema.object(
        properties: {
          'scope': JsonSchema.string(
            description: '范围：third / system / all',
            enumValues: ['third', 'system', 'all'],
            defaultValue: 'third',
          ),
        },
        required: [],
      ),
      callback: (args, extra) async {
        _bump();
        final scope = args['scope'] as String? ?? 'third';
        final filter = switch (scope) {
          'system' => '-s',
          'all' => '',
          _ => '-3',
        };
        onLog(LogEntry.info('app_list($scope)'));
        final r = await engine.run('pm list packages $filter --show-versioncode',
            asRoot: false, timeout: const Duration(seconds: 30));
        final apps = <Map<String, String>>[];
        for (final line in r.stdout.split('\n')) {
          if (!line.startsWith('package:')) continue;
          final rest = line.substring(8).trim();
          final parts = rest.split(RegExp(r'\s+'));
          final name = parts.first;
          String? vc;
          for (final p in parts.skip(1)) {
            if (p.startsWith('versionCode:')) vc = p.substring(12);
          }
          apps.add({'package': name, 'version_code': ?vc});
        }
        return _structured({'scope': scope, 'count': apps.length, 'apps': apps});
      },
    );

    server.registerTool(
      'app_info',
      description: '查询单个应用详情：版本/UID/数据目录/安装时间/是否启用',
      inputSchema: JsonSchema.object(
        properties: {
          'package': JsonSchema.string(description: '包名'),
        },
        required: ['package'],
      ),
      callback: (args, extra) async {
        _bump();
        final pkg = (args['package'] as String?)?.trim();
        if (pkg == null || !_isPkg(pkg)) return _err('参数 package 无效');
        onLog(LogEntry.info('app_info: $pkg'));
        final r = await engine.run(
          'dumpsys package $pkg | grep -E '
          "'versionName=|versionCode=|userId=|dataDir=|codePath=|firstInstallTime=|lastUpdateTime=|enabled=' "
          '| head -12',
          asRoot: false,
          timeout: const Duration(seconds: 20),
        );
        final info = <String, dynamic>{'package': pkg};
        for (final line in r.stdout.split('\n')) {
          final t = line.trim();
          final idx = t.indexOf('=');
          if (idx > 0) info[t.substring(0, idx)] = t.substring(idx + 1);
        }
        return _structured(info);
      },
    );

    server.registerTool(
      'app_control',
      description: '控制应用：禁用/启用/强停/清数据/启动。清数据不可恢复，谨慎使用',
      inputSchema: JsonSchema.object(
        properties: {
          'package': JsonSchema.string(description: '包名'),
          'action': JsonSchema.string(
            description: '操作：disable / enable / force_stop / clear_data / launch',
            enumValues: ['disable', 'enable', 'force_stop', 'clear_data', 'launch'],
          ),
        },
        required: ['package', 'action'],
      ),
      callback: (args, extra) async {
        _bump();
        final pkg = (args['package'] as String?)?.trim();
        final action = args['action'] as String?;
        if (pkg == null || !_isPkg(pkg)) return _err('参数 package 无效');
        if (action == null) return _err('参数 action 不能为空');
        final cmd = switch (action) {
          'disable' => 'pm disable-user --user 0 $pkg',
          'enable' => 'pm enable $pkg',
          'force_stop' => 'am force-stop $pkg',
          'clear_data' => 'pm clear $pkg',
          'launch' =>
            'monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1',
          _ => null,
        };
        if (cmd == null) return _err('未知 action');
        onLog(LogEntry.info('app_control($action): $pkg'));
        final r = await engine.run(cmd,
            asRoot: true, timeout: const Duration(seconds: 30));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'logcat',
      description: '抓取系统日志 logcat（root 可读全部应用日志，含崩溃栈）',
      inputSchema: JsonSchema.object(
        properties: {
          'lines': JsonSchema.integer(
              description: '行数（默认 200，最大 5000）',
              minimum: 1,
              maximum: 5000,
              defaultValue: 200),
          'level': JsonSchema.string(
            description: '最低级别：V/D/I/W/E（可选）',
            enumValues: ['V', 'D', 'I', 'W', 'E'],
          ),
          'tag': JsonSchema.string(description: '按 tag 过滤（可选）'),
        },
        required: [],
      ),
      callback: (args, extra) async {
        _bump();
        final lines = (args['lines'] as num?)?.toInt() ?? 200;
        final level = args['level'] as String?;
        final tag = (args['tag'] as String?)?.trim();
        if (tag != null &&
            (tag.isEmpty || !RegExp(r'^[a-zA-Z0-9._*:/-]{1,40}$').hasMatch(tag))) {
          return _err('参数 tag 无效');
        }
        final filter = (tag != null && tag.isNotEmpty && level != null)
            ? '$tag:$level'
            : (tag != null && tag.isNotEmpty ? '$tag:*' : null);
        final cmd =
            'logcat -d -t $lines${filter != null ? ' $filter' : ''}';
        onLog(LogEntry.info('logcat: $lines 行${tag != null ? ' tag=$tag' : ''}'));
        final r = await engine.run(cmd,
            asRoot: true, timeout: const Duration(seconds: 20));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'dumpsys',
      description: '转储任意系统服务（如 activity/battery/window/package），诊断神器',
      inputSchema: JsonSchema.object(
        properties: {
          'service': JsonSchema.string(description: '服务名，如 activity、battery、window'),
          'args': JsonSchema.string(description: '附加参数（可选，如 --top）'),
        },
        required: ['service'],
      ),
      callback: (args, extra) async {
        _bump();
        final service = (args['service'] as String?)?.trim();
        if (service == null ||
            !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(service)) {
          return _err('参数 service 无效');
        }
        final extra = (args['args'] as String?)?.trim() ?? '';
        if (extra.isNotEmpty &&
            !RegExp(r'^[a-zA-Z0-9._\- /]{1,80}$').hasMatch(extra)) {
          return _err('参数 args 含非法字符');
        }
        onLog(LogEntry.info('dumpsys: $service $extra'));
        final r = await engine.run('dumpsys $service $extra',
            asRoot: true, timeout: const Duration(seconds: 30));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'audit_log',
      description: '读取命令审计日志（最近 N 条，JSON 行）：每条 root/shell 执行的命令、时间、退出码、耗时都会落盘，用于排查 AI 执行过什么',
      inputSchema: JsonSchema.object(
        properties: {
          'tail': JsonSchema.integer(
              description: '最近 N 条（默认 50，最大 200）',
              minimum: 1,
              maximum: 200,
              defaultValue: 50),
        },
        required: [],
      ),
      callback: (args, extra) async {
        _bump();
        final tail = ((args['tail'] as num?)?.toInt() ?? 50).clamp(1, 200);
        onLog(LogEntry.info('audit_log: tail=$tail'));
        final content = await AuditLog.read(tail: tail);
        return _structured({
          'audit_path': AuditLog.path ?? '(unavailable)',
          'entries': content,
        });
      },
    );

    // set_prop 仅 root/sui 可用（setprop 需要 root 权限）
    if (perm.hasRoot) {
      server.registerTool(
        'set_prop',
      description: '设置系统属性 setprop（需要 root，立即生效，重启丢失）',
      inputSchema: JsonSchema.object(
        properties: {
          'name': JsonSchema.string(description: '属性名，如 persist.sys.usb.config'),
          'value': JsonSchema.string(description: '属性值'),
        },
        required: ['name', 'value'],
      ),
      callback: (args, extra) async {
        _bump();
        final name = (args['name'] as String?)?.trim();
        final value = (args['value'] as String?)?.trim();
        if (name == null ||
            !RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(name)) {
          return _err('参数 name 无效');
        }
        if (value == null || value.length > 92) return _err('参数 value 无效');
        onLog(LogEntry.info('set_prop: $name=$value'));
        final r = await engine.run('setprop ${RootEngine.sq(name)} ${RootEngine.sq(value)}',
            asRoot: true, timeout: const Duration(seconds: 10));
        final check = await engine.run('getprop ${RootEngine.sq(name)}',
            asRoot: false, timeout: const Duration(seconds: 5));
        return _structured({
          ..._cap(r).toJson(),
          'current': check.stdout.trim(),
        });
      },
    );
    }

    server.registerTool(
      'input_event',
      description: '模拟输入：按键(keyevent)/文本(text)/点击(tap)/滑动(swipe)',
      inputSchema: JsonSchema.object(
        properties: {
          'type': JsonSchema.string(
            description: 'keyevent / text / tap / swipe',
            enumValues: ['keyevent', 'text', 'tap', 'swipe'],
          ),
          'arg1': JsonSchema.string(description: 'keyevent: 键码(如 26=电源, 4=返回, 3=主页)；text: 文本内容；tap: x'),
          'arg2': JsonSchema.string(description: 'tap: y；swipe: x1'),
          'arg3': JsonSchema.string(description: 'swipe: y1'),
          'arg4': JsonSchema.string(description: 'swipe: x2'),
          'arg5': JsonSchema.string(description: 'swipe: y2（可选 duration）'),
        },
        required: ['type'],
      ),
      callback: (args, extra) async {
        _bump();
        final type = args['type'] as String?;
        String? a1 = (args['arg1'] as String?)?.trim();
        final a2 = (args['arg2'] as String?)?.trim();
        final a3 = (args['arg3'] as String?)?.trim();
        final a4 = (args['arg4'] as String?)?.trim();
        final a5 = (args['arg5'] as String?)?.trim();
        String cmd;
        switch (type) {
          case 'keyevent':
            if (a1 == null || !RegExp(r'^\d{1,3}$').hasMatch(a1)) {
              return _err('keyevent 需要数字键码');
            }
            cmd = 'input keyevent $a1';
          case 'text':
            if (a1 == null) return _err('text 需要内容');
            cmd = 'input text ${RootEngine.sq(a1)}';
          case 'tap':
            if (a1 == null || a2 == null ||
                !RegExp(r'^\d+$').hasMatch(a1) ||
                !RegExp(r'^\d+$').hasMatch(a2)) {
              return _err('tap 需要数字坐标 x y');
            }
            cmd = 'input tap $a1 $a2';
          case 'swipe':
            if ([a1, a2, a3, a4].any((v) =>
                v == null || !RegExp(r'^\d+$').hasMatch(v))) {
              return _err('swipe 需要数字坐标 x1 y1 x2 y2');
            }
            cmd = 'input swipe $a1 $a2 $a3 $a4${a5 != null ? ' $a5' : ''}';
          default:
            return _err('未知 type');
        }
        onLog(LogEntry.info('input_event($type)'));
        final r = await engine.run(cmd,
            asRoot: false, timeout: const Duration(seconds: 15));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'file_ops',
      description: '文件操作：delete/move/copy/mkdir/chmod/chown（默认 root）',
      inputSchema: JsonSchema.object(
        properties: {
          'action': JsonSchema.string(
            description: 'delete / move / copy / mkdir / chmod / chown',
            enumValues: ['delete', 'move', 'copy', 'mkdir', 'chmod', 'chown'],
          ),
          'path': JsonSchema.string(description: '目标路径（delete/mkdir/chmod/chown 用）'),
          'src': JsonSchema.string(description: '源路径（move/copy 用）'),
          'dst': JsonSchema.string(description: '目标路径（move/copy 用）'),
          'mode': JsonSchema.string(description: 'chmod 模式，如 0644 / 0755'),
          'owner': JsonSchema.string(description: 'chown 属主，如 root / system:system'),
        },
        required: ['action'],
      ),
      callback: (args, extra) async {
        _bump();
        final action = args['action'] as String?;
        final path = (args['path'] as String?)?.trim();
        final src = (args['src'] as String?)?.trim();
        final dst = (args['dst'] as String?)?.trim();
        final mode = (args['mode'] as String?)?.trim();
        final owner = (args['owner'] as String?)?.trim();
        String? cmd;
        switch (action) {
          case 'delete':
            if (path == null) return _err('delete 需要 path');
            cmd = 'rm -rf ${RootEngine.sq(path)}';
          case 'move':
            if (src == null || dst == null) return _err('move 需要 src+dst');
            cmd = 'mv ${RootEngine.sq(src)} ${RootEngine.sq(dst)}';
          case 'copy':
            if (src == null || dst == null) return _err('copy 需要 src+dst');
            cmd = 'cp -r ${RootEngine.sq(src)} ${RootEngine.sq(dst)}';
          case 'mkdir':
            if (path == null) return _err('mkdir 需要 path');
            cmd = 'mkdir -p ${RootEngine.sq(path)}';
          case 'chmod':
            if (path == null || mode == null ||
                !RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
              return _err('chmod 需要 path + 八进制 mode');
            }
            cmd = 'chmod $mode ${RootEngine.sq(path)}';
          case 'chown':
            if (path == null || owner == null ||
                !RegExp(r'^[a-zA-Z0-9_.-]+(:[a-zA-Z0-9_.-]+)?$')
                    .hasMatch(owner)) {
              return _err('chown 需要 path + owner');
            }
            cmd = 'chown $owner ${RootEngine.sq(path)}';
          default:
            return _err('未知 action');
        }
        onLog(LogEntry.info('file_ops($action): $path$src$dst'));
        final r = await engine.run(cmd,
            asRoot: true, timeout: const Duration(seconds: 30));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    server.registerTool(
      'find_file',
      description: 'root 全盘搜索文件（建议指定 dir 避免扫全盘过慢）',
      inputSchema: JsonSchema.object(
        properties: {
          'name': JsonSchema.string(description: '文件名模式，支持通配符 * ？'),
          'dir': JsonSchema.string(
              description: '搜索目录（默认 / 全盘，较慢）',
              defaultValue: '/'),
        },
        required: ['name'],
      ),
      callback: (args, extra) async {
        _bump();
        final name = (args['name'] as String?)?.trim();
        final dir = (args['dir'] as String?)?.trim() ?? '/';
        if (name == null || name.isEmpty) return _err('参数 name 不能为空');
        onLog(LogEntry.info('find_file: $name in $dir'));
        final r = await engine.run(
          'find ${RootEngine.sq(dir)} -name ${RootEngine.sq(name)} 2>/dev/null | head -200',
          asRoot: true,
          timeout: const Duration(seconds: 40),
        );
        final files = r.stdout
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        return _structured({'count': files.length, 'matches': files});
      },
    );


    server.registerTool(
      'settings_edit',
      description: '读写系统设置：settings get/put（namespace: system/global/secure）',
      inputSchema: JsonSchema.object(
        properties: {
          'action': JsonSchema.string(
            description: 'get / put',
            enumValues: ['get', 'put'],
          ),
          'namespace': JsonSchema.string(
            description: 'system / global / secure',
            enumValues: ['system', 'global', 'secure'],
          ),
          'key': JsonSchema.string(description: '设置项，如 screen_brightness、wifi_on'),
          'value': JsonSchema.string(description: 'put 时的值'),
        },
        required: ['action', 'namespace', 'key'],
      ),
      callback: (args, extra) async {
        _bump();
        final action = args['action'] as String?;
        final ns = args['namespace'] as String?;
        final key = (args['key'] as String?)?.trim();
        final value = (args['value'] as String?)?.trim();
        if (!['get', 'put'].contains(action)) return _err('action 无效');
        if (!['system', 'global', 'secure'].contains(ns)) {
          return _err('namespace 无效');
        }
        if (key == null || !RegExp(r'^[a-zA-Z0-9_.-]{1,128}$').hasMatch(key)) {
          return _err('key 无效');
        }
        if (action == 'put' && (value == null || value.length > 256)) {
          return _err('put 需要 value');
        }
        final cmd = action == 'put'
            ? 'settings put $ns $key ${RootEngine.sq(value!)}'
            : 'settings get $ns $key';
        onLog(LogEntry.info('settings_edit($action): $ns/$key'));
        final r = await engine.run(cmd,
            asRoot: true,
            timeout: const Duration(seconds: 15));
        return CallToolResult.fromStructuredContent(_cap(r).toJson());
      },
    );

    // ADB 服务（需要 root/sui，走系统 adbd）
    if (perm.hasRoot) {
      server.registerTool(
        'adb_service',
        description: '内置 ADB 服务：start 开启无线 adb（端口 5555，adbd 以 root 运行，电脑 adb connect 直连即 root）；stop 关闭；status 查询',
        inputSchema: JsonSchema.object(
          properties: {
            'action': JsonSchema.string(
              description: 'start / stop / status',
              enumValues: ['start', 'stop', 'status'],
            ),
          },
          required: ['action'],
        ),
        callback: (args, extra) async {
          _bump();
          final action = args['action'] as String? ?? 'status';
          onLog(LogEntry.info('adb_service($action)'));
          final runner = adbRunner;
          final r = runner != null
              ? await runner(action)
              : await engine.run(
            switch (action) {
              'start' => 'setprop service.adb.tcp.port 5555; stop adbd; '
                  'sleep 1; start adbd; sleep 2; '
                  'echo PORT=\$(getprop service.adb.tcp.port); '
                  'echo ADBD_COUNT=\$(ps -A | grep -c adbd)',
              'stop' => 'setprop service.adb.tcp.port 0; stop adbd; '
                  'sleep 1; start adbd; sleep 1; '
                  'echo PORT=\$(getprop service.adb.tcp.port)',
              _ => 'getprop service.adb.tcp.port; '
                  'echo ADBD_COUNT=\$(ps -A | grep -c adbd)',
            },
            asRoot: true,
            timeout: const Duration(seconds: 30),
          );
          return CallToolResult.fromStructuredContent(_cap(r).toJson());
        },
      );
    }
  }

    if (perm.hasRoot || perm.capture) {
      server.registerTool(
        'screenshot',
        description: '截取当前屏幕并返回 base64（root 用 screencap；无 root 自动降级到屏幕捕获授权）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          if (perm.hasRoot) {
            const tmp = '/data/local/tmp/rmcp_shot.png';
            onLog(LogEntry.info('screenshot (root)'));
            final cap = await engine.run('screencap -p ${RootEngine.sq(tmp)}',
                asRoot: true, timeout: const Duration(seconds: 15));
            if (cap.exitCode != 0) {
              return _err('截屏失败: ${cap.stderr.trim().isEmpty ? cap.stdout.trim() : cap.stderr.trim()}');
            }
            final b64r = await engine.run('base64 -w0 ${RootEngine.sq(tmp)}',
                asRoot: true, timeout: const Duration(seconds: 20));
            await engine.run('rm -f ${RootEngine.sq(tmp)}',
                asRoot: true, timeout: const Duration(seconds: 5));
            if (b64r.exitCode != 0) return _err('读取截屏失败');
            final b64 = b64r.stdout.replaceAll('\n', '');
            if (b64.length > 4 * 1024 * 1024) {
              return _err('截屏过大，请先缩小屏幕内容');
            }
            return _structured({
              'format': 'png',
              'size_bytes': b64.length * 3 ~/ 4,
              'base64': b64,
              'source': 'root',
            });
          }
          onLog(LogEntry.info('screenshot (mediaprojection)'));
          final b64 = await NativeBridge.capturePng();
          if (b64 == null) {
            return _err('屏幕捕获失败：请先在设置页授权屏幕捕获');
          }
          return _structured({
            'format': 'png',
            'size_bytes': b64.length * 3 ~/ 4,
            'base64': b64,
            'source': 'mediaprojection',
          });
        },
      );
    }

    // 无障碍 UI 自动化工具（可选，开启后可用）
    if (perm.accessibility) {
      server.registerTool(
        'ui_dump',
        description: '读取当前屏幕 UI 结构（JSON：文本/坐标/可点击性），需要无障碍服务',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('ui_dump'));
          final raw = await NativeBridge.a11yDump();
          try {
            return CallToolResult.fromStructuredContent(
                jsonDecode(raw) as Map<String, dynamic>);
          } catch (_) {
            return _err(raw);
          }
        },
      );

      server.registerTool(
        'ui_click',
        description: '点击屏幕元素：按文本查找或按坐标点击（需要无障碍服务）',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: '目标文本（文本/描述匹配）'),
            'x': JsonSchema.number(description: '坐标 x（与 y 同时提供时按坐标）'),
            'y': JsonSchema.number(description: '坐标 y'),
            'long': JsonSchema.boolean(description: '长按', defaultValue: false),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final text = (args['text'] as String?)?.trim();
          final x = (args['x'] as num?)?.toDouble();
          final y = (args['y'] as num?)?.toDouble();
          if ((text == null || text.isEmpty) && (x == null || y == null)) {
            return _err('需要 text 或 x+y');
          }
          onLog(LogEntry.info("ui_click: ${text ?? '$x,$y'}"));
          final ok = await NativeBridge.a11yClick(
              text: text, x: x, y: y, longClick: args['long'] as bool? ?? false);
          return _structured({'ok': ok});
        },
      );

      server.registerTool(
        'ui_text',
        description: '向聚焦/可编辑输入框写入文本（需要无障碍服务）',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: '要输入的文本'),
          },
          required: ['text'],
        ),
        callback: (args, extra) async {
          _bump();
          final text = args['text'] as String? ?? '';
          onLog(LogEntry.info('ui_text: \$text'));
          final ok = await NativeBridge.a11ySetText(text);
          return _structured({'ok': ok});
        },
      );

      server.registerTool(
        'ui_action',
        description: '全局操作：back/home/recents/notifications/quick_settings/power_dialog/scroll_forward/scroll_backward（需要无障碍服务）',
        inputSchema: JsonSchema.object(
          properties: {
            'action': JsonSchema.string(
              enumValues: ['back', 'home', 'recents', 'notifications', 'quick_settings', 'power_dialog', 'scroll_forward', 'scroll_backward'],
            ),
          },
          required: ['action'],
        ),
        callback: (args, extra) async {
          _bump();
          final action = args['action'] as String? ?? '';
          final ok = action.startsWith('scroll_')
              ? await NativeBridge.a11yScroll(action == 'scroll_backward' ? 'backward' : 'forward')
              : await NativeBridge.a11yGlobal(action);
          return _structured({'action': action, 'ok': ok});
        },
      );

      server.registerTool(
        'ui_swipe',
        description: '滑动屏幕（需要无障碍服务）',
        inputSchema: JsonSchema.object(
          properties: {
            'x1': JsonSchema.number(),
            'y1': JsonSchema.number(),
            'x2': JsonSchema.number(),
            'y2': JsonSchema.number(),
            'duration': JsonSchema.integer(defaultValue: 200),
          },
          required: ['x1', 'y1', 'x2', 'y2'],
        ),
        callback: (args, extra) async {
          _bump();
          final ok = await NativeBridge.a11ySwipe(
            (args['x1'] as num?)?.toDouble() ?? 0,
            (args['y1'] as num?)?.toDouble() ?? 0,
            (args['x2'] as num?)?.toDouble() ?? 0,
            (args['y2'] as num?)?.toDouble() ?? 0,
            (args['duration'] as num?)?.toInt() ?? 200,
          );
          return _structured({'ok': ok});
        },
      );

      server.registerTool(
        'ui_wait',
        description: '等待屏幕出现指定文本（轮询无障碍节点树，适合等页面加载/弹窗出现）',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: '目标文本（出现在任意节点文本/描述中即命中）'),
            'timeout_s': JsonSchema.integer(description: '超时秒数（默认 15，最大 60）', minimum: 1, maximum: 60, defaultValue: 15),
          },
          required: ['text'],
        ),
        callback: (args, extra) async {
          _bump();
          final text = (args['text'] as String?)?.trim() ?? '';
          if (text.isEmpty) return _err('text 不能为空');
          final timeout = (args['timeout_s'] as num?)?.toInt() ?? 15;
          onLog(LogEntry.info('ui_wait: $text (${timeout}s)'));
          final deadline = DateTime.now().add(Duration(seconds: timeout));
          var attempts = 0;
          while (DateTime.now().isBefore(deadline)) {
            attempts++;
            try {
              final dump = await NativeBridge.a11yDump();
              if (dump.contains(text)) {
                final elapsed = deadline.difference(DateTime.now()).inSeconds;
                return _structured({'found': true, 'text': text, 'attempts': attempts, 'elapsed_s': timeout - elapsed});
              }
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 800));
          }
          return _structured({'found': false, 'text': text, 'attempts': attempts, 'timeout_s': timeout});
        },
      );
    }

    // 定位（无需 root，普通权限）
    if (perm.location) {
      server.registerTool(
        'location_get',
        description: '获取设备当前位置（GPS/网络定位，需要定位权限）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('location_get'));
          final loc = await NativeBridge.locationGet();
          if (loc == null) return _err('定位失败：请确认定位权限已开启且系统定位已打开');
          return CallToolResult.fromStructuredContent(loc);
        },
      );

      server.registerTool(
        'location_watch',
        description: '连续定位采样：多次读取位置取精度最优（适合移动中追踪），需定位权限',
        inputSchema: JsonSchema.object(
          properties: {
            'count': JsonSchema.integer(description: '采样次数（默认 5，最大 20）', minimum: 1, maximum: 20, defaultValue: 5),
            'interval_ms': JsonSchema.integer(description: '采样间隔毫秒（默认 1000）', minimum: 100, maximum: 5000, defaultValue: 1000),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final count = (args['count'] as num?)?.toInt() ?? 5;
          final intervalMs = (args['interval_ms'] as num?)?.toInt() ?? 1000;
          onLog(LogEntry.info('location_watch($count x ${intervalMs}ms)'));
          final r = await NativeBridge.locationWatch(count: count, intervalMs: intervalMs);
          if (r == null) return _err('定位采样失败：请确认定位权限已开启且系统定位已打开');
          return _structured(r);
        },
      );
    }

    // 通知读取（无需 root，通知使用权）
    if (perm.notifications) {
      server.registerTool(
        'notifications_list',
        description: '读取当前通知栏全部通知（包名/标题/内容/时间），需要通知读取权限',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('notifications_list'));
          final list = await NativeBridge.notificationsList();
          return _structured({'count': list.length, 'notifications': list});
        },
      );

      server.registerTool(
        'notifications_act',
        description: '操作通知：open=点击打开对应界面，clear=清除单条，clear_all=全部清除',
        inputSchema: JsonSchema.object(
          properties: {
            'action': JsonSchema.string(
              description: 'open / clear / clear_all',
              enumValues: ['open', 'clear', 'clear_all'],
            ),
            'key': JsonSchema.string(description: '通知 key（open/clear 时需要，来自 notifications_list）'),
          },
          required: ['action'],
        ),
        callback: (args, extra) async {
          _bump();
          final action = args['action'] as String? ?? '';
          final key = (args['key'] as String?) ?? '';
          onLog(LogEntry.info('notifications_act($action)'));
          final ok = switch (action) {
            'open' => await NativeBridge.notificationOpen(key),
            'clear' => await NativeBridge.notificationClear(key),
            'clear_all' => await NativeBridge.notificationClearAll(),
            _ => false,
          };
          return _structured({'action': action, 'ok': ok});
        },
      );
    }

    // 悬浮窗（无需 root，设置页授权）
    if (perm.overlay) {
      server.registerTool(
        'overlay_show',
        description: '在屏幕上显示一行文字（悬浮窗，N 秒后消失），需要悬浮窗权限',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: '要显示的文字'),
            'seconds': JsonSchema.integer(description: '显示秒数（默认 3）', minimum: 1, maximum: 60, defaultValue: 3),
          },
          required: ['text'],
        ),
        callback: (args, extra) async {
          _bump();
          final text = (args['text'] as String?) ?? '';
          final secs = (args['seconds'] as num?)?.toInt() ?? 3;
          onLog(LogEntry.info('overlay_show: $text'));
          final ok = await NativeBridge.overlayShow(text, secs);
          return _structured({'ok': ok});
        },
      );
    }

    // 共享存储文件访问（MANAGE_EXTERNAL_STORAGE，无 root 也可用）
    if (perm.fileAccess) {
      server.registerTool(
        'storage_list',
        description: '列出共享存储目录内容（/sdcard 下，需文件访问权限），与 root 的 list_dir 分离',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '目录路径（如 /sdcard/Download）', defaultValue: '/sdcard'),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '/sdcard';
          onLog(LogEntry.info('storage_list: $path'));
          try {
            final dir = Directory(path);
            if (!await dir.exists()) return _err('目录不存在: $path');
            final entries = <Map<String, dynamic>>[];
            await for (final e in dir.list(followLinks: false)) {
              final isDir = await e.stat().then((st) => st.type == FileSystemEntityType.directory);
              final size = await e.stat().then((st) => st.size);
              entries.add({
                'name': e.path.split('/').last,
                'type': isDir ? 'dir' : 'file',
                'size': isDir ? null : size,
                'path': e.path,
              });
            }
            entries.sort((a, b) {
              if (a['type'] != b['type']) return a['type'] == 'dir' ? -1 : 1;
              return (a['name'] as String).compareTo(b['name'] as String);
            });
            return _structured({'path': path, 'count': entries.length, 'entries': entries});
          } catch (e) {
            return _err('读取失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_mkdir',
        description: '创建目录（共享存储，需文件访问权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '目录路径'),
          },
          required: ['path'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_mkdir: $path'));
          try {
            await Directory(path).create(recursive: true);
            return _structured({'path': path, 'ok': true});
          } catch (e) {
            return _err('创建失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_delete',
        description: '删除文件或目录（目录默认递归，需文件访问权限，不可恢复）',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '文件或目录路径'),
          },
          required: ['path'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_delete: $path'));
          try {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
              return _structured({'path': path, 'ok': true, 'type': 'file'});
            }
            final d = Directory(path);
            if (await d.exists()) {
              await d.delete(recursive: true);
              return _structured({'path': path, 'ok': true, 'type': 'dir'});
            }
            return _err('路径不存在: $path');
          } catch (e) {
            return _err('删除失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_move',
        description: '移动/重命名文件或目录（需文件访问权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'src': JsonSchema.string(description: '源路径'),
            'dst': JsonSchema.string(description: '目标路径'),
          },
          required: ['src', 'dst'],
        ),
        callback: (args, extra) async {
          _bump();
          final src = (args['src'] as String?) ?? '';
          final dst = (args['dst'] as String?) ?? '';
          if (src.isEmpty || dst.isEmpty) return _err('src/dst 不能为空');
          onLog(LogEntry.info('storage_move: $src → $dst'));
          try {
            await File(src).rename(dst);
            return _structured({'src': src, 'dst': dst, 'ok': true});
          } catch (_) {
            try {
              await Directory(src).rename(dst);
              return _structured({'src': src, 'dst': dst, 'ok': true});
            } catch (e) {
              return _err('移动失败: $e');
            }
          }
        },
      );

      server.registerTool(
        'storage_copy',
        description: '复制文件或目录（需文件访问权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'src': JsonSchema.string(description: '源路径'),
            'dst': JsonSchema.string(description: '目标路径'),
          },
          required: ['src', 'dst'],
        ),
        callback: (args, extra) async {
          _bump();
          final src = (args['src'] as String?) ?? '';
          final dst = (args['dst'] as String?) ?? '';
          if (src.isEmpty || dst.isEmpty) return _err('src/dst 不能为空');
          onLog(LogEntry.info('storage_copy: $src → $dst'));
          try {
            await File(src).copy(dst);
            return _structured({'src': src, 'dst': dst, 'ok': true});
          } catch (_) {
            try {
              await _copyDir(Directory(src), Directory(dst));
              return _structured({'src': src, 'dst': dst, 'ok': true});
            } catch (e) {
              return _err('复制失败: $e');
            }
          }
        },
      );

      server.registerTool(
        'storage_stat',
        description: '查询文件/目录信息：存在/类型/大小/修改时间',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '路径'),
          },
          required: ['path'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_stat: $path'));
          try {
            final f = File(path);
            if (await f.exists()) {
              final st = await f.stat();
              return _structured({
                'path': path,
                'exists': true,
                'type': 'file',
                'size': st.size,
                'modified': st.modified.millisecondsSinceEpoch,
              });
            }
            final d = Directory(path);
            if (await d.exists()) {
              final st = await d.stat();
              return _structured({
                'path': path,
                'exists': true,
                'type': 'dir',
                'size': st.size,
                'modified': st.modified.millisecondsSinceEpoch,
              });
            }
            return _structured({'path': path, 'exists': false});
          } catch (e) {
            return _err('查询失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_read',
        description: '读取共享存储文件内容（文本，需文件访问权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '文件路径（如 /sdcard/Download/x.txt）'),
          },
          required: ['path'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_read: $path'));
          try {
            final f = File(path);
            if (!await f.exists()) return _err('文件不存在: $path');
            var content = await f.readAsString();
            if (content.length > 1024 * 1024) {
              content = '${content.substring(0, 1024 * 1024)}\n...[truncated]';
            }
            return _structured({'path': path, 'content': content, 'truncated': content.contains('[truncated]')});
          } catch (e) {
            return _err('读取失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_write',
        description: '写入共享存储文件（需文件访问权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '文件路径'),
            'content': JsonSchema.string(description: '文件内容'),
          },
          required: ['path', 'content'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          final content = (args['content'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_write: $path'));
          try {
            await File(path).writeAsString(content);
            return _structured({'path': path, 'ok': true, 'bytes': content.length});
          } catch (e) {
            return _err('写入失败: $e');
          }
        },
      );
      server.registerTool(
        'storage_touch',
        description: '创建空文件（若已存在则更新时间戳，不覆盖内容），需文件访问权限',
        inputSchema: JsonSchema.object(
          properties: {
            'path': JsonSchema.string(description: '文件路径（如 /sdcard/Download/note.txt）'),
          },
          required: ['path'],
        ),
        callback: (args, extra) async {
          _bump();
          final path = (args['path'] as String?) ?? '';
          if (path.isEmpty) return _err('path 不能为空');
          onLog(LogEntry.info('storage_touch: $path'));
          try {
            final f = File(path);
            if (!await f.exists()) {
              await f.create(recursive: true);
            } else {
              final now = DateTime.now();
              await f.setLastModified(now);
            }
            return _structured({'path': path, 'ok': true});
          } catch (e) {
            return _err('创建失败: $e');
          }
        },
      );

      server.registerTool(
        'storage_disk',
        description: '磁盘空间信息：总容量/可用/已用（共享存储），需文件访问权限',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('storage_disk'));
          try {
            var total = 0, free = 0;
            try {
              final rs = await Process.run('df', ['-k', '/sdcard']);
              final lines = (rs.stdout as String).trim().split('\n');
              if (lines.length >= 2) {
                final parts = lines[1].split(RegExp(r'\s+'));
                if (parts.length >= 4) {
                  total = int.tryParse(parts[1]) ?? 0;
                  free = int.tryParse(parts[3]) ?? 0;
                }
              }
            } catch (_) {}
            if (total == 0) return _err('无法读取磁盘信息');
            return _structured({
              'total_kb': total,
              'free_kb': free,
              'used_kb': total - free,
              'root': '/sdcard',
            });
          } catch (e) {
            return _err('读取失败: $e');
          }
        },
      );
    }

    // ===== 设备工具（剪贴板/振动/传感器/流量/NFC/电池 无需授权） =====
    server.registerTool(
      'battery_status',
      description: '电池信息：电量/充电状态/温度（无需授权）',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        onLog(LogEntry.info('battery_status'));
        final r = await NativeBridge.batteryStatus();
        if (r == null) return _err('读取电池信息失败');
        return _structured(r);
      },
    );

    server.registerTool(
      'clipboard_get',
      description: '读取剪贴板内容',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        onLog(LogEntry.info('clipboard_get'));
        final t = await NativeBridge.clipboardGet();
        return _structured({'content': t ?? ''});
      },
    );

    server.registerTool(
      'clipboard_set',
      description: '写入剪贴板内容',
      inputSchema: JsonSchema.object(
        properties: {
          'text': JsonSchema.string(description: '要写入的内容'),
        },
        required: ['text'],
      ),
      callback: (args, extra) async {
        _bump();
        final text = (args['text'] as String?) ?? '';
        onLog(LogEntry.info('clipboard_set'));
        final ok = await NativeBridge.clipboardSet(text);
        return _structured({'ok': ok});
      },
    );

    server.registerTool(
      'vibrate',
      description: '设备振动（毫秒）',
      inputSchema: JsonSchema.object(
        properties: {
          'ms': JsonSchema.integer(description: '振动时长（默认 300）', minimum: 50, maximum: 10000, defaultValue: 300),
        },
        required: [],
      ),
      callback: (args, extra) async {
        _bump();
        final ms = (args['ms'] as num?)?.toInt() ?? 300;
        final ok = await NativeBridge.vibrate(ms);
        return _structured({'ok': ok});
      },
    );

    server.registerTool(
      'sensor_read',
      description: '读取传感器数据：accelerometer/light/proximity/gyroscope/magnetic',
      inputSchema: JsonSchema.object(
        properties: {
          'type': JsonSchema.string(
            description: '传感器类型',
            enumValues: ['accelerometer', 'light', 'proximity', 'gyroscope', 'magnetic'],
            defaultValue: 'accelerometer',
          ),
        },
        required: [],
      ),
      callback: (args, extra) async {
        _bump();
        final type = (args['type'] as String?) ?? 'accelerometer';
        final r = await NativeBridge.sensorRead(type);
        if (r == null) return _err('读取传感器失败（设备无此传感器）');
        return CallToolResult.fromStructuredContent(r);
      },
    );

    server.registerTool(
      'traffic_stats',
      description: '各应用网络流量统计（开机累计，排行前 20）',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        final r = await NativeBridge.trafficStats();
        if (r == null) return _err('读取流量统计失败');
        return _structured({'count': r.length, 'apps': r});
      },
    );

    server.registerTool(
      'nfc_status',
      description: '查询 NFC 硬件状态（是否可用/开启）',
      inputSchema: JsonSchema.object(properties: {}, required: []),
      callback: (args, extra) async {
        _bump();
        final r = await NativeBridge.nfcStatus();
        return CallToolResult.fromStructuredContent(r ?? {'available': false});
      },
    );

    // 电话（CALL_PHONE / READ_PHONE_STATE）
    if (perm.phone) {
      server.registerTool(
        'phone_state',
        description: '电话/SIM 状态：网络类型/SIM 运营商/漫游（需电话权限）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          final r = await NativeBridge.phoneState();
          if (r == null) return _err('读取电话状态失败或未授权');
          return CallToolResult.fromStructuredContent(r);
        },
      );

      server.registerTool(
        'call_phone',
        description: '直接拨打电话（需电话权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'number': JsonSchema.string(description: '电话号码'),
          },
          required: ['number'],
        ),
        callback: (args, extra) async {
          _bump();
          final number = (args['number'] as String?) ?? '';
          onLog(LogEntry.info('call_phone → $number'));
          final ok = await NativeBridge.callDirect(number);
          return _structured({'ok': ok, 'number': number});
        },
      );

      server.registerTool(
        'open_dialer',
        description: '打开拨号界面（预填号码，无需权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'number': JsonSchema.string(description: '电话号码（可选）'),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final number = (args['number'] as String?) ?? '';
          final ok = await NativeBridge.openDialer(number);
          return _structured({'ok': ok});
        },
      );

      server.registerTool(
        'call_end',
        description: '挂断当前通话（root 执行 ENDCALL 按键，无通话时无效）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('call_end'));
          final r = await engine.run('input keyevent 6',
              asRoot: true, timeout: const Duration(seconds: 10));
          return _structured({'ok': r.exitCode == 0, 'detail': r.stderr.isNotEmpty ? r.stderr.trim() : r.stdout.trim()});
        },
      );
    }

    // WiFi 扫描
    if (perm.wifi) {
      server.registerTool(
        'wifi_scan',
        description: '扫描附近 WiFi（SSID/信号强度），需 WiFi 权限',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          final r = await NativeBridge.wifiScan();
          if (r == null) return _err('WiFi 扫描失败或未授权');
          return _structured({'count': r.length, 'networks': r});
        },
      );

      server.registerTool(
        'wifi_status',
        description: 'WiFi 状态：开关/当前连接 SSID/信号强度/链路速率/IP（需 WiFi 权限）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('wifi_status'));
          final r = await NativeBridge.wifiStatus();
          if (r == null) return _err('WiFi 状态读取失败');
          return _structured(r);
        },
      );
    }

    // 蓝牙扫描
    if (perm.bluetooth) {
      server.registerTool(
        'bluetooth_scan',
        description: '扫描附近蓝牙设备（4 秒发现窗口），需蓝牙权限',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          final r = await NativeBridge.bluetoothScan();
          if (r == null) return _err('蓝牙扫描失败或未授权');
          return _structured({'count': r.length, 'devices': r});
        },
      );

      server.registerTool(
        'bluetooth_status',
        description: '蓝牙状态：开关/已配对设备列表（需蓝牙权限）',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('bluetooth_status'));
          final r = await NativeBridge.bluetoothStatus();
          if (r == null) return _err('蓝牙状态读取失败');
          return _structured(r);
        },
      );
    }

    // 相机（普通权限）
    if (perm.camera) {
      server.registerTool(
        'camera_photo',
        description: '调用相机拍一张照片（JPEG base64，可直接交给视觉模型），需要相机权限',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('camera_photo'));
          final r = await NativeBridge.cameraPhoto();
          if (r == null) return _err('拍照失败或未授权相机');
          return CallToolResult.fromStructuredContent(r);
        },
      );
    }

    // 麦克风（普通权限）
    if (perm.microphone) {
      server.registerTool(
        'audio_record',
        description: '录音 N 秒（m4a base64，可交给语音模型），需要麦克风权限',
        inputSchema: JsonSchema.object(
          properties: {
            'seconds': JsonSchema.integer(description: '录音秒数（默认 5，最大 60）', minimum: 1, maximum: 60, defaultValue: 5),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final secs = (args['seconds'] as num?)?.toInt() ?? 5;
          onLog(LogEntry.info('audio_record($secs s)'));
          final r = await NativeBridge.audioRecord(secs);
          if (r == null) return _err('录音失败或未授权麦克风');
          return CallToolResult.fromStructuredContent(r);
        },
      );
    }

    // 短信（普通权限）
    if (perm.sms) {
      server.registerTool(
        'sms_list',
        description: '读取收件箱短信（最新 N 条，含验证码场景），需要短信权限',
        inputSchema: JsonSchema.object(
          properties: {
            'limit': JsonSchema.integer(description: '条数（默认 50，最大 200）', minimum: 1, maximum: 200, defaultValue: 50),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final limit = (args['limit'] as num?)?.toInt() ?? 50;
          onLog(LogEntry.info('sms_list($limit)'));
          final r = await NativeBridge.dataCall('smsList', {'limit': limit});
          if (r == null) return _err('读取短信失败或未授权');
          return _structured({'count': r.length, 'sms': r});
        },
      );

      server.registerTool(
        'sms_send',
        description: '发送短信（需要短信权限）',
        inputSchema: JsonSchema.object(
          properties: {
            'number': JsonSchema.string(description: '接收号码'),
            'text': JsonSchema.string(description: '短信内容'),
          },
          required: ['number', 'text'],
        ),
        callback: (args, extra) async {
          _bump();
          final number = (args['number'] as String?) ?? '';
          final text = (args['text'] as String?) ?? '';
          onLog(LogEntry.info('sms_send → $number'));
          final ok = await NativeBridge.smsSend(number, text);
          return _structured({'ok': ok, 'to': number});
        },
      );

      server.registerTool(
        'sms_threads',
        description: '短信会话列表（按 thread_id 分组，含未读数/最新内容），需要短信权限',
        inputSchema: JsonSchema.object(
          properties: {
            'limit': JsonSchema.integer(description: '会话数（默认 50，最大 100）', minimum: 1, maximum: 100, defaultValue: 50),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final limit = (args['limit'] as num?)?.toInt() ?? 50;
          onLog(LogEntry.info('sms_threads($limit)'));
          final r = await NativeBridge.smsThreads(limit);
          if (r == null) return _err('读取短信会话失败或未授权');
          return _structured({'count': r.length, 'threads': r});
        },
      );

      server.registerTool(
        'sms_delete',
        description: '删除短信：按 id 删单条，或按 number 删除该号码全部短信（不可恢复）',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '短信 id（来自 sms_list/短信会话）', minimum: 1),
            'number': JsonSchema.string(description: '号码（删除该号码全部短信；与 id 二选一）'),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          final number = (args['number'] as String?)?.trim();
          if (id == null && (number == null || number.isEmpty)) {
            return _err('需要提供 id 或 number');
          }
          onLog(LogEntry.info('sms_delete id=$id number=$number'));
          final ok = await NativeBridge.smsDelete(id: id, number: number);
          return _structured({'ok': ok});
        },
      );

      server.registerTool(
        'sms_mark_read',
        description: '标记短信已读：不传 id 则全部标记已读',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '短信 id（可选，缺省=全部）', minimum: 1),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          onLog(LogEntry.info('sms_mark_read id=$id'));
          final ok = await NativeBridge.smsMarkRead(id: id);
          return _structured({'ok': ok});
        },
      );
    }

    // 通讯录（普通权限）
    if (perm.contacts) {
      server.registerTool(
        'contacts_list',
        description: '读取通讯录联系人（姓名+号码），需要通讯录权限',
        inputSchema: JsonSchema.object(
          properties: {
            'limit': JsonSchema.integer(description: '条数（默认 200，最大 500）', minimum: 1, maximum: 500, defaultValue: 200),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final limit = (args['limit'] as num?)?.toInt() ?? 200;
          onLog(LogEntry.info('contacts_list($limit)'));
          final r = await NativeBridge.dataCall('contacts', {'limit': limit});
          if (r == null) return _err('读取通讯录失败或未授权');
          return _structured({'count': r.length, 'contacts': r});
        },
      );

      server.registerTool(
        'contacts_search',
        description: '搜索联系人（按姓名或号码模糊匹配），需要通讯录权限',
        inputSchema: JsonSchema.object(
          properties: {
            'query': JsonSchema.string(description: '搜索关键词（姓名或号码片段）'),
          },
          required: ['query'],
        ),
        callback: (args, extra) async {
          _bump();
          final q = ((args['query'] as String?) ?? '').trim().toLowerCase();
          if (q.isEmpty) return _err('query 不能为空');
          onLog(LogEntry.info('contacts_search: $q'));
          final r = await NativeBridge.dataCall('contacts', {'limit': 2000});
          if (r == null) return _err('读取通讯录失败或未授权');
          final hits = r
              .where((c) =>
                  ((c['name'] as String?) ?? '').toLowerCase().contains(q) ||
                  ((c['number'] as String?) ?? '').contains(q))
              .take(50)
              .toList();
          return _structured({'query': q, 'count': hits.length, 'contacts': hits});
        },
      );

      server.registerTool(
        'contacts_add',
        description: '新增联系人（姓名+号码，无号码可只存姓名），需要通讯录权限',
        inputSchema: JsonSchema.object(
          properties: {
            'name': JsonSchema.string(description: '联系人姓名'),
            'number': JsonSchema.string(description: '手机号码'),
          },
          required: ['name'],
        ),
        callback: (args, extra) async {
          _bump();
          final name = (args['name'] as String?) ?? '';
          final number = (args['number'] as String?) ?? '';
          if (name.trim().isEmpty) return _err('name 不能为空');
          onLog(LogEntry.info('contacts_add: $name'));
          final ok = await NativeBridge.contactAdd(name, number);
          return _structured({'ok': ok, 'name': name, 'number': number});
        },
      );

      server.registerTool(
        'contacts_update',
        description: '更新联系人：按 id（contacts_list 返回的 id）更新姓名/号码，只更新非空字段',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '联系人 id（来自 contacts_list）', minimum: 1),
            'name': JsonSchema.string(description: '新姓名（可选）'),
            'number': JsonSchema.string(description: '新号码（可选）'),
          },
          required: ['id'],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          if (id == null) return _err('id 不能为空');
          final name = (args['name'] as String?)?.trim();
          final number = (args['number'] as String?)?.trim();
          if ((name == null || name.isEmpty) && (number == null || number.isEmpty)) {
            return _err('至少提供一个 name 或 number');
          }
          onLog(LogEntry.info('contacts_update id=$id'));
          final ok = await NativeBridge.contactUpdate(id, name: name, number: number);
          return _structured({'ok': ok, 'id': id});
        },
      );

      server.registerTool(
        'contacts_delete',
        description: '删除联系人（按 id，不可恢复），需要通讯录权限',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '联系人 id（来自 contacts_list）', minimum: 1),
          },
          required: ['id'],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          if (id == null) return _err('id 不能为空');
          onLog(LogEntry.info('contacts_delete id=$id'));
          final ok = await NativeBridge.contactDelete(id);
          return _structured({'ok': ok, 'id': id});
        },
      );
    }

    // 通话记录（普通权限）
    if (perm.callLog) {
      server.registerTool(
        'call_log',
        description: '读取通话记录（号码/类型/时长/时间），需要通话记录权限',
        inputSchema: JsonSchema.object(
          properties: {
            'limit': JsonSchema.integer(description: '条数（默认 100，最大 200）', minimum: 1, maximum: 200, defaultValue: 100),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final limit = (args['limit'] as num?)?.toInt() ?? 100;
          onLog(LogEntry.info('call_log($limit)'));
          final r = await NativeBridge.dataCall('callLog', {'limit': limit});
          if (r == null) return _err('读取通话记录失败或未授权');
          return _structured({'count': r.length, 'calls': r});
        },
      );

      server.registerTool(
        'call_log_delete',
        description: '删除通话记录：按 id 删单条、按 number 删该号码全部、all=true 清空（不可恢复）',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '记录 id（来自 call_log）', minimum: 1),
            'number': JsonSchema.string(description: '号码（删除该号码全部记录）'),
            'all': JsonSchema.boolean(description: 'true=清空全部通话记录', defaultValue: false),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          final number = (args['number'] as String?)?.trim();
          final all = (args['all'] as bool?) ?? false;
          if (!all && id == null && (number == null || number.isEmpty)) {
            return _err('需要提供 id / number 或 all=true');
          }
          onLog(LogEntry.info('call_log_delete id=$id number=$number all=$all'));
          final ok = await NativeBridge.callLogDelete(id: id, number: number, all: all);
          return _structured({'ok': ok});
        },
      );
    }

    // 日历（普通权限）
    if (perm.calendar) {
      server.registerTool(
        'calendar_list',
        description: '读取日历事件（最近 24h 起，含标题/时间/描述），需要日历权限',
        inputSchema: JsonSchema.object(
          properties: {
            'limit': JsonSchema.integer(description: '条数（默认 50，最大 100）', minimum: 1, maximum: 100, defaultValue: 50),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final limit = (args['limit'] as num?)?.toInt() ?? 50;
          onLog(LogEntry.info('calendar_list($limit)'));
          final r = await NativeBridge.dataCall('calendar', {'limit': limit});
          if (r == null) return _err('读取日历失败或未授权');
          return _structured({'count': r.length, 'events': r});
        },
      );

      server.registerTool(
        'calendar_add',
        description: '新增日历事件（自动写入第一个可写日历；时间毫秒时间戳）',
        inputSchema: JsonSchema.object(
          properties: {
            'title': JsonSchema.string(description: '事件标题'),
            'start_ms': JsonSchema.integer(description: '开始时间（epoch 毫秒，默认现在）'),
            'end_ms': JsonSchema.integer(description: '结束时间（epoch 毫秒，默认 1 小时后）'),
            'description': JsonSchema.string(description: '描述（可选）'),
          },
          required: ['title'],
        ),
        callback: (args, extra) async {
          _bump();
          final title = (args['title'] as String?) ?? '';
          if (title.trim().isEmpty) return _err('title 不能为空');
          final now = DateTime.now().millisecondsSinceEpoch;
          final start = (args['start_ms'] as num?)?.toInt() ?? now;
          final end = (args['end_ms'] as num?)?.toInt() ?? (now + 3600000);
          final desc = (args['description'] as String?)?.trim();
          onLog(LogEntry.info('calendar_add: $title'));
          final ok = await NativeBridge.calendarAdd(
            title: title,
            startMs: start,
            endMs: end,
            description: desc == null || desc.isEmpty ? null : desc,
          );
          return _structured({'ok': ok, 'title': title});
        },
      );

      server.registerTool(
        'calendar_delete',
        description: '删除日历事件（按 id，不可恢复）',
        inputSchema: JsonSchema.object(
          properties: {
            'id': JsonSchema.integer(description: '事件 id（来自 calendar_list）', minimum: 1),
          },
          required: ['id'],
        ),
        callback: (args, extra) async {
          _bump();
          final id = (args['id'] as num?)?.toInt();
          if (id == null) return _err('id 不能为空');
          onLog(LogEntry.info('calendar_delete id=$id'));
          final ok = await NativeBridge.calendarDelete(id);
          return _structured({'ok': ok, 'id': id});
        },
      );
    }

    // 使用统计（设置页授权）
    if (perm.usageStats) {
      server.registerTool(
        'usage_stats',
        description: '应用使用时长统计（近 N 天前台时间排行），需要「使用情况访问」权限',
        inputSchema: JsonSchema.object(
          properties: {
            'days': JsonSchema.integer(description: '统计天数（默认 1，最大 30）', minimum: 1, maximum: 30, defaultValue: 1),
          },
          required: [],
        ),
        callback: (args, extra) async {
          _bump();
          final days = (args['days'] as num?)?.toInt() ?? 1;
          onLog(LogEntry.info('usage_stats($days d)'));
          final r = await NativeBridge.dataCall('usage', {'days': days});
          if (r == null) return _err('读取使用统计失败或未授权');
          return _structured({'count': r.length, 'usage': r});
        },
      );
    }

    // 屏幕捕获专用工具（授权后可用）
    if (perm.capture) {
      server.registerTool(
        'screen_capture',
        description: '经 MediaProjection 捕获屏幕一帧（PNG base64），无需 root',
        inputSchema: JsonSchema.object(properties: {}, required: []),
        callback: (args, extra) async {
          _bump();
          onLog(LogEntry.info('screen_capture'));
          final b64 = await NativeBridge.capturePng();
          if (b64 == null) return _err('捕获失败，请确认屏幕捕获已授权');
          return _structured({
            'format': 'png',
            'size_bytes': b64.length * 3 ~/ 4,
            'base64': b64,
          });
        },
      );
    }
  }

  /// 递归复制目录
  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      if (e is File) {
        await e.copy('${dst.path}/${e.uri.pathSegments.last}');
      } else if (e is Directory) {
        await _copyDir(e, Directory('${dst.path}/${e.uri.pathSegments.last}'));
      }
    }
  }

  String _elevation(bool asRoot) {
    if (!asRoot) return 'app';
    final lv = getPermissions().shellLevel;
    return switch (lv) {
      ShellLevel.root => 'root',
      ShellLevel.sui => 'sui',
      ShellLevel.shizuku => 'shizuku',
      ShellLevel.none => 'none',
    };
  }

  static bool _isPkg(String p) => RegExp(r'^[a-zA-Z0-9._]{1,256}$').hasMatch(p);

  CallToolResult _structured(Map<String, dynamic> m) =>
      CallToolResult.fromStructuredContent(m);
  void _bump() {
    _callCount++;
    onStatusChanged();
  }

  ExecResult _cap(ExecResult r) {
    const maxLen = 128 * 1024; // 128KB：防止超大输出堵死 MCP 通道 / 打爆 AI 用量
    var out = r.stdout;
    var truncated = r.truncated;
    final originalLen = out.length;
    if (out.length > maxLen) {
      out = '${out.substring(0, maxLen)}\n...[truncated ${out.length - maxLen} bytes, 共 $originalLen bytes；可用 lines/过滤参数缩小范围]';
      truncated = true;
    }
    return ExecResult(
      exitCode: r.exitCode,
      stdout: out,
      stderr: r.stderr,
      timedOut: r.timedOut,
      truncated: truncated,
      originalLen: originalLen,
    );
  }

  CallToolResult _err(String msg) =>
      CallToolResult(content: [TextContent(text: msg)], isError: true);
}
