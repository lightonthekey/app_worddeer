import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bank.dart';

/// 一个 CEFR 级别（A1..C1）
class LvInfo {
  final String id;
  final String name;
  final int code;

  const LvInfo(this.id, this.name, this.code);
}

const List<LvInfo> kLevels = [
  LvInfo('A1', '入门', 1),
  LvInfo('A2', '基础', 2),
  LvInfo('B1', '进阶', 3),
  LvInfo('B2', '高阶', 4),
  LvInfo('C1', '精通', 5),
];

/// 主题（名称 + 图标）。主题与分级一对多绑定：每个级别只显示挂在该级别下的主题。
class ThemeInfo {
  final String name;
  final String emoji;

  const ThemeInfo(this.name, this.emoji);
}

/// A1 兜底主题（与后台 topic_catalog 种子一致）；其他级别从词库取
const List<ThemeInfo> kThemes = [
  ThemeInfo('个人信息', '🪪'),
  ThemeInfo('动物', '🐾'),
  ThemeInfo('天气季节', '🌤'),
  ThemeInfo('学校学习', '📚'),
  ThemeInfo('家庭家人', '👪'),
  ThemeInfo('数字', '🔢'),
  ThemeInfo('日常问候', '👋'),
  ThemeInfo('时间', '⏰'),
  ThemeInfo('衣服', '👕'),
  ThemeInfo('身体', '🫀'),
  ThemeInfo('颜色', '🎨'),
  ThemeInfo('食物饮品', '🍽'),
];

/// 全部主题的图标（后台目录新增主题时没配图标的用 📖）
const Map<String, String> kTopicEmoji = {
  // A1
  '个人信息': '🪪', '动物': '🐾', '天气季节': '🌤', '学校学习': '📚',
  '家庭家人': '👪', '数字': '🔢', '日常问候': '👋', '时间': '⏰',
  '衣服': '👕', '身体': '🫀', '颜色': '🎨', '食物饮品': '🍽',
  // A2
  '交通出行': '🚌', '假期旅行': '✈️', '健康': '💊', '兴趣爱好': '🎯',
  '城市地点': '🏙', '描述人物': '🧑', '方位位置': '🧭', '日常作息': '🌅',
  '职业': '👷', '购物': '🛒', '运动': '⚽', '餐饮': '🍜',
  // B1
  '人际关系': '🤝', '城市生活': '🏘', '媒体新闻': '📰', '学习考试': '📝',
  '工作职场': '💼', '教育与未来': '🚀', '旅行经历': '🗺', '环境环保': '🌱',
  '生活健康': '🏃', '科技网络': '💻', '表达观点': '💬', '金钱经济': '💰',
  // B2
  '全球议题': '🌍', '决策风险': '🎲', '医疗健康': '🏥', '可持续发展': '♻️',
  '商业经济': '📈', '心理情感': '💗', '法律权利': '📜', '社会问题': '🏛',
  '科学研究': '🔬', '职业生涯': '📊', '艺术文化': '🎭', '语言沟通': '🗣',
  // C1
  '公共卫生': '🦠', '哲学思想': '🤔', '复杂社会分析': '🧩', '学术高等教育': '🎓',
  '心理认知': '🧠', '法律治理': '⚖️', '科技伦理前沿': '🤖', '经济金融': '🏦',
  '能源地缘': '⚡', '艺术批判': '🖼', '语言学术': '🔤', '高级商业管理': '🗂',
};

ThemeInfo _theme(String name) => ThemeInfo(name, kTopicEmoji[name] ?? '📖');

/// 推导结果的缓存（按级别），热更新词库后随 [Curriculum.invalidateCache] 清空
Map<String, List<ThemeInfo>>? _derivedThemeCache;

/// 某级别的主题列表。优先用内容包下发的分级绑定表（后台 topic_catalog）；
/// 词库数据里没带层级表时，按词表推导（每个主题取其词分级众数，
/// 与后台目录种子规则一致），保证旧数据也能按级展示。
List<ThemeInfo> themesFor(String lv) {
  final bank = WordBank.I;
  if (bank.levelTopics.isNotEmpty) {
    return [for (final n in bank.levelTopics[lv] ?? const <String>[]) _theme(n)];
  }
  return _derivedThemeCache?.putIfAbsent(lv, () => _deriveThemes(lv)) ??
      _deriveThemes(lv);
}

