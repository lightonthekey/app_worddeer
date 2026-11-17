import 'dart:convert';

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

  factory Word.fromJson(List<dynamic> r) => Word(
        en: r[0] as String,
        zh: r[1] as String,
        detail: r[2] as String? ?? '',
        phUs: r[3] as String? ?? '',
        phUk: r[4] as String? ?? '',
        lv: r[5] as int,
        cefr: _split(r[6]),
        topic: _split(r[7]),
      );

  static List<String> _split(dynamic v) {
    final s = (v as String?) ?? '';
    return s.isEmpty ? const [] : s.split(',');
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
  Future<void> load() async {
    String raw;
    try {
      final f = await ContentSync.I.localFile();
      if (f != null) {
        raw = await f.readAsString();
      } else {
        raw = await rootBundle.loadString('assets/words.json');
      }
    } catch (_) {
      raw = await rootBundle.loadString('assets/words.json');
    }
    applyRaw(raw);
  }

  /// 解析并整体替换当前词库（load 与后台热更新共用）。
  /// 解析失败抛异常也没关系：调用方不替换现有词库，App 继续用旧数据。
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
    for (final r in list) {
      final w = Word.fromJson(r as List<dynamic>);
      nextWords.add(w);
      nextByEn.putIfAbsent(w.en, () => w);
      nextByLevel.putIfAbsent(w.lv, () => []).add(w);
    }
    // 全部构建成功后才替换，解析中途抛异常不会留下半份词库
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
