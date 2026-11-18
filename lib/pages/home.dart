import 'dart:math';

import 'package:flutter/material.dart';

import '../bank.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../progress.dart';
import '../ui.dart';
import 'checkin.dart';
import 'match.dart';
import 'paywall.dart';
import 'session.dart';

/// 首页：关卡路径（台地 + S 线）/ 主题阶梯 / 自由练习。
///
/// 三种模式共用一条顶栏：左上角级别胶囊点开是**从顶部滑下**的面板
/// （级别 / 进度 / 今日 / 统计 / 快捷），比原来的底部半屏信息更全。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onNavigate});

  /// 切换底部导航（0 学习 / 1 复习 / 2 词典 / 3 我的）。
  /// 下拉面板里的「去复习」要用它，而不是自己 push 一个没有 Scaffold 的页面。
  final ValueChanged<int>? onNavigate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  /// 0=关卡 1=主题 2=自由
  int _mode = 0;

  bool _dropOpen = false;
  late final AnimationController _dropCtl;
  final _pathScroll = ScrollController();
  final _themeScroll = ScrollController();

  /// 已经自动滚到过哪个节点的标记（'A1:2'），避免每帧重建都把用户拽回去
  String? _autoScrolled;

  /// 主题页同理：'A1:2'
  String? _themeAutoScrolled;

  @override
  void initState() {
    super.initState();
    _dropCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _dropCtl.dispose();
    _pathScroll.dispose();
    _themeScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appTick,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = Curriculum.I;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _header(c),
              _tabs(c),
              Expanded(
                child: switch (_mode) {
                  1 => _themeBody(c),
                  2 => _freeBody(c),
                  _ => _pathBody(c),
                },
              ),
            ],
          ),
          _dropLayer(c),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 顶栏

  Widget _header(Curriculum c) {
    final lv = kLevels.firstWhere((l) => l.id == c.curLv,
        orElse: () => kLevels.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          _levelPill(lv),
          const Spacer(),
          _streakChip(),
        ],
      ),
    );
  }

  Widget _levelPill(LvInfo lv) {
    return GestureDetector(
      onTap: _toggleDrop,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
                color: ta(kPrimaryDeep, 0x3D),
                blurRadius: 14,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kHeroA, kHeroB],
                ),
              ),
              child: Text(lv.id,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
            const SizedBox(width: 7),
            Text(lv.name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInk)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _dropOpen ? .5 : 0,
              duration: const Duration(milliseconds: 250),
              child: Icon(Icons.expand_more_rounded,
                  size: 18, color: kN4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _streakChip() {
    return GestureDetector(
      onTap: _openCheckin,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
                color: ta(kPrimaryDeep, 0x33),
                blurRadius: 14,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded,
                size: 15, color: kFlame),
            const SizedBox(width: 3),
            Text('${Progress.I.streak} 天',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kFlame)),
          ],
        ),
      ),
    );
  }

  Widget _tabs(Curriculum c) {
    const labels = ['关卡', '主题', '自由'];
    final hint = switch (_mode) {
      1 => '${c.curThemes.length} 个主题',
      2 => '随机 ${Curriculum.perUnit} 词',
      _ => '${_learnedWords(c, c.curLv)} / ${c.wordCountOf(c.curLv)} 词',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            _tab(labels[i], i),
          ],
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Text(hint,
                style: TextStyle(fontSize: 10.5, color: kMuted)),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, int i) {
    final on = _mode == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _mode = i),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? kInk : kN4)),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: on ? 18 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 关卡路径

  Widget _pathBody(Curriculum c) {
    final lv = c.curLv;
    final units = c.unitsOf(lv);
    if (units.isEmpty) {
      return _emptyState('这个级别还没有词', '联网同步一次词库，或换一个级别看看');
    }
    final idx = c.currentIndex(lv);

    return LayoutBuilder(
      builder: (context, cons) {
        final geo = _PathGeo(width: cons.maxWidth, count: units.length);
        _scheduleAutoScroll(lv, idx, geo.y(idx));

        return SingleChildScrollView(
          controller: _pathScroll,
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: geo.height,
            child: Stack(
              children: [
                for (var s = 0;
                    s * _PathGeo.perBand < units.length;
                    s++)
                  _band(geo, units, s),
                Positioned.fill(
                    child: CustomPaint(painter: _PathPainter(geo, idx))),
                for (var i = 0; i < units.length; i++)
                  ..._node(c, geo, units, i, idx),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 台地色块：每 5 个学习关 + 1 个复习关裹成一块，色块本身就是进度条
  Widget _band(_PathGeo geo, List<Unit> units, int s) {
    final from = s * _PathGeo.perBand;
    final to = min(from + _PathGeo.perBand - 1, units.length - 1);
    final top = geo.y(from) - 62;
    final bottom = geo.y(to) + 70;
    return Positioned(
      left: 12,
      right: 12,
      top: top,
      height: bottom - top,
      child: Container(
        decoration: BoxDecoration(
          color: s.isOdd ? kPrimary50 : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ta(kPrimary, 0x12)),
          boxShadow: [
            BoxShadow(
                color: ta(kInk, 0x14),
                blurRadius: 30,
                offset: Offset(0, 14)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('第 ${s + 1} 段',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                      color: kN5)),
              const SizedBox(width: 6),
              Text('U${from + 1}–U${to + 1}',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: kN3)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _node(
      Curriculum c, _PathGeo geo, List<Unit> units, int i, int cur) {
    final lv = c.curLv;
    final u = units[i];
    final done = c.isPassed(lv, u.id);
    final open = c.isOpen(lv, i);
    final byPlan = c.lockedByPlan(lv, i);
    final isCur = i == cur;
    final size = isCur ? 70.0 : 56.0;

    final Gradient? grad;
    final Color bg;
    final Color border;
    final Color fg;
    final Color shadow;

    if (u.review && done) {
      grad = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0B450), Color(0xFFDE9418)]);
      bg = Colors.transparent;
      border = Colors.transparent;
      fg = Colors.white;
      shadow = const Color(0xFFB7790D);
    } else if (done) {
      grad = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kHeroA, kHeroB]);
      bg = Colors.transparent;
      border = Colors.transparent;
      fg = Colors.white;
      shadow = kPrimary;
    } else if (isCur) {
      grad = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kHeroA, kHeroB]);
      bg = Colors.transparent;
      border = Colors.transparent;
      fg = Colors.white;
      shadow = kPrimary;
    } else if (u.review) {
      grad = null;
      bg = kAmber50;
      border = const Color(0xFFEFC97E);
      fg = const Color(0xFFB26A0B);
      shadow = kLine;
    } else {
      grad = null;
      bg = Colors.white;
      border = kN2;
      fg = kN3;
      shadow = kLine;
    }

    final glyph = done
        ? Icon(Icons.check_rounded,
            size: isCur ? 28 : 24, color: Colors.white)
        : (u.review
            ? Icon(Icons.auto_stories_rounded,
                size: isCur ? 24 : 20, color: fg)
            : Text('${i + 1}',
                style: TextStyle(
                    fontSize: isCur ? 21 : 15,
                    fontWeight: FontWeight.w800,
                    color: fg)));

    return [
      Positioned(
        left: geo.x(i) - size / 2,
        top: geo.y(i) - size / 2,
        width: size,
        height: size,
        child: GestureDetector(
          onTap: () {
            if (byPlan) {
              showPaywall(context, reason: '解锁 $lv 的 ${u.id} 及后续关卡');
            } else if (!open) {
              _toast('完成 ${units[i - 1].id} 后解锁 ${u.id}');
            } else {
              _openLevel(i);
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 当前关：一圈静态柔光（不做无限呼吸动画，省电也省测试时间）
              if (isCur && !done)
                Positioned(
                  left: -9,
                  top: -9,
                  width: size + 18,
                  height: size + 18,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: kDash, width: 2),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: grad == null ? bg : null,
                  gradient: grad,
                  border: Border.all(
                      color: border, width: grad == null ? 2 : 0),
                  boxShadow: [
                    BoxShadow(
                        color: shadow, offset: const Offset(0, 4)),
                    if (isCur)
                      BoxShadow(
                          color: ta(kPrimaryDeep, 0x8C),
                          blurRadius: 26,
                          offset: Offset(0, 10)),
                  ],
                ),
                alignment: Alignment.center,
                child: glyph,
              ),
              if (isCur && !done)
                const Positioned(
                  right: -3,
                  top: -13,
                  child: Text('🚩', style: TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      ),
      if (isCur) _bubble(geo, i, done, size),
    ];
  }

  /// 当前关旁边的「继续 · U9」标签。
  ///
  /// 原来放在节点正下方，会和下一关撞在一起（下一关往往就往那一侧偏），
  /// 改成贴在节点侧面、垂直居中：既不挡下一关，也不会盖住曲线。
  Widget _bubble(_PathGeo geo, int i, bool done, double size) {
    const w = 112.0;
    const h = 32.0;
    final x = geo.x(i);
    final rightRoom = geo.width - 16 - (x + size / 2 + 8);
    final leftRoom = (x - size / 2 - 8) - 16;
    final toRight = rightRoom >= w || rightRoom >= leftRoom;
    final left = toRight ? x + size / 2 + 8 : x - size / 2 - 8 - w;
    final top = geo.y(i) - h / 2;

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: GestureDetector(
        onTap: () => _openLevel(i),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kHeroB,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                  color: ta(kPrimaryDeep, 0xB3),
                  blurRadius: 22,
                  offset: Offset(0, 10)),
            ],
          ),
          child: Text(done ? '重刷 · U${i + 1}' : '继续 · U${i + 1}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ),
    );
  }

  void _scheduleAutoScroll(String lv, int idx, double nodeY) {
    final key = '$lv:$idx';
    if (_autoScrolled == key) return;
    _autoScrolled = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pathScroll.hasClients) return;
      final max = _pathScroll.position.maxScrollExtent;
      final target = (nodeY - 240).clamp(0.0, max);
      if ((_pathScroll.offset - target).abs() > 2) {
        _pathScroll.jumpTo(target);
      }
    });
  }

  // ------------------------------------------------------------ 主题阶梯

  Widget _themeBody(Curriculum c) {
    final themes = c.curThemes;
    if (themes.isEmpty) {
      return _emptyState('这个级别还没有主题', '换一个级别看看，或稍后联网同步一次内容');
    }
    final hero = _heroThemeIndex(c);

    // 水平内边距 18 + 18，曲线几何按内容宽度算，和内层 Column 同宽
    return LayoutBuilder(
      builder: (context, cons) {
        final geo = _BowGeo(width: cons.maxWidth - 36, count: themes.length);
        _scheduleThemeScroll(c.curLv, hero, geo.centerY(hero));
        return Stack(
          children: [
            SingleChildScrollView(
              controller: _themeScroll,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 76),
              child: Column(
                children: [
                  _themeHead(c),
                  const SizedBox(height: 12),
                  _themePath(c, geo, hero),
                ],
              ),
            ),
            if (hero >= 0) _themeFab(geo, hero),
          ],
        );
      },
    );
  }

  /// 打开主题页时滚到当前主题；同一级别同一主题只滚一次，
  /// 之后用户自己滚到哪儿都算数（重建不会把人拽回去）
  void _scheduleThemeScroll(String lv, int hero, double y) {
    final key = '$lv:$hero';
    if (_themeAutoScrolled == key) return;
    _themeAutoScrolled = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_themeScroll.hasClients) return;
      final pos = _themeScroll.position;
      if (!pos.hasViewportDimension) return;
      final target =
          (y - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
      _themeScroll.jumpTo(target);
    });
  }

  /// 当前的（第一个没学完的）主题。全部学完时落回第一个，让「继续」有个落点。
  int _heroThemeIndex(Curriculum c) {
    final n = c.curThemes.length;
    if (n == 0) return -1;
    for (var i = 0; i < n; i++) {
      if (c.themeLearned(i) < c.themeWords(i).length) return i;
    }
    return 0;
  }

  Widget _themeHead(Curriculum c) {
    final total = c.curThemes.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            Ent.I.vip
                ? '${c.curLv} · $total 个主题全部解锁'
                : '${c.curLv} · 免费开放 '
                    '${min(Ent.I.ent.limits.themesPerLevel, total)} / $total 个主题',
            style: TextStyle(fontSize: 10.5, color: kMuted),
          ),
        ),
        if (!Ent.I.vip)
          GestureDetector(
            onTap: () => showPaywall(context, reason: '解锁全部 $total 个主题'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kLine),
              ),
              child: Text('解锁全部',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryDeep)),
            ),
          ),
      ],
    );
  }

  /// S 线方块：左右两列交替，每两格之间一段弓形弧
  Widget _themePath(Curriculum c, _BowGeo geo, int hero) {
    final n = c.curThemes.length;
    return SizedBox(
      height: geo.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _BowPainter(geo, hero))),
          for (var i = 0; i < n; i++)
            Positioned(
              left: geo.left(i),
              top: geo.topOf(i),
              width: _BowGeo.size,
              height: _BowGeo.size,
              child: _themeTile(c, i, hero),
            ),
        ],
      ),
    );
  }

  /// 右下角「回到学习位置」：当前主题在视口上半屏 → ↑，下半屏 → ↓
  Widget _themeFab(_BowGeo geo, int hero) {
    return Positioned(
      right: 16,
      bottom: 18,
      child: AnimatedBuilder(
        animation: _themeScroll,
        builder: (context, _) {
          var up = false;
          // 首帧还没量出视口尺寸时 viewportDimension 会抛空断言，必须挡一下
          if (_themeScroll.hasClients) {
            final pos = _themeScroll.position;
            if (pos.hasViewportDimension) {
              up = geo.centerY(hero) - pos.pixels < pos.viewportDimension / 2;
            }
          }
          return _RoundFab(up: up, onTap: () => _jumpToTheme(geo, hero));
        },
      ),
    );
  }

  /// 点一下把当前主题滚到视口正中。上面还有标题和 10dp 内边距，补 46dp
  void _jumpToTheme(_BowGeo geo, int hero) {
    if (!_themeScroll.hasClients) return;
    final pos = _themeScroll.position;
    if (!pos.hasViewportDimension) return;
    final target = (geo.centerY(hero) - pos.viewportDimension / 2 + 46)
        .clamp(0.0, pos.maxScrollExtent);
    _themeScroll.animateTo(target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic);
  }

  /// 一个主题方块（92dp）：图标 + 名称 + 一行副文字。
  ///
  /// 状态不写字，只靠颜色：已学完 = 淡紫底 + 右上角紫对勾，
  /// 当前 = 紫渐变 + 底部进度条，未开始 = 灰底，会员 = 灰底 + 虚线 + 金锁。
  Widget _themeTile(Curriculum c, int i, int hero) {
    final t = c.curThemes[i];
    final total = c.themeWords(i).length;
    final learned = c.themeLearned(i);
    final locked = !c.themeUnlocked(i);
    // 免费额度用完时，「当前」可能落在锁住的主题上（学完 1 个就轮到第 2 个），
    // 这时仍要给它紫渐变 + 金锁当落点，否则整页没有视觉锚点、像卡住了
    final isCur = i == hero;
    final done = !locked && !isCur && total > 0 && learned >= total;

    final sub = locked || !isCur ? '$total 词' : '已学 $learned / $total';
    final titleColor = isCur
        ? Colors.white
        : (done
            ? kPrimaryDeep
            : (locked ? kN4 : kN5));
    final subColor = isCur
        ? Colors.white.withValues(alpha: .85)
        : (done ? kN4 : kMuted);

    return GestureDetector(
      onTap: () => locked
          ? showPaywall(context, reason: '解锁「${t.name}」及全部主题')
          : _openTheme(i),
      child: CustomPaint(
        foregroundPainter: locked
            ? _DashedBorderPainter(radius: 20, color: kN2)
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: isCur
                ? null
                : (done ? kPrimary50 : kN1),
            gradient: isCur
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kHeroA, kHeroB])
                : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCur
                  ? Colors.transparent
                  : (done
                      ? kPriLine
                      : (locked
                          ? Colors.transparent
                          : kN1)),
            ),
            boxShadow: isCur
                ? [
                    BoxShadow(color: kPrimary, offset: Offset(0, 4)),
                    BoxShadow(color: ta(kPrimary, 0x22), spreadRadius: 7),
                    BoxShadow(
                        color: ta(kPrimaryDeep, 0x66),
                        blurRadius: 26,
                        offset: Offset(0, 14)),
                  ]
                : locked
                    ? null
                    : [
                        BoxShadow(
                            color: done
                                ? kN1
                                : kN2,
                            offset: const Offset(0, 3)),
                        BoxShadow(
                            color: ta(kInk, 0x2E),
                            blurRadius: 20,
                            offset: Offset(0, 10)),
                      ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(6, 8, 6, isCur ? 12 : 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: locked ? .55 : 1,
                        child: Text(t.emoji,
                            style: const TextStyle(fontSize: 21, height: 1.05)),
                      ),
                      const SizedBox(height: 3),
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.1,
                              color: titleColor)),
                      const SizedBox(height: 1),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, color: subColor)),
                    ],
                  ),
                ),
              ),
              if (isCur && !locked)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : (learned / total).clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: .28),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              if (done)
                Positioned(top: 6, right: 6, child: _tickBadge()),
              if (locked)
                Positioned(top: 6, right: 6, child: _lockBadge()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tickBadge() => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: kPrimary),
        child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
      );

  Widget _lockBadge() => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              LinearGradient(colors: [Color(0xFFF7D488), Color(0xFFE0A02A)]),
        ),
        child: const Icon(Icons.lock_rounded, size: 9, color: Colors.white),
      );

  // ------------------------------------------------------------ 自由练习

  Widget _freeBody(Curriculum c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Text(
          '${c.curLv} · 从整级词库随机抽 ${Curriculum.perUnit} 词，不限次数',
          style: TextStyle(fontSize: 11.5, color: kMuted, height: 1.5),
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLine),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎲', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('每轮 ${Curriculum.perUnit} 词 · 混合题型',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '选择、拼写、听音三种题型混排，答错的词会再次出现，直到答对为止。',
                      style: TextStyle(
                          fontSize: 11.5, color: kN4, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _openFree,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('开始自由练习',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 顶部下拉

  Widget _dropLayer(Curriculum c) {
    return AnimatedBuilder(
      animation: _dropCtl,
      builder: (context, _) {
        final t = _dropCtl.value;
        if (t <= 0.001) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDrop,
                child: ColoredBox(
                  color: kInk.withValues(alpha: .36 * t),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 46,
              child: FractionalTranslation(
                translation: Offset(0, -(1 - t)),
                child: _dropPanel(c),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dropPanel(Curriculum c) {
    final maxH = MediaQuery.of(context).size.height * .68;
    final lv = kLevels.firstWhere((l) => l.id == c.curLv,
        orElse: () => kLevels.first);
    final units = c.unitCountOf(c.curLv);
    final passed = c.passedCount(c.curLv);
    final totalWords = c.wordCountOf(c.curLv);
    final learned = _learnedWords(c, c.curLv);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: ta(kInk, 0x8C),
              blurRadius: 40,
              offset: Offset(0, 22)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('选择级别',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 7),
                      Text('每关 ${Curriculum.perUnit} 词 · '
                          '每 ${Curriculum.learnPerReview} 关一次复习',
                          style: TextStyle(
                              fontSize: 10.5, color: kMuted)),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (var i = 0; i < kLevels.length; i++) ...[
                        if (i > 0) const SizedBox(width: 7),
                        Expanded(child: _dropLevelCard(c, kLevels[i])),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _dropBar(
                    left: '${lv.id} ${lv.name} · 已学 $learned / $totalWords 词',
                    right: '$passed / $units 关',
                    value: units == 0 ? 0 : passed / units,
                    colors: [kHeroA, kHeroB],
                    boxed: true,
                  ),
                  const SizedBox(height: 12),
                  _dropBar(
                    left: '今天已学',
                    right: '${c.todayWords} / ${Curriculum.dailyGoal} 词',
                    value: c.todayRatio,
                    colors: const [Color(0xFF5BBF8A), Color(0xFF2E9E63)],
                    boxed: false,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _dropStat('${Progress.I.masteredCount}', '已掌握'),
                      const SizedBox(width: 8),
                      _dropStat('${Progress.I.dueWords().length}', '待复习'),
                      const SizedBox(width: 8),
                      _dropStat('${Progress.I.wrongBook().length}', '易错词'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _dropQuick('📚', '换主题', () {
                        _closeDrop();
                        setState(() => _mode = 1);
                      }),
                      const SizedBox(width: 8),
                      _dropQuick('↻', '去复习', () {
                        _closeDrop();
                        widget.onNavigate?.call(1);
                      }),
                      const SizedBox(width: 8),
                      _dropQuick('🔥', '打卡记录', () {
                        _closeDrop();
                        _openCheckin();
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropLevelCard(Curriculum c, LvInfo l) {
    final on = l.id == c.curLv;
    final locked = !Ent.I.canLevel(l.id);
    final units = c.unitCountOf(l.id);
    final passed = c.passedCount(l.id);
    final pct = units == 0 ? 0.0 : (passed / units).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () {
        if (locked) {
          _closeDrop();
          showPaywall(context, reason: '解锁 ${l.id} 级别全部内容');
          return;
        }
        if (on) {
          _closeDrop();
          return;
        }
        setState(() {
          c.curLv = l.id;
          _autoScrolled = null;
        });
        c.save();
        _closeDrop();
        _toast('已切换到 ${l.id} ${l.name}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: on ? kPrimary50 : (locked ? kBg : Colors.white),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: on ? kPrimary : kLine, width: on ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(l.id,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                          color: on
                              ? kPrimaryDeep
                              : (locked ? kN3 : kInk))),
                ),
                if (locked) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.lock_rounded,
                      size: 9, color: kN3),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(l.name,
                maxLines: 1,
                style: TextStyle(fontSize: 9.5, color: kMuted)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: pct <= 0 ? 0.04 : pct,
                minHeight: 4,
                backgroundColor: kN1,
                valueColor: AlwaysStoppedAnimation(
                    locked ? kN3 : kPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropBar({
    required String left,
    required String right,
    required double value,
    required List<Color> colors,
    required bool boxed,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: kMuted)),
            ),
            const SizedBox(width: 8),
            Text(right,
                style:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 9),
        _gradientBar(value, colors, 6),
      ],
    );
    if (!boxed) return content;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: content,
    );
  }

  /// 渐变进度条（LinearProgressIndicator 只支持单色）
  Widget _gradientBar(double value, List<Color> colors, double height) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            Positioned.fill(
                child: ColoredBox(color: kN1)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropStat(String v, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kLine),
        ),
        child: Column(
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(fontSize: 9.5, color: kMuted)),
          ],
        ),
      ),
    );
  }

  Widget _dropQuick(String emoji, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kLine),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16, height: 1.1)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: kN5)),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleDrop() {
    _dropOpen ? _closeDrop() : _openDrop();
  }

  void _openDrop() {
    setState(() => _dropOpen = true);
    _dropCtl.forward();
  }

  void _closeDrop() {
    if (!_dropOpen) return;
    setState(() => _dropOpen = false);
    _dropCtl.reverse();
  }

  // ------------------------------------------------------------ 跳转

  Future<void> _openCheckin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CheckinPage()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _runSession({
    required List<Word> words,
    required String title,
    required int startDone,
    required void Function(int n) onProgress,
    MatchScene? scene,
  }) async {
    if (words.isEmpty) return;
    var seen = startDone;
    void progress(int n) {
      onProgress(n);
      if (n > seen) {
        Curriculum.I.addToday(n - seen);
        seen = n;
      }
    }

    // 关卡 / 主题统一走两列配对棋盘（只有一种展示方式）；
    // 自由练习保留原来的四选一·拼写·听音混排。
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => scene != null
          ? MatchPage(
              words: words,
              title: title,
              subtitle: '${words.length} 对配对 · 左边英文 · 右边中文',
              scene: scene,
              onProgress: progress,
            )
          : SessionPage(
              items: SessionPlan.fromWords(words),
              title: title,
              onProgress: progress,
            ),
    ));
    if (!mounted) return;
    setState(() {});
    if (ok == true) appTick.value++;
  }

  Future<void> _openLevel(int i) async {
    final c = Curriculum.I;
    final lv = c.curLv;
    final units = c.unitsOf(lv);
    if (i < 0 || i >= units.length) return;
    final u = units[i];
    await _runSession(
      words: u.words,
      title: u.title,
      startDone: c.partOf(lv, u.id),
      onProgress: (n) => c.setPart(lv, u.id, n),
      scene: MatchScene.level,
    );
    // 全部答完才算通关（中途退出只记半程进度）
    if (c.partOf(lv, u.id) >= u.total) c.markPassed(lv, u.id);
  }

  Future<void> _openTheme(int i) async {
    final c = Curriculum.I;
    final lv = c.curLv;
    final ws = c.themeWords(i);
    if (ws.isEmpty) {
      _toast('这个主题还没有词');
      return;
    }
    await _runSession(
      words: ws,
      title: c.curThemes[i].name,
      startDone: c.themeLearned(i),
      onProgress: (n) => c.markTheme(lv, i, n),
      scene: MatchScene.theme,
    );
  }

  Future<void> _openFree() async {
    final c = Curriculum.I;
    if (!Ent.I.canLevel(c.curLv)) {
      await showPaywall(context, reason: '解锁 ${c.curLv} 的自由练习');
      return;
    }
    final info =
        kLevels.firstWhere((l) => l.id == c.curLv, orElse: () => kLevels.first);
    final pool =
        List<Word>.from(WordBank.I.byLevel[info.code] ?? WordBank.I.words)
          ..shuffle(Random());
    await _runSession(
      words: pool.take(Curriculum.perUnit).toList(),
      title: '自由练习 · ${c.curLv}',
      startDone: 0,
      onProgress: (_) {},
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kInk,
        duration: const Duration(seconds: 2),
      ));
  }

  /// 该级别累计学过的词数（通关算满，半程按已答数）
  int _learnedWords(Curriculum c, String lv) {
    var n = 0;
    for (final u in c.unitsOf(lv)) {
      if (u.review) continue;
      n += c.isPassed(lv, u.id) ? u.total : c.partOf(lv, u.id);
    }
    return n;
  }

  Widget _emptyState(String title, String sub) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      children: [
        _EmptyCard(emoji: '🦌', title: title, sub: sub),
      ],
    );
  }
}

