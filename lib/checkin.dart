/// 打卡相关的纯计算：日期键、月历分格、连续段、连胜统计。
///
/// 单独放一个文件（不依赖 Flutter），打卡页和单测都用它：
/// 「连续打卡串成一条胶囊」这类逻辑一旦嵌在 build 里，就只能靠截图验。
library;

/// '2026-11-18'
String dayKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseDayKey(String key) {
  final p = key.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// 一个月的日历格子：7 列，周一为第一天，空位是 null。
class MonthGrid {
  MonthGrid(this.year, this.month);

  final int year;
  final int month;

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// 1 号前面有几个空位（周一 = 0）
  int get leading => (DateTime(year, month, 1).weekday + 6) % 7;

  /// 按周切好的行；每行 7 个，格子里是几号
  List<List<int?>> get weeks {
    final cells = <int?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
  }

  String keyOf(int day) =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// 一行里连续打卡的区段：[起始列, 长度]，用于画渐变胶囊。
  /// 断一天就断开成两条，跨行不会连起来（周与周之间本来就换行了）。
  List<List<int>> runsIn(List<int?> week, Set<String> days) {
    final out = <List<int>>[];
    var start = -1;
    for (var i = 0; i < week.length; i++) {
      final d = week[i];
      final on = d != null && days.contains(keyOf(d));
      if (on) {
        if (start < 0) start = i;
      } else if (start >= 0) {
        out.add([start, i - start]);
        start = -1;
      }
    }
    if (start >= 0) out.add([start, week.length - start]);
    return out;
  }

  MonthGrid shift(int delta) {
    final t = DateTime(year, month + delta, 1);
    return MonthGrid(t.year, t.month);
  }
}

/// 历史最长连胜（按已记录的日期算）
int longestRun(Set<String> days) {
  if (days.isEmpty) return 0;
  final list = days.map(parseDayKey).whereType<DateTime>().toList()
    ..sort();
  var best = 1;
  var cur = 1;
  for (var i = 1; i < list.length; i++) {
    final gap = list[i].difference(list[i - 1]).inDays;
    if (gap == 1) {
      cur++;
      if (cur > best) best = cur;
    } else if (gap != 0) {
      cur = 1;
    }
  }
  return best;
}

int countInMonth(Set<String> days, int year, int month) {
  final prefix = '$year-${month.toString().padLeft(2, '0')}-';
  return days.where((d) => d.startsWith(prefix)).length;
}

/// 本周（周一起）打卡天数
int countInWeek(Set<String> days, DateTime ref) {
  final monday = DateTime(ref.year, ref.month, ref.day)
      .subtract(Duration(days: (ref.weekday + 6) % 7));
  var n = 0;
  for (var i = 0; i < 7; i++) {
    if (days.contains(dayKeyOf(monday.add(Duration(days: i))))) n++;
  }
  return n;
}
