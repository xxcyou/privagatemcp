import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models.dart';
import '../../core/permissions.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/components.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        DS.pagePad,
        DS.sp16,
        DS.pagePad,
        DS.bottomNavPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandBar(app),
          const SizedBox(height: DS.sp20),
          _permissionHero(app),
          const SizedBox(height: DS.sp16),
          _serverCard(app),
          const SizedBox(height: DS.sp16),
          _connectionCard(context, app),
        ],
      ),
    );
  }

  // ---------- 品牌栏 ----------
  Widget _brandBar(AppState app) {
    return Row(
      children: [
        BrandIcon(size: 42, radius: 13, glow: true),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PrivaGate MCP',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: DS.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'SukiSU 内核 Root · MCP 通道',
                style: TextStyle(fontSize: 11.5, color: DS.textTertiary),
              ),
            ],
          ),
        ),
        if (app.mcp.running)
          StatusBadge('● 在线', color: DS.ok, filled: true)
        else
          StatusBadge('离线', color: DS.textTertiary),
      ],
    );
  }

  // ---------- 权限 Hero ----------
  Widget _permissionHero(AppState app) {
    final perm = app.permissions;
    final rooted = perm.hasRoot;
    final level = perm.shellLevel;

    final (title, desc, color) = switch (level) {
      ShellLevel.root => ('ROOT', 'SukiSU 内核授权 · uid=0 · 全部工具可用', DS.ok),
      ShellLevel.sui => ('SUI', 'Sui 授权 · uid=0 · 全部工具可用', DS.accent),
      ShellLevel.shizuku => (
        'SHIZUKU',
        'Shizuku shell 权限 · 自动降级生效',
        DS.brandSoft,
      ),
      ShellLevel.none => (
        '无权限',
        '未获得 shell 权限 · 检查 root/sui/shizuku',
        DS.danger,
      ),
    };

    return AppCard(
      tint: color,
      padding: const EdgeInsets.all(DS.sp20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BreathingDot(color: app.checkingRoot ? DS.warn : color, size: 9),
              const SizedBox(width: 10),
              // 必须弹性：大字/窄屏时 'Shell 权限' 按固有宽度会把
              // 右侧标题挤出屏幕（Spacer 只占剩余空间，不约束文本）
              Expanded(
                child: Text(
                  'Shell 权限',
                  style: DS.h2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: DS.sp12,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DS.r12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DS.sp16),
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  'su 路径',
                  app.rootStatus?.suPath ?? '—',
                  color: rooted ? DS.accent : DS.textTertiary,
                ),
              ),
              const SizedBox(width: DS.sp12),
              Expanded(
                child: _statBlock(
                  'SELinux',
                  app.rootStatus?.seLinux ?? '—',
                  color: rooted ? DS.accent : DS.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: DS.sp12),
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  'ADB 服务',
                  app.adbEnabled ? '5555 开启' : '未开启',
                  color: app.adbEnabled ? DS.ok : DS.textTertiary,
                ),
              ),
              const SizedBox(width: DS.sp12),
              Expanded(
                child: _statBlock(
                  '附加能力',
                  perm.extraCount > 0 ? '${perm.extraCount} 项已开启' : '—',
                  color: perm.extraCount > 0 ? DS.warn : DS.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.sp12, vertical: 11),
      decoration: BoxDecoration(
        color: DS.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(DS.r12),
        border: Border.all(color: DS.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DS.caption),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 服务器卡 ----------
  Widget _serverCard(AppState app) {
    final running = app.mcp.running;
    return AppCard(
      tint: running ? DS.brand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (running ? DS.brand : DS.surfaceAlt).withValues(
                    alpha: running ? 0.14 : 0.6,
                  ),
                  borderRadius: BorderRadius.circular(DS.r12),
                  border: Border.all(
                    color: (running ? DS.brand : DS.border).withValues(
                      alpha: running ? 0.35 : 1,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.dns_rounded,
                  size: 19,
                  color: running ? DS.brandSoft : DS.textTertiary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MCP 服务器', style: DS.h2),
                    SizedBox(height: 2),
                    Text(
                      'AI 客户端通过此服务调用设备能力',
                      style: TextStyle(fontSize: 12, color: DS.textTertiary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: running,
                onChanged: (v) => v ? app.startServer() : app.stopServer(),
              ),
            ],
          ),
          const SizedBox(height: DS.sp16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: DS.surfaceAlt.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(DS.r12),
              border: Border.all(color: DS.border),
            ),
            child: Row(
              children: [
                _miniStat(Icons.dns_rounded, '端口', '${app.mcp.port}'),
                SizedBox(
                  width: 1,
                  height: 26,
                  child: VerticalDivider(color: DS.divider, width: 1),
                ),
                _miniStat(Icons.terminal_rounded, '工具', '$kToolCount · 按权限'),
                SizedBox(
                  width: 1,
                  height: 26,
                  child: VerticalDivider(color: DS.divider, width: 1),
                ),
                _miniStat(
                  running ? Icons.hub_rounded : Icons.pause_rounded,
                  '状态',
                  running ? '监听中' : '已停止',
                  valueColor: running ? DS.ok : DS.textTertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            running
                ? '已处理 ${app.mcp.callCount} 次调用 · 前台服务保活中'
                : '开启后 AI 客户端即可通过 MCP 执行设备命令',
            style: TextStyle(fontSize: 11.5, color: DS.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: DS.textTertiary),
          const SizedBox(width: 6),
          // 必须包 Expanded：Column 否则按固有宽度撑开，长文本（如
          // '74 · 按权限'）会把 Row 撑爆溢出屏幕右侧
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: DS.textTertiary),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? DS.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 连接卡 ----------
  Widget _connectionCard(BuildContext context, AppState app) {
    final ip = app.mcp.lanIp ?? '—';
    final url = 'http://$ip:${app.mcp.port}/mcp';
    final token = app.token;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('连接信息', style: DS.h2),
          const SizedBox(height: DS.sp16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 二维码
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DS.surfaceAlt.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DS.border),
                ),
                child: QrImageView(
                  data: jsonEncode({'url': url, 'token': token}),
                  version: QrVersions.auto,
                  size: 108,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: DS.textPrimary,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: DS.textPrimary,
                  ),
                  backgroundColor: Colors.transparent,
                ),
              ),
              const SizedBox(width: DS.sp16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.mcp.running ? url : '服务器未开启',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        height: 1.4,
                        color: app.mcp.running ? DS.accent : DS.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _copyChip(context, 'URL', url,
                            icon: Icons.link_rounded),
                        _copyChip(context, 'Token', token,
                            icon: Icons.key_rounded),
                        _copyChip(
                          context,
                          'JSON',
                          jsonEncode({'url': url, 'token': token}),
                          icon: Icons.data_object_rounded,
                          highlight: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'USB 隧道：adb reverse tcp:${app.mcp.port} tcp:${app.mcp.port}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: DS.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _copyChip(
    BuildContext context,
    String label,
    String value, {
    IconData icon = Icons.copy_rounded,
    bool highlight = false,
  }) {
    final color = highlight ? DS.ok : DS.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('已复制 $label'),
              duration: const Duration(milliseconds: 1200),
            ),
          );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: highlight ? DS.ok : DS.brandSoft),
            const SizedBox(width: 5),
            // Flexible：系统大字（1.3x）下 'Token' 会超宽撑爆 chip
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: DS.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
