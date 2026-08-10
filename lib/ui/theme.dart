import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ============ 设计系统 v3（多主题 + 亮暗双模） ============
///
/// - 间距/圆角/字体规范固定（const），颜色/渐变/文本色随主题切换
/// - 主题 = 配色方案(6 套) × 亮度(dark/light)
/// - 调用方通过 DS.* 读取，切换主题时自动跟随（getter 委托）

/// 配色方案定义（用户可选主题）
class AppThemeDef {
  final String name;
  final Color seed; // 品牌主色
  final Color accent; // 辅助色（渐变第二色/高亮）
  final Color? bg; // 深色背景（可选，默认深蓝黑）

  const AppThemeDef({
    required this.name,
    required this.seed,
    required this.accent,
    this.bg,
  });
}

/// 预置 6 套配色
const List<AppThemeDef> appThemeDefs = [
  AppThemeDef(name: '暗黑紫罗兰', seed: Color(0xFF7C5CFF), accent: Color(0xFF00D4FF)),
  AppThemeDef(name: '深空蓝', seed: Color(0xFF3D7BFF), accent: Color(0xFF00E5FF)),
  AppThemeDef(name: '极光绿', seed: Color(0xFF00B35A), accent: Color(0xFF69F0AE)),
  AppThemeDef(name: '落日橙', seed: Color(0xFFFF6D3F), accent: Color(0xFFFFC24B)),
  AppThemeDef(name: '樱花粉', seed: Color(0xFFE84393), accent: Color(0xFFFF80AB)),
  AppThemeDef(name: '石墨黑', seed: Color(0xFF7E8A99), accent: Color(0xFFB0BEC5)),
];

/// 完整调色板（某主题 × 某亮度）
class ThemePalette {
  final String name;
  final bool dark;
  final Color bg, bgElevated, surface, surfaceAlt;
  final Color border, borderStrong, divider;
  final Color textPrimary, textSecondary, textTertiary;
  final Color brand, brandSoft, accent;
  final Color ok, warn, danger;
  final LinearGradient brandGrad, bgGradient;

  ThemePalette({
    required this.name,
    required this.dark,
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.brandSoft,
    required this.accent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.brandGrad,
    required this.bgGradient,
  });
}

Color _lighten(Color c, [double f = 0.25]) => Color.lerp(c, Colors.white, f)!;
Color _darken(Color c, [double f = 0.15]) => Color.lerp(c, Colors.black, f)!;

/// 构建调色板（暗/亮两版）
ThemePalette buildPalette(AppThemeDef def, {required bool dark}) {
  if (dark) {
    final bg = def.bg ?? const Color(0xFF0A0E1A);
    return ThemePalette(
      name: def.name,
      dark: true,
      bg: bg,
      bgElevated: Color.lerp(bg, Colors.white, 0.045)!,
      surface: Color.lerp(bg, Colors.white, 0.075)!,
      surfaceAlt: Color.lerp(bg, Colors.white, 0.13)!,
      border: Colors.white.withValues(alpha: 0.10),
      borderStrong: Colors.white.withValues(alpha: 0.16),
      divider: Colors.white.withValues(alpha: 0.06),
      textPrimary: const Color(0xFFF4F6FB),
      textSecondary: const Color(0xFF9AA3B8),
      textTertiary: const Color(0xFF5D6579),
      brand: def.seed,
      brandSoft: _lighten(def.seed, 0.2),
      accent: def.accent,
      ok: const Color(0xFF2ED573),
      warn: const Color(0xFFFFA726),
      danger: const Color(0xFFFF6B6B),
      brandGrad: LinearGradient(
        colors: [def.seed, Color.lerp(def.seed, def.accent, 0.55)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      bgGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(bg, def.seed, 0.10)!,
          bg,
          bg,
          Color.lerp(bg, def.seed, 0.05)!,
        ],
        stops: const [0.0, 0.25, 0.7, 1.0],
      ),
    );
  }
  return ThemePalette(
    name: def.name,
    dark: false,
    bg: const Color(0xFFF5F6FA),
    bgElevated: Colors.white,
    surface: Colors.white,
    surfaceAlt: const Color(0xFFF0F2F7),
    border: Colors.black.withValues(alpha: 0.08),
    borderStrong: Colors.black.withValues(alpha: 0.13),
    divider: Colors.black.withValues(alpha: 0.05),
    textPrimary: const Color(0xFF1A1D29),
    textSecondary: const Color(0xFF5D6579),
    textTertiary: const Color(0xFF9AA3B8),
    brand: def.seed,
    brandSoft: _darken(def.seed, 0.15),
    accent: def.accent,
    ok: const Color(0xFF00A84D),
    warn: const Color(0xFFE68A00),
    danger: const Color(0xFFE5484D),
    brandGrad: LinearGradient(
      colors: [def.seed, Color.lerp(def.seed, def.accent, 0.55)!],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    bgGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(const Color(0xFFF5F6FA), def.seed, 0.07)!,
        const Color(0xFFF5F6FA),
        const Color(0xFFF5F6FA),
        const Color(0xFFF5F6FA),
      ],
      stops: const [0.0, 0.25, 0.7, 1.0],
    ),
  );
}

