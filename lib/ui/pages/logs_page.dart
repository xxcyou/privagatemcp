import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/components.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final logs = app.logs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.pagePad, DS.sp16, DS.pagePad, 0),
          child: Row(
            children: [
              Text('执行日志', style: DS.h1),
              const Spacer(),
              GhostButton(
                label: '清空',
                icon: Icons.delete_sweep_rounded,
                color: DS.textSecondary,
                onTap: app.clearLogs,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.pagePad),
          child: Text('服务器运行与工具调用记录（${logs.length} 条）', style: DS.caption),
        ),
        const SizedBox(height: DS.sp16),
        Expanded(
          child: logs.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: '暂无日志',
                  hint: 'MCP 工具调用后记录会显示在这里',
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      DS.pagePad, 4, DS.pagePad, DS.bottomNavPad),
                  itemCount: logs.length,
                  itemBuilder: (_, i) => _logTile(logs[i]),
                ),
        ),
      ],
    );
  }

  Widget _logTile(LogEntry e) {
    final (color, icon) = switch (e.level) {
      'success' => (DS.ok, Icons.check_circle_rounded),
      'error' => (DS.danger, Icons.error_rounded),
      _ => (DS.accent, Icons.info_rounded),
    };

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间线刻度
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: DS.textPrimary,
                  ),
                ),
                if (e.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    e.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: DS.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(_fmt(e.time),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: DS.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
