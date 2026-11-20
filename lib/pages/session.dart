import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio.dart';
import '../bank.dart';
import '../entitlement.dart';
import '../ui.dart';
import '../progress.dart';

enum QType { flash, choice, listen, spell }

class SessionItem {
  final Word w;
  final QType type;
  final bool isNew;
  final List<String> options;

  const SessionItem(this.w, this.type, this.isNew, this.options);
}

class SessionPlan {
  /// 今日队列：到期复习在前，新词混排其中
  static List<SessionItem> build({bool reviewOnly = false}) {
    final p = Progress.I;
    final rnd = Random();
    final items = <SessionItem>[];

    // 用户自己设的每日量（Progress.newPerDay）还要再受权益上限约束：
    // 会员过期后 prefs 里仍留着 40，不截断的话等于降级了还能按会员量学。
    final limits = Ent.I.ent.limits;
    final reviewCap = min(p.reviewPerDay, limits.reviewPerDayMax);
    final newCap = min(p.newPerDay, limits.newPerDayMax);

    for (final w in p.dueWords().take(reviewCap)) {
      items.add(_reviewItem(w, rnd));
    }

    if (!reviewOnly) {
      final remain = (newCap - p.todayNew).clamp(0, 100);
      for (final w in p.newWords(limit: remain)) {
        items.add(SessionItem(w, QType.flash, true, const []));
      }
    }

    if (!reviewOnly && items.length > 4) {
      // 每 5 个里插 1 个新词，避免开头全是新词劝退。
      // 注意别在这里「清空 fresh 再往下加」—— 以前 while 里无条件 clear()，
      // 新词多于剩余轮次时（old=10 / fresh=5）后 4 个新词会被整批吞掉。
      final old = items.where((e) => !e.isNew).toList();
      final fresh = items.where((e) => e.isNew).toList();
      items.clear();
      var fi = 0;
      while (old.isNotEmpty && fi < fresh.length) {
        for (var i = 0; i < 4 && old.isNotEmpty; i++) {
          items.add(old.removeAt(0));
        }
        items.add(fresh[fi++]);
      }
      // 旧词或新词哪一头先耗尽，剩下的原序接上
      items
        ..addAll(old)
        ..addAll(fresh.sublist(fi));
    }
    return items;
  }

  /// 按指定词表出题（自由练习专用；关卡 / 主题已统一走配对棋盘）
  static List<SessionItem> fromWords(List<Word> words, {bool shuffleAll = true}) {
    final rnd = Random();
    const types = [QType.choice, QType.spell, QType.listen];
    final list = List<Word>.from(words);
    if (shuffleAll) list.shuffle(rnd);
    return [
      for (final w in list)
        SessionItem(w, types[rnd.nextInt(types.length)], true, _options(w, rnd)),
    ];
  }

  static SessionItem _reviewItem(Word w, Random rnd) {
    const types = [QType.choice, QType.spell, QType.listen];
    final type = types[rnd.nextInt(types.length)];
    return SessionItem(w, type, false, _options(w, rnd));
  }

  static List<String> _options(Word w, Random rnd) {
    final pool = <String>{w.zh};
    final same = WordBank.I.byLevel[w.lv] ?? WordBank.I.words;
    var guard = 0;
    while (pool.length < 4 && guard < 200) {
      guard++;
      final cand = same[rnd.nextInt(same.length)];
      if (cand.zh != w.zh) pool.add(cand.zh);
    }
    final list = pool.toList()..shuffle(rnd);
    return list;
  }
}

class SessionPage extends StatefulWidget {
  final List<SessionItem> items;
  final String title;

  /// 每答完一题回调已答数量，用于保存半程进度
  final ValueChanged<int>? onProgress;

  const SessionPage({
    super.key,
    required this.items,
    this.title = '学习',
    this.onProgress,
  });

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  int _idx = 0;
  bool _revealed = false;
  bool _correct = false;
  bool _finished = false;
  bool _showBack = false;

  int _right = 0;
  int _wrong = 0;
  int _newDone = 0;
  String _picked = '';
  String _typed = '';
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  DateTime _start = DateTime.now();