/// 设计系统入口：全部 UI 通过 DS.* 读取当前主题
/// 颜色/渐变/文本色为 getter，随 DS.p 自动切换
class DS {
  /// 当前配色方案下标（供 buildAppTheme 读取）
  static int _activeIndex = 0;
  static void setActiveIndex(int i) => _activeIndex = i;
  static int get activeIndex => _activeIndex;

  /// 当前调色板（App 初始化/主题切换时赋值）
  static ThemePalette p = buildPalette(appThemeDefs[0], dark: true);

  // ---------- 颜色 ----------
  static Color get bg => p.bg;
  static Color get bgElevated => p.bgElevated;
  static Color get surface => p.surface;
  static Color get surfaceAlt => p.surfaceAlt;
  static Color get border => p.border;
  static Color get borderStrong => p.borderStrong;
  static Color get divider => p.divider;
  static Color get textPrimary => p.textPrimary;
  static Color get textSecondary => p.textSecondary;
  static Color get textTertiary => p.textTertiary;
  static Color get brand => p.brand;
  static Color get brandSoft => p.brandSoft;
  static Color get accent => p.accent;
  static Color get ok => p.ok;
  static Color get warn => p.warn;
  static Color get danger => p.danger;
  static LinearGradient get brandGrad => p.brandGrad;
  static LinearGradient get bgGradient => p.bgGradient;

  // ---------- 间距（固定） ----------
  static const sp4 = 4.0, sp8 = 8.0, sp12 = 12.0;
  static const sp16 = 16.0, sp20 = 20.0, sp24 = 24.0, sp32 = 32.0;
  static const pagePad = 20.0;

  // ---------- 圆角（固定） ----------
  static const r8 = 8.0, r12 = 12.0, r20 = 20.0, r28 = 28.0;

  /// 底部导航栏占位（extendBody 下页面底部需预留：导航栏 64 + 外边距 14 + 安全余量）
  static const bottomNavPad = 104.0;

  /// 卡片阴影（柔和三层）
  static List<BoxShadow> cardShadow({bool elevated = false}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.5 : 0.35),
          blurRadius: elevated ? 32 : 20,
          offset: Offset(0, elevated ? 12 : 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  // ---------- 文本样式（随主题） ----------
  static TextStyle get h1 => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      );
  static TextStyle get h2 => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.3,
      );
  static TextStyle get body => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        height: 1.5,
      );
  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textTertiary,
        height: 1.4,
      );
  static TextStyle get mono => TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        color: textSecondary,
        height: 1.4,
      );
}

/// 主题构建
ThemeData buildAppTheme({required bool dark}) {
  final def = appThemeDefs[DS._activeIndex];
  final scheme = ColorScheme.fromSeed(
    seedColor: def.seed,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: def.seed,
    secondary: def.accent,
    surface: dark ? DS.surface : Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? DS.bg : DS.bg,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      titleLarge: DS.h2,
      bodyMedium: DS.body,
      bodySmall: DS.caption,
      labelMedium: TextStyle(
          fontSize: 12.5, fontWeight: FontWeight.w600, color: DS.textSecondary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark
          ? DS.bgElevated.withValues(alpha: 0.96)
          : Colors.white.withValues(alpha: 0.96),
      indicatorColor: DS.brand.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: dark ? DS.textSecondary : const Color(0xFF5D6579),
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected
              ? dark
                  ? DS.brandSoft
                  : DS.brand
              : dark
                  ? DS.textTertiary
                  : const Color(0xFF9AA3B8),
        );
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? DS.brand
            : (dark ? Colors.white12 : Colors.black12),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DS.r12),
        borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DS.r12),
        borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DS.r12),
        borderSide: BorderSide(color: DS.brand, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? DS.bgElevated : Colors.white,
      contentTextStyle:
          TextStyle(color: dark ? DS.textPrimary : const Color(0xFF1A1D29)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DS.r12),
        side: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? DS.bgElevated : Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.r20)),
      titleTextStyle: DS.h2,
      contentTextStyle: DS.body,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
