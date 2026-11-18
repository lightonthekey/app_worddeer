import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/pages/match.dart';

import 'package:app_worddeer/confetti.dart';

Word _w(int i) => Word(
      en: 'w$i',
      zh: '词$i',
      detail: 'n.词$i, 释义$i',
      phUs: '[w$i]',
      phUk: '',
      lv: 1,
      cefr: const [],
      topic: const [],
    );

const ok50 = Color(0xFFEAF9EF);
const bad50 = Color(0xFFFCECEC);

/// 某一格现在是哪个词（返回序号，空格返回 -1）
int _slotWord(WidgetTester t, bool en, int slot) {
  for (var k = 0; k < 40; k++) {
    final f = find.descendant(
      of: find.byKey(ValueKey('${en ? 'en' : 'zh'}$slot')),
      matching: find.text(en ? 'w$k' : '词$k'),
    );
    if (f.evaluate().isNotEmpty) return k;
  }
  return -1;
}

List<int> _column(WidgetTester t, bool en) =>
    [for (var i = 0; i < kPairs; i++) _slotWord(t, en, i)];

/// 某一格卡的底色（白=普通、绿=配对成功、红=配错）
Color? _slotBg(WidgetTester t, bool en, int slot) {
  final f = find.descendant(
    of: find.byKey(ValueKey('${en ? 'en' : 'zh'}$slot')),
    matching: find.byType(AnimatedContainer),
  );
  if (f.evaluate().isEmpty) return null;
  final d = t.widget<AnimatedContainer>(f.first).decoration as BoxDecoration?;
  return d?.color;
}

/// 巩固台里按位置排列的英文（左→右）
List<String> _shelfWords(WidgetTester t) => t
    .widgetList<Text>(find.descendant(
      of: find.byKey(const ValueKey('shelf')),
      matching: find.byType(Text),
    ))
    .map((w) => w.data ?? '')
    .where((s) => s.startsWith('w'))
    .toList();

