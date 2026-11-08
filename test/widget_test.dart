import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/main.dart';
import 'package:app_worddeer/progress.dart';

void main() {
  // 平时这些在 main() 里加载；测试直接 pumpWidget，得自己备好数据
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await WordBank.I.load();
    await Progress.I.load();
    await Curriculum.I.load();
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

    // 配对棋盘的列头与计数
    expect(find.text('ENGLISH'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.textContaining('对配对'), findsOneWidget);
  });
}
