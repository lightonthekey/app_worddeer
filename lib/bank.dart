import 'dart:convert';

import 'package:flutter/services.dart';

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

  bool get ready => words.isNotEmpty;

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/words.json');
    final list = jsonDecode(raw) as List<dynamic>;
    words.clear();
    byEn.clear();
    byLevel.clear();
    for (final r in list) {
      final w = Word.fromJson(r as List<dynamic>);
      words.add(w);
      byEn.putIfAbsent(w.en, () => w);
      byLevel.putIfAbsent(w.lv, () => []).add(w);
    }
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