Future<void> _mount(WidgetTester t, {int n = 10, MatchScene? scene, String? title}) async {
  await t.pumpWidget(MaterialApp(
    home: MatchPage(
      words: List.generate(n, _w),
      title: title ?? 'U3 学习关',
      scene: scene ?? MatchScene.level,
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 60));
}

/// 点一对能配上的卡；[settle] 是配对后要等的时长（默认走完整条时间轴）
Future<int> _playOne(WidgetTester t, {int settle = 1100}) async {
  var ei = -1;
  var zi = -1;
  for (var i = 0; i < kPairs && ei < 0; i++) {
    final w = _slotWord(t, true, i);
    if (w < 0) continue;
    // 已经配对、还没退场的绿卡不能再点，换一对
    if (_slotBg(t, true, i) == ok50) continue;
    for (var j = 0; j < kPairs; j++) {
      if (_slotBg(t, false, j) == ok50) continue;
      if (_slotWord(t, false, j) == w) {
        ei = i;
        zi = j;
        break;
      }
    }
  }
  expect(ei, greaterThanOrEqualTo(0), reason: '桌上该有一对能配上的卡');
  final word = _slotWord(t, true, ei);

  await t.tap(find.descendant(
    of: find.byKey(ValueKey('en$ei')),
    matching: find.text('w$word'),
  ));
  await t.pump();
  await t.tap(find.descendant(
    of: find.byKey(ValueKey('zh$zi')),
    matching: find.text('词$word'),
  ));
  await t.pump();
  await t.pump(Duration(milliseconds: settle));
  // 巩固台左移靠帧推进，补两帧让它走完
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
  return word;
}

void main() {
  testWidgets('首屏：4 行 8 张卡，巩固台空着', (tester) async {
    await _mount(tester);

    for (var i = 0; i < kPairs; i++) {
      expect(find.byKey(ValueKey('en$i')), findsOneWidget);
      expect(find.byKey(ValueKey('zh$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('en4')), findsNothing,
        reason: '棋盘只有 4 行');

    // 4 张英文 + 4 张中文
    expect(_column(tester, true).where((w) => w >= 0).length, kPairs);
    expect(_column(tester, false).where((w) => w >= 0).length, kPairs);

    expect(find.text('刚配对'), findsOneWidget);
    expect(find.text('配对成功的词会停在这里'), findsOneWidget);
    expect(_shelfWords(tester), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('中文卡保留释义：detail 显示在中文下面', (tester) async {
    await _mount(tester);
    expect(find.textContaining('n.词'), findsWidgets,
        reason: '中文卡副行应该是 w.detail');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('配对正确：变绿 → 飞进巩固台 → 英文原位补新词', (tester) async {
    await _mount(tester);

    final e0 = _slotWord(tester, true, 0);
    var zi = -1;
    for (var j = 0; j < kPairs; j++) {
      if (_slotWord(tester, false, j) == e0) {
        zi = j;
        break;
      }
    }
    expect(zi, greaterThanOrEqualTo(0));

    final enBefore = _column(tester, true);

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('en0')),
      matching: find.text('w$e0'),
    ));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey('zh$zi')),
      matching: find.text('词$e0'),
    ));
    await tester.pump();

    // 判定后（140ms）两张卡变绿
    await tester.pump(const Duration(milliseconds: 200));
    expect(_slotBg(tester, true, 0), ok50, reason: '英文卡该变绿');
    expect(_slotBg(tester, false, zi), ok50, reason: '中文卡该变绿');

    // 再等飞行 + 落位（480 + 340）走完
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();

    // 巩固台里有这个词
    expect(_shelfWords(tester), ['w$e0']);
    expect(find.text('最近 1 个'), findsOneWidget);

    // 英文列位置固定：第 0 格换成了新词，其余 3 格原地不动
    expect(_slotWord(tester, true, 0), isNot(e0));
    for (var i = 1; i < kPairs; i++) {
      expect(_slotWord(tester, true, i), enBefore[i],
          reason: '英文列第 $i 行不该动');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('判错：只红一下，卡不回退也不换位', (tester) async {
    await _mount(tester);

    final e0 = _slotWord(tester, true, 0);
    var zi = -1;
    for (var j = 0; j < kPairs; j++) {
      if (_slotWord(tester, false, j) != e0) {
        zi = j;
        break;
      }
    }

    final enBefore = _column(tester, true);
    final zhBefore = _column(tester, false);

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('en0')),
      matching: find.text('w$e0'),
    ));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('zh$zi')));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));
    expect(_slotBg(tester, true, 0), bad50);
    expect(_slotBg(tester, false, zi), bad50);

    // 恢复
    await tester.pump(const Duration(milliseconds: 600));
    expect(_slotBg(tester, true, 0), Colors.white);
    expect(_column(tester, true), enBefore, reason: '配错不该换牌');
    expect(_column(tester, false), zhBefore);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('流畅度：绿卡还在停留就能配下一组，直接连对 2', (tester) async {
    await _mount(tester);

    // 第一对
    await _playOne(tester, settle: 200);
    expect(_slotBg(tester, true, 0), isNot(Colors.white));

    // 立刻配第二对（此刻上一对还在绿卡停留期）
    await _playOne(tester, settle: 200);
    expect(find.text('连对 2！'), findsOneWidget,
        reason: '前一组的动画没走完也应该能接着配');

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('巩固台满 3 个后整体左移：最新在最右，最旧的滑走', (tester) async {
    await _mount(tester, n: 12);

    final got = <int>[];
    for (var k = 0; k < 4; k++) {
      got.add(await _playOne(tester, settle: 1200));
    }

    final shelf = _shelfWords(tester);
    expect(shelf.length, 3, reason: '巩固台最多留 3 个');
    expect(shelf.map((s) => s.substring(1)).map(int.parse).toList(),
        got.sublist(1), reason: '第 4 个进来后，最旧那个被挤出去');

    // 最新的那个仍然高亮
    expect(find.text('最近 3 个'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget, reason: '只有最新的那个带绿勾');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('中文列每次配对后都重排，且不会出现「同一行左右同词」', (tester) async {
    await _mount(tester, n: 16);

    var changed = 0;
    List<int> prev = _column(tester, false);
    for (var k = 0; k < 4; k++) {
      await _playOne(tester, settle: 1200);
      final now = _column(tester, false);
      // 不变式：没有任何一行左右是同一个词
      final en = _column(tester, true);
      for (var i = 0; i < kPairs; i++) {
        if (en[i] >= 0 && now[i] >= 0) {
          expect(now[i], isNot(en[i]), reason: '第 $i 行左右成了同一对');
        }
      }
      if (now.join(',') != prev.join(',')) changed++;
      prev = now;
    }
    expect(changed, greaterThanOrEqualTo(2), reason: '中文列该被打乱，不能固定');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('整局能打完并出结算', (tester) async {
    await _mount(tester, n: 10);

    for (var k = 0; k < 10; k++) {
      await _playOne(tester, settle: 1100);
      if (find.text('本关完成').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('本关完成'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(find.text('一次全对，整关满星'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('主题场景：玩法一致，结算文案是「主题完成」', (tester) async {
    await _mount(tester, n: 6, scene: MatchScene.theme);

    for (var k = 0; k < 6; k++) {
      await _playOne(tester, settle: 1100);
      if (find.text('主题完成').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('主题完成'), findsOneWidget);
    expect(find.text('一次全对，直接满星拿下这个主题'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词数不是 4 的倍数（13 词）也能打完', (tester) async {
    await _mount(tester, n: 13);

    for (var k = 0; k < 13; k++) {
      await _playOne(tester, settle: 1100);
      if (find.text('本关完成').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('本关完成'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('小屏（320×568）不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await _mount(tester, n: 12);

    expect(tester.takeException(), isNull, reason: '小屏首屏不该 overflow');

    await _playOne(tester, settle: 1200);
    expect(tester.takeException(), isNull, reason: '巩固台有词后也不该 overflow');

    await _playOne(tester, settle: 1200);
    await _playOne(tester, settle: 1200);
    await _playOne(tester, settle: 1400);
    expect(tester.takeException(), isNull, reason: '巩固台满 3 个左移时不该 overflow');

    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  test('纸屑：中点炸开后能全部散尽', () {
    final f = ConfettiField(seed: 1);
    f.burstAt(const Offset(100, 100), n: 14);
    expect(f.length, 14);
    f.advanceFrames(600);
    expect(f.length, 0);
  });
}