  SessionItem get _item => widget.items[_idx];

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    // 开局顺手把这关的词都取到本地（20 词约 1MB），之后重听/复习不再走网络。
    // 不 await：下载不该拖慢开局。
    Voice.prefetch(widget.items.map((e) => e.w.en));
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlay());
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    widget.onProgress?.call(_finished ? widget.items.length : _idx);
    appTick.value++;
    super.dispose();
  }

  void _maybePlay() {
    if (_finished || !mounted) return;
    if (_item.type == QType.listen) Voice.say(_item.w.en);
  }

  void _submit(bool ok, {int? self}) {
    if (_revealed) return;
    final g = self ?? (ok ? 2 : 0);
    Progress.I.grade(_item.w, g, isNew: _item.isNew);
    if (ok || (self != null && self > 0)) {
      _right++;
    } else {
      _wrong++;
    }
    if (_item.isNew) _newDone++;
    setState(() {
      _revealed = true;
      _correct = ok;
    });
    if (ok) {
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted && _revealed) _next();
      });
    }
  }

  void _next() {
    if (_idx + 1 >= widget.items.length) {
      Progress.I.save();
      widget.onProgress?.call(widget.items.length);
      setState(() => _finished = true);
      appTick.value++;
      return;
    }
    setState(() {
      _idx++;
      _revealed = false;
      _correct = false;
      _showBack = false;
      _picked = '';
      _typed = '';
      _ctl.clear();
    });
    widget.onProgress?.call(_idx);
    _maybePlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: Text(_finished ? '本次完成' : widget.title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: kInk)),
        leading: IconButton(
          icon: Icon(Icons.close, color: kMuted),
          onPressed: () {
            Progress.I.save();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _finished ? _summary() : _body(),
        ),
      ),
    );
  }

  // ---------------- 主体 ----------------

  Widget _body() {
    final total = widget.items.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _idx / total,
                    minHeight: 7,
                    backgroundColor: kN1,
                    valueColor: AlwaysStoppedAnimation(kPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_idx + 1}/$total',
                  style: TextStyle(fontSize: 12, color: kMuted)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 18),
                _question(),
                if (_revealed) ...[const SizedBox(height: 16), _feedback()],
              ],
            ),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _header() {
    final w = _item.w;
    final isNew = _item.isNew;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: isNew
                ? kPrimary.withValues(alpha: 0.12)
                : kGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(isNew ? '新词' : '复习',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isNew ? kPrimary : kGreen)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: kN2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(w.levelName,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: kMuted)),
        ),
        const Spacer(),
        if (_item.type != QType.listen)
          IconButton(
            onPressed: () => Voice.say(w.en),
            icon: Icon(Icons.volume_up_rounded, color: kPrimary, size: 22),
            tooltip: '发音',
          ),
      ],
    );
  }

  Widget _question() {
    switch (_item.type) {
      case QType.flash:
        return _flash();
      case QType.choice:
        return _choice();
      case QType.listen:
        return _listen();
      case QType.spell:
        return _spell();
    }
  }

  Widget _card({required Widget child, double minH = 200}) {
    return Container(
      constraints: BoxConstraints(minHeight: minH),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
      ),
      child: child,
    );
  }

  // 闪卡：正面英文，点开看释义
  Widget _flash() {
    final w = _item.w;
    return _card(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(w.en,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 38, fontWeight: FontWeight.w700, color: kInk)),
          if (w.phUs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(w.phUs,
                style: TextStyle(fontSize: 14, color: kMuted)),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => Voice.say(w.en),
            icon: Icon(Icons.volume_up_rounded, size: 18, color: kPrimary),
            label: Text('听发音',
                style: TextStyle(fontSize: 13, color: kPrimary)),
          ),
          if (_showBack) ...[
            Divider(height: 26, color: kN2),
            Text(w.zh,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: kInk)),
            if (w.detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(w.detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.5)),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text('先想一想意思，再点下面的按钮',
                  style: TextStyle(fontSize: 12, color: kMuted.withValues(alpha: 0.8))),
            ),
        ],
      ),
    );
  }

  // 英 → 中 四选一
  Widget _choice() {
    final w = _item.w;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          minH: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(w.en,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w700, color: kInk)),
              if (w.phUs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(w.phUs,
                      style: TextStyle(fontSize: 13, color: kMuted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._item.options.map((o) => _optionTile(o, o == w.zh)),
      ],
    );
  }

  // 听音 → 中 四选一
  Widget _listen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          minH: 130,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                button: true,
                label: '播放发音',
                child: GestureDetector(
                onTap: () => Voice.say(_item.w.en),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.volume_up_rounded,
                      size: 36, color: kPrimary),
                ),
              ),
              ),
              const SizedBox(height: 10),
              Text('点击重听',
                  style: TextStyle(fontSize: 12, color: kMuted)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._item.options.map((o) => _optionTile(o, o == _item.w.zh)),
      ],
    );
  }

  Widget _optionTile(String text, bool isAnswer) {
    Color border = kLine;
    Color bg = kCard;
    Color fg = kInk;
    if (_revealed) {
      if (isAnswer) {
        border = kGreen;
        bg = kGreen.withValues(alpha: 0.08);
        fg = kGreen;
      } else if (_picked == text) {
        border = kRed;
        bg = kRed.withValues(alpha: 0.06);
        fg = kRed;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        enabled: !_revealed,
        selected: _picked == text,
        // 答完后要能听出「哪个是对的、我选了哪个」，否则只能靠颜色
        label: _revealed
            ? (isAnswer ? '正确答案：$text' : (_picked == text ? '你选的：$text，不对' : text))
            : null,
        child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _revealed
            ? null
            : () {
                setState(() => _picked = text);
                _submit(text == _item.w.zh);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 15, color: fg, height: 1.3)),
        ),
      ),
      ),
    );
  }

  // 中 → 拼写
  Widget _spell() {
    final w = _item.w;
    final parts = _typed.split('');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          minH: 130,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(w.zh,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600, color: kInk)),
              if (w.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(w.detail,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: kMuted, height: 1.5)),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => Voice.say(w.en),
                    tooltip: '播放发音',
                    icon: Icon(Icons.volume_up_rounded,
                        size: 20, color: kPrimary),
                  ),
                  Text('${w.en.length} 个字母',
                      style: TextStyle(fontSize: 12, color: kMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ctl,
          focusNode: _focus,
          autofocus: true,
          enabled: !_revealed,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(
              fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\-\s]')),
          ],
          onChanged: (v) => setState(() => _typed = v),
          onSubmitted: (v) => _checkSpell(),
          decoration: InputDecoration(
            hintText: '输入英文单词',
            hintStyle: TextStyle(
                fontSize: 16, letterSpacing: 0, color: kN3),
            filled: true,
            fillColor: kCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kLine),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kLine),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kPrimary),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (!_revealed && parts.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('首字母：${w.en[0].toUpperCase()}',
                style: TextStyle(fontSize: 12, color: kMuted)),
          ),
      ],
    );
  }

  void _checkSpell() {
    if (_revealed) return;
    final ok = _typed.trim().toLowerCase() == _item.w.en.toLowerCase();
    _submit(ok);
  }

  Widget _feedback() {
    final w = _item.w;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _correct ? kGreen.withValues(alpha: 0.07) : kRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _correct
                ? kGreen.withValues(alpha: 0.35)
                : kRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 20, color: _correct ? kGreen : kRed),
              const SizedBox(width: 6),
              Text(_correct ? '答对了' : '再记一下',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _correct ? kGreen : kRed)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(w.en,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(width: 8),
              if (w.phUs.isNotEmpty)
                Text(w.phUs,
                    style: TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: '播放 ${w.en} 的发音',
                child: InkWell(
                  onTap: () => Voice.say(w.en),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.volume_up_rounded, size: 16, color: kPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(w.zh,
              style: TextStyle(fontSize: 14, color: kInk, height: 1.4)),
          if (w.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(w.detail,
                  style: TextStyle(fontSize: 12, color: kMuted, height: 1.5)),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    if (!_revealed) {
      if (_item.type == QType.flash) {
        if (!_showBack) {
          return _bigButton('显示释义', () => setState(() => _showBack = true));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              _gradeBtn('忘记', kRed, 0),
              const SizedBox(width: 10),
              _gradeBtn('模糊', kAmber, 1),
              const SizedBox(width: 10),
              _gradeBtn('认识', kGreen, 2),
            ],
          ),
        );
      }
      if (_item.type == QType.spell) {
        return _bigButton('提交', _checkSpell);
      }
      // 选择题在选项里直接作答
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text('选一个意思',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: kMuted.withValues(alpha: 0.9))),
      );
    }
    return _bigButton('继续', _next);
  }

  Widget _gradeBtn(String label, Color color, int grade) {
    return Expanded(
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: () => _submit(grade > 0, self: grade),
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }

  Widget _bigButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // ---------------- 小结 ----------------

  Widget _summary() {
    final secs = DateTime.now().difference(_start).inSeconds;
    final total = _right + _wrong;
    final acc = total == 0 ? 0 : (_right * 100 / total).round();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: kGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, size: 46, color: kGreen),
            ),
            const SizedBox(height: 18),
            Text('今天又前进了一步',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kLine),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _stat('${_right + _wrong}', '作答'),
                  _stat('$acc%', '正确率'),
                  _stat('$_newDone', '新学'),
                  _stat('${secs ~/ 60}′', '用时'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('完成',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String v, String label) {
    return Column(
      children: [
        Text(v,
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }
}
