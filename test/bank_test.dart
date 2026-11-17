import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/bank.dart';
import 'package:app_worddeer/curriculum.dart';

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

  test('内容包的 topics 层级表被解析，主题按级别绑定', () {
    final bank = WordBank.I;
    bank.applyRaw('''
      {"version":6,"count":2,
       "topics":{"A1":["日常问候","动物"],"A2":["交通出行"],"B1":[]},
       "words":[
        ["hello","你好","x","[a]","[a]",1,"A1","日常问候"],
        ["bus","公交","n.公交","[a]","[a]",2,"A2","交通出行"]
      ]}
    ''');
    expect(bank.levelTopics['A1'], ['日常问候', '动物']);
    expect(bank.levelTopics['A2'], ['交通出行']);
    // 主题与分级绑定：A1 只看 A1 的主题，看不到 A2 的
    expect(themesFor('A1').map((t) => t.name), ['日常问候', '动物']);
    expect(themesFor('A2').map((t) => t.name), ['交通出行']);
    expect(themesFor('B1'), isEmpty);
  });

  test('旧数据（无 topics 表）按词分级众数推导主题归属', () {
    final bank = WordBank.I;
    bank.applyRaw('''
      [["hi","你好","x","[a]","[a]",1,"A1","问候"],
       ["hello","你好","x","[a]","[a]",1,"A1","问候"],
       ["journey","旅程","x","[a]","[a]",2,"B1","旅行"],
       ["travel","旅行","v.旅行","[a]","[a]",3,"B1","旅行"],
       ["trip","短途旅行","x","[a]","[a]",4,"A1,B1","旅行"]]
    ''');
    // 「旅行」3 个词里 B1 占 2（trip 最低分级是 A1），归 B1；「问候」全 A1，归 A1
    expect(themesFor('A1').map((t) => t.name), ['问候']);
    expect(themesFor('B1').map((t) => t.name), ['旅行']);
  });
}
