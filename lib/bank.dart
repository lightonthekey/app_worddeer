import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'content_sync.dart';

/// 词条。id 直接用英文原形，作为进度表的主键（人类可读、跨端稳定）。
class Word {
  final String en;
  final String zh;
  final String detail;
  final String phUs;
  final String phUk;

  /// 1..5 对应 A1..C1（取该词最低级别）
  final int lv;
  final List<String> cefr;
  final List<String> topic;

  const Word({
    required this.en,
    required this.zh,
    required this.detail,
    required this.phUs,
    required this.phUk,
    required this.lv,
    required this.cefr,
    required this.topic,
  });

  String get levelName => const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'][lv - 1];

  /// 宽松解析：词库是后台下发的，格式不完全可控。
  /// 列缺失、类型不对（比如 lv 变成 "A1" 或 "3"）都不该让整份词库解析失败 ——
  /// 一条坏数据只丢掉这一条，其余照常用。`en` 为空的行由调用方跳过。
  factory Word.fromJson(List<dynamic> r) => Word(
        en: _str(r, 0).trim(),
        zh: _str(r, 1),
        detail: _str(r, 2),
        phUs: _str(r, 3),
        phUk: _str(r, 4),
        lv: _lvOf(r.length > 5 ? r[5] : null),
        cefr: _split(r.length > 6 ? r[6] : null),
        topic: _split(r.length > 7 ? r[7] : null),
      );

  static String _str(List<dynamic> r, int i) =>
      i < r.length && r[i] != null ? r[i].toString() : '';

  /// 级别列可能是 1..6、也可能是 'A1'..'C2'，统一收敛到 1..6
  static int _lvOf(dynamic v) {
    if (v is num) return v.toInt().clamp(1, 6);
    final s = v?.toString().trim().toUpperCase() ?? '';
    final n = int.tryParse(s);
    if (n != null) return n.clamp(1, 6);
    final i = const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'].indexOf(s);
    return i >= 0 ? i + 1 : 1;
  }

  static List<String> _split(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return const [];
    return [
      for (final x in s.split(','))
        if (x.trim().isNotEmpty) x.trim(),
    ];
  }
}

class WordBank {
  WordBank._();
  static final WordBank I = WordBank._();

  final List<Word> words = [];
  final Map<String, Word> byEn = {};

  /// 按级别分组的词表，供选项干扰项抽取
  final Map<int, List<Word>> byLevel = {};

  /// 分级 → 主题列表（主题与分级一对多绑定，随内容包下发）。
  /// 空表示数据里没带层级表，调用方自行回退。
  final Map<String, List<String>> levelTopics = {};

  bool get ready => words.isNotEmpty;

  /// 词库来源：后台下发的 wordbank.json 优先，读不到（还没同步过 / 文件损坏）
  /// 就退回内置 assets/words.json —— 保证 App 永远可用。
  /// 两种容器都认：内置是裸数组，后台包是 {"version":n,"words":[...]}。
  ///
  /// 注意「读到文件」和「解析出词条」是两件事：后台包可能 md5 校验通过
  /// 但结构已经不对（少列、类型变），这时也必须回退到内置词库，
  /// 否则启动后词库为空，首页直接白屏。
  Future<void> load() async {
    try {
      final f = await ContentSync.I.localFile();
      if (f != null) applyRaw(await f.readAsString());
    } catch (e) {
      debugPrint('[bank] 远程词库读取失败，改用内置：$e');
    }
    if (words.isNotEmpty) return;
    try {
      applyRaw(await rootBundle.loadString('assets/words.json'));
    } catch (e) {
      debugPrint('[bank] 内置词库加载失败：$e');
    }
  }

  /// 解析并整体替换当前词库（load 与后台热更新共用）。
  /// 解析失败或一条有效词都没有时保持现有词库不动。
  void applyRaw(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // 格式不对时保持现有词库不动
    }
    final List<dynamic> list;
    Map<String, List<String>>? topicsMap;
    if (decoded is List<dynamic>) {
      list = decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['words'] is! List<dynamic>) {
        return; // 格式不对时保持现有词库不动
      }
      list = decoded['words'] as List<dynamic>;
      final t = decoded['topics'];
      if (t is Map<String, dynamic>) {
        topicsMap = t.map((k, v) =>
            MapEntry(k, v is List<dynamic> ? v.cast<String>() : <String>[]));
      }
    } else {
      return; // 格式不对时保持现有词库不动
    }
    final nextWords = <Word>[];
    final nextByEn = <String, Word>{};
    final nextByLevel = <int, List<Word>>{};
    var skipped = 0;
    for (final r in list) {
      if (r is! List) {
        skipped++;
        continue;
      }
      try {
        final w = Word.fromJson(r);
        if (w.en.isEmpty) {
          skipped++;
          continue;
        }
        nextWords.add(w);
        nextByEn.putIfAbsent(w.en, () => w);
        nextByLevel.putIfAbsent(w.lv, () => []).add(w);
      } catch (_) {
        // 单条坏数据只丢这一条，不让整份词库解析失败
        skipped++;
      }
    }
    if (skipped > 0) {
      debugPrint('[bank] 跳过 $skipped 条无法解析的词条（共 ${list.length} 条）');
    }
    // 一条有效词都没有：当成坏包，保留现有词库（首次启动时由 load 回退内置）
    if (nextWords.isEmpty) return;
    // 全部构建成功后才替换，解析中途出错不会留下半份词库
    words
      ..clear()
      ..addAll(nextWords);
    byEn
      ..clear()
      ..addAll(nextByEn);
    byLevel
      ..clear()
      ..addAll(nextByLevel);
    levelTopics
      ..clear()
      ..addAll(topicsMap ?? {});
  }

  List<Word> search(String q, {int limit = 60}) {
    q = q.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    final exact = <Word>[];
    final prefix = <Word>[];
    final fuzzy = <Word>[];
    for (final w in words) {
      final en = w.en.toLowerCase();
      if (en == lower) {
        exact.add(w);
      } else if (en.startsWith(lower)) {
        prefix.add(w);
      } else if (en.contains(lower) || w.zh.contains(q) || w.detail.contains(q)) {
        fuzzy.add(w);
      }
      if (exact.length >= limit) break;
    }
    return [...exact, ...prefix, ...fuzzy].take(limit).toList();
  }
}
