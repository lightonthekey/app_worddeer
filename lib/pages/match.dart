import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bank.dart';
import '../confetti.dart';

/// 5 对 5 配对棋盘（design/game-a-desk.html 的 Flutter 版）。
///
/// 规则：
/// - 左列英文、右列中文，两列各自打乱，所以配对的两张通常不在同一行；
/// - 一对卡消失后，空出来的格子会和上下邻格「就近挪一两格」再补新词，
///   且补位后两列不会落在同一行 —— 否则同一行左右就是现成的一对，
///   用户闭着眼一直点那一行就能连对（位置固定会变成白送分）；
/// - 点左边的英文、再点右边的中文，判对就变绿 → 停 680ms 让人再看一眼词形 →
///   蹦一下 + 炸成纸屑 → 淡出 → 新卡补位；
/// - 判错只让你点的那两张变红上下颠；同一个词的另一半也要一起退场，
///   但它不做任何变色/变灰标记（一变灰就等于把正确答案指出来），只是安静淡出，
///   2 对牌一起换掉，隔两三个词后重新出现，直到配对正确；
/// - 桌面清空且没有待补的词 → 结算。

// ---------------------------------------------------------------- 视觉常量

const _bg = Color(0xFFF4F3FB);
const _line = Color(0xFFE7E5F2);
const _primary = Color(0xFF5A50E0);
const _primaryDeep = Color(0xFF463CBE);
const _primary50 = Color(0xFFEEEDFE);
const _ink = Color(0xFF211E3B);
const _ink2 = Color(0xFF6E6B8A);
const _ink3 = Color(0xFF9B98B5);
const _okColor = Color(0xFF1D9E75);
const _ok50 = Color(0xFFE5F6EF);
const _badColor = Color(0xFFE24B4A);
const _bad50 = Color(0xFFFCECEC);
const _amber50 = Color(0xFFFDF2DC);

/// 动效时间轴（毫秒，从点下第二张卡开始算）
class _T {
  static const judge = Duration(milliseconds: 220);
  static const burst = Duration(milliseconds: 680);
  static const gone = Duration(milliseconds: 700);
  static const wipe = Duration(milliseconds: 170);

  /// 配错后红卡恢复成白卡的等待时间。
  /// 配错的卡不消失、不挪位，只抖一下变红提示，抖完就恢复，
  /// 用户可以在原地重新选 —— 所以这里只需要覆盖 shake（420ms）再多给一点余量。
  static const wrongClear = Duration(milliseconds: 520);
}

const int kPairs = 5;

// ---------------------------------------------------------------- 牌面模型

enum CardFx { none, hop, shake, pop, fade, slide }

class _Card {
  Word? w;
  /// 这张卡显示英文还是中文（决定大字取 en 还是 zh、副行取音标还是释义）
  bool isEn = true;
  bool sel = false;
  bool ok = false;
  bool bad = false;
  bool blasting = false;

  /// 状态透明度（起爆后 0.12、隐去后 0），配合 [opacityDur] 做慢速化掉
  double opacity = 1;
  Duration opacityDur = const Duration(milliseconds: 160);

  CardFx fx = CardFx.none;
  int fxNonce = 0;
  Duration fxDelay = Duration.zero;

  /// [CardFx.slide] 用：这一格的内容是从哪一格滑过来的（行号）
  int slideFrom = 0;

  /// 播一次动画：fxNonce 变了，卡片视图才会重新跑一遍动画
  void play(CardFx fx) {
    this.fx = fx;
    fxNonce++;
  }

  /// 把另一张卡的「内容」整体搬到这一格（用来挪位置）。
  ///
  /// 只搬看得见的东西（词、方向、三种状态、透明度、起点），
  /// 不搬 fx/fxNonce —— 动画由调用方另设，否则会继承对方已经播完的那一版。
  void absorb(_Card o) {
    w = o.w;
    isEn = o.isEn;
    sel = o.sel;
    ok = o.ok;
    bad = o.bad;
    blasting = o.blasting;
    opacity = o.opacity;
    opacityDur = o.opacityDur;
    slideFrom = o.slideFrom;
  }

  void reset() {
    w = null;
    sel = ok = bad = blasting = false;
    opacity = 1;
    opacityDur = const Duration(milliseconds: 160);
    fx = CardFx.none;
    fxDelay = Duration.zero;
    slideFrom = 0;
  }
}

// ---------------------------------------------------------------- 页面

class MatchPage extends StatefulWidget {
  const MatchPage({
    super.key,
    required this.words,
    this.title = '学习关',
    this.subtitle = '5 对 5 配对',
    this.onProgress,
    this.nextTitle,
    this.autoDemo = 0,
  });

