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

  testWidgets('下拉里的「换主题」切到主题阶梯', (t) async {
    await boot(t, const Size(390, 844));

    await t.tap(find.text('入门'));
    await t.pumpAndSettle();
    await t.tap(find.text('换主题'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // 阶梯底部常驻「继续 · 主题名」
    expect(find.textContaining('继续 · '), findsOneWidget);
    expect(find.textContaining('免费开放'), findsOneWidget);
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
