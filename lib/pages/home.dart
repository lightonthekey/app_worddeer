import 'dart:math';

import 'package:flutter/material.dart';

import '../bank.dart';
import '../curriculum.dart';
import '../progress.dart';
import '../ui.dart';
import 'match.dart';
import 'session.dart';

/// 首页：学习信息（级别 / 今日目标 / 进度卡）+ 三种模式（关卡 / 主题 / 自由）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 0=关卡 1=主题 2=自由
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appTick,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = Curriculum.I;
    final lv = c.curLv;
    final units = c.unitsOf(lv);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _header(c, units.length),
          const SizedBox(height: 14),
          _levels(c),
          const SizedBox(height: 12),
          _goal(c),
          const SizedBox(height: 12),
          _modeBar(units.length),
          const SizedBox(height: 10),
          if (_mode == 0) ..._levelPanel(c, units),
          if (_mode == 1) ..._themePanel(c),
          if (_mode == 2) ..._freePanel(c),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 学习信息

  Widget _header(Curriculum c, int unitCount) {
    final passed = c.passedCount(c.curLv);
    final learned = _learnedWords(c, c.curLv);
    final lvName =
        kLevels.firstWhere((l) => l.id == c.curLv, orElse: () => kLevels[0]).name;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${greet()} 👋',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: .2)),
              const SizedBox(height: 3),
              Text(
                '${c.curLv} $lvName · 已通关 $passed / $unitCount 关 · 已学 $learned 词',
                style: const TextStyle(fontSize: 11.5, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: kAmber50,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 15, color: kFlame),
              const SizedBox(width: 3),
              Text('${Progress.I.streak} 天',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: kFlame)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _levels(Curriculum c) {
    final items = <Widget>[];
    for (var i = 0; i < kLevels.length; i++) {
      if (i > 0) items.add(const SizedBox(width: 6));
      final l = kLevels[i];
      final on = l.id == c.curLv;
      final dn = c.passedCount(l.id);
      final pct = dn / Curriculum.unitsPerLevel;

      items.add(Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => c.curLv = l.id);
            c.save();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(0, 7, 0, 7),
            decoration: BoxDecoration(
              color: on ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? kPrimary : kLine, width: 1.5),
              boxShadow: on
                  ? const [
                      BoxShadow(
                          color: Color(0x425A50E0),
                          blurRadius: 14,
                          offset: Offset(0, 6))
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.id,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : const Color(0xFF5B5772))),
                Text(l.name,
                    style: TextStyle(
                        fontSize: 9,
                        height: 1.4,
                        color: on ? Colors.white70 : kMuted)),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: pct <= 0 ? 0.04 : pct,
                      minHeight: 3,
                      backgroundColor: on
                          ? Colors.white.withValues(alpha: .32)
                          : const Color(0xFFEDEBF7),
                      valueColor:
                          AlwaysStoppedAnimation(on ? Colors.white : kPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return Row(children: items);
  }

  Widget _goal(Curriculum c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '今日 '),
              TextSpan(
                  text: '${c.todayWords}/${Curriculum.dailyGoal}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: kInk)),
              const TextSpan(text: ' 词'),
            ]),
            style: const TextStyle(fontSize: 11, color: kMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: c.todayRatio,
                minHeight: 6,
                backgroundColor: kPrimary50,
                valueColor: const AlwaysStoppedAnimation(kPrimary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            c.todayLeft > 0 ? '还差 ${c.todayLeft} 词' : '今日达标 🎉',
            style: const TextStyle(fontSize: 10.5, color: kMuted),
          ),
        ],
      ),
    );
  }

  Widget _modeBar(int unitCount) {
    const labels = ['关卡', '主题', '自由'];
    final hint = [
      'U1–U$unitCount',
      '${kThemes.length} 个主题',
      '随机 ${Curriculum.perUnit} 词',
    ][_mode];

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _modePill(labels[i], i),
        ],
        const Spacer(),
        Text(hint, style: const TextStyle(fontSize: 10.5, color: kMuted)),
      ],
    );
  }

  Widget _modePill(String label, int i) {
    final on = _mode == i;
    return GestureDetector(
      onTap: () => setState(() => _mode = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: on ? kPrimary50 : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? const Color(0xFFC9C5F5) : kLine),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: on ? kPrimaryDeep : const Color(0xFF6F6B85))),
      ),
    );
  }

  // ------------------------------------------------------------ 关卡模式

  List<Widget> _levelPanel(Curriculum c, List<Unit> units) {
    final lv = c.curLv;
    final idx = c.currentIndex(lv);
    final u = units[idx];
    final done = c.partOf(lv, u.id);
    final allDone = c.passedCount(lv) == units.length;

    return [
      _heroCard(
        eyebrow: allDone ? '本级别全部通关' : '继续学习 · $lv 第 ${idx + 1} 关',
        title: allDone ? '${u.id} 已完成 🎉' : u.title,
        sub: allDone
            ? '已通关 ${units.length} / ${units.length} 关 · 点这里重刷最后一关'
            : '${u.total} 词 · 已学 $done 词 · 剩 ${u.total - done} 词',
        done: done,
        total: u.total,
        onTap: () => _openLevel(idx),
      ),
      const SizedBox(height: 12),
      _tree(c, units),
      const SizedBox(height: 12),
      _duoStats(),
    ];
  }

  Widget _heroCard({
    required String eyebrow,
    required String title,
    required String sub,
    required int done,
    required int total,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kHeroA, kHeroB],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x425A50E0),
                blurRadius: 22,
                offset: Offset(0, 10)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -26,
              top: -38,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .09),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(eyebrow,
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: .7,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: .82))),
                        const SizedBox(height: 4),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: .2)),
                        const SizedBox(height: 5),
                        Text(sub,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: Colors.white.withValues(alpha: .86))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _ring(done, total),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(int done, int total) {
    final v = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withValues(alpha: .26),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          Text('$done/$total',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _tree(Curriculum c, List<Unit> units) {
    final lv = c.curLv;
    return Stack(
      children: [
        Positioned(
          left: 25,
          top: 16,
          bottom: 34,
          width: 2,
          child: CustomPaint(painter: _DashPainter()),
        ),
        Column(
          children: [
            for (var i = 0; i < units.length; i++) _unitRow(c, lv, units, i),
          ],
        ),
      ],
    );
  }

  Widget _unitRow(Curriculum c, String lv, List<Unit> units, int i) {
    final u = units[i];
    final done = c.isPassed(lv, u.id);
    final open = c.isOpen(lv, i);
    final cur = open && !done;

    final Color bg;
    final Color border;
    final Color fg;
    if (u.review) {
      bg = done ? const Color(0xFFEF9F27) : kAmber50;
      border = done ? const Color(0xFFEF9F27) : const Color(0xFFEFC97E);
      fg = done ? Colors.white : const Color(0xFFB26A0B);
    } else if (done) {
      bg = kPrimary;
      border = kPrimary;
      fg = Colors.white;
    } else {
      bg = Colors.white;
      border = cur ? kPrimary : kLine;
      fg = cur ? kPrimaryDeep : const Color(0xFFA9A5BC);
    }

    final Widget nodeChild = done
        ? const Icon(Icons.check_rounded, size: 24, color: Colors.white)
        : (open
            ? Text('${i + 1}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: fg))
            : Icon(Icons.lock_rounded, size: 17, color: fg));

    final sub = u.review
        ? '复习前 5 关 · ${u.total} 词'
        : '学习关 · ${u.total} 词 · 约 ${_mins(u.total)} 分钟';

    return Opacity(
      opacity: open ? 1 : .55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => open
            ? _openLevel(i)
            : _toast('完成 ${units[i - 1].id} 后解锁 ${u.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: border, width: 2),
                  boxShadow: cur
                      ? const [
                          BoxShadow(
                              color: Color(0x226D5AE0),
                              blurRadius: 0,
                              spreadRadius: 5)
                        ]
                      : null,
                ),
                child: Center(child: nodeChild),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(u.id,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        if (u.review) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: kFlame,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('复习',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done ? '$sub · 已完成' : sub,
                      style:
                          TextStyle(fontSize: 11, color: done ? kGreen : kMuted),
                    ),
                  ],
                ),
              ),
              if (open)
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFFA9A5BC)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _duoStats() {
    final stats = [
      ('${Progress.I.masteredCount}', '已掌握词汇'),
      ('+${Progress.I.todayNew + Progress.I.todayReview}', '今日学习词数'),
      ('${Progress.I.wrongBook().length}', '易错词待攻克'),
    ];
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stats[i].$1,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(stats[i].$2,
                      style: const TextStyle(fontSize: 10.5, color: kMuted)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ 主题模式

  List<Widget> _themePanel(Curriculum c) {
    final ws = c.themeWords(0);
    final learned = c.themeLearned(0);
    return [
      _heroCard(
        eyebrow: '继续学习 · ${c.curLv} 主题',
        title: kThemes[0].name,
        sub: '${ws.length} 词 · 已学 $learned 词 · 剩 ${ws.length - learned} 词',
        done: learned,
        total: ws.length,
        onTap: () => _openTheme(0),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              '${c.curLv} · 免费开放 1 / ${kThemes.length} 个主题',
              style: const TextStyle(fontSize: 10.5, color: kMuted),
            ),
          ),
          GestureDetector(
            onTap: () => _toast('会员可解锁全部 ${kThemes.length} 个主题'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kLine),
              ),
              child: const Text('解锁全部',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryDeep)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: kThemes.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 98,
        ),
        itemBuilder: (context, i) => _themeCard(c, i),
      ),
    ];
  }

  Widget _themeCard(Curriculum c, int i) {
    final t = kThemes[i];
    final unlocked = c.themeUnlocked(i);
    final total = c.themeWords(i).length;

    return GestureDetector(
      onTap: () => unlocked ? _openTheme(i) : _toast('「${t.name}」需要会员解锁'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: unlocked ? Colors.white : const Color(0xFFFBFAFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Opacity(
                  opacity: unlocked ? 1 : .4,
                  child: Text(t.emoji, style: const TextStyle(fontSize: 19)),
                ),
                const Spacer(),
                if (unlocked)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kGreen50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('免费',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kGreen)),
                  )
                else
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFFF7D488), Color(0xFFE0A02A)]),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        size: 12, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: unlocked ? kInk : kMuted)),
            const SizedBox(height: 3),
            Text(
              unlocked ? '$total 词 · 约 ${_mins(total)} 分钟' : '会员解锁 · $total 词',
              style: const TextStyle(fontSize: 10.5, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 自由模式

  List<Widget> _freePanel(Curriculum c) {
    return [
      Text(
        '${c.curLv} · 从整级词库随机抽 ${Curriculum.perUnit} 词，不限次数',
        style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.5),
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
                  const Text(
                    '选择、拼写、听音三种题型混排，答错的词会再次出现，直到答对为止。',
                    style: TextStyle(
                        fontSize: 11.5, color: Color(0xFF6F6B85), height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: () => _openFree(),
          style: FilledButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('开始自由练习',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------ 跳转

  Future<void> _runSession({
    required List<Word> words,
    required String title,
    required int startDone,
    required void Function(int n) onProgress,
    bool match = false,
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

    // 关卡走 5 对 5 配对棋盘，主题 / 自由仍走原来的四选一·拼写·听音
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => match
          ? MatchPage(
              words: words,
              title: title,
              subtitle: '${words.length} 对配对 · 左边英文 · 右边中文',
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
    final u = c.unitsOf(lv)[i];
    await _runSession(
      words: u.words,
      title: u.title,
      startDone: c.partOf(lv, u.id),
      onProgress: (n) => c.setPart(lv, u.id, n),
      match: true,
    );
    // 全部答完才算通关（中途退出只记半程进度）
    if (c.partOf(lv, u.id) >= u.total) c.markPassed(lv, u.id);
  }

  Future<void> _openTheme(int i) async {
    final c = Curriculum.I;
    final lv = c.curLv;
    final ws = c.themeWords(i);
    await _runSession(
      words: ws,
      title: kThemes[i].name,
      startDone: c.themeLearned(i),
      onProgress: (n) => c.markTheme(lv, i, n),
    );
  }

  Future<void> _openFree() async {
    final c = Curriculum.I;
    final info =
        kLevels.firstWhere((l) => l.id == c.curLv, orElse: () => kLevels[0]);
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
        backgroundColor: const Color(0xFF3A3550),
        duration: const Duration(seconds: 2),
      ));
  }

  String _mins(int words) => '${max(1, (words / 12).round())}';

  /// 该级别累计学过的词数（通关算满，半程按已答数）
  int _learnedWords(Curriculum c, String lv) {
    var n = 0;
    for (final u in c.unitsOf(lv)) {
      if (u.review) continue;
      n += c.isPassed(lv, u.id) ? u.total : c.partOf(lv, u.id);
    }
    return n;
  }
}

/// 关卡树左侧的虚线连接线
class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD9D5F0)
      ..strokeWidth = size.width.clamp(1, 2);
    var y = 0.0;
    while (y < size.height) {
      final h = (y + 5 > size.height) ? size.height - y : 5.0;
      canvas.drawLine(
          Offset(size.width / 2, y), Offset(size.width / 2, y + h), paint);
      y += 11;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
