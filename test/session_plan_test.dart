import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:app_worddeer/pages/session.dart';
import 'package:app_worddeer/progress.dart';
import 'package:flutter_test/flutter_test.dart';

/// 今日队列的新词混排。
///
/// 曾经的写法在 while 里无条件 `fresh.clear()`：只要「到期旧词」比「新词」多，
/// 插完第一轮以后剩下的新词就被整批吞掉（old=10 / fresh=5 时只剩 1 个新词）。
void main() {
  setUp(() {
    // 20 个词，A1，中文各不相同（选项需要 4 个干扰项）
    final rows = [
      for (var i = 0; i < 20; i++)
        '["w$i","词$i","x","[a]","[a]",1,"A1","测试"]',
    ];
    WordBank.I.applyRaw('[${rows.join(',')}]');
    Progress.I.states.clear();
    Progress.I.newPerDay = 10;
    Progress.I.reviewPerDay = 40;
    Progress.I.todayNew = 0;
    // 每例都从内置免费档起（newPerDayMax=10），避免上一条用例改了 Ent 影响下一条
    Ent.I.ent = const Entitlement();
  });

  tearDown(() {
    Progress.I.states.clear();
    Progress.I.newPerDay = 10;
    Progress.I.reviewPerDay = 40;
    Progress.I.todayNew = 0;
  });

  void markDue(int from, int to) {
    for (var i = from; i < to; i++) {
      Progress.I.states['w$i'] =
          CardState(box: 1, due: 0, seen: 2, right: 2, last: 1000);
    }
  }

  test('旧词多于新词时，新词一个都不能丢', () {
    markDue(0, 10); // 10 个到期旧词
    // 剩下 10 个（w10..w19）是生词，每天上限 10 → 正好全部进来

    final plan = SessionPlan.build();
    final fresh = plan.where((e) => e.isNew).length;
    final old = plan.where((e) => !e.isNew).length;

    expect(old, 10);
    expect(fresh, 10, reason: '10 个生词都要在队列里，不能被混排吞掉');
    expect(plan, hasLength(20));

    // 新词不能全挤在开头：前 4 个应还是旧词
    expect(plan.take(4).every((e) => !e.isNew), isTrue);
  });

  test('新词很少时也要全部保留，且仍按每 4 旧 1 新混排', () {
    markDue(0, 10);
    Progress.I.newPerDay = 2; // 只放 2 个生词进来

    final plan = SessionPlan.build();
    expect(plan.where((e) => e.isNew).length, 2);
    expect(plan.where((e) => !e.isNew).length, 10);
    expect(plan, hasLength(12));
  });

  test('没有旧词时，新词原序全部保留', () {
    final plan = SessionPlan.build();
    expect(plan, hasLength(10));
    expect(plan.every((e) => e.isNew), isTrue);
  });

  test('用户设的每日新词量超过权益上限时，按上限截断', () {
    // 会员到期后 prefs 里仍是 40，后台已把他降回免费档（上限 5）
    Progress.I.newPerDay = 40;
    Ent.I.ent = const Entitlement(
      limits: Limits(
        levels: ['A1'],
        unitsPerLevel: 2,
        themesPerLevel: 1,
        newPerDayMax: 5,
        reviewPerDayMax: 40,
        cloudSync: true,
        offlineAudio: false,
        wrongBook: true,
      ),
    );

    final plan = SessionPlan.build();
    expect(plan.where((e) => e.isNew).length, 5,
        reason: '降级后不能继续按 40 词/天学');
  });
}
