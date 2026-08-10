import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/components.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(DS.pagePad, DS.sp16, DS.pagePad, DS.bottomNavPad),
      children: [
        Text('设置', style: DS.h1),
        const SizedBox(height: DS.sp16),

        // ---------- 服务器 ----------
        const SectionHeader(title: '服务器'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            children: [
              _settingRow(
                icon: Icons.dns_rounded,
                title: '监听端口',
                desc: 'MCP 服务 TCP 端口',
                trailing: SizedBox(
                  width: 96,
                  child: TextField(
                    key: const ValueKey('port_field'),
                    controller:
                        TextEditingController(text: app.port.toString()),
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13.5,
                        color: DS.textPrimary),
                    onSubmitted: (v) {
                      final p = int.tryParse(v.trim());
                      if (p != null && p > 0 && p < 65536) {
                        app.setPort(p);
                      } else {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('端口无效')));
                      }
                    },
                  ),
                ),
              ),
              Divider(height: 30, color: DS.divider),
              _settingRow(
                icon: Icons.rocket_launch_rounded,
                title: '启动时自动开启服务器',
                desc: 'App 启动后自动进入监听状态',
                trailing: Switch(
                  value: app.autoStart,
                  onChanged: app.setAutoStart,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- 外观 ----------
        const SectionHeader(title: '外观'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('亮度模式', style: DS.h2),
              const SizedBox(height: DS.sp12),
              Row(
                children: [
                  _modeChip(context, app, ThemeMode.system,
                      Icons.brightness_auto_rounded, '跟随系统'),
                  const SizedBox(width: 8),
                  _modeChip(
                      context, app, ThemeMode.light, Icons.light_mode_rounded, '浅色'),
                  const SizedBox(width: 8),
                  _modeChip(
                      context, app, ThemeMode.dark, Icons.dark_mode_rounded, '深色'),
                ],
              ),
              const SizedBox(height: DS.sp20),
              Text('主题配色', style: DS.h2),
              const SizedBox(height: DS.sp12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < appThemeDefs.length; i++)
                    _themeChip(context, app, i),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- 万能权限 ----------
        const SectionHeader(title: '万能权限', subtitle: '权限自动降级，能力随权限激活'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当前级别
              Row(
                children: [
                  BreathingDot(
                    color: app.permissions.hasRoot
                        ? DS.ok
                        : (app.permissions.shizuku
                            ? DS.brandSoft
                            : DS.danger),
                    size: 9,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Shell 权限（自动降级）',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DS.textPrimary)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      await app.refreshPermissions();
                      await app.refreshAdbStatus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.refresh_rounded,
                          size: 17, color: DS.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusBadge(
                    app.permissions.shellLevel.label.toUpperCase(),
                    color: app.permissions.hasRoot
                        ? DS.ok
                        : (app.permissions.shizuku
                            ? DS.brandSoft
                            : DS.danger),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '降级链：root → sui → shizuku → 无。root/sui 为 uid=0，shizuku 为 shell 权限。',
                style: TextStyle(fontSize: 11.5, height: 1.4, color: DS.textTertiary),
              ),
              Divider(height: 28, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.shield_rounded,
                name: 'Shizuku',
                desc: '无 root 时以 shell 权限执行命令（自动降级链第三级）',
                on: app.permissions.shizuku,
                actionLabel: app.permissions.shizuku ? '已授权' : '去授权',
                onTap: app.requestShizuku,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.accessible_rounded,
                name: '无障碍服务',
                desc: '特殊能力：读取界面组件信息 + UI 自动化（ui_dump/ui_click 等），root 也不具备',
                on: app.permissions.accessibility,
                actionLabel: app.permissions.accessibility ? '已开启' : '去开启',
                onTap: app.openAccessibilitySettings,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.screenshot_monitor_rounded,
                name: '屏幕捕获',
                desc: '特殊能力：MediaProjection 截屏（screen_capture 工具）',
                on: app.permissions.capture,
                actionLabel: app.permissions.capture ? '已授权' : '去授权',
                onTap: app.requestScreenCapture,
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- 扩展权限（无需 root） ----------
        const SectionHeader(title: '扩展权限', subtitle: '普通权限即可，无需 root'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            children: [
              _permRow(
                context, app,
                icon: Icons.folder_zip_rounded,
                name: '文件访问',
                desc: '所有文件访问权限：无 root 也可读写共享存储',
                on: app.permissions.fileAccess,
                actionLabel: app.permissions.fileAccess ? '已授权' : '去开启',
                onTap: app.requestAllFilesPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.location_on_rounded,
                name: '定位',
                desc: '获取设备位置（location_get 工具）',
                on: app.permissions.location,
                actionLabel: app.permissions.location ? '已授权' : '去授权',
                onTap: app.requestLocationPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.notifications_rounded,
                name: '通知读取',
                desc: '读取通知栏（notifications_list 工具），AI 能“看到”通知',
                on: app.permissions.notifications,
                actionLabel: app.permissions.notifications ? '已开启' : '去开启',
                onTap: app.requestNotificationAccessPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.picture_in_picture_alt_rounded,
                name: '悬浮窗',
                desc: '在屏幕上显示文字（overlay_show 工具）',
                on: app.permissions.overlay,
                actionLabel: app.permissions.overlay ? '已授权' : '去开启',
                onTap: app.requestOverlayPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.photo_camera_rounded,
                name: '相机',
                desc: '拍照（camera_photo 工具，AI 看图）',
                on: app.permissions.camera,
                actionLabel: app.permissions.camera ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.CAMERA']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.mic_rounded,
                name: '麦克风',
                desc: '录音（audio_record 工具，AI 听声）',
                on: app.permissions.microphone,
                actionLabel: app.permissions.microphone ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.RECORD_AUDIO']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.sms_rounded,
                name: '短信',
                desc: '读/发短信（sms_list / sms_send，验证码场景）',
                on: app.permissions.sms,
                actionLabel: app.permissions.sms ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(
                    ['android.permission.READ_SMS', 'android.permission.SEND_SMS']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.contacts_rounded,
                name: '通讯录',
                desc: '读取联系人（contacts_list 工具）',
                on: app.permissions.contacts,
                actionLabel: app.permissions.contacts ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.READ_CONTACTS']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.call_rounded,
                name: '通话记录',
                desc: '读取通话记录（call_log 工具）',
                on: app.permissions.callLog,
                actionLabel: app.permissions.callLog ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.READ_CALL_LOG']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.event_rounded,
                name: '日历',
                desc: '读取日历事件（calendar_list 工具）',
                on: app.permissions.calendar,
                actionLabel: app.permissions.calendar ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.READ_CALENDAR']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.timeline_rounded,
                name: '使用统计',
                desc: '应用使用时长（usage_stats 工具，设置页授权）',
                on: app.permissions.usageStats,
                actionLabel: app.permissions.usageStats ? '已授权' : '去开启',
                onTap: app.requestUsageStatsPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.battery_saver_rounded,
                name: '忽略电池优化',
                desc: '后台保活增强（防止系统杀进程）',
                on: app.permissions.ignoreBattery,
                actionLabel: app.permissions.ignoreBattery ? '已开启' : '去开启',
                onTap: app.requestIgnoreBatteryPerm,
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.call_rounded,
                name: '电话',
                desc: '拨打电话/设备状态（call_phone / phone_state 工具）',
                on: app.permissions.phone,
                actionLabel: app.permissions.phone ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms([
                  'android.permission.CALL_PHONE',
                  'android.permission.READ_PHONE_STATE',
                ]),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.wifi_rounded,
                name: 'WiFi',
                desc: '扫描附近网络（wifi_scan 工具）',
                on: app.permissions.wifi,
                actionLabel: app.permissions.wifi ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms(['android.permission.NEARBY_WIFI_DEVICES']),
              ),
              Divider(height: 24, color: DS.divider),
              _permRow(
                context, app,
                icon: Icons.bluetooth_rounded,
                name: '蓝牙',
                desc: '扫描附近设备（bluetooth_scan 工具）',
                on: app.permissions.bluetooth,
                actionLabel: app.permissions.bluetooth ? '已授权' : '去授权',
                onTap: () => app.requestRuntimePerms([
                  'android.permission.BLUETOOTH_SCAN',
                  'android.permission.BLUETOOTH_CONNECT',
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- ADB 服务 ----------
        const SectionHeader(title: 'ADB 服务（内置）'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (app.adbEnabled ? DS.ok : DS.surfaceAlt)
                          .withValues(alpha: app.adbEnabled ? 0.14 : 0.6),
                      borderRadius: BorderRadius.circular(DS.r12),
                      border: Border.all(
                          color: app.adbEnabled
                              ? DS.ok.withValues(alpha: 0.4)
                              : DS.border),
                    ),
                    child: Icon(Icons.adb_rounded,
                        size: 20,
                        color:
                            app.adbEnabled ? DS.ok : DS.textTertiary),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('无线 ADB（5555）',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DS.textPrimary)),
                        SizedBox(height: 2),
                        Text(
                          '以 root 启动系统 adbd，电脑 adb connect 直连',
                          style: TextStyle(fontSize: 11.5, color: DS.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: app.adbEnabled,
                    onChanged: (v) => _toggleAdb(context, app, v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: DS.surfaceAlt.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DS.border),
                ),
                child: Text(
                  '状态：${app.adbStatusText}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: DS.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '⚠ 开启会断开当前无线调试连接；adb shell 为 uid=2000，需 root 请在 SukiSU 管理器给 shell 授权',
                style: TextStyle(fontSize: 11, height: 1.45, color: DS.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- 安全 ----------
        const SectionHeader(title: '安全'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, size: 18, color: DS.ok),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('访问 Token',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DS.textPrimary)),
                  ),
                  Text('Bearer 鉴权', style: DS.caption),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DS.surfaceAlt.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(DS.r12),
                  border: Border.all(color: DS.border),
                ),
                child: Text(
                  app.token,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    letterSpacing: 1.1,
                    color: DS.accent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: '复制',
                      icon: Icons.copy_rounded,
                      color: DS.textSecondary,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: app.token));
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                              const SnackBar(content: Text('Token 已复制')));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GhostButton(
                      label: '重新生成',
                      icon: Icons.autorenew_rounded,
                      color: DS.danger,
                      onTap: () => _confirmRegenerate(context, app),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '⚠ 重新生成后，所有已连接的客户端需要更新 Token',
                style: TextStyle(fontSize: 11.5, color: DS.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.sp24),

        // ---------- 关于 ----------
        const SectionHeader(title: '关于'),
        AppCard(
          padding: const EdgeInsets.all(DS.sp20),
          child: InkWell(
            borderRadius: BorderRadius.circular(DS.r20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: DS.brand.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const BrandIcon(size: 44, radius: 13),
                ),
                const SizedBox(height: 12),
                Text('PrivaGate MCP',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: DS.textPrimary)),
                const SizedBox(height: 2),
                Text('v1.6.0 · SukiSU-Ultra · mcp_dart · Flutter',
                    style:
                        TextStyle(fontSize: 11.5, color: DS.textTertiary)),
                const SizedBox(height: 12),
                Text(
                  '点击查看完整功能、权限说明与免责声明',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: DS.textTertiary),
                ),
                const SizedBox(height: 10),
                Text('查看详情 →',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: DS.brandSoft)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String desc,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DS.surfaceAlt.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DS.border),
          ),
          child: Icon(icon, size: 18, color: DS.textSecondary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DS.textPrimary)),
              const SizedBox(height: 2),
              Text(desc,
                  style:
                      TextStyle(fontSize: 11.5, color: DS.textTertiary)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }

  Widget _permRow(
    BuildContext context,
    AppState app, {
    required IconData icon,
    required String name,
    required String desc,
    required bool on,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final color = on ? DS.ok : DS.brand;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DS.r12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DS.textPrimary)),
              const SizedBox(height: 2),
              Text(desc,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.4, color: DS.textTertiary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              actionLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? DS.ok : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleAdb(BuildContext context, AppState app, bool enable) async {
    final r = await app.adbService(enable ? 'start' : 'stop');
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (r.isOk) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(enable ? 'ADB 已开启（5555）' : 'ADB 已关闭'),
          duration: const Duration(seconds: 2),
        ));
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('ADB 操作失败：${r.stderr.trim()}')));
    }
  }

  Future<void> _confirmRegenerate(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成 Token？'),
        content: const Text('现有客户端将立即失效，需要重新配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: DS.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确认', style: TextStyle(color: DS.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await app.regenerateToken();
  }

  // ---------- 外观选择组件 ----------

  Widget _modeChip(BuildContext context, AppState app, ThemeMode mode,
      IconData icon, String label) {
    final selected = app.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => app.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DS.r12),
            color: selected ? DS.brand.withValues(alpha: 0.16) : DS.surfaceAlt,
            border: Border.all(
              color: selected ? DS.brand : DS.borderStrong,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: selected ? DS.brand : DS.textSecondary),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? DS.textPrimary : DS.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeChip(BuildContext context, AppState app, int index) {
    final def = appThemeDefs[index];
    final selected = app.themeIndex == index;
    return GestureDetector(
      onTap: () => app.setThemeIndex(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DS.r12),
          color: selected ? DS.brand.withValues(alpha: 0.16) : DS.surfaceAlt,
          border: Border.all(
            color: selected ? DS.brand : DS.borderStrong,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [def.seed, def.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              def.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? DS.textPrimary : DS.textSecondary,
              ),
            ),
            if (selected) ...[const SizedBox(width: 4), Icon(Icons.check_rounded, size: 14, color: DS.brand)],
          ],
        ),
      ),
    );
  }
}
