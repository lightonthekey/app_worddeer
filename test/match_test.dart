import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/confetti.dart';
import 'package:app_worddeer/pages/match.dart';

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

/// 数一数当前有多少张卡用了某个底色（绿 / 红 / 灰）
int _countBg(WidgetTester t, Color color) => t
    .widgetList<Container>(find.byType(Container))
    .where((w) => (w.decoration as BoxDecoration?)?.color == color)
    .length;

Future<void> _tapText(WidgetTester t, String s) async {
  final f = find.text(s);
  expect(f, findsOneWidget, reason: '找不到卡面文字 $s');
  await t.tap(f);
  await t.pump();
}

/// 桌面上现在有哪些词的序号（英文卡 / 中文卡各一份）
List<int> _onDesk(WidgetTester t, {required bool en}) => [
      for (var i = 0; i < 10; i++)
        if (find.text(en ? 'w$i' : '词$i').evaluate().isNotEmpty) i,
    ];

/// 牌桌上每张卡的两层 Transform（外层 translate / 内层 scale）的矩阵
List<Matrix4> _deskTransforms(WidgetTester t) => t
    .widgetList<Transform>(find.descendant(
      of: find.byKey(const ValueKey('desk')),
      matching: find.byType(Transform),
    ))
    .map((w) => w.transform)
    .toList();

/// 某一格现在放的是哪个词（返回序号，空格返回 -1）
///
/// 扫到 40：测试里一桌最多用到 20 个词，别把上限定成 10 就以为够了。
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
    [for (var i = 0; i < 5; i++) _slotWord(t, en, i)];

/// 同一个词不能在同列出现两次（补位时最容易踩）
void _expectNoDup(WidgetTester t) {
  for (var i = 0; i < 10; i++) {
    expect(find.text('w$i').evaluate().length, lessThanOrEqualTo(1),
        reason: '英文卡重复了 w$i');
    expect(find.text('词$i').evaluate().length, lessThanOrEqualTo(1),
        reason: '中文卡重复了 词$i');
  }
}