List<ThemeInfo> _deriveThemes(String lv) {
  // 主题 → (级别 → 词数)。按词的 cefr 列表逐级计数（与后台目录种子规则一致），
  // 不能用 w.lv——那是第 5 列的级别序号，一词多级时不准
  final dist = <String, Map<int, int>>{};
  final codeOf = {for (final l in kLevels) l.id: l.code};
  for (final w in WordBank.I.words) {
    for (final t in w.topic) {
      final m = dist.putIfAbsent(t, () => {});
      for (final c in w.cefr) {
        final code = codeOf[c];
        if (code != null) m[code] = (m[code] ?? 0) + 1;
      }
    }
  }
  final want = kLevels.firstWhere((l) => l.id == lv, orElse: () => kLevels[0]);
  final names = <String>[];
  dist.forEach((t, m) {
    var bestLv = 1;
    var bestN = -1;
    m.forEach((code, n) {
      if (n > bestN || (n == bestN && code < bestLv)) {
        bestLv = code;
        bestN = n;
      }
    });
    if (bestLv == want.code) names.add(t);
  });
  names.sort();
  return [for (final n in names) _theme(n)];
}

/// 关卡：每 6 关插入 1 关复习
class Unit {
  final String id; // U1..U12
  final bool review;
  final List<Word> words;

  const Unit(this.id, this.review, this.words);

  int get total => words.length;
  String get title => review ? '$id 复习关' : '$id 学习关';
}

/// 课程进度：级别 / 关卡 / 主题 / 今日目标。
/// 与 [Progress] 的 SRS 记忆状态分开存，互不干扰。
class Curriculum {
  Curriculum._();
  static final Curriculum I = Curriculum._();

  /// 每关词数
  static const int perUnit = 50;

  /// 每级别关卡数（第 6、12 关为复习关）
  static const int unitsPerLevel = 12;

  /// 免费开放的关卡数（后续会员逻辑用）
  static const int freeUnits = 1;

  static const int dailyGoal = 50;

  static const _kStore = 'curriculum_v1';

  String curLv = 'A1';

  /// 已通关：'A1:U1' -> true
  final Map<String, bool> passed = {};

  /// 半程进度：'A1:U3' -> 已学词数
  final Map<String, int> part = {};

  /// 主题已学：'A1:t0' -> 词数
  final Map<String, int> themes = {};

  int todayWords = 0;
  String dayKey = '';

  /// 最后修改时间（epoch ms）：云同步时用来判断「谁的数据更新」。
  /// 只在真正发生学习行为时更新，读档/存盘不碰，否则每次启动都会把自己变成"最新"。
  int updatedAt = 0;

  /// 进度变化回调（由 ProgressSync 注册，用于标记待同步）
  void Function()? onChanged;

  final Map<String, List<Unit>> _cache = {};
  final Map<String, List<Word>> _themeCache = {};

  /// 词库热更新后调用：关卡、主题与推导缓存都是按词库内容缓存的，必须清掉
  void invalidateCache() {
    _cache.clear();
    _themeCache.clear();
    _derivedThemeCache?.clear();
  }

  SharedPreferences? _sp;

