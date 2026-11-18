import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/pages/match.dart';

/// 视觉探针（不是常规回归测试）。
///
///   flutter test test/visual_probe.dart --update-goldens
///
/// 用系统里的中文字体渲染真实排版，把四个关键状态存成 PNG：
/// test/shots/visual-01-idle / 02-one / 03-shelf-full / 04-done。
/// 文件故意不叫 *_test.dart，`flutter test` 不会自动跑它。

const _words = [
  ('hello', '你好', 'interj.你好, 哎呀, 喂', '[heˈloʊ]'),
  ('sleep', '睡觉', 'vi.睡觉, 容纳 n.睡眠, 睡眠时间, 眼屎', '[sliːp]'),
  ('milk', '牛奶', 'n.牛奶, 母乳, 植物乳汁 v.挤奶, 榨取', '[mɪlk]'),
  ('sugar', '糖', 'n.糖, 一勺糖, 糖分, 甜心 v.加糖 interj.哎呀', '[ˈʃʊɡər]'),
  ('head', '头部', 'n.头部, 头脑, 头痛, 领导, 顶部, 源头 v.朝...方向前进', '[hed]'),
  ('water', '水', 'n.水, 水体, 水面, 领海, 困境 v.浇水, 流泪, 灌溉', '[ˈwɑːtər]'),
  ('friend', '朋友', 'n.朋友, 友人, 支持者, 赞助者', '[frend]'),
  ('school', '学校', 'n.学校, 学院, 学派, 一群鱼 v.教育, 训练', '[skuːl]'),
  ('beautiful', '美丽的', 'adj.美丽的, 出色的, 令人愉快的', '[ˈbjuːtɪfl]'),
  ('happy', '快乐的', 'adj.快乐的, 幸福的, 乐意的, 恰当的', '[ˈhæpi]'),
  ('cat', '猫', 'n.猫, 猫科动物, 恶毒的女人', '[kæt]'),
  ('book', '书', 'n.书, 书籍, 账簿, 剧本 v.预订, 登记', '[bʊk]'),
];

Word _w(int i) => Word(
      en: _words[i].$1,
      zh: _words[i].$2,
      detail: _words[i].$3,
      phUs: _words[i].$4,
      phUk: '',
      lv: 1,
      cefr: const [],
      topic: const [],
    );

Future<void> _loadFont() async {
  final bytes = File('C:/Windows/Fonts/Deng.ttf').readAsBytesSync();
  final loader = FontLoader('Probe')
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

int _slotWord(WidgetTester t, bool en, int slot) {
  for (var k = 0; k < _words.length; k++) {
    final f = find.descendant(
      of: find.byKey(ValueKey('${en ? 'en' : 'zh'}$slot')),
      matching: find.text(en ? _words[k].$1 : _words[k].$2),
    );
    if (f.evaluate().isNotEmpty) return k;
  }
  return -1;
}

Color? _slotBg(WidgetTester t, bool en, int slot) {
  final f = find.descendant(
    of: find.byKey(ValueKey('${en ? 'en' : 'zh'}$slot')),
    matching: find.byType(AnimatedContainer),
  );
  if (f.evaluate().isEmpty) return null;
  final d = t.widget<AnimatedContainer>(f.first).decoration as BoxDecoration?;
  return d?.color;
}

/// 按 16ms 一帧推进：tester.pump(大时长) 只出 1 帧，
/// 动画控制器会「跳」到终点，截图里就会看到飞行中的克隆卡停在空中。
Future<void> _advance(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    final step = left < 16 ? left : 16;
    await t.pump(Duration(milliseconds: step));
    left -= step;
  }
}

Future<void> _playOne(WidgetTester t) async {
  var ei = -1, zi = -1;
  for (var i = 0; i < kPairs && ei < 0; i++) {
    final w = _slotWord(t, true, i);
    if (w < 0 || _slotBg(t, true, i) == const Color(0xFFEAF9EF)) continue;
    for (var j = 0; j < kPairs; j++) {
      if (_slotWord(t, false, j) == w) {
        ei = i;
        zi = j;
        break;
      }
    }
  }
  if (ei < 0) return;
  final w = _slotWord(t, true, ei);

  await t.tap(find.descendant(
    of: find.byKey(ValueKey('en$ei')),
    matching: find.text(_words[w].$1),
  ));
  await t.pump();
  await t.tap(find.descendant(
    of: find.byKey(ValueKey('zh$zi')),
    matching: find.text(_words[w].$2),
  ));
  await t.pump();
  await _advance(t, 1100);
  await _advance(t, 400);
  await t.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont();
  });

  testWidgets('视觉探针', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 2;

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Probe', useMaterial3: true),
      home: MatchPage(
        words: List.generate(_words.length, _w),
        title: 'U3 学习关',
        subtitle: '12 对配对 · 左边英文 · 右边中文',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    await expectLater(
      find.byType(MatchPage),
      matchesGoldenFile('shots/visual-01-idle.png'),
    );

    // 配一对：绿卡停留的画面
    var ei = 0;
    var zi = 0;
    for (var i = 0; i < kPairs; i++) {
      final w = _slotWord(tester, true, i);
      if (w < 0) continue;
      for (var j = 0; j < kPairs; j++) {
        if (_slotWord(tester, false, j) == w) {
          ei = i;
          zi = j;
        }
      }
    }
    final w0 = _slotWord(tester, true, ei);
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey('en$ei')),
      matching: find.text(_words[w0].$1),
    ));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey('zh$zi')),
      matching: find.text(_words[w0].$2),
    ));
    await tester.pump();
    await _advance(tester, 260);

    await expectLater(
      find.byType(MatchPage),
      matchesGoldenFile('shots/visual-02-green.png'),
    );

    // 走完飞行，巩固台 1 个
    await _advance(tester, 800);
    await expectLater(
      find.byType(MatchPage),
      matchesGoldenFile('shots/visual-03-shelf-one.png'),
    );

    // 再配三对，巩固台满载
    await _playOne(tester);
    await _playOne(tester);
    await _playOne(tester);
    await expectLater(
      find.byType(MatchPage),
      matchesGoldenFile('shots/visual-04-shelf-full.png'),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
