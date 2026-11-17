import 'package:app_worddeer/auth.dart';
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
}