  final List<Word> words;
  final String title;
  final String subtitle;

  /// 每配对成功一对回调已掌握词数（用于半程进度与今日词数）
  final ValueChanged<int>? onProgress;

  /// 结算页“下一关”的文案，为空则不显示该按钮
  final String? nextTitle;

  /// 演示/截图用：启动后自动点一对（1=正确、2=错误），走完整条动效时间轴
  final int autoDemo;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  final math.Random _rnd = math.Random();
  final ConfettiField _field = ConfettiField();
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _enKeys = List.generate(kPairs, (_) => GlobalKey());
  final List<GlobalKey> _zhKeys = List.generate(kPairs, (_) => GlobalKey());

  final List<_Card> _en = List.generate(kPairs, (_) => _Card());
  final List<_Card> _zh = List.generate(kPairs, (_) => _Card());

  final List<Word> _queue = [];

  final Set<String> _wrong = {};
  int _done = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _firstTry = 0;
  int? _selEn;
  int? _selZh;
  bool _lock = false;
  bool _over = false;
  bool _finished = false;

  late DateTime _t0;
  Duration _elapsed = Duration.zero;
  Timer? _clock;

  String _ftA = '先点左边英文，再点右边对应的中文';
  String _ftEm = '';
  String _ftB = '';
  _FtKind _ftKind = _FtKind.hint;

  int get _total => widget.words.length;

  @override
  void initState() {
    super.initState();
    _start();
    if (widget.autoDemo > 0) {
      // 3 = 连打三对（每对间隔 6s），用来复现「纸屑会不会越积越多」
      _autoLeft = widget.autoDemo == 3 ? 3 : 1;
      Future<void>.delayed(const Duration(milliseconds: 400), _autoStep);
    }
  }

  int _autoLeft = 0;

  void _autoStep() {
    if (!mounted || _over) return;
    _autoTap();
    _autoLeft--;
    if (_autoLeft > 0) {
      Future<void>.delayed(const Duration(seconds: 6), _autoStep);
    }
  }

  void _autoTap() {
    if (!mounted || _over) return;
    for (var i = 0; i < kPairs; i++) {
      final w = _en[i].w;
      if (w == null) continue;
      final zi = widget.autoDemo == 2
          ? _zh.indexWhere((c) => c.w != null && c.w!.en != w.en)
          : _zh.indexWhere((c) => c.w?.en == w.en);
      if (zi < 0) continue;
      _tap(true, i);
      _tap(false, zi);
      return;
    }
  }

