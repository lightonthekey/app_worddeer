import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// 配对成功时的纸屑爆炸（Canvas 粒子）。
///
/// 移植自 design/game-a-desk.html 里那套（本身参考了 engmatch.html 的 fireConfetti）：
/// 实心色块、无描边无阴影，每帧加重力 + 左右摆动 + 自转，寿命 2.7~4.2 秒，
/// 前 60% 保持实心、后 40% 才淡出——所以纸屑是“飘”下来的，不是一闪就没。
///
/// 时间用固定 1/60 秒的物理步长推进，120Hz 屏和掉帧设备上飘落速度一致。
/// 用法见 [ConfettiOverlay]；想手动推进帧（截图/测试）用 [advanceFrames]。

const kConfettiColors = <Color>[
  Color(0xFF16A34A),
  Color(0xFF34D399),
  Color(0xFF0EA5A4),
  Color(0xFF5A50E0),
  Color(0xFF8B7CF6),
  Color(0xFFF59E0B),
  Color(0xFFFBBF24),
  Color(0xFFEF4444),
  Color(0xFFFFFFFF),
  Color(0xFFCDEBDE),
];

/// 每帧竖直加速度（px / frame²，60fps 基准）
const double kConfettiGravity = .062;

/// 一帧的毫秒数
const double kConfettiFrameMs = 1000 / 60;

/// 纸片掉到出生点下方这么多像素时开始淡出，再往下 [kFallFadeWidth] 像素完全消失。
///
/// 不加这个约束的话，纸片会带着重力一路往下落 2~3 秒，最后变成一条条竖线
/// 穿过屏幕中下部的牌面，很干扰读词。现在炸开 → 向四周飘 → 掉到下方
/// 260~350px 开始淡、再掉 90px 彻底消失（起始值每片随机，避免整批同时消失）。
const double kFallFadeStart = 60;
const double kFallFadeWidth = 30;

/// 纸片的最小水平速度。出射角接近正上/正下时 vx 几乎为 0，
/// 纸片会沿一条竖线直直落下（中缝那个爆点尤其明显），必须掰开。
const double kMinVx = 2.6;

class ConfettiParticle {
  ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required this.rot,
    required this.vr,
    required this.phase,
    required this.sway,
    required this.color,
    required this.maxLife,
    required this.fadeStart,
  }) : spawnY = y;

  double x, y, vx, vy;
  final double w, h;
  double rot;
  final double vr, phase, sway;
  final Color color;
  int life = 0;
  final int maxLife;

  /// 出生高度：用来判断「已经往下掉了多远」，落太深就提前淡出
  final double spawnY;

  /// 这一片开始淡出的下落距离（每片在 [kFallFadeStart, +90] 内随机，错开退场）
  final double fadeStart;

  /// 1 = 满不透明；掉到 [fadeStart] 以下开始递减，到 0 就移除
  double fade = 1;

  /// 0→1 的生命进度
  double get progress => life / maxLife;
}

class ConfettiField extends ChangeNotifier {
  ConfettiField({int? seed}) : _rnd = math.Random(seed);

  final math.Random _rnd;
  final List<ConfettiParticle> _parts = [];
  double _accMs = 0;

  List<ConfettiParticle> get particles => List.unmodifiable(_parts);
  bool get isEmpty => _parts.isEmpty;
  int get length => _parts.length;

  /// 在一个点上炸开 [n] 片纸屑
  void burstAt(Offset c, {int n = 16, double boost = 1}) {
    for (var i = 0; i < n; i++) {
      final ang = _rnd.nextDouble() * math.pi * 2;
      final spd = (2.2 + _rnd.nextDouble() * 5.4) * boost;
      // 四成细纸条、六成小方块
      final strip = _rnd.nextDouble() < .4;
      // 角度接近垂直时 cos 接近 0，纸片会沿一条竖线直上直下；
      // 补到最小水平速度，保证都往两侧散开
      var vx = math.cos(ang) * spd;
      if (vx.abs() < kMinVx) {
        vx = (vx == 0 ? (_rnd.nextBool() ? 1.0 : -1.0) : vx.sign) * kMinVx;
      }
      _parts.add(
        ConfettiParticle(
          x: c.dx + (_rnd.nextDouble() - .5) * 14,
          y: c.dy + (_rnd.nextDouble() - .5) * 14,
          w: strip ? 3 + _rnd.nextDouble() * 2.2 : 5.5 + _rnd.nextDouble() * 5.5,
          h: strip ? 12 + _rnd.nextDouble() * 7 : 7 + _rnd.nextDouble() * 7,
          rot: _rnd.nextDouble() * math.pi * 2,
          vr: (_rnd.nextDouble() - .5) * .65,
          vx: vx,
          vy: math.sin(ang) * spd - 1.8, // 整体偏上，像被“顶”起来
          phase: _rnd.nextDouble() * math.pi * 2,
          sway: .3 + _rnd.nextDouble() * .5,
          color: kConfettiColors[_rnd.nextInt(kConfettiColors.length)],
          maxLife: 165 + _rnd.nextInt(85), // 2.7 ~ 4.2 秒
          fadeStart: kFallFadeStart + _rnd.nextDouble() * 90,
        ),
      );
    }
    notifyListeners();
  }

