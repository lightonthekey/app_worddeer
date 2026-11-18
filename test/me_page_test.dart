import 'package:app_worddeer/app_settings.dart';
import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/pages/me.dart';
import 'package:app_worddeer/progress.dart';
import 'package:app_worddeer/progress_sync.dart';
import 'package:app_worddeer/theme.dart';
import 'package:app_worddeer/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() async {
    Auth.I.user = null;
    ProgressSync.I.resetForTest();
    Ent.I.ent = const Entitlement();
    SharedPreferences.setMockInitialValues({});
    AppSettings.I.accent = 'us';
    AppSettings.I.haptic = true;
  });

  tearDown(() => AppTheme.I.set('indigo'));

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
    expect(find.text('编辑资料'), findsOneWidget, reason: '退出登录已收进设置页');
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

  testWidgets('已登录：昵称为空（选填）不崩，头像与显示名退回用户名', (tester) async {
    // 注册页明写「昵称（可选）」，空串是常态。
    // 之前头像取 `nickname.characters.first`，空串直接抛 StateError → 白屏。
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '');
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('deer'), findsOneWidget, reason: '没有昵称就显示用户名');
    expect(find.text('D'), findsOneWidget, reason: '头像取用户名的首字');
  });

  testWidgets('已登录：我的页监听 appTick，学完词切回来统计会跟着变', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    Progress.I.states.clear();
    await pump(tester);
    expect(find.text('0'), findsWidgets); // 三个统计初始都是 0

    // 模拟在别处学完一个词，然后通知全局刷新
    final now = DateTime.now().millisecondsSinceEpoch;
    Progress.I.states['apple'] =
        CardState(box: 1, due: now, seen: 1, right: 1, last: now);
    appTick.value++;
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget, reason: '学过 1 —— 不监听 appTick 就停在 0');
    Progress.I.states.clear();
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

  testWidgets('外观主题：点青绿整套换掉，重启别的页面也跟着走', (tester) async {
    await pump(tester);
    expect(AppTheme.I.key, 'indigo');

    await tester.tap(find.text('青绿'));
    await tester.pumpAndSettle();

    expect(AppTheme.I.key, 'teal');
    expect(AppTheme.I.pal.pri, const Color(0xFF109E90));
    // 派生色跟着换：已学底不再是靛蓝那套
    expect(AppTheme.I.pal.doneBg, isNot(kPalettes.first.doneBg));
    // 选中的那颗圆点带勾
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('设置入口：改昵称 / 清除记录 / 注销账号都在设置页', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    await pump(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('清除学习记录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);

    // 改昵称：弹窗里保存后账号卡跟着变
    await tester.tap(find.text('昵称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新小鹿');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(Auth.I.user!.displayName, '新小鹿');

    // 退出登录在最底下，滚到底才在树里
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('设置：发音切英式，设置写盘并在下次启动读回', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    await pump(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('美式'), findsOneWidget, reason: '默认美式');
    await tester.tap(find.text('发音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英式'));
    await tester.pumpAndSettle();

    expect(AppSettings.I.accent, 'uk');
    expect(find.text('英式'), findsOneWidget, reason: '行上的值跟着变');

    // 模拟重启：内存值清掉后从 prefs 读回来
    AppSettings.I.accent = 'us';
    await AppSettings.I.load();
    expect(AppSettings.I.accent, 'uk');
  });

  testWidgets('设置：答题震动可关，配对页不再触发震动', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    await pump(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.text('答题震动'));
    await tester.pumpAndSettle();

    expect(AppSettings.I.haptic, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('设置：关于里的词库/记忆算法可点开，用户名点按可复制', (tester) async {
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    await pump(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // 用户名 → 复制（测试环境没有真剪贴板，补一个通道处理器）
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
    await tester.tap(find.text('@deer'));
    await tester.pumpAndSettle();
    expect(find.text('用户名已复制'), findsOneWidget);

    // 「关于」在屏幕外，先滚下去
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();

    // 记忆算法 → 说明弹窗
    await tester.tap(find.text('记忆算法'));
    await tester.pumpAndSettle();
    expect(find.textContaining('30 天'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // 词库 → 规模弹窗
    await tester.tap(find.text('词库'));
    await tester.pumpAndSettle();
    expect(find.text('词库'), findsNWidgets(2), reason: '行 + 弹窗标题');
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });
}