// ---------------------------------------------------------------- 几何与画笔

/// S 形关卡路径的坐标。正弦曲线一个周期铺 5 关（周期取 6 会让相邻两关
/// 落在同一条纵线上，连起来是一根直柱子）。
class _PathGeo {
  _PathGeo({required this.width, required this.count});

  static const double gap = 92;
  static const double top = 78;
  static const double segGap = 52;
  static const double ampMax = 68;
  static const int perBand = 6; // 5 学习关 + 1 复习关

  final double width;
  final int count;

  double get center => width / 2;

  /// 窄屏时收幅度，保证节点不出界
  double get amp => min(ampMax, max(26.0, width / 2 - 46));

  double x(int i) => center + sin(2 * pi * i / 5) * amp;

  double y(int i) => top + i * gap + (i ~/ perBand) * segGap;

  /// 最后一个节点下面留出气泡和台地底边
  double get height => y(max(0, count - 1)) + 150;
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.geo, this.cur);

  final _PathGeo geo;
  final int cur;

  @override
  void paint(Canvas canvas, Size size) {
    final rest = Path();
    final done = Path();
    for (var i = 0; i < geo.count - 1; i++) {
      final x0 = geo.x(i), y0 = geo.y(i);
      final x1 = geo.x(i + 1), y1 = geo.y(i + 1);
      final d = (y1 - y0) * .42;
      final p = Path()
        ..moveTo(x0, y0)
        ..cubicTo(x0, y0 + d, x1, y1 - d, x1, y1);
      (i < cur ? done : rest).addPath(p, Offset.zero);
    }

    // 没走到的：圆点虚线
    final dotPaint = Paint()..color = kN2;
    for (final m in rest.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final tan = m.getTangentForOffset(d);
        if (tan != null) canvas.drawCircle(tan.position, 3.5, dotPaint);
        d += 14;
      }
    }
    // 走过的：实线
    canvas.drawPath(
      done,
      Paint()
        ..color = kPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) =>
      old.cur != cur ||
      old.geo.count != geo.count ||
      old.geo.width != geo.width;
}

