import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bank.dart';

/// 单词记忆状态。box 0..6 对应间隔 10 分钟 → 30 天，box>=5 视为已掌握。
class CardState {
  int box;
  int due; // epoch ms
  int seen;
  int right;
  int wrong;
  int last;

  CardState({
    this.box = 0,
    this.due = 0,
    this.seen = 0,
    this.right = 0,
    this.wrong = 0,
    this.last = 0,
  });

  bool get mastered => box >= 5;

  List<int> toList() => [box, due, seen, right, wrong, last];

  factory CardState.fromList(List<dynamic> l) => CardState(
        box: l[0] as int,
        due: l[1] as int,
        seen: l[2] as int,
        right: l[3] as int,
        wrong: l[4] as int,
        last: l[5] as int,
      );

  /// 云同步用的短键格式（与后台 learning_progress 一致，省流量）
  Map<String, dynamic> toSyncJson(String word) => {
        'w': word,
        'b': box,
        'd': due,
        's': seen,
        'r': right,
        'x': wrong,
        't': last,
      };

  factory CardState.fromSyncJson(Map<String, dynamic> j) => CardState(
        box: (j['b'] as num?)?.toInt() ?? 0,
        due: (j['d'] as num?)?.toInt() ?? 0,
        seen: (j['s'] as num?)?.toInt() ?? 0,
        right: (j['r'] as num?)?.toInt() ?? 0,
        wrong: (j['x'] as num?)?.toInt() ?? 0,
        last: (j['t'] as num?)?.toInt() ?? 0,
      );

  /// 合并两条记录（服务端与本地规则完全相同，见后台 service/progress）：
  /// 计数取大（只增不减），档位/到期时间跟随「最后作答更晚」的一方 ——
  /// 答错会把档位打回 0，不能取大，否则错题永远不会重来。
  static CardState merge(CardState a, CardState b) {
    final newer = a.last >= b.last ? a : b;
    final older = a.last >= b.last ? b : a;
    return CardState(
      box: newer.box,
      due: newer.due,
      seen: newer.seen > older.seen ? newer.seen : older.seen,
      right: newer.right > older.right ? newer.right : older.right,
      wrong: newer.wrong > older.wrong ? newer.wrong : older.wrong,
      last: newer.last,
    );
  }
}

/// 间隔表（分钟）：索引即目标 box
const List<int> kIntervals = [
  10,
  60 * 24,
  60 * 24 * 2,
  60 * 24 * 4,
  60 * 24 * 7,
  60 * 24 * 15,
  60 * 24 * 30,
];

class Progress {
  Progress._();
  static final Progress I = Progress._();

  static const _kSrs = 'srs_v2';
  static const _kPrefs = 'prefs_v2';

  final Map<String, CardState> states = {};

  int newPerDay = 10;
  int reviewPerDay = 40;
  int streak = 0;
  String lastActiveDay = '';
  String dayKey = '';
  int todayNew = 0;
  int todayReview = 0;
  int todayRight = 0;
  int todayWrong = 0;

  /// 最后修改时间（epoch ms），云同步判断"谁更新"用；只有真正作答才更新
  int updatedAt = 0;

  SharedPreferences? _sp;

  /// 单词状态变化的回调（由 ProgressSync 注册，用于标记待同步）。
  /// 用回调而不是直接 import：progress 保持零网络依赖，单测可以单独跑。
  void Function(String en)? onChanged;

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();

    final srsRaw = _sp!.getString(_kSrs);
    if (srsRaw != null && srsRaw.isNotEmpty) {
      final map = jsonDecode(srsRaw) as Map<String, dynamic>;
      map.forEach((k, v) {
        states[k] = CardState.fromList(v as List<dynamic>);
      });
    }

