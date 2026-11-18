import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/pages/checkin.dart';
import 'package:app_worddeer/pages/home.dart';
import 'package:app_worddeer/progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页改版后的回归测试：小屏不溢出、下拉能开合、三页能互相到达。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await WordBank.I.load();
    await Progress.I.load();
    await Curriculum.I.load();
    Ent.I.ent = const Entitlement();
  });

  Future<void> boot(WidgetTester t, Size size) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: HomePage())));
    await t.pumpAndSettle();
  }

  testWidgets('小屏 320×568：关卡路径不溢出', (t) async {
    await boot(t, const Size(320, 568));

    expect(t.takeException(), isNull);
    expect(find.text('关卡'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('自由'), findsOneWidget);
    // 当前关的「继续」标签在窄屏也得放得下
    expect(find.textContaining('继续 · U'), findsOneWidget);
  });

  testWidgets('级别下拉：从顶部展开，5 个级别都在，点遮罩收起', (t) async {
    await boot(t, const Size(390, 844));

    await t.tap(find.text('入门'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('选择级别'), findsOneWidget);
    for (final id in ['A1', 'A2', 'B1', 'B2', 'C1']) {
      expect(find.textContaining(id), findsWidgets);
    }
    expect(find.text('今天已学'), findsOneWidget);
    expect(find.text('换主题'), findsOneWidget);

    // 点下方的遮罩收起
    await t.tapAt(const Offset(195, 760));
    await t.pumpAndSettle();
    expect(find.text('选择级别'), findsNothing);
  });

  testWidgets('下拉里的「换主题」切到主题路径', (t) async {
    await boot(t, const Size(390, 844));

    await t.tap(find.text('入门'));
    await t.pumpAndSettle();
    await t.tap(find.text('换主题'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // 主题是方块：当前那个写已学进度，底部常驻 CTA 已删
    expect(find.textContaining('已学 '), findsOneWidget);
    expect(find.textContaining('继续 · '), findsNothing);
    expect(find.textContaining('免费开放'), findsOneWidget);
    // 右下角「回到学习位置」
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });

  testWidgets('主题页滚走以后，右下角按钮把人带回当前主题', (t) async {
    await boot(t, const Size(390, 844));
    await t.tap(find.text('主题'));
    await t.pumpAndSettle();

    // 当前主题是第 0 个，打开时就在顶部
    final start = t.getTopLeft(find.text('个人信息')).dy;

    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -520));
    await t.pumpAndSettle();
    final scrolled = t.getTopLeft(find.text('个人信息')).dy;
    expect(scrolled, lessThan(start - 200), reason: '没滚动，后面就测不出回位');

    await t.tap(find.byTooltip('回到学习位置'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('个人信息')).dy, closeTo(start, 4),
        reason: '点完应该回到当前主题的位置');
    expect(t.takeException(), isNull);
  });

  testWidgets('小屏 320×568：主题方块不贴边、不溢出', (t) async {
    await boot(t, const Size(320, 568));
    await t.tap(find.text('主题'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    final tiles = find.textContaining('词');
    expect(tiles, findsWidgets);

    // 最左/最右的方块必须落在 18dp 内边距之内
    final names = Curriculum.I.curThemes.map((e) => e.name).toList();
    for (final n in names.take(4)) {
      final f = find.text(n);
      if (f.evaluate().isEmpty) continue;
      final r = t.getRect(f.first);
      expect(r.left, greaterThan(18), reason: '$n 的方块贴到屏幕左边缘了');
      expect(r.right, lessThan(320 - 18), reason: '$n 的方块超出右边缘');
    }
  });

  testWidgets('顶栏火焰进打卡页，能返回', (t) async {
    await boot(t, const Size(390, 844));

    await t.tap(find.textContaining('天'));
    await t.pumpAndSettle();

    expect(find.byType(CheckinPage), findsOneWidget);
    expect(find.text('连胜日历'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.tap(find.byTooltip('关闭'));
    await t.pumpAndSettle();
    expect(find.byType(CheckinPage), findsNothing);
  });
}
