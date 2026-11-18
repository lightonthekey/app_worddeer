import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/checkin.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/pages/checkin.dart';
import 'package:app_worddeer/pages/home.dart';
import 'package:app_worddeer/progress.dart';
import 'package:app_worddeer/ui.dart';

/// 首页 / 主题 / 打卡三页的视觉探针（不是常规回归测试）。
///
///   flutter test test/home_probe.dart --update-goldens
///
/// 产物：test/shots/home-01-path / 02-drop / 03-theme / 04-checkin。
/// 文件故意不叫 *_test.dart，`flutter test` 不会自动跑它。
Future<void> _loadFont() async {
  final bytes = File('C:/Windows/Fonts/Deng.ttf').readAsBytesSync();
  final loader = FontLoader('Probe')
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();

  // 测试环境默认不带图标字体，不加这一步截图里所有 Icon 都是空方块
  for (final p in const [
    'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final icons = FontLoader('MaterialIcons')
      ..addFont(
          Future<ByteData>.value(ByteData.view(f.readAsBytesSync().buffer)));
    await icons.load();
    break;
  }
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(
        textTheme: buildTheme().textTheme.apply(fontFamily: 'Probe'),
      ),
      home: Scaffold(body: home),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont();
    SharedPreferences.setMockInitialValues({});
    await WordBank.I.load();
    await Progress.I.load();
    await Curriculum.I.load();
  });

  testWidgets('首页视觉探针', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 2;

    await tester.pumpWidget(_app(const HomePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('shots/home-01-path.png'),
    );

    // 级别下拉
    await tester.tap(find.text('入门'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('shots/home-02-drop.png'),
    );

    // 收起，切到主题
    await tester.tapAt(const Offset(195, 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('主题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('shots/home-03-theme.png'),
    );

    // 学到中段：看台地之间有没有断开、S 线是否连续
    final c = Curriculum.I;
    final units = c.unitsOf(c.curLv);
    for (var i = 0; i < 8 && i < units.length; i++) {
      c.passed['${c.curLv}:${units[i].id}'] = true;
    }
    if (units.length > 8) c.part['${c.curLv}:${units[8].id}'] = 6;

    await tester.tap(find.text('关卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('shots/home-05-mid.png'),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('小屏视觉探针（320×568）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.view.devicePixelRatio = 2;

    await tester.pumpWidget(_app(const HomePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('shots/home-06-small.png'),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('打卡页视觉探针', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 2;

    // 造 18 天连续打卡（只改内存，不落盘）
    final now = DateTime.now();
    Progress.I.days.clear();
    for (var i = 17; i >= 0; i--) {
      Progress.I.days.add(dayKeyOf(now.subtract(Duration(days: i))));
    }
    Progress.I.streak = 18;

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(
        textTheme: buildTheme().textTheme.apply(fontFamily: 'Probe'),
      ),
      home: const CheckinPage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await expectLater(
      find.byType(CheckinPage),
      matchesGoldenFile('shots/home-04-checkin.png'),
    );

    Progress.I.days.clear();
    Progress.I.streak = 0;
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
