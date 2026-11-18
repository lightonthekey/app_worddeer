import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/pages/home.dart';
import 'package:app_worddeer/pages/match.dart';
import 'package:app_worddeer/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/pages/me.dart';
import 'package:app_worddeer/pages/settings.dart';
import 'package:app_worddeer/theme.dart';
import 'package:app_worddeer/ui.dart';

/// 主题视觉探针（不是常规回归测试）。
///
///   flutter test test/theme_probe.dart --update-goldens
///
/// 产出 test/shots/theme-me-indigo / -teal / -orange / -purple、theme-settings。
/// 文件故意不叫 *_test.dart，`flutter test` 不会自动跑它。

Future<void> _loadFont() async {
  final bytes = File('C:/Windows/Fonts/Deng.ttf').readAsBytesSync();
  final loader = FontLoader('Probe')
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
  final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
  if (emoji.existsSync()) {
    final e = FontLoader('ProbeEmoji')
      ..addFont(Future<ByteData>.value(
          ByteData.view(emoji.readAsBytesSync().buffer)));
    await e.load();
  }
  final icons = File(
      'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(
          ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont();
    SharedPreferences.setMockInitialValues({});
    await WordBank.I.load();
    await Progress.I.load();
    await Curriculum.I.load();
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '词汇旅人');
    Ent.I.ent = const Entitlement();
    _seedProgress();
  });

  tearDown(() => AppTheme.I.set('indigo'));

  Future<void> shot(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final base = buildTheme(AppTheme.I.pal);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(
            fontFamily: 'Probe', fontFamilyFallback: const ['ProbeEmoji']),
      ),
      home: Scaffold(body: page),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  for (final key in ['indigo', 'teal', 'orange', 'purple']) {
    testWidgets('我的页 · $key', (tester) async {
      AppTheme.I.set(key);
      await shot(tester, 'theme-me-$key', const MePage());
    });
  }

  testWidgets('设置页 · indigo', (tester) async {
    await shot(tester, 'theme-settings', const SettingsPage());
  });

  for (final key in ['teal', 'orange']) {
    testWidgets('关卡页 · $key', (tester) async {
      AppTheme.I.set(key);
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final base = buildTheme(AppTheme.I.pal);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(
              fontFamily: 'Probe', fontFamilyFallback: const ['ProbeEmoji']),
        ),
        home: const HomePage(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await expectLater(
        find.byType(HomePage),
        matchesGoldenFile('shots/theme-home-$key.png'),
      );
    });

    testWidgets('配对页 · $key', (tester) async {
      AppTheme.I.set(key);
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final base = buildTheme(AppTheme.I.pal);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(
              fontFamily: 'Probe', fontFamilyFallback: const ['ProbeEmoji']),
        ),
        home: MatchPage(
          words: [
            for (var i = 0; i < 8; i++)
              Word(
                en: ['hello', 'sleep', 'milk', 'sugar'][i % 4] + (i > 3 ? '2' : ''),
                zh: ['你好', '睡觉', '牛奶', '糖'][i % 4] + (i > 3 ? '2' : ''),
                detail: 'n. 释义',
                phUs: '[heˈloʊ]',
                phUk: '',
                lv: 1,
                cefr: const [],
                topic: const [],
              ),
          ],
          title: 'U3 学习关',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await expectLater(
        find.byType(MatchPage),
        matchesGoldenFile('shots/theme-match-$key.png'),
      );
    });
  }
}

/// 让统计数字有点内容，免得截图全是 0
void _seedProgress() {}
