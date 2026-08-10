import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(PrivaGateApp(app: app));
}

class PrivaGateApp extends StatelessWidget {
  final AppState app;

  const PrivaGateApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          // 同步设计系统到当前主题（配色 × 亮度）
          DS.setActiveIndex(state.themeIndex);
          final dark = state.themeMode == ThemeMode.dark ||
              (state.themeMode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          DS.p = buildPalette(appThemeDefs[state.themeIndex], dark: dark);
          return MaterialApp(
            title: 'PrivaGate MCP',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark: false),
            darkTheme: buildAppTheme(dark: true),
            themeMode: state.themeMode,
            home: Shell(),
          );
        },
      ),
    );
  }
}