void main() {
  const ok50 = Color(0xFFE5F6EF);
  const bad50 = Color(0xFFFCECEC);
  const voidBg = Color(0xFFF6F5FB);

  testWidgets('配对正确：变绿停留 → 起爆 → 补位，桌面不空', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(10, _w))),
    );
    await tester.pump();

    // 10 张卡都在（桌面只有 5 对，逐个按在场判断）
    expect(_onDesk(tester, en: true).length, 5);
    expect(_onDesk(tester, en: false).length, 5);

    final enIdx = _onDesk(tester, en: true).first;
    await _tapText(tester, 'w$enIdx');
    await _tapText(tester, '词$enIdx');

    // 220ms 判定后变绿
    await tester.pump(const Duration(milliseconds: 300));
    expect(_countBg(tester, ok50), 2, reason: '应该正好两张绿卡');

    // 680ms 后起爆，绿卡只是慢慢淡出，仍然占位
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('w$enIdx'), findsOneWidget, reason: '起爆时词还在，方便再看一眼');

    // 走完 700 + 170，新卡补位
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('w$enIdx'), findsNothing, reason: '配过的词应已换掉');
    expect(_countBg(tester, ok50), 0, reason: '绿色状态应已清掉');

    // 桌面仍是 5 对 10 张
    expect(_onDesk(tester, en: true).length, 5);
    expect(_onDesk(tester, en: false).length, 5);
    _expectNoDup(tester);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('配对错误：卡片不消失也不换位，只红一下再恢复', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(10, _w))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 首屏 pop 收尾

    final enBefore = _column(tester, true);
    final zhBefore = _column(tester, false);

    // 桌上一张英文卡 + 一张不同词的英文卡，必然配错
    final ens = _onDesk(tester, en: true);
    final zhs = _onDesk(tester, en: false);
    final e = ens.first;
    final z = zhs.firstWhere((i) => i != e);

    await _tapText(tester, 'w$e');
    await _tapText(tester, '词$z');

    await tester.pump(const Duration(milliseconds: 300));
    expect(_countBg(tester, bad50), 2, reason: '红的只该有被点的那两张');
    // 同一个词的另一半绝不能变成灰卡虚框：那等于把正确答案指给用户
    expect(_countBg(tester, voidBg), 0, reason: '作废的另一半不许变色');
    // 也不能淡出：突然变透明同样是在提示「这张要退场了」
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.descendant(
            of: find.byKey(const ValueKey('desk')),
            matching: find.byType(AnimatedOpacity),
          ))
          .where((w) => w.opacity != 1)
          .length,
      0,
      reason: '配错后牌桌上不该有任何卡在变淡',
    );

    // 抖完红标撤掉：牌桌一个字、一个位置都没变（配错不该换牌）
    await tester.pump(const Duration(milliseconds: 700));
    expect(_countBg(tester, bad50), 0, reason: '红标要撤掉，两张卡能重新点');
    expect(_column(tester, true), enBefore, reason: '配错不该换牌、也不该挪位');
    expect(_column(tester, false), zhBefore, reason: '配错不该换牌、也不该挪位');
    expect(_onDesk(tester, en: true).length, 5, reason: '不许出现空格子');
    expect(_onDesk(tester, en: false).length, 5);
    _expectNoDup(tester);

    // 恢复之后还能正常选：点对同一张英文卡的正确中文，应该判定成功
    await _tapText(tester, 'w$e');
    await _tapText(tester, '词$e');
    await tester.pump(const Duration(milliseconds: 300));
    expect(_countBg(tester, ok50), 2, reason: '恢复后的卡必须还能操作');

    // 把后续定时跑完，避免拆树时报「Timer 还挂着」
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('连着打两对：两轮纸屑都会散尽，不会停在屏幕上', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(10, _w))),
    );
    await tester.pump();

    final field =
        tester.widget<ConfettiOverlay>(find.byType(ConfettiOverlay)).field;

    for (var round = 1; round <= 2; round++) {
      final enIdx = _onDesk(tester, en: true).first;
      await _tapText(tester, 'w$enIdx');
      await _tapText(tester, '词$enIdx');

      // 越过判定(220ms)与起爆(680ms)，这一对已经炸出纸屑
      await tester.pump(const Duration(milliseconds: 1000));
      expect(field.isEmpty, isFalse, reason: '第 $round 对应该炸出纸屑');

      // 按真实节奏走 5 秒（每次 pump 100ms ≈ 6 个物理帧），纸屑必须散尽。
      // 修复前第二轮会在 createTicker 处抛异常，纸屑永远停在原地。
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(field.isEmpty, isTrue,
          reason: '第 $round 对纸屑必须全部消失，不能留在屏幕上');
      expect(_onDesk(tester, en: true).length, 5);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('答对的卡只是「轻轻一抬」：280ms 收尾停在 -3.5px，全程不压进桌面',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(10, _w))),
    );
    await tester.pump();
    // 先让首屏的 pop 入场（340ms）走完，否则会误判成「往下载」
    await tester.pump(const Duration(milliseconds: 500));

    final idx = _onDesk(tester, en: true).first;
    await _tapText(tester, 'w$idx');
    await _tapText(tester, '词$idx');

    // 判定 220ms 后开始 hop（280ms）。逐段推进：
    // 不许有任何卡被压到桌面以下，也不许抬过高（幅度刻意做小，峰值 10px）
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      for (final t in _deskTransforms(tester)) {
        final dy = t.getTranslation().y;
        expect(dy, lessThanOrEqualTo(.1),
            reason: 'hop 过程中不该出现卡片「凹」下去的位移');
        expect(dy, greaterThanOrEqualTo(-12),
            reason: '抬升幅度要小，不该超过 12px');
      }
    }

    // 起跳结束：两张绿卡停在悬浮位（-3.5px、放大 1.015），其余 8 张还贴着 0
    final lifted = _deskTransforms(tester)
        .where((t) => t.getTranslation().y < -1)
        .map((t) => t.getTranslation().y)
        .toList();
    expect(lifted.length, 2, reason: '悬浮的应该正好是配对成功的那两张');
    for (final dy in lifted) {
      expect(dy, closeTo(-3.5, .05), reason: '收尾要停在 -3.5px 的悬浮位，不能落回 0');
    }
    final scaled = _deskTransforms(tester)
        .map((t) => t.getMaxScaleOnAxis())
        .where((s) => s > 1.01)
        .toList();
    expect(scaled.length, 2, reason: '两张绿卡都应该略微放大');

    // 把后续的 680/700/170 三段定时跑完，否则拆树时会报“Timer 还挂着”
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('补位不再固定在原位：空位挪一格，也不会补出一整行白送分', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(20, _w))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 首屏 pop 收尾

    var moved = 0;
    for (var round = 0; round < 6; round++) {
      // 找一对同词的两张卡，记下它们在各自列里的行号
      var word = -1, enSlot = -1, zhSlot = -1;
      for (var i = 0; i < 5 && word < 0; i++) {
        final w = _slotWord(tester, true, i);
        if (w < 0) continue;
        for (var j = 0; j < 5; j++) {
          if (_slotWord(tester, false, j) == w) {
            word = w;
            enSlot = i;
            zhSlot = j;
            break;
          }
        }
      }
      expect(word, greaterThanOrEqualTo(0), reason: '第 $round 轮桌上该有一对能配上的卡');

      final enBefore = _column(tester, true);
      final zhBefore = _column(tester, false);

      await _tapText(tester, 'w$word');
      await _tapText(tester, '词$word');
      // 走完判定(220)+停留(680)+散尽(700)+空档(170)，再留出补位动画
      await tester.pump(const Duration(milliseconds: 2400));
      await tester.pump(const Duration(milliseconds: 400));

      final enAfter = _column(tester, true);
      final zhAfter = _column(tester, false);
      expect(enAfter.contains(word), isFalse, reason: '配过的词该换掉了');
      expect(zhAfter.contains(word), isFalse);

      // 每列只换掉一个词，所以「新词」就是唯一没出现在打之前那列的词
      final newEn =
          enAfter.where((w) => w >= 0 && !enBefore.contains(w)).toList();
      final newZh =
          zhAfter.where((w) => w >= 0 && !zhBefore.contains(w)).toList();
      expect(newEn.length, 1);
      expect(newZh.length, 1);

      final enNew = enAfter.indexOf(newEn.single);
      final zhNew = zhAfter.indexOf(newZh.single);

      // 只挪一两格（不是整列重排）：挪了的那一列必须离开原位，且不超过两格
      final enMoved = enNew != enSlot;
      final zhMoved = zhNew != zhSlot;
      if (enMoved) {
        expect((enNew - enSlot).abs(), lessThanOrEqualTo(2),
            reason: '最多只该挪动两格');
      }
      if (zhMoved) {
        expect((zhNew - zhSlot).abs(), lessThanOrEqualTo(2),
            reason: '最多只该挪动两格');
      }
      if (enMoved || zhMoved) moved++;

      // 同一个词的两半不能补在同一行：那一行等于白送分
      expect(enNew, isNot(zhNew), reason: '两列的补位行不能重合');
      // 也不许通过「挪过去正好凑一对」造出白送格
      for (var r = 0; r < 5; r++) {
        final a = enAfter[r], b = zhAfter[r];
        if (a >= 0 && b >= 0) {
          expect(a, isNot(b), reason: '第 $r 行左右成了同一对');
        }
      }
    }

    expect(moved, greaterThanOrEqualTo(3),
        reason: '补位位置要跟着变，不能总是落回原来那一格');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('一直点同一行不会连对：那一行左右永远不是现成的一对', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(20, _w))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (var round = 0; round < 6; round++) {
      final e = _slotWord(tester, true, 2);
      final z = _slotWord(tester, false, 2);
      expect(e, greaterThanOrEqualTo(0));
      expect(z, greaterThanOrEqualTo(0));
      expect(e, isNot(z),
          reason: '第 $round 轮第 2 行左右成了同一对 —— 用户闭眼点这行就能连对');

      // 完全不动脑，固定点第 2 行的左右两张
      await _tapText(tester, 'w$e');
      await _tapText(tester, '词$z');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('整局能打完并出结算页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPage(words: List.generate(10, _w), title: 'U3 学习关')),
    );
    await tester.pump();

    for (var round = 0; round < 30; round++) {
      if (find.text('本关完成').evaluate().isNotEmpty) break;
      String? en;
      for (var i = 0; i < 10; i++) {
        if (find.text('w$i').evaluate().isNotEmpty) {
          en = 'w$i';
          break;
        }
      }
      if (en == null) {
        await tester.pump(const Duration(milliseconds: 600));
        continue;
      }
      final idx = en.substring(1);
      await _tapText(tester, en);
      await _tapText(tester, '词$idx');
      await tester.pump(const Duration(milliseconds: 2400));
    }

    expect(find.text('本关完成'), findsOneWidget);
    expect(find.text('10'), findsWidgets); // 配对正确 10 个
    // 一次全对，没有配错记录
    expect(find.textContaining('一次全对'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
