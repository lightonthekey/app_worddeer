import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../bank.dart';
import '../ui.dart';
import '../confetti.dart';

/// 4 对 4 配对棋盘 —— design/game-v2.html 的 Flutter 版。
///
/// 规则（和原型逐条对齐）：
/// - 左列英文、右列中文，共 4 行；
/// - 点英文再点中文，判对就变绿 → 绿卡一帧后收走 → 两张「飞到」顶部「巩固台」→
///   棋盘原地补新词；
/// - **英文列位置固定**（哪格消失补哪格），**中文列每次都整列重排**，
///   且保证没有任何一行左右是同一个词 —— 位置记不住，就没法靠蒙连对；
/// - 巩固台是一关到底的横滑轨道：配对成功的词全按顺序留着，一屏露 3 格，
///   新词落位时自动跟到最右，用户往回翻过就不抢位置；
/// - 词池空了以后的最后几对**原地置灰**（不飞、不补位），收尾是一整盘学完的词；
/// - 判错只让点的两张红一下再恢复，不换位、也不把正确答案标出来；
/// - 配对数量够了 → 结算。
///
/// 时间轴见 [_T]。核心约定：**只有 judge 的 140ms 会锁住操作**，
/// 收卡、飞行、补位、巩固台落位全是背景动画，手快可以一路配下去。
///
/// 巩固台不用系统滚动条：`overflow` 那套在桌面端会自动画一条横向滚动条，
/// 手机应用里很少见这种控件，所以这里用 `_NoBarScrollBehavior` 把它整个关掉。

// ---------------------------------------------------------------- 视觉常量

const int kPairs = 4; // 棋盘行数（原型从 5 行收到 4 行，给巩固台腾位置）

Color get _bg => kN1;
Color get _line => kN1;
Color get _primary => kPrimary;
Color get _primaryDeep => kPrimaryDeep;
Color get _primary50 => kPrimary50;
Color get _ink => kInk;
Color get _ink2 => kN4;
Color get _ink3 => kN4;
const _okColor = Color(0xFF58CC02);
// 深色下这三个必须换：浅绿底 + 深绿字放到暗色主题里就是一块白斑
Color get _ok50 => pal.isDark ? const Color(0xFF12291A) : const Color(0xFFEAF9EF);
Color get _okInk => pal.isDark ? const Color(0xFF7BE8A8) : const Color(0xFF237A00);
Color get _okInk2 => pal.isDark ? const Color(0xFF8FD3BE) : const Color(0xFF3E8F76);
Color get _badColor => kRed;
Color get _bad50 => pal.isDark ? const Color(0xFF2C1516) : const Color(0xFFFCECEC);
/// 错词卡上的字：暗色底要用亮红，否则 #A32D2D 贴在 #2C1516 上几乎看不见
Color get _badInk => pal.isDark ? const Color(0xFFFF8A80) : const Color(0xFFA32D2D);
Color get _shelfBg => kN1;

class _T {
  /// 判定停顿：两张都选中到给结果之间的留白，太短看不出点了哪两张。
  static const judge = Duration(milliseconds: 140);

  /// 绿卡留在原地的时长（从判定算起），之后开始起飞。
  /// 40ms ≈ 绿一帧就收走 —— 原来 480ms 的停顿玩起来很拖。
  static const flyStart = Duration(milliseconds: 40);

  /// 飞向巩固台的时长。
  static const flyDur = Duration(milliseconds: 340);

  /// 巩固台跟到最右的时长。
  static const shelfFollow = Duration(milliseconds: 320);

  /// 巩固台新词的绿框高亮停留。
  static const fresh = Duration(milliseconds: 2000);

  /// 配错后红卡恢复的等待。
  static const wrong = Duration(milliseconds: 520);

  static const shake = Duration(milliseconds: 420);
}

/// 结算页措辞场景：关卡说「本关」，主题说「本主题」。玩法完全一致。
enum MatchScene { level, theme }

class MatchPage extends StatefulWidget {
  const MatchPage({
    super.key,
    required this.words,
    this.title = '学习关',
    this.subtitle = '',
    this.onProgress,
    this.nextTitle,
    this.autoDemo = 0,
    this.scene = MatchScene.level,
  });

  final List<Word> words;
  final String title;
  final String subtitle;
  final MatchScene scene;

  /// 每配对成功一对回调已掌握词数（用于半程进度与今日词数）
  final ValueChanged<int>? onProgress;