    final pRaw = _sp!.getString(_kPrefs);
    if (pRaw != null && pRaw.isNotEmpty) {
      final p = jsonDecode(pRaw) as Map<String, dynamic>;
      newPerDay = p['newPerDay'] as int? ?? 10;
      reviewPerDay = p['reviewPerDay'] as int? ?? 40;
      streak = p['streak'] as int? ?? 0;
      lastActiveDay = p['lastActiveDay'] as String? ?? '';
      dayKey = p['dayKey'] as String? ?? '';
      todayNew = p['todayNew'] as int? ?? 0;
      todayReview = p['todayReview'] as int? ?? 0;
      todayRight = p['todayRight'] as int? ?? 0;
      todayWrong = p['todayWrong'] as int? ?? 0;
      updatedAt = (p['ts'] as num?)?.toInt() ?? 0;
    }
    _rollDay();
    await save();
  }

  static String _keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get today => _keyOf(DateTime.now());

  /// 跨天时清零当日计数
  void _rollDay() {
    if (dayKey == today) return;
    dayKey = today;
    todayNew = 0;
    todayReview = 0;
    todayRight = 0;
    todayWrong = 0;
  }

  Future<void> save() async {
    if (_sp == null) return;
    await _sp!.setString(_kSrs, jsonEncode({
      for (final e in states.entries) e.key: e.value.toList(),
    }));
    await _sp!.setString(
      _kPrefs,
      jsonEncode({
        'newPerDay': newPerDay,
        'reviewPerDay': reviewPerDay,
        'streak': streak,
        'lastActiveDay': lastActiveDay,
        'dayKey': dayKey,
        'todayNew': todayNew,
        'todayReview': todayReview,
        'todayRight': todayRight,
        'todayWrong': todayWrong,
        'ts': updatedAt,
      }),
    );
  }

  void _touchStreak() {
    _rollDay();
    if (lastActiveDay == today) return;
    final y = DateTime.now().subtract(const Duration(days: 1));
    streak = (lastActiveDay == _keyOf(y)) ? streak + 1 : 1;
    lastActiveDay = today;
  }

  /// 提交一次作答。g: 0=忘记 1=模糊 2=认识
  void grade(Word w, int g, {required bool isNew}) {
    _rollDay();
    final now = DateTime.now().millisecondsSinceEpoch;
    final st = states.putIfAbsent(w.en, () => CardState(due: now));
    st.seen += 1;
    st.last = now;

    if (g >= 2) {
      st.right += 1;
      st.box = (st.box + 1).clamp(0, 6);
    } else if (g == 1) {
      st.right += 1;
      st.box = st.box.clamp(1, 6);
    } else {
      st.wrong += 1;
      st.box = 0;
    }
    st.due = now + kIntervals[st.box.clamp(0, 6)] * 60 * 1000;
    updatedAt = now;

    if (isNew) {
      todayNew += 1;
    } else {
      todayReview += 1;
    }
    if (g >= 1) {
      todayRight += 1;
    } else {
      todayWrong += 1;
    }
    _touchStreak();
    onChanged?.call(w.en);
  }

  /// 合并一条服务端记录进本地（不写盘，调用方批量合并后 save 一次）
  void mergeRemote(String en, CardState remote) {
    final local = states[en];
    if (local == null) {
      if (remote.seen > 0 || remote.last > 0) states[en] = remote;
      return;
    }
    states[en] = CardState.merge(local, remote);
  }

  /// 待复习：已学过且到期
  List<Word> dueWords({DateTime? at}) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final out = <Word>[];
    states.forEach((en, st) {
      if (st.due <= now && st.seen > 0) {
        final w = WordBank.I.byEn[en];
        if (w != null) out.add(w);
      }
    });
    out.sort((a, b) => states[a.en]!.due.compareTo(states[b.en]!.due));
    return out;
  }

  /// 生词：从未学过的词，按级别从低到高
  List<Word> newWords({int limit = 10}) {
    final out = <Word>[];
    for (final w in WordBank.I.words) {
      if (states.containsKey(w.en)) continue;
      out.add(w);
      if (out.length >= limit) break;
    }
    return out;
  }

  int get learnedCount =>
      states.values.where((s) => s.seen > 0).length;

  int get masteredCount =>
      states.values.where((s) => s.mastered).length;

  /// 各级别掌握率，返回 [级别名, 掌握数, 该级别总数]
  List<List<dynamic>> levelProgress() {
    final res = <List<dynamic>>[];
    for (var lv = 1; lv <= 5; lv++) {
      final all = WordBank.I.byLevel[lv] ?? const [];
      var done = 0;
      for (final w in all) {
        final s = states[w.en];
        if (s != null && s.mastered) done++;
      }
      res.add([lv, done, all.length]);
    }
    return res;
  }

  List<Word> wrongBook({int limit = 50}) {
    final list = states.entries.where((e) => e.value.wrong > 0).toList();
    list.sort((a, b) => b.value.wrong.compareTo(a.value.wrong));
    return list
        .map((e) => WordBank.I.byEn[e.key])
        .whereType<Word>()
        .take(limit)
        .toList();
  }

  Future<void> reset() async {
    states.clear();
    streak = 0;
    lastActiveDay = '';
    dayKey = '';
    todayNew = todayReview = todayRight = todayWrong = 0;
    await save();
  }
}
