import 'package:flutter_test/flutter_test.dart';

import 'package:privagate_mcp/ui/theme.dart';

void main() {
  test('深色主题可构建', () {
    final t = buildAppTheme(dark: true);
    expect(t.useMaterial3, isTrue);
  });

  test('浅色主题可构建', () {
    final t = buildAppTheme(dark: false);
    expect(t.useMaterial3, isTrue);
  });
}