  /// 结算页主按钮文案，为空则「完成」
  final String? nextTitle;

  /// 演示/截图用：启动后自动点一对（1=正确、2=错误、3=连打三对）
  final int autoDemo;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> with TickerProviderStateMixin {
  final math.Random _rnd = math.Random();
  final ConfettiField _field = ConfettiField();
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _enKeys = List.generate(kPairs, (_) => GlobalKey());
  final List<GlobalKey> _zhKeys = List.generate(kPairs, (_) => GlobalKey());

  /// 巩固台轨道（量飞行落点用）
  final GlobalKey _shelfInnerKey = GlobalKey();

  late final AnimationController _shake =
      AnimationController(vsync: this, duration: _T.shake);

  /// 巩固台横滑：滚到最右才算「跟拍」，用户往回翻过就不再抢位置
  final ScrollController _shelfCtrl = ScrollController();
  bool _shelfPinned = true;

  final List<_Card> _en = List.generate(kPairs, (_) => _Card(isEn: true));
  final List<_Card> _zh = List.generate(kPairs, (_) => _Card(isEn: false));
  final List<Word> _queue = [];

  /// 巩固台：一关的词全按顺序留着，左旧右新
  final List<_ShelfItem> _shelf = [];
  int _shelfSeq = 0;

  /// 局数。重开时 +1，异步流程（退场、落位）恢复后靠它判断自己是不是上一局的，
  /// 否则上一局还在飞的克隆卡会补到新棋盘、旧定时器会把新巩固台提前灭灯。
  int _round = 0;

  /// 巩固台的高亮定时器：dispose 时要一起收掉，否则页面关掉还挂着 timer
  final List<Timer> _shelfTimers = [];

  final List<_Flight> _flights = [];

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

  String _cheer = '';
  bool _cheerOn = false;
  bool _cheerBig = false;
  int _cheerSeq = 0;
  Timer? _cheerTimer;

  int get _total => widget.words.length;

  @override
  void initState() {
    super.initState();
    _start();
    if (widget.autoDemo > 0) {
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
    _cheerTimer?.cancel();
    for (final t in _shelfTimers) {
      t.cancel();
    }
    _shelfTimers.clear();
    _shake.dispose();
    _shelfCtrl.dispose();
    for (final f in _flights) {
      f.ctrl.dispose();
    }
    _field.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 开局

  void _start() {
    // 重开时把上一局残留的动画和定时器收干净：
    // 还在飞的克隆卡会继续飞向旧槽位，巩固台的高亮定时器也会一局局累积。
    _round++;
    _cheerTimer?.cancel();
    for (final t in _shelfTimers) {
      t.cancel();
    }
    _shelfTimers.clear();
    for (final f in _flights) {
      f.ctrl.dispose();
    }
    _flights.clear();

    _queue
      ..clear()
      ..addAll(widget.words)
      ..shuffle(_rnd);
    for (final c in _en) {
      c.clear();
    }
    for (final c in _zh) {
      c.clear();
    }
    _shelf.clear();
    _shelfSeq = 0;
    _shelfPinned = true;
    if (_shelfCtrl.hasClients) _shelfCtrl.jumpTo(0);
    _wrong.clear();
    _done = _combo = _maxCombo = _firstTry = 0;
    _selEn = _selZh = null;
    _lock = false;
    _over = false;
    _finished = false;
    _elapsed = Duration.zero;
    _t0 = DateTime.now();
    _field.clear();
    _cheerOn = false;
    _setHint('先点左边英文，再点右边对应的中文');

    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _over || _finished) return;
      setState(() => _elapsed = DateTime.now().difference(_t0));
    });

    // 首屏：取 4 个词，两列各自打乱
    final first = <Word>[];
    for (var i = 0; i < kPairs; i++) {
      if (_queue.isEmpty) break;
      first.add(_queue.removeAt(0));
    }
    final forEn = List<Word>.from(first)..shuffle(_rnd);
    final forZh = List<Word>.from(first)..shuffle(_rnd);

    for (var i = 0; i < forEn.length; i++) {
      _paint(_en[i], forEn[i]);
    }
    for (var i = 0; i < forZh.length; i++) {
      _paint(_zh[i], forZh[i]);
    }
    // 首屏也可能出现「同一行左右同词」，按补位同一套规则洗开
    _reshuffleZh();

    setState(() {});
  }

