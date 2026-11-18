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

    // 当前关旁边挂着「继续 · U3」标签，点它进关
    final label = find.textContaining('继续 · U');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // 配对棋盘：顶部巩固台 + 4 行卡片
    expect(find.byKey(const ValueKey('shelf')), findsOneWidget);
    expect(find.text('巩固台'), findsOneWidget);
    expect(find.textContaining('对配对'), findsOneWidget);
  });

  testWidgets('从首页主题进入配对棋盘（与关卡同一种展示方式）', (WidgetTester tester) async {
    await tester.pumpWidget(const EngApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 当前主题的方块：副行是「已学 x / y」，点它直接进主题（底部 CTA 已删）
    final cur = find.textContaining('已学 ');
    expect(cur, findsOneWidget, reason: '只有当前主题方块显示已学进度');
    await tester.ensureVisible(cur);
    await tester.pumpAndSettle();
    await tester.tap(cur);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // 两列卡片配对：关卡同款棋盘，而不是四选一/拼写/听音混排
    expect(find.byType(MatchPage), findsOneWidget);
    expect(find.byType(SessionPage), findsNothing);
    expect(find.byKey(const ValueKey('shelf')), findsOneWidget);
    expect(find.text('巩固台'), findsOneWidget);
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

  testWidgets('主题方块的当前态跟着「第一个没学完的主题」走，不再写死第 0 个',
      (WidgetTester tester) async {
    final savedLv = Curriculum.I.curLv;
    final savedThemes = Map<String, int>.from(Curriculum.I.themes);
    final savedEnt = Ent.I.ent;
    Curriculum.I.curLv = 'A1';
    // 免费档每个级别只开 1 个主题，t1 会落在锁上、不显示进度，先把主题全开
    Ent.I.ent = const Entitlement(
      vip: true,
      limits: Limits(
        levels: ['A1', 'A2', 'B1', 'B2', 'C1'],
        unitsPerLevel: 12,
        themesPerLevel: 12,
        newPerDayMax: 40,
        reviewPerDayMax: 100,
        cloudSync: true,
        offlineAudio: true,
        wrongBook: true,
      ),
    );
    addTearDown(() {
      Curriculum.I.themes
        ..clear()
        ..addAll(savedThemes);
      Curriculum.I.curLv = savedLv;
      Ent.I.ent = savedEnt;
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

    // 只有「当前」那个方块写已学进度
    final w0 = Curriculum.I.themeWords(0).length;
    final w1 = Curriculum.I.themeWords(1).length;
    expect(find.text('已学 3 / $w1'), findsOneWidget,
        reason: '当前主题应切到第一个没学完的（t1）');
    expect(find.text('已学 $w0 / $w0'), findsNothing,
        reason: '已学完的 t0 不该再被当成当前主题');
  });
}
