import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/pages/me.dart';
import 'package:app_worddeer/progress_sync.dart';
import 'package:app_worddeer/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「我的」页账号卡：未登录 / 已登录（含同步状态）两种形态的布局回归。
/// 账号卡里塞了昵称、@用户名、同步时间三行信息，改版时最容易挤出溢出。
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: MePage()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    Auth.I.user = null;
    ProgressSync.I.resetForTest();
    Ent.I.ent = const Entitlement();
  });

  testWidgets('未登录：显示登录入口与同步承诺', (tester) async {
    await pump(tester);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('登录后学习进度换机不丢'), findsOneWidget);
    expect(find.text('登录 / 注册'), findsOneWidget);
  });

  testWidgets('已登录：显示昵称、用户名与同步时间', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    ProgressSync.I.status = ProgressSync.statusOk;
    ProgressSync.I.lastAt = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    await pump(tester);
    expect(find.text('小鹿'), findsOneWidget);
    expect(find.text('@deer'), findsOneWidget);
    expect(find.text('已同步 · 2 小时前'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('已登录：同步失败可点重试', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    ProgressSync.I.status = ProgressSync.statusError;
    await pump(tester);
    expect(find.text('同步失败 · 点此重试'), findsOneWidget);
  });

  testWidgets('我的页：免费用户点会员横幅打开付费墙（手机尺寸，防溢出）', (tester) async {
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Ent.I.ent = const Entitlement(
      limits: Limits.free,
      plans: [
        PlanInfo(code: 'vip_month', name: '月度会员', price: 18, periodDays: 30),
        PlanInfo(
            code: 'vip_year',
            name: '年度会员',
            price: 98,
            periodDays: 365,
            badge: '省 55%'),
      ],
    );
    await pump(tester);
    expect(find.text('开通会员'), findsOneWidget);

    await tester.tap(find.text('开通会员'));
    await tester.pumpAndSettle();

    expect(find.text('解锁全部课程'), findsOneWidget);
    expect(find.text('月度会员'), findsOneWidget);
    expect(find.text('年度会员'), findsOneWidget);
    expect(find.text('立即开通 ¥98'), findsOneWidget, reason: '默认选中最划算的年度套餐');
  });

  testWidgets('我的页：会员显示有效期，不再显示购买按钮', (tester) async {
    Ent.I.ent = const Entitlement(
      tier: 2,
      tierName: '年度会员',
      vip: true,
      expireAt: '2026-12-17 13:20:20',
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
    await pump(tester);
    expect(find.textContaining('有效期至 2026-12-17'), findsOneWidget);

    await tester.tap(find.text('查看权益'));
    await tester.pumpAndSettle();
    expect(find.text('你已是年度会员'), findsOneWidget);
    expect(find.textContaining('立即开通'), findsNothing);
  });
}