  void _paint(_Card c, Word w) {
    c.w = w;
    c.ok = false;
    c.bad = false;
    c.sel = false;
    c.gone = false;
    c.done = false;
    c.stamp++;
  }

  // ------------------------------------------------------------ 点击与判定

  void _tap(bool isEn, int i) {
    if (_lock || _over || _finished) return;
    final c = isEn ? _en[i] : _zh[i];
    if (c.w == null || c.ok || c.gone || c.done) return;

    if (isEn) {
      if (_selEn == i) {
        setState(() => _en[i].sel = false);
        _selEn = null;
        return;
      }
      final prev = _selEn;
      setState(() {
        if (prev != null) _en[prev].sel = false;
        _selEn = i;
        _en[i].sel = true;
      });
    } else {
      if (_selZh == i) {
        setState(() => _zh[i].sel = false);
        _selZh = null;
        return;
      }
      final prev = _selZh;
      setState(() {
        if (prev != null) _zh[prev].sel = false;
        _selZh = i;
        _zh[i].sel = true;
      });
    }

    if (_selEn != null && _selZh != null) _judge();
  }

  Future<void> _judge() async {
    final ei = _selEn!;
    final zi = _selZh!;
    final a = _en[ei].w;
    final b = _zh[zi].w;
    if (a == null || b == null) return;

    _lock = true;
    setState(() {
      _en[ei].sel = false;
      _zh[zi].sel = false;
    });

    await Future<void>.delayed(_T.judge);
    if (!mounted || _over) return;
    _selEn = _selZh = null;

    if (a.en == b.en) {
      _onMatch(ei, zi, a);
    } else {
      _onMiss(ei, zi);
    }
  }

  void _onMatch(int ei, int zi, Word w) {
    _done++;
    _combo++;
    _maxCombo = math.max(_maxCombo, _combo);
    if (!_wrong.contains(w.en)) _firstTry++;
    widget.onProgress?.call(_done);
    if (AppSettings.I.haptic) HapticFeedback.mediumImpact();
    _beep();

    final pa = _centerOf(_enKeys[ei]);
    final pb = _centerOf(_zhKeys[zi]);

    setState(() {
      _en[ei].ok = true;
      _zh[zi].ok = true;
    });

    // 纸屑从两张卡的连线中点炸一簇：在各自中心炸会正好盖住刚配对的词
    if (pa != null && pb != null) {
      _field.burstAt(
        Offset((pa.dx + pb.dx) / 2, (pa.dy + pb.dy) / 2),
        n: _combo % 5 == 0 ? 26 : 14,
        boost: 2.2,
      );
    }

    _setHint(
      _combo >= 2 ? '连对 $_combo 对 · ${w.en} = ${w.zh}' : '✓ ${w.en} = ${w.zh}',
      kind: _FtKind.ok,
    );
    if (_combo >= 2) _showCheer('连对 $_combo！');

    // 关键：判定一结束就解锁，绿卡停留期间就能点下一组
    _lock = false;

    final rect = _rectOf(_enKeys[ei]);
    Future<void>.delayed(_T.flyStart, () => _retire(ei, zi, w, pa, pb, rect));
  }

  Future<void> _onMiss(int ei, int zi) async {
    _combo = 0;
    final a = _en[ei].w;
    final b = _zh[zi].w;
    if (a != null) _wrong.add(a.en);
    if (b != null) _wrong.add(b.en);

    if (AppSettings.I.haptic) HapticFeedback.heavyImpact();
    setState(() {
      _en[ei].bad = true;
      _zh[zi].bad = true;
    });
    _shake.forward(from: 0);
    _setHint('不对，再看看', kind: _FtKind.bad);

    await Future<void>.delayed(_T.wrong);
    if (!mounted || _over) return;
    setState(() {
      _en[ei]
        ..bad = false
        ..sel = false;
      _zh[zi]
        ..bad = false
        ..sel = false;
    });
    _lock = false;
    _selEn = _selZh = null;
    _setHint('再试一次');
  }

  // ------------------------------------------------------------ 退场 / 补位

