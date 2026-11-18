import 'package:app_worddeer/checkin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打卡页的日历是纯算出来的，这里只测算法，不拉整个界面。
void main() {
  group('日期键', () {
    test('补零成 yyyy-MM-dd', () {
      expect(dayKeyOf(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKeyOf(DateTime(2026, 11, 18)), '2026-11-18');
    });

    test('能往返解析', () {
      final d = DateTime(2026, 11, 18);
      expect(parseDayKey(dayKeyOf(d)), d);
      expect(parseDayKey('坏数据'), isNull);
      expect(parseDayKey('2026-13'), isNull);
    });
  });

  group('月历分格', () {
    test('2026 年 11 月 1 日是周日，前面空 6 格', () {
      final g = MonthGrid(2026, 11);
      expect(g.daysInMonth, 30);
      expect(g.leading, 6);
      final weeks = g.weeks;
      expect(weeks.length, 6, reason: '前空 6 格 + 30 天 = 36，向上补到 42');
      expect(weeks.first.sublist(0, 6), everyElement(isNull));
      expect(weeks.first[6], 1);
    });

    test('2 月闰年天数', () {
      expect(MonthGrid(2028, 2).daysInMonth, 29);
      expect(MonthGrid(2026, 2).daysInMonth, 28);
      // 28 天的月刚好 4 周，不多出空行
      expect(MonthGrid(2027, 2).weeks.length, 4);
    });

    test('每行都是 7 格', () {
      for (var m = 1; m <= 12; m++) {
        for (final w in MonthGrid(2026, m).weeks) {
          expect(w.length, 7);
        }
      }
    });

    test('翻月能跨年', () {
      final g = MonthGrid(2026, 12).shift(1);
      expect(g.year, 2027);
      expect(g.month, 1);
      final p = MonthGrid(2026, 1).shift(-1);
      expect(p.year, 2025);
      expect(p.month, 12);
    });
  });

  group('连续打卡胶囊', () {
    final g = MonthGrid(2026, 11);

    test('断一天就分成两段', () {
      // 11/2、3 连打，4 断，5、6 连打
      final days = {'2026-11-02', '2026-11-03', '2026-11-05', '2026-11-06'};
      final row = g.weeks.first; // 11/1 是周日那行，这里看第二周
      final second = g.weeks[1];
      expect(row.length, 7);
      expect(second, [2, 3, 4, 5, 6, 7, 8]);

      final runs = g.runsIn(second, days);
      expect(runs, [
        [0, 2],
        [3, 2],
      ], reason: '2-3 一段、5-6 一段，4 号断开');
    });

    test('一周全打卡就是整条', () {
      final days = {
        for (var d = 2; d <= 8; d++)
          '2026-11-${d.toString().padLeft(2, '0')}',
      };
      expect(g.runsIn(g.weeks[1], days), [
        [0, 7],
      ]);
    });

    test('空位不算打卡，也不会把两段连起来', () {
      final days = {'2026-10-31', '2026-11-01'};
      // 10 月那格是 null，不参与
      expect(g.runsIn(g.weeks.first, days), [
        [6, 1],
      ]);
    });
  });

  group('统计', () {
    test('最长连胜', () {
      expect(longestRun({}), 0);
      expect(longestRun({'2026-11-18'}), 1);
      // 11/1-3 三天、11/5-9 五天 → 5
      final days = {
        '2026-11-01',
        '2026-11-02',
        '2026-11-03',
        '2026-11-05',
        '2026-11-06',
        '2026-11-07',
        '2026-11-08',
        '2026-11-09',
      };
      expect(longestRun(days), 5);
    });

    test('跨月连续算一段', () {
      final days = {'2026-10-31', '2026-11-01', '2026-11-02'};
      expect(longestRun(days), 3);
    });

    test('本月打卡数只数当月', () {
      final days = {'2026-10-31', '2026-11-01', '2026-11-18'};
      expect(countInMonth(days, 2026, 11), 2);
      expect(countInMonth(days, 2026, 10), 1);
    });

    test('本周从周一算', () {
      // 2026-11-18 是周三，所在周是 16(一)–22(日)
      final ref = DateTime(2026, 11, 18);
      final days = {'2026-11-15', '2026-11-16', '2026-11-18', '2026-11-22'};
      expect(countInWeek(days, ref), 3, reason: '15 号是上周日，不算本周');
    });
  });
}
