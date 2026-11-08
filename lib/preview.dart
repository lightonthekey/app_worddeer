// 界面预览入口（不参与正式打包）：
//   flutter run -d chrome -t lib/preview.dart
//   加 ?q=choice|listen|spell|flash 可切换题型
import 'package:flutter/material.dart';

import 'bank.dart';
import 'pages/session.dart';
import 'progress.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordBank.I.load();
  await Progress.I.load();

  final q = Uri.base.queryParameters['q'] ?? 'flash';
  final w = WordBank.I.byEn['abandon'] ?? WordBank.I.words.first;
  final others = WordBank.I.words
      .where((e) => e.zh != w.zh)
      .take(3)
      .map((e) => e.zh)
      .toList();
  final opts = [w.zh, ...others];

  final type = switch (q) {
    'choice' => QType.choice,
    'listen' => QType.listen,
    'spell' => QType.spell,
    _ => QType.flash,
  };
  final isFlash = type == QType.flash;

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: SessionPage(
      items: [SessionItem(w, type, isFlash, isFlash ? const [] : opts)],
      title: '预览 · $q',
    ),
  ));
}
