import 'package:app_worddeer/curriculum.dart';
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
}