  // ---------------------------------------------------------------- 持久化

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    final raw = _sp!.getString(_kStore);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        curLv = m['curLv'] as String? ?? 'A1';
        (m['passed'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          if (v == true) passed[k] = true;
        });
        (m['part'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          part[k] = (v as num).toInt();
        });
        (m['themes'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          themes[k] = (v as num).toInt();
        });
        todayWords = (m['todayWords'] as num?)?.toInt() ?? 0;
        dayKey = m['dayKey'] as String? ?? '';
        updatedAt = (m['ts'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // 存档损坏就当新用户
      }
    }
    _rollDay();
    _seedIfEmpty();
    await save();
  }

  Future<void> save() async {
    if (_sp == null) return;
    await _sp!.setString(
      _kStore,
      jsonEncode({
        'curLv': curLv,
        'passed': passed,
        'part': part,
        'themes': themes,
        'todayWords': todayWords,
        'dayKey': dayKey,
        'ts': updatedAt,
      }),
    );
  }

  /// 标记「有改动」：更新时间戳 + 通知同步模块
  void _touch() {
    updatedAt = DateTime.now().millisecondsSinceEpoch;
    onChanged?.call();
  }

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  void _rollDay() {
    if (dayKey == _today) return;
    dayKey = _today;
    todayWords = 0;
  }

  /// 演示数据：只在 debug 包、且从未玩过时写入，方便对照设计稿
  void _seedIfEmpty() {
    if (!kDebugMode) return;
    if (passed.isNotEmpty || part.isNotEmpty || themes.isNotEmpty) return;
    passed['A1:U1'] = true;
    passed['A1:U2'] = true;
    part['A1:U3'] = 32;
    themes['A1:t0'] = 18;
    todayWords = 30;
  }

  // ---------------------------------------------------------------- 课程树

  List<Unit> unitsOf(String lv) {
    if (_cache.containsKey(lv)) return _cache[lv]!;
    final info = kLevels.firstWhere((l) => l.id == lv, orElse: () => kLevels[0]);
    final pool = WordBank.I.byLevel[info.code] ?? WordBank.I.words;
    final out = <Unit>[];
    final learns = <List<Word>>[];
    var cursor = 0;

    for (var i = 1; i <= unitsPerLevel; i++) {
      if (i % 6 == 0) {
        // 复习关：把前 5 关的词再过一遍
        final words = <Word>[for (final u in learns) ...u];
        out.add(Unit('U$i', true, words));
      } else {
        final words = <Word>[];
        for (var k = 0; k < perUnit; k++) {
          if (pool.isEmpty) break;
          words.add(pool[cursor % pool.length]);
          cursor++;
        }
        learns.add(words);
        out.add(Unit('U$i', false, words));
      }
    }
    if (pool.isNotEmpty) _cache[lv] = out;
    return out;
  }

  Unit unitAt(String lv, int index) {
    final list = unitsOf(lv);
    return list[index.clamp(0, list.length - 1)];
  }

  String _key(String lv, String unitId) => '$lv:$unitId';

  bool isPassed(String lv, String unitId) => passed[_key(lv, unitId)] == true;

  int partOf(String lv, String unitId) {
    final u = unitsOf(lv).firstWhere((e) => e.id == unitId,
        orElse: () => Unit(unitId, false, const []));
    return isPassed(lv, unitId)
        ? u.total
        : (part[_key(lv, unitId)] ?? 0).clamp(0, u.total);
  }

  /// 关卡是否已解锁（第一关永远开，其余要求上一关通关）
  bool isOpen(String lv, int index) {
    if (index <= 0) return true;
    return isPassed(lv, unitsOf(lv)[index - 1].id);
  }

  int passedCount(String lv) =>
      unitsOf(lv).where((u) => isPassed(lv, u.id)).length;

  /// 当前该学到第几关（全部通关时返回最后一关）
  int currentIndex(String lv) {
    final list = unitsOf(lv);
    for (var i = 0; i < list.length; i++) {
      if (!isPassed(lv, list[i].id)) return i;
    }
    return list.length - 1;
  }

  void markPassed(String lv, String unitId) {
    passed[_key(lv, unitId)] = true;
    part.remove(_key(lv, unitId));
    _touch();
    save();
  }

  /// 只前进不后退：重做同一关不会把已学比例做小
  void setPart(String lv, String unitId, int done) {
    final k = _key(lv, unitId);
    if (passed[k] == true) return;
    final old = part[k] ?? 0;
    if (done > old) {
      part[k] = done;
      _touch();
      save();
    }
  }

  /// 结算后累加今日词数（跨天自动清零）
  void addToday(int n) {
    _rollDay();
    todayWords += n;
    _touch();
    save();
  }

  double get todayRatio => (todayWords / dailyGoal).clamp(0.0, 1.0);

  int get todayLeft => (dailyGoal - todayWords).clamp(0, dailyGoal);

  // ---------------------------------------------------------------- 主题

  /// 当前级别的主题列表（主题与分级绑定，每个级别只看自己的）
  List<ThemeInfo> get curThemes => themesFor(curLv);

  String themeKey(int i) => '$curLv:t$i';

  bool themeUnlocked(int i) => i == 0; // 每个级别默认只开第一个

  /// 某主题在某级别下的词：该级别优先，不够再往下补
  List<Word> themeWords(int i, {int limit = perUnit}) {
    final themes = curThemes;
    if (i >= themes.length) return const [];
    final ck = '$curLv:$i';
    if (_themeCache.containsKey(ck)) return _themeCache[ck]!;
    final name = themes[i].name;
    final info = kLevels.firstWhere((l) => l.id == curLv, orElse: () => kLevels[0]);

    final same = <Word>[];
    final lower = <Word>[];
    for (final w in WordBank.I.words) {
      if (!w.topic.contains(name)) continue;
      if (w.lv == info.code) {
        same.add(w);
      } else if (w.lv < info.code) {
        lower.add(w);
      }
    }
    final out = <Word>[...same, ...lower].take(limit).toList();
    if (out.isNotEmpty) _themeCache[ck] = out;
    return out;
  }

  int themeLearned(int i) {
    final total = themeWords(i).length;
    return (themes[themeKey(i)] ?? 0).clamp(0, total);
  }

  void markTheme(String lv, int i, int learned) {
    final key = '$lv:t$i';
    if (learned > (themes[key] ?? 0)) {
      themes[key] = learned;
      _touch();
      save();
    }
  }
}
