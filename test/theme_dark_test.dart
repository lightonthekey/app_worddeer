import 'package:app_worddeer/theme.dart';
import 'package:app_worddeer/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 深色模式：色板选择、系统跟随、落盘与派生色
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppTheme.I.setMode(AppThemeMode.light);
    AppTheme.I.set('indigo');
    await AppTheme.I.load();
  });

  tearDown(() {
    AppTheme.I.setMode(AppThemeMode.light);
    AppTheme.I.set('indigo');
  });

  test('6 套色板都有对应的暗色版，键与亮色一致', () {
    expect(kPalettes, hasLength(6));
    expect(kDarkPalettes, hasLength(6));
    for (final p in kPalettes) {
      final d = darkPaletteOf(p.key);
      expect(d.key, p.key);
      expect(d.name, p.name, reason: '暗色版名字要和亮色一致');
      expect(d.isDark, isTrue);
      expect(d.bg, isNot(p.bg), reason: '${p.key} 的暗色底不能沿用亮色底');
      // 暗色底一定是「暗」的：亮度低于 0.2
      expect(d.bg.computeLuminance(), lessThan(.2), reason: '${p.key} 底色不够暗');
      // 正文要亮
      expect(d.ink.computeLuminance(), greaterThan(.6),
          reason: '${p.key} 暗色正文不够亮');
    }
  });

  test('暗色下卡片面不是白色', () {
    AppTheme.I.setMode(AppThemeMode.dark);
    for (final key in kPalettes.map((e) => e.key)) {
      AppTheme.I.set(key);
      expect(kCard, isNot(Colors.white), reason: '$key 深色卡片仍是白色');
      expect(kCard.computeLuminance(), lessThan(.2), reason: '$key 卡片不够暗');
      // 卡片要比页面底色亮一点，才有层次
      expect(kCard.computeLuminance(),
          greaterThan(AppTheme.I.pal.bg.computeLuminance()),
          reason: '$key 卡片和底色一样，没有层次');
    }
  });

  test('跟随系统：系统深色时 App 也深色', () {
    AppTheme.I.setMode(AppThemeMode.system);
    AppTheme.I.setSystemBrightness(Brightness.light);
    expect(AppTheme.I.isDark, isFalse);
    AppTheme.I.setSystemBrightness(Brightness.dark);
    expect(AppTheme.I.isDark, isTrue);
    expect(AppTheme.I.pal.isDark, isTrue);
  });

  test('强制浅色时不跟随系统', () {
    AppTheme.I.setMode(AppThemeMode.light);
    AppTheme.I.setSystemBrightness(Brightness.dark);
    expect(AppTheme.I.isDark, isFalse, reason: '显式浅色不该被系统覆盖');
  });

  test('模式写盘并在下次启动读回', () async {
    AppTheme.I.setMode(AppThemeMode.dark);
    AppTheme.I.set('teal');
    // 落盘是 fire-and-forget，给事件队列一点时间
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('ui.themeMode'), 'dark');
    expect(sp.getString('ui.theme'), 'teal');

    // 模拟下一次冷启动：prefs 里有什么，load 后就是什么
    SharedPreferences.setMockInitialValues(
        {'ui.themeMode': 'dark', 'ui.theme': 'coral'});
    await AppTheme.I.load();
    expect(AppTheme.I.mode, AppThemeMode.dark);
    expect(AppTheme.I.key, 'coral');
    expect(AppTheme.I.isDark, isTrue);
  });

  test('buildTheme 带上正确的 brightness 与表面色', () {
    AppTheme.I.setMode(AppThemeMode.dark);
    final t = buildTheme(AppTheme.I.darkPal);
    expect(t.brightness, Brightness.dark);
    expect(t.colorScheme.surface, AppTheme.I.darkPal.card);

    final l = buildTheme(AppTheme.I.lightPal);
    expect(l.brightness, Brightness.light);
    expect(l.colorScheme.surface, Colors.white);
  });

  test('语义浅底在深色下调暗，否则会在暗背景上发光', () {
    AppTheme.I.setMode(AppThemeMode.light);
    final lightGreen = kGreen50;
    AppTheme.I.setMode(AppThemeMode.dark);
    expect(kGreen50, isNot(lightGreen));
    expect(kGreen50.computeLuminance(), lessThan(.1));
    expect(kAmber50.computeLuminance(), lessThan(.1));
  });
}
