import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/logs_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(gradient: DS.bgGradient),
        child: IndexedStack(
          index: _index,
          // 注意：不能 const 实例化页面。主题切换时 DS.p 变化，
          // 只有页面 rebuild 才会重新读取颜色；const 复用会导致
          // 切换主题后其他页面颜色不刷新，需切页才生效。
          children: [
            HomePage(),
            ToolsPage(),
            LogsPage(),
            SettingsPage(),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DS.bgElevated.withValues(alpha: 0.9),
                border: Border.all(color: DS.border),
                boxShadow: DS.cardShadow(elevated: true),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                height: 64,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.terminal_outlined),
                    selectedIcon: Icon(Icons.terminal_rounded),
                    label: '工具',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: '日志',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