/// 主题方块的位置：左右两列交替，横移全部发生在两格之间的空隙里
class _BowGeo {
  _BowGeo({required this.width, required this.count});

  static const double size = 92; // 方块边长
  static const double gap = 140; // 行距（方块之间露出 48dp 给弧线起落）
  static const double ampMax = 72; // 左右摆幅
  static const double top = 56; // 首块顶部留白（必须 ≥ size/2，否则首块 top 为负）

  final double width;
  final int count;

  /// 两侧至少留 14dp；窄屏（320）时摆幅自动收窄，方块不会贴边
  double get amp => max(0.0, min(ampMax, width / 2 - size / 2 - 14));

  double centerX(int i) => width / 2 + (i.isOdd ? amp : -amp);

  double centerY(int i) => top + i * gap + size / 2;

  double left(int i) => centerX(i) - size / 2;

  double topOf(int i) => top + i * gap;

  double get height => top + (count - 1) * gap + size + 8;
}

/// 弓形连线：每个节点对之间一段「竖直起笔 → 鼓出去 → 竖直落下」的弧。
///
/// 不能用正弦铺整条路 —— 正弦的波峰会被方块盖住，方块之间露出来的
/// 恰好是最陡、最接近直线的那一段，无论振幅加多大都看着像斜线。
/// 把横移全部塞进两格之间的空隙里，才看得出弯。
class _BowPainter extends CustomPainter {
  _BowPainter(this.geo, this.hero);

