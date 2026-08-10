import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/permissions.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/components.dart';

/// 应用版本（与 pubspec.yaml 同步）
const String kAppVersion = '1.6.0';

/// 关于页：版本 / 功能 / 权限说明 / 免责声明
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: DS.bgGradient),
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(DS.pagePad, DS.sp16, DS.pagePad, DS.sp32),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: DS.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  Text('关于', style: DS.h1),
                ],
              ),
              const SizedBox(height: DS.sp24),

              // 品牌区
              Center(
                child: BrandIcon(size: 84, radius: DS.r20, glow: true),
              ),
              const SizedBox(height: DS.sp16),
              Center(child: Text('PrivaGate MCP', style: DS.h1)),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'SukiSU 内核 Root · MCP 通道 · 万能权限',
                  style: TextStyle(fontSize: 12.5, color: DS.textTertiary),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: DS.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(DS.r8),
                  ),
                  child: Text(
                    'v$kAppVersion',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DS.brandSoft,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DS.sp24),

              // 功能简介
              const SectionHeader(title: '功能'),
              AppCard(
                padding: const EdgeInsets.all(DS.sp20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _feature(Icons.shield_rounded, 'Root 能力引擎',
                        'SukiSU-Ultra / KernelSU / Sui / Shizuku 自动降级链，root 权限稳定执行'),
                    _feature(Icons.hub_rounded, 'MCP 服务器',
                        'Streamable HTTP 协议，AI 客户端经 Bearer Token 安全接入'),
                    _feature(Icons.apps_rounded, '74 个工具',
                        '文件/短信/通讯录/通话/日历/定位/通知/无障碍/截屏/相机/麦克风等'),
                    _feature(Icons.dns_rounded, '内置 ADB',
                        '一键开启无线调试，电脑 adb connect 直连'),
                    _feature(Icons.palette_rounded, '多主题',
                        '6 套配色 × 跟随系统/手动亮暗'),
                  ],
                ),
              ),
              const SizedBox(height: DS.sp24),

              // 权限说明
              const SectionHeader(title: '权限说明'),
              AppCard(
                padding: const EdgeInsets.all(DS.sp20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _perm(Icons.sms_rounded, '短信', '读取/发送/删除/标记已读'),
                    _perm(Icons.contacts_rounded, '通讯录', '增删改查联系人'),
                    _perm(Icons.call_rounded, '通话记录', '读取/删除，拨号'),
                    _perm(Icons.event_rounded, '日历', '读取/新增/删除事件'),
                    _perm(Icons.place_rounded, '定位', '单次/连续采样'),
                    _perm(Icons.camera_alt_rounded, '相机 / 麦克风', '拍照 / 录音'),
                    _perm(Icons.notifications_rounded, '通知', '读取/操作通知栏'),
                    _perm(Icons.accessibility_new_rounded, '无障碍', '界面解析与自动化操作'),
                    _perm(Icons.screenshot_rounded, '屏幕捕获', '截屏/投屏能力'),
                    _perm(Icons.storage_rounded, '存储', '共享存储文件管理'),
                  ],
                ),
              ),
              const SizedBox(height: DS.sp24),

              // 免责声明
              const SectionHeader(title: '免责声明'),
              AppCard(
                padding: const EdgeInsets.all(DS.sp20),
                child: Text(
                  'PrivaGate MCP 向 AI 客户端暴露了设备的高权限控制能力（含 root 执行）。'
                  '请仅将 Token 配置给你信任的 AI 客户端，并在可信网络中使用。'
                  '任何越权、滥用或信息泄露风险由使用者自行承担。'
                  '本应用仅供个人设备管理与自动化学习用途，请遵守当地法律法规。',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: DS.textSecondary),
                ),
              ),
              const SizedBox(height: DS.sp24),

              // 当前连接信息
              SectionHeader(title: '当前连接'),
              AppCard(
                padding: const EdgeInsets.all(DS.sp20),
                child: Column(
                  children: [
                    InfoRow('监听端口', '${app.port}', valueColor: DS.accent),
                    Divider(height: 20, color: DS.divider),
                    InfoRow('服务器状态', app.mcp.running ? '运行中' : '已停止',
                        valueColor: app.mcp.running ? DS.ok : DS.textTertiary),
                    Divider(height: 20, color: DS.divider),
                    InfoRow('权限级别', app.permissions.shellLevel.label,
                        valueColor: app.permissions.hasRoot ? DS.ok : DS.warn),
                    Divider(height: 20, color: DS.divider),
                    InfoRow('工具总数', '$kToolCount', valueColor: DS.brandSoft),
                  ],
                ),
              ),
              const SizedBox(height: DS.sp32),
              Center(
                child: Text(
                  'PrivaGate MCP · 个人设备管理工具',
                  style: TextStyle(fontSize: 11, color: DS.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DS.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DS.r12),
            ),
            child: Icon(icon, size: 18, color: DS.brandSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DS.h2),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, height: 1.4, color: DS.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _perm(IconData icon, String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: DS.textSecondary),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: Text(name, style: DS.body)),
          Expanded(
            child: Text(desc,
                style: TextStyle(fontSize: 12, color: DS.textTertiary)),
          ),
        ],
      ),
    );
  }
}
