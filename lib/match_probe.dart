import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'bank.dart';
import 'confetti.dart';
import 'pages/match.dart';

/// 配对游戏页的截图验证入口（独立于正式 App）。
///
///   flutter run -t lib/match_probe.dart -d windows
/// 它会自动摆一桌牌、点一对正确的卡，按 150ms 抽 18 帧存到
/// design/shots/flutter-match-NN.png，然后退出。
/// 想看配错：`--dart-define=DEMO=2`。
/// 只看答对后卡片「悬浮」那一帧：`--dart-define=DEMO=4` → flutter-hold.png。
/// 想验纸屑不累积：`--dart-define=DEMO=3`，连打三对，每对结束各截一张
/// （flutter-soak-N.png）并打印当时的粒子数，三张都应是干净的牌桌。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordBank.I.load();
  runApp(const _ProbeApp());
}

final GlobalKey _rootKey = GlobalKey();

/// 1=演示配对成功（默认），2=演示配错，3=连打三对，4=只拍答对后的悬浮态
const int _demo = int.fromEnvironment('DEMO', defaultValue: 1);

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    final words = (WordBank.I.byLevel[1] ?? WordBank.I.words).take(20).toList();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Stack(
        children: [
          RepaintBoundary(
            key: _rootKey,
            child: MatchPage(
              words: words,
              title: 'U3 学习关',
              subtitle: 'A1 · 5 对 5 配对',
              autoDemo: _demo,
            ),
          ),
          // 只负责定时截图，不参与画面
          const _Shooter(),
        ],
      ),
    );
  }
}

class _Shooter extends StatefulWidget {
  const _Shooter();
  @override
  State<_Shooter> createState() => _ShooterState();
}

class _ShooterState extends State<_Shooter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  Future<void> _loop() async {
    final dir = Directory('${Directory.current.path}/design/shots');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (_demo == 3) return _soak(dir);
    // 4 = 只拍「答对后卡片悬浮」那一段：起跳 400ms 已结束、还没到 900ms 后的起爆。
    //     定时器起跑时刻不确定，所以在悬浮窗口里连拍 4 张，挑干净的看。
    if (_demo == 4) {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 620));
        await WidgetsBinding.instance.endOfFrame;
        await _shoot('${dir.path}/flutter-hold-$i.png');
      }
      stdout.writeln('HOLD PROBE OK -> ${dir.path}/flutter-hold-0..3.png');
      exit(0);
    }
    // 5 = 连拍 22 张密集帧（给动画做 GIF 用）
    if (_demo == 5) {
      for (var i = 0; i < 26; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await WidgetsBinding.instance.endOfFrame;
        await _shoot(
          '${dir.path}/flutter-hop-${i.toString().padLeft(2, '0')}.png',
          pixelRatio: 1,
        );
      }
      stdout.writeln('HOP PROBE OK -> ${dir.path}/flutter-hop-00..21.png');
      exit(0);
    }

    final prefix = _demo == 2 ? 'flutter-miss' : 'flutter-match';
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (var i = 0; i < 18; i++) {
      await WidgetsBinding.instance.endOfFrame;
      await _shoot(
          '${dir.path}/$prefix-${i.toString().padLeft(2, '0')}.png');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    stdout.writeln('MATCH PROBE OK -> ${dir.path}');
    exit(0);
  }

  /// 连打三对，每对之间隔 6 秒。第 N 张图拍在下一对还没点时，
  /// 此时上一对的纸屑早该散尽 —— 如果还能看到纸片，就是残留 bug。
  Future<void> _soak(Directory dir) async {
    for (var round = 1; round <= 3; round++) {
      await Future<void>.delayed(const Duration(milliseconds: 5800));
      await WidgetsBinding.instance.endOfFrame;
      final n = _particles();
      await _shoot('${dir.path}/flutter-soak-$round.png');
      stdout.writeln('SOAK round=$round particles=$n');
    }
    stdout.writeln('MATCH PROBE OK -> ${dir.path}');
    exit(0);
  }

  /// 从树上找到纸屑层，读它当前还剩多少片
  int _particles() {
    final ctx = _rootKey.currentContext;
    if (ctx is! Element) return -1;
    var n = -1;
    void walk(Element e) {
      if (n >= 0) return;
      final w = e.widget;
      if (w is ConfettiOverlay) {
        n = w.field.length;
        return;
      }
      e.visitChildElements(walk);
    }

    ctx.visitChildElements(walk);
    return n;
  }

  Future<void> _shoot(String path, {double pixelRatio = 2}) async {
    final boundary =
        _rootKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final img = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