  final _BowGeo geo;

  /// 当前主题：到它为止是实线，之后是圆点
  final int hero;

  @override
  void paint(Canvas canvas, Size size) {
    const half = _BowGeo.size / 2;
    final walked = Path();
    final ahead = Path();

    // 从上一块底边中点竖直起笔、鼓到对面、再竖直落进下一块顶边中点。
    // 控制点都放在两块之间的垂直中点，所以起落两端的切线是竖直的 ——
    // 这段"先竖再弯"才是弓形看得见的部分。
    for (var i = 0; i < geo.count - 1; i++) {
      final x0 = geo.centerX(i), y0 = geo.centerY(i) + half - 1;
      final x1 = geo.centerX(i + 1), y1 = geo.centerY(i + 1) - half + 1;
      final ym = (y0 + y1) / 2;
      (i < hero ? walked : ahead)
        ..moveTo(x0, y0)
        ..cubicTo(x0, ym, x1, ym, x1, y1);
    }

    // 未走到的段用细虚线（圆点太大会把浅弧读成一串珠子、像斜线）
    final dashPaint = Paint()
      ..color = kDash
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    for (final m in ahead.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final end = (d + 2.6).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, end), dashPaint);
        d += 9.6;
      }
    }

    canvas.drawPath(
      walked,
      Paint()
        ..color = kPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BowPainter old) =>
      old.hero != hero ||
      old.geo.count != geo.count ||
      old.geo.width != geo.width;
}

