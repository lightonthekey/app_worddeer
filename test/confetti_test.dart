import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_worddeer/confetti.dart';

Widget _host(ConfettiField field) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: ConfettiOverlay(field: field)),
          ],
        ),
      ),
    );

/// 按真实节奏推进：每次 pump 100ms，[ConfettiField.tick] 会把它拆成约 6 个 1/60 物理帧。
Future<void> _run(WidgetTester tester, double seconds) async {
  final n = (seconds * 10).ceil();
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('连续多轮纸屑都能散尽，不会停在屏幕上越积越多', (WidgetTester tester) async {
    final field = ConfettiField(seed: 7);
    await tester.pumpWidget(_host(field));

    for (var round = 1; round <= 3; round++) {
      field.burstAt(const Offset(120, 200), n: 24);
      await tester.pump();
      expect(field.length, 24, reason: '第 $round 轮应该有 24 片纸屑');

      // 起爆后 1 秒：纸屑还活着，而且已经被推进过（不是停在原地的死碎片）
      await _run(tester, 1);
      expect(field.isEmpty, isFalse, reason: '第 $round 轮 1 秒时纸屑仍在飘');
      final moved = field.particles.where((p) => p.life > 0).length;
      expect(moved, field.length,
          reason: '第 $round 轮所有纸屑都应该在动，卡住的碎片 life 会一直是 0');

      // 寿命上限 250 帧 ≈ 4.2s，5 秒足够散尽
      await _run(tester, 5);
      expect(field.isEmpty, isTrue, reason: '第 $round 轮纸屑必须全部消失');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('粒子落到底部以下也会按寿命移除，不会留残余', (WidgetTester tester) async {
    final field = ConfettiField(seed: 11);
    await tester.pumpWidget(_host(field));

    field.burstAt(const Offset(120, 200), n: 30);
    await tester.pump();
    await _run(tester, 6);

    expect(field.isEmpty, isTrue);
    expect(field.length, 0);

    await tester.pumpWidget(const SizedBox());
  });

  test('不会有纸片垂直落进屏幕中缝压住学习区', () {
    final field = ConfettiField(seed: 5);
    // 左列一行、右列另一行（中英两列各自打乱，这是常见情况），屏幕宽约 430
    field.burstBetween(const Offset(100, 320), const Offset(330, 500));

    final verticalInMiddle = <ConfettiParticle>{};
    for (var i = 0; i < 300; i++) {
      field.advanceFrames(1);
      for (final p in field.particles) {
        final visible = p.fade > .2;
        // vy 明显向下、横向几乎不动 = 一条竖线直直掉
        final fallingStraight = p.vy > 2 && p.vx.abs() < 1.2;
        if (visible && fallingStraight && p.x > 175 && p.x < 255) {
          verticalInMiddle.add(p);
        }
      }
    }

    expect(verticalInMiddle, isEmpty, reason: '纸片不能沿中缝垂直落下');
  });

  test('纸片下落到出生点下方一定距离后必须消失', () {
    final field = ConfettiField(seed: 9);
    field.burstAt(const Offset(200, 300), n: 40);

    var deepest = 0.0;
    for (var i = 0; i < 300; i++) {
      field.advanceFrames(1);
      for (final p in field.particles) {
        deepest = deepest > p.y - p.spawnY ? deepest : p.y - p.spawnY;
      }
    }

    // 允许一点余量：淡出区间 260~350 + 90 宽
    expect(deepest, lessThan(kFallFadeStart + 90 + kFallFadeWidth),
        reason: '纸片不该一路掉到屏幕下部牌面上');
  });
}
