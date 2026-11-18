import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/main.dart';
import 'package:app_worddeer/pages/home.dart';
import 'package:app_worddeer/pages/match.dart';
import 'package:app_worddeer/pages/session.dart';
import 'package:app_worddeer/progress.dart';

void main() {
  // 平时这些在 main() 里加载；测试直接 pumpWidget，得自己备好数据
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await WordBank.I.load();
    await Progress.I.load();
    await Curriculum.I.load();
    // 权益用内置免费档（后台不可达），保证断言稳定
    Ent.I.ent = const Entitlement();
  });

  testWidgets('App 启动冒烟测试：底部导航与首页可见', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 四个底部标签（'复习' 在关卡树里也有同名徽标，所以只断言存在）
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('复习'), findsWidgets);
    expect(find.text('词典'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    // 首页的学习信息：级别卡与模式胶囊
    expect(find.text('A1'), findsWidgets);
    expect(find.text('关卡'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('自由'), findsOneWidget);
  });

  testWidgets('从首页关卡进入配对棋盘', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final row = find.textContaining('学习关 ·').first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // 配对棋盘：顶部巩固台 + 4 行卡片
    expect(find.byKey(const ValueKey('shelf')), findsOneWidget);
    expect(find.text('刚配对'), findsOneWidget);
    expect(find.textContaining('对配对'), findsOneWidget);
  });

  testWidgets('从首页主题进入配对棋盘（与关卡同一种展示方式）', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 免费档第一个主题已解锁，点主卡片进入游戏
    final hero = find.textContaining('继续学习');
    await tester.ensureVisible(hero);
    await tester.pumpAndSettle();
    await tester.tap(hero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // 两列卡片配对：关卡同款棋盘，而不是四选一/拼写/听音混排
    expect(find.byType(MatchPage), findsOneWidget);
    expect(find.byType(SessionPage), findsNothing);
    expect(find.byKey(const ValueKey('shelf')), findsOneWidget);
    expect(find.text('刚配对'), findsOneWidget);
    expect(find.textContaining('对配对'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自由练习仍是混合题型，不受主题改造影响', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('自由'));
    await tester.pumpAndSettle();
    final start = find.text('开始自由练习');
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(SessionPage), findsOneWidget);
    expect(find.byType(MatchPage), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页主题区：免费额度按权益显示，锁着的主题点开付费墙', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 免费档：每级 1 个主题（后台可改，这里读的是 Ent）
    expect(find.textContaining('免费开放 1 /'), findsOneWidget);

    // 点「解锁全部」→ 付费墙
    await tester.ensureVisible(find.text('解锁全部'));
    await tester.tap(find.text('解锁全部'));
    await tester.pumpAndSettle();
    expect(find.text('解锁全部课程'), findsOneWidget);
  });

  testWidgets('主题列表为空时不 RangeError，显示空态卡片', (WidgetTester tester) async {
    // 后台 topics 表漏配一个级别时 themesFor 会返回空列表，
    // 以前 _themePanel 直接取 [0]，首页当场崩掉。
    final savedLv = Curriculum.I.curLv;
    final savedTopics = Map<String, List<String>>.from(WordBank.I.levelTopics);
    WordBank.I.levelTopics['ZZ'] = const [];
    Curriculum.I.curLv = 'ZZ';
    addTearDown(() {
      WordBank.I.levelTopics
        ..clear()
        ..addAll(savedTopics);
      Curriculum.I.curLv = savedLv;
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('这个级别还没有主题'), findsOneWidget);
  });

  testWidgets('主题英雄卡跟着「第一个没学完的主题」走，不再写死第 0 个', (WidgetTester tester) async {
    final savedLv = Curriculum.I.curLv;
    final savedThemes = Map<String, int>.from(Curriculum.I.themes);
    Curriculum.I.curLv = 'A1';
    addTearDown(() {
      Curriculum.I.themes
        ..clear()
        ..addAll(savedThemes);
      Curriculum.I.curLv = savedLv;
    });

    final all = Curriculum.I.curThemes;
    expect(all.length, greaterThan(1), reason: 'A1 至少要有两个主题才测得出差别');

    // 第一个主题标记为「学完了」，第二个学了一半
    Curriculum.I.themes['A1:t0'] = Curriculum.I.themeWords(0).length;
    Curriculum.I.themes['A1:t1'] = 3;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 英雄卡显示第 2 个主题 → 屏上出现两次（英雄卡 + 下面网格卡）；
    // 已学完的第 1 个只剩网格里那一次
    expect(find.text(all[1].name), findsNWidgets(2),
        reason: '英雄卡应切到第一个没学完的主题');
    expect(find.text(all[0].name), findsOneWidget,
        reason: '已学完的主题不该再占英雄卡');
  });
}
