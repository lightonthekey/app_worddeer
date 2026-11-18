import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课程进度的两个坑：
/// 1. debug 演示数据曾经跟着 save() 落盘，而 debug / release 同包名同签名
///    共用一份本地存储 —— 装上正式版会继承「已通关 U1/U2、今日 30 词」。
/// 2. 演示数据必须在用户真正开始学习时让位，否则真实进度永远被假数据压着。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Curriculum.I.passed.clear();
    Curriculum.I.part.clear();
    Curriculum.I.themes.clear();
    Curriculum.I.todayWords = 0;
    Curriculum.I.dayKey = '';
    Curriculum.I.updatedAt = 0;
  });

  test('debug 演示数据只在内存里，不写进本地存档', () async {
    await Curriculum.I.load();

    expect(Curriculum.I.passed['A1:U1'], isTrue, reason: 'debug 包内存里应有演示数据');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('curriculum_v1'), isNull,
        reason: '假进度一旦落盘，正式版装到同台设备就会继承');
  });

  test('真实学习一开始，演示数据清掉并正常落盘', () async {
    await Curriculum.I.load();

    Curriculum.I.markPassed('A1', 'U3');
    // markPassed 里的 save() 不 await，给它一点时间写完
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(Curriculum.I.passed.containsKey('A1:U1'), isFalse,
        reason: '演示数据要让位给真实进度');
    expect(Curriculum.I.part, isEmpty);
    final raw = (await SharedPreferences.getInstance())
        .getString('curriculum_v1');
    expect(raw, isNotNull, reason: '真实进度必须落盘');
    expect(raw, contains('A1:U3'));
  });

  group('关卡表', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await WordBank.I.load();
    });

    test('每 20 词一关，每 5 个学习关插一关复习', () {
      final units = Curriculum.I.unitsOf('A1');
      final words = Curriculum.I.wordCountOf('A1');
      expect(words, greaterThan(100), reason: 'A1 词库应已加载');

      final learns = units.where((u) => !u.review).toList();
      final reviews = units.where((u) => u.review).toList();

      expect(learns.length, (words / Curriculum.perUnit).ceil());
      expect(learns.first.total, Curriculum.perUnit);
      // 只有最后一关可以不满 20 词
      for (final u in learns) {
        expect(u.total, lessThanOrEqualTo(Curriculum.perUnit));
        expect(u.total, greaterThan(0));
      }
      expect(reviews.length, (learns.length - 1) ~/ 5);
      // 复习关 = 前 5 个学习关的 100 词
      for (final r in reviews) {
        expect(r.total, Curriculum.perUnit * 5);
      }
      // 最后一关必须是学习关：学完了不该再弹一个空复习关
      expect(units.last.review, isFalse);
    });

    test('关卡编号连续，复习关排在第 5、10… 个学习关之后', () {
      final units = Curriculum.I.unitsOf('A1');
      for (var i = 0; i < units.length; i++) {
        expect(units[i].id, 'U${i + 1}');
      }
      expect(units[5].review, isTrue, reason: 'U6 应是第 1 段复习');
      expect(units[11].review, isTrue, reason: 'U12 应是第 2 段复习');
      expect(units[4].review, isFalse);
    });

    test('关数按词库动态算，不是写死的 12', () {
      final n = Curriculum.I.unitCountOf('A1');
      expect(n, greaterThan(12));
      expect(n, Curriculum.I.unitsOf('A1').length);
    });
  });

  test('学完词就算打卡：addToday 记进 Progress.days', () {
    Progress.I.days.clear();
    Progress.I.streak = 0;
    Progress.I.lastActiveDay = '';

    Curriculum.I.addToday(20);

    expect(Progress.I.checkedToday, isTrue);
    expect(Progress.I.streak, 1);
    expect(Progress.I.days, contains(Progress.I.today));
  });
}