  /// 绿卡先藏起来 → 两张「飞到」巩固台 → 棋盘原地补新词 → 落位。
  ///
  /// 词池已经空了的那几对走另一条路：**不飞、不补位，原地置灰**。
  /// 一关 10 对、一屏 4 对，前 6 对配完刚好把最后一屏补满，
  /// 之后的每一对都是「最后几对」—— 收尾时盘上是一整盘学完的词，
  /// 而不是一屏错开的虚线空格（那看着像界面坏了）。
  Future<void> _retire(
    int ei,
    int zi,
    Word w,
    Offset? fromEn,
    Offset? fromZh,
    Rect? rect,
  ) async {
    if (!mounted || _over) return;
    final r = _round;

    // 词池空 = 盘上这几对就是最后的
    if (_queue.isEmpty) {
      setState(() {
        _en[ei]
          ..ok = false
          ..done = true;
        _zh[zi]
          ..ok = false
          ..done = true;
      });
      Future<void>.delayed(const Duration(milliseconds: 240), () {
        if (!mounted || _over || r != _round) return;
        _enqueueShelf(w);
      });
      _checkEnd();
      return;
    }

    final target = _shelfTarget();
    if (fromEn != null && fromZh != null && target != null && rect != null) {
      _launchFlyer(w, fromEn, target, rect);
      _launchFlyer(w, fromZh, target, rect);
    }

    setState(() {
      _en[ei].gone = true;
      _zh[zi].gone = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _over || r != _round) return;
    _refill(ei, zi);

    // 飞行结束的那一刻才落位，卡片「到达」和巩固台高亮是同一瞬间
    await Future<void>.delayed(_T.flyDur - const Duration(milliseconds: 120));
    if (!mounted || _over || r != _round) return;
    _enqueueShelf(w);
  }

  /// 英文列位置固定（哪格消失补哪格），中文列整列重排。
  void _refill(int ei, int zi) {
    final next = _queue.isEmpty ? null : _queue.removeAt(0);

    // 兜底：正常走不到（词池空了几率已在 _retire 里分流），
    // 万一走到就当这一对也置灰，别把棋盘弄成半张。
    if (next == null) {
      setState(() {
        _en[ei]
          ..ok = false
          ..done = true;
        _zh[zi]
          ..ok = false
          ..done = true;
        _selEn = _selZh = null;
      });
      _checkEnd();
      return;
    }

    setState(() {
      _selEn = _selZh = null;
      _paint(_en[ei], next); // 英文：原位补，位置永远不动
      _zh[zi].w = next; // 中文：先塞进空位，再整列洗
      _reshuffleZh();
    });
    _checkEnd();
  }

  /// 中文列整列重排：位置全打乱，且保证没有任何一行左右是同一个词。
  void _reshuffleZh() {
    final idxs = <int>[for (var i = 0; i < kPairs; i++) if (_zh[i].w != null) i];
    if (idxs.length < 2) return;
    final items = <Word>[for (final i in idxs) _zh[i].w!];

    for (var t = 0; t < 30; t++) {
      items.shuffle(_rnd);
      var bad = false;
      for (var k = 0; k < idxs.length; k++) {
        final e = _en[idxs[k]].w;
        if (e != null && e.en == items[k].en) {
          bad = true;
          break;
        }
      }
      if (!bad) break;
    }

    for (var k = 0; k < idxs.length; k++) {
      final c = _zh[idxs[k]];
      if (c.w?.en != items[k].en) {
        c.w = items[k];
        c.stamp++;
      }
      c.ok = false;
      c.bad = false;
      c.sel = false;
      c.gone = false;
    }
  }

  void _checkEnd() {
    if (_over || _finished) return;
    // 收尾那几对是置灰留在盘上的，不再是「盘空了才算完」——按配对数量收
    if (_done < _total) return;
    _finished = true;
    Future<void>.delayed(const Duration(milliseconds: 460), () {
      if (!mounted || !_finished) return;
      _finish();
    });
    setState(() {});
  }

  void _finish() {
    _over = true;
    _clock?.cancel();
    setState(() {});
    for (var i = 0; i < 3; i++) {
      Future<void>.delayed(Duration(milliseconds: i * 110), () {
        if (!mounted) return;
        _field.burstAt(Offset(60.0 + i * 130, 120), n: 30, boost: 1.4);
      });
    }
  }

  // ------------------------------------------------------------ 巩固台

  /// 飞行落点：台子右端（新词总是加在最右边）。
  /// 飞行途中就淡到 0 了，不需要落得像素级准。
  Offset? _shelfTarget() {
    final r = _rectOf(_shelfInnerKey);
    if (r == null) return null;
    return Offset(r.right - 30, r.center.dy);
  }

  void _enqueueShelf(Word w) => _landOnShelf(w);

  void _landOnShelf(Word w) {
    if (!mounted || _over) return;
    final item = _ShelfItem(w, _shelfSeq++);
    setState(() => _shelf.add(item));
    _freshTimer(item);
    _followShelf();
  }

  /// 贴着最右才跟拍。
  ///
  /// 为什么不用 `ScrollController.addListener` 判断：新词进来后轨道变长，
  /// `ScrollPosition` 会自己发一次通知（maxScrollExtent 变了），
  /// 那一帧 pixels 还停在旧的最右，会被误判成「用户往回翻了」，
  /// 于是从第 4 个词起就再也不跟随。改成只认 `UserScrollNotification`——
  /// 它只在手指拖 / 惯性滚动时发，程序自己滚不发。
  void _followShelf() {
    if (!_shelfPinned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollShelfToEnd(0));
  }

  /// 一关最多 10 对，补滚两次就到头了（深度限制只是保险）。
  Future<void> _scrollShelfToEnd(int depth) async {
    if (!mounted || depth > 3 || !_shelfCtrl.hasClients) return;
    final p = _shelfCtrl.position;
    if (!p.hasContentDimensions) return;
    final target = p.maxScrollExtent;
    if ((target - p.pixels).abs() < 1) return;
    await _shelfCtrl.animateTo(
      target,
      duration: depth == 0
          ? _T.shelfFollow
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_shelfCtrl.hasClients) return;
    // 懒加载的 ListView 里 maxScrollExtent 是估算值：滚完可能又变长，再补一次
    if (_shelfCtrl.position.maxScrollExtent - _shelfCtrl.position.pixels > 1) {
      await _scrollShelfToEnd(depth + 1);
    }
  }

  void _freshTimer(_ShelfItem item) {
    _shelfTimers.add(Timer(_T.fresh, () {
      if (!mounted) return;
      setState(() => item.fresh = false);
    }));
  }

  // ------------------------------------------------------------ 飞行

  void _launchFlyer(Word w, Offset from, Offset to, Rect rect) {
    final c = AnimationController(vsync: this, duration: _T.flyDur);
    final f = _Flight(ctrl: c, word: w, from: from, to: to, size: rect.size);
    c.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      if (!mounted) return;
      setState(() => _flights.remove(f));
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    });
    setState(() => _flights.add(f));
    c.forward();
  }

  // ------------------------------------------------------------ 坐标工具

  Rect? _rectOf(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    final local = stack.globalToLocal(topLeft);
    return local & box.size;
  }

  Offset? _centerOf(GlobalKey k) => _rectOf(k)?.center;

  // ------------------------------------------------------------ 文案

  void _setHint(String text, {_FtKind kind = _FtKind.hint}) {
    setState(() {
      _ftA = text;
      _ftEm = '';
      _ftB = '';
      _ftKind = kind;
    });
  }

  void _showCheer(String text, {bool big = false}) {
    _cheerTimer?.cancel();
    setState(() {
      _cheer = text;
      _cheerBig = big;
      _cheerOn = true;
      _cheerSeq++;
    });
    _cheerTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _cheerOn = false);
    });
  }

  void _beep() {
    // 音效用系统点击声（WebAudio 那套没法直接搬过来），失败不影响玩法
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  String _clockText() {
    final s = _elapsed.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  String _durationText() {
    final s = _elapsed.inSeconds;
    return s >= 60 ? '${s ~/ 60} 分 ${s % 60} 秒' : '$s 秒';
  }

  // ------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            key: _stackKey,
            children: [
              Column(
                children: [
                  _top(),
                  _shelfBar(),
                  Expanded(child: _desk()),
                  _foot(),
                ],
              ),
              // 纸屑层盖在牌桌上，不挡点击
              Positioned.fill(child: ConfettiOverlay(field: _field)),
              // 飞行中的卡片
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                      [for (final f in _flights) f.ctrl],
                    ),
                    builder: (context, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [for (final f in _flights) _flyer(f)],
                    ),
                  ),
                ),
              ),
              // 连击飘字（放在巩固台下方，不压住牌面）
              Positioned(
                left: 0,
                right: 0,
                top: box.maxHeight * .245 - 10,
                child: IgnorePointer(child: _cheerWidget()),
              ),
              if (_finished) _sheet(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flyer(_Flight f) {
    final t = Curves.easeInOutCubic.transform(f.ctrl.value);
    final p = Offset.lerp(f.from, f.to, t)! - Offset(0, math.sin(t * math.pi) * 16);
    return Positioned(
      left: p.dx - f.size.width / 2,
      top: p.dy - f.size.height / 2,
      width: f.size.width,
      height: f.size.height,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 1 - .5 * t,
          child: Container(
            decoration: BoxDecoration(
              color: _ok50,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _okColor, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x3D58CC02), blurRadius: 22, offset: Offset(0, 8)),
              ],
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                f.word.en,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _okInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cheerWidget() {
    return Center(
      child: AnimatedOpacity(
        opacity: _cheerOn ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_cheerSeq),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
          child: Text(
            _cheer,
            style: TextStyle(
              fontSize: _cheerBig ? 32 : 26,
              fontWeight: FontWeight.w800,
              color: _okColor,
              // 白描边光晕：飘字压在棋盘顶边上时，靠它和卡片分开
              shadows: const [
                Shadow(color: Color(0xFFFFFFFF), blurRadius: 14),
                Shadow(color: Color(0xFFFFFFFF), blurRadius: 7),
              ],
            ),
          ),
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
                    color: kCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: _line, width: 1),
                  ),
                  child: Icon(Icons.close_rounded, size: 17, color: _ink2),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                        color: _ink,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: _ink3),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: _ink2),
                    SizedBox(width: 5),
                    Text(
                      _clockText(),
                      style: TextStyle(
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
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _total == 0 ? 0 : _done / _total),
                    duration: Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: kN1,
                      valueColor: AlwaysStoppedAnimation(_primary),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: ' / $_total',
                      style: TextStyle(
                        fontSize: 11.5,
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
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 巩固台

  Widget _shelfBar() {
    // 一屏固定 3 格：填满后往右加格，一关 10 对全留着，用户自己拖回去看
    final count = math.max(3, _shelf.length);

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Container(
        key: ValueKey('shelf'),
        height: 76,
        padding: EdgeInsets.all(6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _shelfBg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            const gap = 6.0;
            // 槽宽跟着台子宽度走：一屏正好 3 格铺满，右边不留灰缝
            final w = (box.maxWidth - gap * 2) / 3;
            return ScrollConfiguration(
              // 桌面端默认会给可滚动区域画滚动条，这里整个关掉
              behavior: _NoBarScrollBehavior(),
              child: NotificationListener<UserScrollNotification>(
                onNotification: (n) {
                  final m = n.metrics;
                  _shelfPinned = m.maxScrollExtent <= 0 ||
                      m.pixels >= m.maxScrollExtent - 8;
                  return false;
                },
                child: ListView.separated(
                  key: _shelfInnerKey,
                  controller: _shelfCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: ClampingScrollPhysics(),
                  itemCount: count,
                  separatorBuilder: (_, _) => SizedBox(width: gap),
                  itemBuilder: (context, i) {
                    final it = i < _shelf.length ? _shelf[i] : null;
                    return SizedBox(
                      width: w,
                      child: _shelfSlot(
                        it,
                        // 空态第一格上印台子的名字，卡片被词填上就没了
                        placeholder: i == 0 && _shelf.isEmpty,
                        pop: it != null && it.fresh,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _shelfSlot(_ShelfItem? it, {bool placeholder = false, bool pop = false}) {
    final filled = it != null;
    final fresh = it?.fresh ?? false;

    final Color bg = !filled
        ? Colors.transparent
        : fresh
            ? _ok50
            : kCard;
    final Color border = !filled
        ? kN2
        : fresh
            ? _okColor
            : kN2;

    Widget content = Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: Duration(milliseconds: 200),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: (Theme.of(context).textTheme.bodyMedium ?? TextStyle())
                    .merge(TextStyle(
                    fontSize: fresh ? 15 : 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: fresh ? _okInk : _ink,
                  )),
              child: Text(it?.w.en ?? ''),
            ),
            SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: Duration(milliseconds: 200),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: (Theme.of(context).textTheme.bodyMedium ?? TextStyle())
                    .merge(TextStyle(
                    fontSize: fresh ? 12.5 : 11,
                    height: 1.15,
                    color: fresh ? _okInk2 : kN4,
                  )),
              child: Text(it?.w.zh ?? ''),
            ),
          ],
        ),
      ),
    );

    if (pop) {
      content = TweenAnimationBuilder<double>(
        key: ValueKey(it!.seq),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420),
        builder: (context, t, child) => Transform.scale(
          scale: .72 + .28 * Curves.easeOutBack.transform(t),
          child: child,
        ),
        child: content,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: filled ? Border.all(color: border, width: 1) : null,
            boxShadow: fresh
                ? [
                    BoxShadow(
                        color: Color(0x2E58CC02),
                        blurRadius: 12,
                        offset: Offset(0, 3)),
                  ]
                : null,
          ),
          child: filled ? content : null,
        ),
        if (!filled)
          IgnorePointer(
            child: CustomPaint(
              painter: _DashBorder(color: border, radius: 9, width: 1),
            ),
          ),
        // 空态第一格就是台子的名字：字压在背景卡上，不占额外一行
        if (!filled && placeholder)
          Center(
            child: Text(
              '巩固台',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
                color: kN4,
              ),
            ),
          ),
        if (fresh)
          Positioned(
            top: 3,
            right: 4,
            child: Text('✓', style: TextStyle(fontSize: 9, color: _okColor)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ 牌桌

  Widget _desk() {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(
        key: ValueKey('desk'),
        children: [
          for (var i = 0; i < kPairs; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey('en$i'),
                        child: _cardView(_en[i], i, true),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey('zh$i'),
                        child: _cardView(_zh[i], i, false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardView(_Card c, int i, bool isEn) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, _) {
        var dy = 0.0;

        // 配对成功不再抖：判定完绿一帧就收走，反馈交给纸屑 + 飞向巩固台
        if (c.bad) {
          const ys = [0.0, -8.0, 7.0, -5.0, 4.0, -2.0, 0.0];
          final p = _shake.value * (ys.length - 1);
          final idx = p.floor().clamp(0, ys.length - 2);
          dy = ys[idx] + (ys[idx + 1] - ys[idx]) * (p - idx);
        }

        final lift = c.sel ? -3.0 : 0.0;
        return Transform.translate(
          offset: Offset(0, dy + lift),
          child: _cardBox(c, i, isEn),
        );
      },
    );
  }

  Widget _cardBox(_Card c, int i, bool isEn) {
    final word = c.w;
    final blank = word == null;

    Color bg = kCard;
    Color border = _line;
    Color textColor = _ink;
    Color subColor = _ink3;
    var dashed = false;
    List<BoxShadow> shadow = [
      BoxShadow(color: kN2, offset: Offset(0, 2.5)),
      BoxShadow(color: ta(kPrimaryDeep, 0x0F), offset: Offset(0, 8), blurRadius: 16),
    ];
    var borderWidth = 1.5;

    if (blank) {
      bg = Colors.transparent;
      border = kN2;
      dashed = true;
      shadow = [];
    } else if (c.done) {
      // 收尾置灰：这一盘都学完了，词留在原位当背景
      bg = kN1;
      border = kN2;
      textColor = kN4;
      subColor = kN3;
      shadow = [];
    } else if (c.ok) {
      bg = _ok50;
      border = _okColor;
      textColor = _okInk;
      subColor = _okInk2;
      shadow = [
        BoxShadow(color: kN2, offset: Offset(0, 3.5)),
        BoxShadow(
            color: Color(0x2E58CC02),
            blurRadius: 20,
            offset: Offset(0, 11),
            spreadRadius: 1),
      ];
    } else if (c.bad) {
      bg = _bad50;
      border = _badColor;
      textColor = _badInk;
      subColor = _badInk;
    } else if (c.sel) {
      bg = _primary50;
      border = _primary;
      textColor = _primaryDeep;
      subColor = _primaryDeep;
      shadow = [
        BoxShadow(color: kDash, offset: Offset(0, 4.5)),
        BoxShadow(color: ta(kPrimary, 0x38), blurRadius: 22, offset: Offset(0, 14)),
      ];
    }

    final main = blank ? '' : (isEn ? word.en : word.zh);
    final sub = blank ? '' : (isEn ? word.phUs : word.detail);

    return AnimatedOpacity(
      opacity: c.gone ? 0 : 1,
      duration: Duration(milliseconds: 140),
      child: AnimatedContainer(
        key: isEn ? _enKeys[i] : _zhKeys[i],
        duration: Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
          border: dashed ? null : Border.all(color: border, width: borderWidth),
          boxShadow: shadow,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!blank)
              Semantics(
                button: true,
                selected: c.sel,
                // 置灰的牌不能再点，读屏也不该把它报成可操作
                enabled: !c.gone,
                label: isEn ? '英文 $main' : '中文 $main',
                child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  onTap: (c.gone) ? null : () => _tap(isEn, i),
                  borderRadius: BorderRadius.circular(15),
                  splashColor: _primary.withValues(alpha: .06),
                  highlightColor: _primary.withValues(alpha: .03),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            main,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isEn ? 19 : 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .1,
                              height: 1.15,
                              color: textColor,
                            ),
                          ),
                          if (sub.isNotEmpty) ...[
                            SizedBox(height: 3),
                            // 中文释义保留（自己玩的时候要看），太长就截断加省略号
                            Text(
                              sub,
                              maxLines: isEn ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isEn ? 11.5 : 10.5,
                                height: 1.25,
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
              ),
            if (dashed)
              IgnorePointer(
                child: CustomPaint(
                  painter: _DashBorder(color: border, radius: 15, width: borderWidth),
                ),
              ),
            // 收尾置灰的卡右上角一个淡对勾：这一对已经学过、不用再管
            if (c.done)
              Positioned(
                top: 6,
                right: 9,
                child: Text('✓',
                    style: TextStyle(fontSize: 11, color: kN3)),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 底部提示

  Widget _foot() {
    final color = switch (_ftKind) {
      _FtKind.ok => _okInk,
      _FtKind.bad => _badColor,
      _FtKind.hint => _ink3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                    .merge(TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: color,
                  fontWeight: _ftKind == _FtKind.hint
                      ? FontWeight.w400
                      : FontWeight.w700,
                )),
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
    final theme = widget.scene == MatchScene.theme;

    return Positioned.fill(
      child: Container(
        color: ta(kInk, 0x6B),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: .94 + .06 * t, child: child),
          ),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(theme ? '主题完成' : '本关完成',
                    style: TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 6),
                Text(
                  wr.isEmpty
                      ? (theme ? '一次全对，直接满星拿下这个主题' : '一次全对，整关满星')
                      : '${_durationText()} · ${wr.length} 个词配错过',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: _ink2),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _stat('$_total', '配对'),
                    const SizedBox(width: 9),
                    _stat('$acc%', '一次选对'),
                    SizedBox(width: 9),
                    _stat('$_maxCombo', '最高连击'),
                  ],
                ),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: Text(widget.nextTitle ?? '完成',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                TextButton(
                  onPressed: _start,
                  child: Text('再来一局',
                      style: TextStyle(fontSize: 12.5, color: _ink3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: kN1,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: _ink3)),
          ],
        ),
      ),
    );
  }
}

enum _FtKind { hint, ok, bad }

// ---------------------------------------------------------------- 模型

class _Card {
  _Card({required this.isEn});

  final bool isEn;
  Word? w;
  bool sel = false;
  bool ok = false;
  bool bad = false;

  /// 已退场（原卡隐藏、等补位）：此时不响应点击
  bool gone = false;

  /// 收尾置灰：词留在原位不再动（最后一屏学完的样子）
  bool done = false;

  /// 每次换词 +1，卡片用它重播入场动画
  int stamp = 0;

  void clear() {
    w = null;
    sel = ok = bad = gone = done = false;
    stamp++;
  }
}

class _ShelfItem {
  _ShelfItem(this.w, this.seq);

  final Word w;

  /// 唯一标识（同一个词可能重复出现），用于重播弹入动画
  final int seq;
  bool fresh = true;
}

class _Flight {
  _Flight({
    required this.ctrl,
    required this.word,
    required this.from,
    required this.to,
    required this.size,
  });

  final AnimationController ctrl;
  final Word word;
  final Offset from;
  final Offset to;
  final Size size;
}

// ---------------------------------------------------------------- 绘制

/// 一列都不画滚动条：巩固台是横滑轨道，手机应用里没人想要那条横条。
/// 桌面端 Flutter 默认会给可滚动区域自动加 Scrollbar，这里把它整个关掉。
class _NoBarScrollBehavior extends MaterialScrollBehavior {
  const _NoBarScrollBehavior();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// 虚线边框（空格用）：Flutter 没有原生 dashed border，沿圆角路径切段画
class _DashBorder extends CustomPainter {
  _DashBorder({required this.color, required this.radius, this.width = 1.5});

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + 5, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashBorder old) =>
      old.color != color || old.radius != radius || old.width != width;
}