  @override
  void dispose() {
    _over = true;
    _clock?.cancel();
    _field.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 开局

  void _start() {
    _queue
      ..clear()
      ..addAll(widget.words)
      ..shuffle(_rnd);
    _wrong.clear();
    for (final c in _en) {
      c.reset();
    }
    for (final c in _zh) {
      c.reset();
    }
    _done = _combo = _maxCombo = _firstTry = 0;
    _selEn = _selZh = null;
    _lock = false;
    _over = false;
    _finished = false;
    _elapsed = Duration.zero;
    _t0 = DateTime.now();
    _field.clear();
    _setHint('先点左边英文，再点右边对应的中文');

    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _over || _finished) return;
      setState(() => _elapsed = DateTime.now().difference(_t0));
    });

    // 首屏：从队列里取 5 个词，两列各自打乱
    final first = <Word>[];
    for (var i = 0; i < kPairs; i++) {
      if (_queue.isEmpty) break;
      first.add(_queue.removeAt(0));
    }
    final forEn = List<Word>.from(first)..shuffle(_rnd);
    final forZh = List<Word>.from(first)..shuffle(_rnd);

    // 两列各自打乱，偶尔会正好让某一行左右是同一个词。那一行就是
    // 「闭眼点都对」的白送格子，和补位落到同一行是同一个毛病 ——
    // 把中文列里这类格子跟别的行换开（换的时候保证两边都还不同词）。
    for (var i = 0; i < forZh.length; i++) {
      if (forEn[i].en != forZh[i].en) continue;
      for (var j = 0; j < forZh.length; j++) {
        if (j == i) continue;
        // 换完之后第 i 行、第 j 行都不能再成对
        if (forZh[j].en == forEn[i].en) continue;
        if (forEn[j].en == forZh[i].en) continue;
        final t = forZh[i];
        forZh[i] = forZh[j];
        forZh[j] = t;
        break;
      }
    }

    for (var i = 0; i < forEn.length; i++) {
      _paint(_en[i], forEn[i], isEn: true);
    }
    for (var i = 0; i < forZh.length; i++) {
      _paint(_zh[i], forZh[i], isEn: false);
    }
    setState(() {});
  }

  void _paint(_Card c, Word w, {required bool isEn}) {
    c.reset();
    c.w = w;
    c.isEn = isEn;
    c.fx = CardFx.pop;
    c.fxNonce++;
  }

  void _wipe(_Card c) {
    c.reset();
    c.w = null;
    // 清成虚线空格，之后由 refill 补新词
  }

  /// 一对卡消失后，把两列的空位各挪一格（最多两格），再补新词。
  ///
  /// 为什么不留原位：留原位等于「消失的那格就是补位的那格」，位置完全可预测，
  /// 而且两列都补在同一行时，同一行左右就是现成的一对 ——
  /// 用户闭着眼一直点那一行就能连对，白送分。
  ///
  /// 为什么不是重排整列：那太乱。这里一次只让一张卡换个格子（每列一张），
  /// 视觉上就是「轻轻动了一下」，但位置不再能靠记忆锚定。
  void _nudgeHoles(int enHole, int zhHole) {
    // 能搬过来的格子：上下各两格以内、且还有词。
    // 往外看两格是为了绕开「唯一邻居恰好跟本行另一半同词」的死锁 ——
    // 那种时候一格内怎么挪都会凑成一对，挪两格就只搬一张卡，照样能错开。
    List<int> adj(int hole, List<_Card> list) => [
          for (var d = 1; d <= 2; d++) ...[
            if (hole - d >= 0 && list[hole - d].w != null) hole - d,
            if (hole + d < kPairs && list[hole + d].w != null) hole + d,
          ],
        ];

    final enAdj = adj(enHole, _en);
    final zhAdj = adj(zhHole, _zh);
    // 候选里带上「不挪」本身：某一列只有一个邻居、挪过去又正好凑成一对时，
    // 宁可这一列不动，也不能造出一个白送格子。
    final enAll = [enHole, ...enAdj];
    final zhAll = [zhHole, ...zhAdj];

    // 只要两列新空位不重合，就不会有「同一行白送」的格子
    final safe = <List<int>>[
      for (final a in enAll)
        for (final b in zhAll)
          if (a != b && !_wouldPair(enHole, a, zhHole, b)) [a, b],
    ];
    // 怎么挪都会凑成一对时，退一步只要求两列空位错开：
    // 至少别让新词的两半补在同一行（那也是白送）。
    final combos = safe.isNotEmpty
        ? safe
        : <List<int>>[
            for (final a in enAll)
              for (final b in zhAll)
                if (a != b) [a, b],
          ];
    if (combos.isEmpty) return;

    // 优先两列都挪一步，其次至少挪一列；只有实在没法时才原地不动
    var pool = combos.where((c) => c[0] != enHole && c[1] != zhHole).toList();
    if (pool.isEmpty) {
      pool = combos.where((c) => c[0] != enHole || c[1] != zhHole).toList();
    }
    if (pool.isEmpty) pool = combos;
    final pick = pool[_rnd.nextInt(pool.length)];

    _moveHole(_en, enHole, pick[0]);
    _moveHole(_zh, zhHole, pick[1]);
  }

  /// 按「en 空位挪到 [a]、zh 空位挪到 [b]」算一遍，会不会有哪一行左右凑成一对。
  ///
  /// 必须有这一步：那张卡是从隔壁行搬过来的，它可能正好和落脚那一行的
  /// 另一半是同一个词 —— 那就又造出一个白送格子。
  bool _wouldPair(int enHole, int a, int zhHole, int b) {
    Word? enAt(int i) => i == enHole ? _en[a].w : (i == a ? null : _en[i].w);
    Word? zhAt(int i) => i == zhHole ? _zh[b].w : (i == b ? null : _zh[i].w);
    for (var i = 0; i < kPairs; i++) {
      final e = enAt(i), z = zhAt(i);
      if (e != null && z != null && e.en == z.en) return true;
    }
    return false;
  }

  void _moveHole(List<_Card> list, int hole, int nb) {
    if (nb == hole) return;
    final dst = list[hole];
    dst.absorb(list[nb]);
    list[nb].reset(); // 邻格腾空，等下由 _refill 填新词
    dst.slideFrom = nb;
    dst.play(CardFx.slide);
  }

  Word? _nextWord() => _queue.isEmpty ? null : _queue.removeAt(0);

  void _refill() {
    final enEmpty = <int>[
      for (var i = 0; i < kPairs; i++)
        if (_en[i].w == null) i,
    ];
    final zhEmpty = <int>[
      for (var i = 0; i < kPairs; i++)
        if (_zh[i].w == null) i,
    ];
    if (enEmpty.isEmpty || zhEmpty.isEmpty) return;

    // 同一个词的两半绝不能补在同一行：那一行就是现成的一对，
    // 用户闭着眼一直点这一行就能连对。
    //
    // 注意不能「填一个算一个」地挑空位 —— 挑到最后可能只剩同一行的两个空位，
    // 那个词就只能同行。所以整体找一个错排：先打乱中文列的空位，
    // 只要有一格撞行，就把整串循环移位一格再试（n>1 时必有解）。
    var zs = [...zhEmpty]..shuffle(_rnd);
    for (var shift = 0; shift < zs.length; shift++) {
      final rot = [...zs.sublist(shift), ...zs.sublist(0, shift)];
      var ok = true;
      for (var i = 0; i < enEmpty.length && i < rot.length; i++) {
        if (enEmpty[i] == rot[i]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        zs = rot;
        break;
      }
    }

    final n = math.min(enEmpty.length, zs.length);
    for (var i = 0; i < n; i++) {
      final w = _nextWord();
      if (w == null) break;
      _paint(_en[enEmpty[i]], w, isEn: true);
      _paint(_zh[zs[i]], w, isEn: false);
    }
  }

  // ------------------------------------------------------------ 交互

  void _tap(bool isEn, int i) {
    if (_lock || _over || _finished) return;
    final c = isEn ? _en[i] : _zh[i];
    if (c.w == null) return;
    final sel = isEn ? _selEn : _selZh;

    if (sel == i) {
      setState(() => c.sel = false);
      if (isEn) {
        _selEn = null;
      } else {
        _selZh = null;
      }
      return;
    }
    setState(() {
      if (sel != null) (isEn ? _en[sel] : _zh[sel]).sel = false;
      c.sel = true;
      if (isEn) {
        _selEn = i;
      } else {
        _selZh = i;
      }
    });
    HapticFeedback.selectionClick();

    final picked = c.w!;
    if (isEn) {
      _setHint('已选 ${picked.en}，请点右侧对应中文', em: picked.en);
    } else {
      _setHint('已选中文，请点左侧对应的英文');
    }

    if (_selEn != null && _selZh != null) _judge();
  }

  Future<void> _judge() async {
    _lock = true;
    final ei = _selEn!, zi = _selZh!;
    final w1 = _en[ei].w, w2 = _zh[zi].w;
    final ok = w1 != null && w2 != null && w1.en == w2.en;

    await Future<void>.delayed(_T.judge);
    if (!mounted || _over) return;

    if (ok) {
      await _onMatch(ei, zi, w1);
    } else {
      await _onMiss(ei, zi, w1, w2);
    }
  }

  Future<void> _onMatch(int ei, int zi, Word w) async {
    _done++;
    _combo++;
    _maxCombo = math.max(_maxCombo, _combo);
    if (!_wrong.contains(w.en)) _firstTry++;
    widget.onProgress?.call(_done);
    HapticFeedback.mediumImpact();

    setState(() {
      _en[ei]
        ..sel = false
        ..ok = true
        ..play(CardFx.hop);
      _zh[zi]
        ..sel = false
        ..ok = true
        ..play(CardFx.hop);
      _setHint(
        _combo >= 2 ? '连对 $_combo 对 · ${w.en} = ${w.zh}' : '✓ ${w.en} = ${w.zh}',
        kind: _FtKind.ok,
      );
    });

    // 绿卡原地停一会儿：答对不代表真记住了，留时间再看一眼词形
    await Future<void>.delayed(_T.burst);
    if (!mounted || _over) return;

    final a = _center(_enKeys[ei]);
    final b = _center(_zhKeys[zi]);
    setState(() {
      for (final c in [_en[ei], _zh[zi]]) {
        c
          ..blasting = true
          ..opacity = .12
          ..opacityDur = const Duration(milliseconds: 800);
      }
    });
    if (a != null && b != null) _field.burstBetween(a, b);
    HapticFeedback.lightImpact();

    await Future<void>.delayed(_T.gone);
    if (!mounted || _over) return;
    setState(() {
      for (final c in [_en[ei], _zh[zi]]) {
        c
          ..opacity = 0
          ..opacityDur = const Duration(milliseconds: 300);
      }
    });

    await Future<void>.delayed(_T.wipe);
    if (!mounted || _over) return;
    setState(() {
      _wipe(_en[ei]);
      _wipe(_zh[zi]);
      // 空位各挪一格再补词：位置不再固定，且两列的补位行必然不同，
      // 不会有「同一行左右现成一对」的白送分行。
      _nudgeHoles(ei, zi);
      _refill();
      _selEn = _selZh = null;
      _lock = false;
    });
    _checkEnd();
  }

  Future<void> _onMiss(int ei, int zi, Word? w1, Word? w2) async {
    _combo = 0;
    for (final w in [w1, w2]) {
      if (w == null) continue;
      _wrong.add(w.en);
    }
    HapticFeedback.heavyImpact();

    // 配错：只把被点的那两张变红颠一下，然后原样恢复。
    //
    // 卡片不退场、不换词、不挪位 —— 用户点错了不该被“惩罚式换牌”：
    // 牌一换，桌面布局跳一下，注意力就被打断了；而且换牌会把这两个词
    // 重新洗到别处，用户反而不用记住「我刚才错在哪」。
    // 现在红卡抖完就恢复白卡，人留在原地继续想，直到真的配对成功。
    //
    // 另一条底线照旧：同一个词的另一半什么都不做（不变色、不变虚线、
    // 不淡出、不抖），否则等于直接把「这张才是正确搭档」指给用户。
    setState(() {
      for (final c in [_en[ei], _zh[zi]]) {
        c
          ..sel = false
          ..bad = true
          ..play(CardFx.shake);
      }
      _setHint('配错了 · 再想想这两个词各自的意思', kind: _FtKind.bad);
    });

    await Future<void>.delayed(_T.wrongClear);
    if (!mounted || _over) return;

    setState(() {
      // 红标撤掉，两张卡回到普通白卡，可以重新点
      for (final c in [_en[ei], _zh[zi]]) {
        c.bad = false;
      }
      _selEn = _selZh = null;
      _lock = false;
    });
  }

  void _checkEnd() {
    final empty = _en.every((c) => c.w == null) && _zh.every((c) => c.w == null);
    if (!empty || _queue.isNotEmpty) return;
    Future<void>.delayed(const Duration(milliseconds: 460), () {
      if (mounted && !_over) _finish();
    });
  }

  void _finish() {
    if (_over) return;
    _over = true;
    _clock?.cancel();
    setState(() => _finished = true);
    HapticFeedback.vibrate();
  }

  // ------------------------------------------------------------ 小工具

  void _setHint(String text, {String? em, _FtKind kind = _FtKind.hint}) {
    if (em == null) {
      _ftA = text;
      _ftEm = '';
      _ftB = '';
    } else {
      final i = text.indexOf(em);
      _ftA = text.substring(0, i);
      _ftEm = em;
      _ftB = text.substring(i + em.length);
    }
    _ftKind = kind;
  }

  Offset? _center(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject() as RenderBox?;
    final root = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (ro == null || root == null || !ro.hasSize) return null;
    return root.globalToLocal(ro.localToGlobal(ro.size.center(Offset.zero)));
  }

  String _clockText() {
    final s = _elapsed.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _durationText() {
    final s = _elapsed.inSeconds;
    return s >= 60 ? '${s ~/ 60} 分 ${s % 60} 秒' : '$s 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          key: _stackKey,
          children: [
            Column(
              children: [
                _top(),
                _colHead(),
                Expanded(child: _desk()),
                _foot(),
              ],
            ),
            // 纸屑层盖在牌桌上，不挡点击
            Positioned.fill(child: ConfettiOverlay(field: _field)),
            if (_finished) _sheet(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 顶栏

  Widget _top() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _line, width: 1),
                  ),
                  child: const Icon(Icons.close_rounded, size: 17, color: _ink2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: _ink3),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: _ink2),
                    const SizedBox(width: 5),
                    Text(
                      _clockText(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _total == 0 ? 0 : _done / _total),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => LinearProgressIndicator(
                      value: v,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE3E0F4),
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFF5A50E0)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$_done',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                      ),
                    ),
                    TextSpan(
                      text: ' / $_total',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: _combo >= 2 ? 1 : .8,
                duration: const Duration(milliseconds: 220),
                child: AnimatedOpacity(
                  opacity: _combo >= 2 ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _amber50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '🔥 $_combo',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB26A0B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colHead() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text('ENGLISH',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: _ink3)),
          ),
          Expanded(
            child: Text('中文',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: _ink3)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 牌桌

  Widget _desk() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Stack(
        // 答对的卡会往上浮 5px、影子再往下探十几 px，Stack 默认 hardEdge 会把
        // 首行/末行这两头切掉，所以这里必须放开裁剪
        clipBehavior: Clip.none,
        children: [
          // 中缝虚线：暗示“左边英文 · 右边中文”
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SeamPainter()),
            ),
          ),
          Column(
            key: const ValueKey('desk'),
            children: [
              for (var i = 0; i < kPairs; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _cardView(_en[i], i, true)),
                        const SizedBox(width: 10),
                        Expanded(child: _cardView(_zh[i], i, false)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardView(_Card c, int i, bool isEn) {
    return _CardView(
      key: ValueKey('${isEn ? 'en' : 'zh'}$i'),
      card: c,
      boxKey: isEn ? _enKeys[i] : _zhKeys[i],
      slot: i,
      onTap: (c.w == null || c.bad || c.blasting)
          ? null
          : () => _tap(isEn, i),
    );
  }

  // ------------------------------------------------------------ 底部提示

  Widget _foot() {
    final color = switch (_ftKind) {
      _FtKind.ok => _okColor,
      _FtKind.bad => _badColor,
      _FtKind.hint => _ink3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 26),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: color,
              fontWeight: _ftKind == _FtKind.hint ? FontWeight.w400 : FontWeight.w700,
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: _ftA),
                  if (_ftEm.isNotEmpty)
                    TextSpan(
                      text: _ftEm,
                      style: TextStyle(
                        color: _ftKind == _FtKind.hint ? _primary : color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(text: _ftB),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 结算

  Widget _sheet() {
    final acc = _total == 0 ? 0 : (_firstTry / _total * 100).round();
    final wr = _wrong.toList();
    return Positioned.fill(
      child: Container(
        color: _bg,
        padding: const EdgeInsets.fromLTRB(26, 90, 26, 32),
        child: Column(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('本关完成',
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 7),
            Text('用时 ${_durationText()} · ${widget.title}',
                style: const TextStyle(fontSize: 12.5, color: _ink2)),
            const SizedBox(height: 26),
            Row(
              children: [
                _stat('$_total', '配对正确'),
                const SizedBox(width: 9),
                _stat('$acc%', '一次选对率'),
                const SizedBox(width: 9),
                _stat('$_maxCombo', '最高连击'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _line, width: 1),
              ),
              child: Text(
                wr.isEmpty
                    ? '🦌 一次全对，直接满星通关'
                    : '🦌 ${wr.length} 个词配错过（${wr.take(6).join('、')}'
                        '${wr.length > 6 ? '…' : ''}），本关内已反复重现直到配对正确',
                style: const TextStyle(fontSize: 11.5, height: 1.6, color: _ink2),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: Text(widget.nextTitle ?? '完成',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
            TextButton(
              onPressed: _start,
              child: const Text('再来一局',
                  style: TextStyle(fontSize: 12.5, color: _ink3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line, width: 1),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(fontSize: 10, color: _ink3)),
          ],
        ),
      ),
    );
  }
}

enum _FtKind { hint, ok, bad }

// ---------------------------------------------------------------- 单张卡

class _CardView extends StatefulWidget {
  const _CardView({
    super.key,
    required this.card,
    required this.boxKey,
    this.slot = 0,
    this.onTap,
  });

  final _Card card;
  final GlobalKey boxKey;

  /// 本卡在第几行（挪位后要朝“自己原来那格”的方向轻轻浮一下）
  final int slot;
  final VoidCallback? onTap;

  @override
  State<_CardView> createState() => _CardViewState();
}

class _CardViewState extends State<_CardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  Timer? _delay;

  /// 已经播过的那一版动画序号（自己存，不能拿 old.card 比 —— 见 didUpdateWidget）
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _seen = widget.card.fxNonce;
    _play();
  }

  @override
  void didUpdateWidget(_CardView old) {
    super.didUpdateWidget(old);
    // 坑：`old.card` 和 `widget.card` 是**同一个可变的 _Card 实例**，
    // 所以 `old.card.fxNonce != widget.card.fxNonce` 永远是 false ——
    // 之前写成那样，等于动画只在 initState 播过那一次（首屏 pop），
    // 之后的 hop / shake / 补位 fade 全都不播，`_t` 一直是 1，
    // 卡片直接「啪」地跳到终点姿态（用户看到的就是“跳了一下就定格/凹进去”）。
    // 正确做法：自己记住上一版序号。
    if (widget.card.fxNonce != _seen) {
      _seen = widget.card.fxNonce;
      _play();
    }
  }

  void _play() {
    _delay?.cancel();
    final fx = widget.card.fx;
    _c.value = 0;
    if (fx == CardFx.none) {
      _c.value = 1;
      return;
    }
    _c.duration = switch (fx) {
      CardFx.hop => const Duration(milliseconds: 280),
      CardFx.shake => const Duration(milliseconds: 420),
      CardFx.pop => const Duration(milliseconds: 340),
      CardFx.fade => const Duration(milliseconds: 300),
      CardFx.slide => const Duration(milliseconds: 300),
      CardFx.none => const Duration(milliseconds: 1),
    };
    final delay = widget.card.fxDelay;
    if (delay == Duration.zero) {
      _c.forward(from: 0);
    } else {
      _delay = Timer(delay, () {
        if (mounted) _c.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  double get _t => Curves.linear.transform(_c.value.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return AnimatedOpacity(
      opacity: card.opacity,
      duration: card.opacityDur,
      curve: Curves.easeOut,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          var dy = 0.0, scale = 1.0;
          var enter = 1.0;
          final k = _t;
          if (card.fx == CardFx.hop) {
            // 答对的卡要「轻轻弹一下 → 再微弹 → 停在半空中」，
            // 收尾必须停在悬浮位（dy=-3.5），不能落回 0：
            // 以前收尾会压到 +3px、scale 掉到 .976，看着就是整张卡「凹进桌面里」。
            // 现在是刻意的小幅度：抬 10px、放大 3.5%，整段 280ms。
            // 早先抬 18px / 400ms 太跳了，卡片像在蹦床上弹，抢走了看词的注意力。
            if (k < .32) {
              final u = k / .32;
              dy = -10 * u; //   0 → -10（起跳）
              scale = 1 + .035 * u; //   1 → 1.035
            } else if (k < .58) {
              final u = (k - .32) / .26;
              dy = -10 + 9 * u; // -10 → -1（下落，几乎贴回桌面）
              scale = 1.035 - .027 * u; // 1.035 → 1.008
            } else if (k < .80) {
              final u = (k - .58) / .22;
              dy = -1 - 3.5 * u; //  -1 → -4.5（第二次弹起）
              scale = 1.008 + .012 * u; //       → 1.020
            } else {
              final u = (k - .80) / .20;
              dy = -4.5 + 1 * u; // -4.5 → -3.5（停在悬浮位，不再下落）
              scale = 1.020 - .002 * u; //       → 1.018
            }
          } else if (card.fx == CardFx.shake) {
            // 上下颠 4 下，不再左右晃
            const ys = [0.0, -8.0, 7.0, -5.0, 4.0, -2.0, 0.0];
            final p = k * (ys.length - 1);
            final i = p.floor().clamp(0, ys.length - 2);
            dy = ys[i] + (ys[i + 1] - ys[i]) * (p - i);
          } else if (card.fx == CardFx.pop) {
            enter = k;
            scale = .86 + .14 * Curves.easeOutBack.transform(k * .8).clamp(0.0, 1.2);
            dy = 6 * (1 - k);
          } else if (card.fx == CardFx.fade) {
            enter = k;
          } else if (card.fx == CardFx.slide) {
            // 邻格那张卡被挪到这一格：朝原来那格的方向轻轻浮一下再落定。
            // 位移刻意只有 14px —— 早先按「整整一格」滑，滑动的卡会压住
            // 相邻行的卡，用户点下去就点到了别人的格子上。
            // 也不做淡入：这张卡本来就是桌上的旧卡，闪一下反而显得刻意。
            final dir = (card.slideFrom - widget.slot).sign.toDouble();
            final e = Curves.easeOutCubic.transform(k);
            dy = dir * 14 * (1 - e);
            scale = 1 + .02 * math.sin(k * math.pi);
          }
          // 选中的卡抬起来 3px
          final lift = card.sel ? -3.0 : 0.0;
          return Transform.translate(
            offset: Offset(0, dy + lift),
            child: Transform.scale(
              scale: scale,
              child: Opacity(opacity: enter, child: child),
            ),
          );
        },
        child: _cardBox(card),
      ),
    );
  }

  Widget _cardBox(_Card c) {
    final word = c.w;
    final blank = word == null;

    Color bg = Colors.white;
    Color border = _line;
    Color textColor = _ink;
    Color subColor = _ink3;
    bool dashed = false;
    List<BoxShadow> shadow = const [
      BoxShadow(color: Color(0xFFE4E0F4), offset: Offset(0, 2.5)),
      BoxShadow(
          color: Color(0x0F463CBE),
          offset: Offset(0, 8),
          blurRadius: 16),
    ];
    double borderWidth = 1.5;

    if (blank) {
      bg = Colors.transparent;
      border = const Color(0xFFDEDAF0);
      dashed = true;
      shadow = const [];
    } else if (c.ok) {
      bg = _ok50;
      border = _okColor;
      textColor = const Color(0xFF0F6E56);
      subColor = const Color(0xFF3E8F76);
      // 答对的卡是「浮」着的：硬影拉远一点假装离开桌面，
      // 再加一层又远又虚的绿光，悬浮感才立得住。
      // 抬升从 18px 收到 10px 后影子也跟着收一点，否则显得卡片飘得太高。
      shadow = const [
        BoxShadow(color: Color(0xFFB7E2D2), offset: Offset(0, 3.5)),
        BoxShadow(
            color: Color(0x2E1D9E75),
            blurRadius: 20,
            offset: Offset(0, 11),
            spreadRadius: 1),
      ];
    } else if (c.bad) {
      bg = _bad50;
      border = _badColor;
      textColor = const Color(0xFFA32D2D);
      subColor = const Color(0xFFA32D2D);
    } else if (c.sel) {
      bg = _primary50;
      border = _primary;
      textColor = _primaryDeep;
      subColor = _primaryDeep;
      shadow = const [
        BoxShadow(color: Color(0xFFCFC8FA), offset: Offset(0, 4.5)),
        BoxShadow(color: Color(0x385A50E0), blurRadius: 22, offset: Offset(0, 14)),
      ];
    }

    final isEn = c.isEn && !blank;
    // 英文卡副行是音标，中文卡副行是释义缩略
    final sub = word == null ? '' : (isEn ? word.phUs : _brief(word));

    return Container(
      key: widget.boxKey,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: dashed ? null : Border.all(color: border, width: borderWidth),
        boxShadow: shadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(15),
          splashColor: _primary.withValues(alpha: .06),
          highlightColor: _primary.withValues(alpha: .03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (word != null)
                    Text(
                      isEn ? word.en : word.zh,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .1,
                        height: 1.15,
                        color: textColor,
                      ),
                    ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isEn ? 11.5 : 10.5,
                        height: 1.2,
                        color: subColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      if (dashed)
            IgnorePointer(
              child: CustomPaint(
                painter: _DashBorder(color: border, radius: 15, width: borderWidth),
              ),
            ),
        ],
      ),
    );
  }
}

/// 中缝虚线
class _SeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFCFC9EE)
      ..strokeWidth = 1;
    final x = size.width / 2 - .5;
    for (var y = 6.0; y < size.height - 6; y += 11) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 5, size.height - 6)), p);
    }
  }

  @override
  bool shouldRepaint(_SeamPainter old) => false;
}

