import 'package:flutter/material.dart';

import '../checkin.dart';
import '../progress.dart';
import '../ui.dart';

/// 打卡记录页：连胜大数字 + 火焰 + 月历（连续打卡串成渐变胶囊）+ 统计。
///
/// 数据全部来自 [Progress.days]（按天存），日历与「最长连胜」都从这一份算，
/// 不再维护第二个计数器。
class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  static const _red = Color(0xFFE01E5A);
  static const _redDeep = Color(0xFFC4123F);
  static const _orange = Color(0xFFFF6B3D);

  late MonthGrid _grid;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _grid = MonthGrid(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final p = Progress.I;
    final days = p.days;
    final streak = p.streak;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _bar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                children: [
                  _hero(streak),
                  _note(days, streak),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    child: Text('连胜日历',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kInk,
                            letterSpacing: -.2)),
                  ),
                  _calendar(days, now),
                  _stats(days, streak, now),
                ],
              ),
            ),
            _foot(p.checkedToday),
          ],
        ),
      ),
    );
  }

  Widget _bar() {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 21, color: kInk),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 英雄区

  Widget _hero(int streak) {
    return SizedBox(
      height: 142,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFE9A8), Color(0xFFFFD465)]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  streak >= 7 ? '🏅 连胜精英俱乐部' : '🔥 连胜刚开始',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A5B00),
                      letterSpacing: .2),
                ),
              ),
              const SizedBox(height: 10),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF5335F), _red, _redDeep],
                ).createShader(r),
                child: Text('$streak',
                    style: const TextStyle(
                        fontSize: 56,
                        height: .92,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                        color: Colors.white)),
              ),
              const SizedBox(height: 6),
              const Text('天连胜！',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                      color: _red)),
            ],
          ),
          Positioned(
            right: 4,
            top: 8,
            width: 112,
            height: 124,
            child: CustomPaint(painter: _FlamePainter()),
          ),
        ],
      ),
    );
  }

  Widget _note(Set<String> days, int streak) {
    final week = countInWeek(days, DateTime.now());
    final text = streak > 0
        ? '本周已打卡 $week 天，连续 $streak 天没断。'
        : (week > 0
            ? '本周已打卡 $week 天，今天再学一关就能续上。'
            : '还没有连胜记录，学完任意一关就算打卡。');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('☀️', style: TextStyle(fontSize: 19, height: 1.15)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.72, color: Color(0xFF4B475E))),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 日历

  Widget _calendar(Set<String> days, DateTime now) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _navBtn(Icons.chevron_left_rounded, -1),
              SizedBox(
                width: 108,
                child: Text('${_grid.year}年${_grid.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                        color: kInk)),
              ),
              _navBtn(Icons.chevron_right_rounded, 1),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(w,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB6B2C8))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, cons) {
            final cellW = cons.maxWidth / 7;
            return Column(
              children: [
                for (final week in _grid.weeks)
                  SizedBox(
                    height: 34,
                    child: Stack(
                      children: [
                        // 连续打卡的胶囊在日期数字下面
                        for (final run in _grid.runsIn(week, days))
                          Positioned(
                            left: run[0] * cellW,
                            top: 2,
                            width: run[1] * cellW - 1.2,
                            height: 30,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  _redDeep,
                                  _red,
                                  _orange,
                                ], stops: [
                                  0,
                                  .4,
                                  1
                                ]),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x8CE01E5A),
                                      blurRadius: 8,
                                      offset: Offset(0, 3)),
                                ],
                              ),
                            ),
                          ),
                        for (var i = 0; i < 7; i++)
                          if (week[i] != null)
                            Positioned(
                              left: i * cellW,
                              top: 0,
                              width: cellW,
                              height: 34,
                              child: _dayCell(week[i]!, days, now),
                            ),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _dayCell(int day, Set<String> days, DateTime now) {
    final on = days.contains(_grid.keyOf(day));
    final today = now.year == _grid.year &&
        now.month == _grid.month &&
        now.day == day;
    final Color color;
    if (on) {
      color = Colors.white;
    } else if (today) {
      color = kPrimary;
    } else {
      color = const Color(0xFFDCD8E8);
    }
    return Center(
      child: Text('$day',
          style: TextStyle(
            fontSize: today ? 13.5 : 12.5,
            fontWeight: on || today ? FontWeight.w800 : FontWeight.w700,
            color: color,
            letterSpacing: -.3,
          )),
    );
  }

  Widget _navBtn(IconData icon, int delta) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: () => setState(() => _grid = _grid.shift(delta)),
        icon: Icon(icon, size: 20, color: const Color(0xFFB6B2C8)),
      ),
    );
  }

  Widget _stats(Set<String> days, int streak, DateTime now) {
    final items = [
      ('${countInMonth(days, _grid.year, _grid.month)}', '本月打卡', _red),
      ('$streak', '当前连胜', kInk),
      ('${longestRun(days)}', '最长连胜', kInk),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kLine),
                ),
                child: Column(
                  children: [
                    Text(items[i].$1,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                            color: items[i].$3)),
                    const SizedBox(height: 2),
                    Text(items[i].$2,
                        style: const TextStyle(fontSize: 10, color: kMuted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 底部

  Widget _foot(bool done) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
      child: Column(
        children: [
          const Text('学完任意一关即算打卡 · 断一天连击归零',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: kMuted)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: done
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F2FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 18, color: kMuted),
                        SizedBox(width: 6),
                        Text('今天已打卡',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: kMuted)),
                      ],
                    ),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_red, _orange],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0xB3E01E5A),
                            blurRadius: 20,
                            offset: Offset(0, 8)),
                      ],
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('去学一关，接上连胜',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 设计稿里的火焰（两段路径，外焰渐变 + 内焰白）
class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 140);

    final outer = Path()
      ..moveTo(60, 6)
      ..cubicTo(76, 34, 98, 42, 98, 72)
      ..arcToPoint(const Offset(22, 72),
          radius: const Radius.circular(38), clockwise: true)
      ..cubicTo(22, 54, 32, 43, 42, 32)
      ..cubicTo(44, 45, 51, 52, 58, 52)
      ..cubicTo(65, 52, 67, 45, 65, 36)
      ..cubicTo(64, 29, 64, 16, 60, 6)
      ..close();

    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            Color(0xFFC4123F),
            Color(0xFFE01E5A),
            Color(0xFFFF6B3D),
            Color(0xFFFFC53D),
          ],
          stops: [0, .45, .78, 1],
        ).createShader(const Rect.fromLTWH(0, 0, 120, 140)),
    );

    final inner = Path()
      ..moveTo(60, 66)
      ..cubicTo(69, 81, 78, 85, 78, 98)
      ..arcToPoint(const Offset(42, 98),
          radius: const Radius.circular(18), clockwise: true)
      ..cubicTo(42, 85, 51, 79, 60, 66)
      ..close();
    canvas.drawPath(
        inner, Paint()..color = Colors.white.withValues(alpha: .92));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