/// 虚线圆角边框（Flutter 没有内置虚线 border，会员锁要用）
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final dst = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        dst.addPath(m.extractPath(d, min(d + 5, m.length)), Offset.zero);
        d += 9;
      }
    }
    canvas.drawPath(
      dst,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.radius != radius || old.color != color;
}

/// 右下角的圆形「回到学习位置」按钮
class _RoundFab extends StatelessWidget {
  const _RoundFab({required this.up, required this.onTap});

  /// 当前主题在视口上半屏 → 箭头朝上
  final bool up;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '回到学习位置',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .94),
            shape: BoxShape.circle,
            border: Border.all(color: kLine),
            boxShadow: [
              BoxShadow(
                  color: ta(kInk, 0x33),
                  blurRadius: 20,
                  offset: Offset(0, 8)),
              BoxShadow(color: kN1, offset: Offset(0, 2)),
            ],
          ),
          child: AnimatedRotation(
            turns: up ? .5 : 0,
            duration: const Duration(milliseconds: 220),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                size: 22, color: kN5),
          ),
        ),
      ),
    );
  }
}

/// 空态卡片：词库/主题为空时占位，避免首页出现空白或报错
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.emoji,
    required this.title,
    required this.sub,
  });

  final String emoji;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                const SizedBox(height: 3),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5, color: kMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