// ---------------------------------------------------------------- 工具

/// 虚线边框（作废卡 / 空格）：Flutter 没有原生 dashed border，沿圆角路径切段画
class _DashBorder extends CustomPainter {
  _DashBorder({
    required this.color,
    required this.radius,
    this.width = 1.5,
  });

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          width / 2, width / 2, size.width - width, size.height - width),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 5, metric.length)),
          paint,
        );
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashBorder old) =>
      old.color != color || old.radius != radius || old.width != width;
}

/// 释义缩略：丢掉与主释义重复的义项，最多保留 2 条（照搬 game-a-desk.html 的 brief）
String _brief(Word w) {
  final d = w.detail.trim();
  if (d.isEmpty) return '';

  final segs = <(String?, String)>[];
  String? pos;
  final chunks = d
      .replaceAllMapped(
        RegExp(r'\s+([a-zA-Z]{1,8}\.)'),
        (m) => '|${m.group(1)}',
      )
      .split('|');
  for (final chunk in chunks) {
    for (var piece in chunk.split(RegExp(r',\s*|，\s*'))) {
      piece = piece.trim();
      if (piece.isEmpty) continue;
      final m = RegExp(r'^([a-zA-Z]{1,8}\.)\s*(.*)$').firstMatch(piece);
      if (m != null) pos = m.group(1)!.toLowerCase();
      segs.add((pos, m != null ? m.group(2)! : piece));
    }
  }

  final zh = w.zh.trim();
  final keep = segs.where((s) {
    if (s.$2.isEmpty) return false;
    final core = s.$2.replaceAll(RegExp(r'[的地得]$'), '');
    return !(zh.isNotEmpty && (zh.contains(s.$2) || core == zh));
  }).toList();
  if (keep.isEmpty) return '';

  final picks = keep.take(2).toList();
  final samePos = picks.every((p) => p.$1 == picks.first.$1);
  var out = samePos
      ? '${picks.first.$1 ?? ''}${picks.map((p) => p.$2).join('，')}'
      : picks.map((p) => '${p.$1 ?? ''}${p.$2}').join('，');
  if (keep.length > 2) out += '…';
  return out;
}