  /// 两张卡之间爆炸。
  ///
  /// 中英两列是各自打乱的，配对的两张卡常常不在同一行，所以两张卡各炸一次，
  /// 各自 10 片纸屑（合计 20 片：原先各 20 片太满，会糊住旁边的牌面，已减半）。
  ///
  /// 不再在两卡连线的中点单独爆一次：中点在屏幕中缝上，那里的纸片即使补了
  /// 水平速度也容易贴着中线往下走，看起来就是「几片碎纸从屏幕正中掉下来」，
  /// 正好压在学习区上。去掉中点后，中间由两侧飞溅自然填满。
  void burstBetween(Offset a, Offset b) {
    burstAt(a, n: 10);
    burstAt(b, n: 10);
  }

  /// 推进一帧物理
  void step() {
    if (_parts.isEmpty) return;
    for (final p in _parts) {
      p.life++;
      p.vy += kConfettiGravity;
      p.vx *= .993;
      // 水平速度不能衰减到 0：一旦 vx≈0，后半程只剩重力，
      // 纸片就会变成一条竖线直直落下（中缝那几片最扎眼）。
      // 留一点横向漂移，让它始终斜着飘出去。
      const floorVx = kMinVx * .44;
      if (p.vx.abs() < floorVx) {
        p.vx = (p.vx.isNegative ? -1.0 : 1.0) * floorVx;
      }
      p.x += p.vx + math.sin(p.life * .055 + p.phase) * p.sway; // 左右飘
      p.y += p.vy;
      p.rot += p.vr;
      // 掉太深就淡掉：别让纸片穿过下半屏的牌面
      final fall = p.y - p.spawnY;
      if (fall > p.fadeStart) {
        p.fade = math.max(0, 1 - (fall - p.fadeStart) / kFallFadeWidth);
      }
    }
    _parts.removeWhere((p) => p.life >= p.maxLife || p.fade <= 0);
  }

  /// 按真实时间推进（固定 1/60 秒步长，慢设备上也不会飘得更快）
  void tick(double dtMs) {
    if (_parts.isEmpty) return;
    _accMs += math.min(dtMs, 120); // 卡顿后不追帧，直接丢掉多余时间
    var stepped = false;
    while (_accMs >= kConfettiFrameMs) {
      step();
      _accMs -= kConfettiFrameMs;
      stepped = true;
      if (_parts.isEmpty) break;
    }
    if (stepped) notifyListeners();
  }

  /// 直接跳到第 [frames] 帧（截图 / 测试用，不走时钟）
  void advanceFrames(int frames) {
    for (var i = 0; i < frames && _parts.isNotEmpty; i++) {
      step();
    }
    notifyListeners();
  }

  void clear() {
    if (_parts.isEmpty) return;
    _parts.clear();
    _accMs = 0;
    notifyListeners();
  }

  void paint(Canvas canvas, Size size) {
    if (_parts.isEmpty) return;
    final paint = Paint()..isAntiAlias = false;
    for (final p in _parts) {
      final k = p.progress;
      // 前 60% 保持实心，最后 40% 才淡掉，飘落时才看得清
      var alpha = k < .6 ? 1.0 : math.max(0.0, 1 - (k - .6) / .4);
      alpha *= p.fade; // 掉太深的那批在这里提前消失
      if (alpha <= 0) continue;
      paint.color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      canvas.drawRect(
        Rect.fromLTWH(-p.w / 2, -p.h / 2, p.w, p.h),
        paint,
      );
      canvas.restore();
    }
  }
}

/// 盖在牌桌上的纸屑层：Ticker 驱动重绘，不接收点击。
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.field});

  final ConfettiField field;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  /// 整个 State 生命周期只创建这一个 Ticker。
  ///
  /// 之前是「粒子清空就 stop 并置 null，下次爆炸再 createTicker」，
  /// 但 [SingleTickerProviderStateMixin] 内部也存着 ticker 引用，只允许创建一次：
  /// 第二次 createTicker 会在 debug 下抛 “multiple tickers were created”，
  /// 新纸屑没人推进，就永远停在爆点原处，玩得越久累积越多。
  /// 正确做法是常驻一个 Ticker，用 start / stop 控制。
  late final Ticker _ticker;

  /// 上一帧的 elapsed；为 null 表示刚从停止状态起跑，这一帧只用来对表
  Duration? _last;

  @override
  void initState() {
    super.initState();
    widget.field.addListener(_onField);
    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(ConfettiOverlay old) {
    super.didUpdateWidget(old);
    if (old.field != widget.field) {
      old.field.removeListener(_onField);
      widget.field.addListener(_onField);
      _last = null;
      _syncTicker();
    }
  }

  void _onField() => _syncTicker();

  void _syncTicker() {
    if (widget.field.isEmpty) {
      if (_ticker.isActive) _ticker.stop();
      _last = null;
      return;
    }
    if (_ticker.isActive) return;
    _last = null; // 重新起跑时 elapsed 从 0 算，别拿旧时间差当 dt
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    if (last == null) return; // 首帧只对表
    final dt = (elapsed - last).inMicroseconds / 1000;
    if (dt <= 0) return;
    widget.field.tick(dt);
    // 粒子散尽后自己收工，省得空转
    if (widget.field.isEmpty && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    widget.field.removeListener(_onField);
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(widget.field),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.field) : super(repaint: field);

  final ConfettiField field;

  @override
  void paint(Canvas canvas, Size size) => field.paint(canvas, size);

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.field != field;
}
