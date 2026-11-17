import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/bank.dart';

void main() {
  test('applyRaw 解析内置裸数组格式', () {
    final bank = WordBank.I;
    bank.applyRaw('''
      [["hello","你好","interj.你好","[heˈloʊ]","[heˈləʊ]",1,"A1","日常问候"]]
    ''');
    expect(bank.words, hasLength(1));
    expect(bank.byEn['hello'], isNotNull);
    expect(bank.byLevel[1], hasLength(1));
    expect(bank.words.first.cefr, ['A1']);
    expect(bank.words.first.topic, ['日常问候']);
    expect(bank.words.first.levelName, 'A1');
  });

  test('applyRaw 解析后台内容包（带 version/words 包装）', () {
    final bank = WordBank.I;
    bank.applyRaw('''
      {"version":3,"count":2,"published_at":"2026-11-17 08:00:00","words":[
        ["hello","你好","interj.你好","[heˈloʊ]","[heˈləʊ]",1,"A1","日常问候"],
        ["coast","海岸","n.海岸","[koʊst]","[kəʊʊt]",2,"A2,B1","城市地点,旅行经历"]
      ]}
    ''');
    expect(bank.words, hasLength(2));
    expect(bank.byEn['coast']!.cefr, ['A2', 'B1']);
    expect(bank.byLevel[2], hasLength(1));
  });

  test('applyRaw 遇到非法格式时保持原词库不动', () {
    final bank = WordBank.I;
    bank.applyRaw('[["hello","你好","x","[a]","[a]",1,"A1","t"]]');
    final before = bank.words.length;
    bank.applyRaw('not a json at all');
    expect(bank.words.length, before);
    bank.applyRaw('{"foo": 1}');
    expect(bank.words.length, before);
  });

  test('reload 后 byLevel 不残留旧数据', () {
    final bank = WordBank.I;
    bank.applyRaw('[["aa","甲","","[a]","[a]",1,"A1","t"],["bb","乙","","[b]","[b]",1,"A1","t"]]');
    expect(bank.byLevel[1], hasLength(2));
    bank.applyRaw('[["cc","丙","","[c]","[c]",2,"B1","t"]]');
    expect(bank.words, hasLength(1));
    expect(bank.byLevel[1] ?? [], isEmpty);
    expect(bank.byLevel[2], hasLength(1));
  });
}
