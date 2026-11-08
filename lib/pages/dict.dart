import 'package:flutter/material.dart';

import '../audio.dart';
import '../bank.dart';
import '../progress.dart';
import '../ui.dart';

class DictPage extends StatefulWidget {
  const DictPage({super.key});

  @override
  State<DictPage> createState() => _DictPageState();
}

class _DictPageState extends State<DictPage> {
  final _ctl = TextEditingController();
  List<Word> _res = const [];
  String _kw = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _kw = q;
      _res = WordBank.I.search(q, limit: 60);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('词典',
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: TextField(
              controller: _ctl,
              onChanged: _search,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: '输入英文或中文，如 abandon / 放弃',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB8B4C8)),
                prefixIcon: const Icon(Icons.search, size: 20, color: kMuted),
                suffixIcon: _kw.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: kMuted),
                        onPressed: () {
                          _ctl.clear();
                          _search('');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kPrimary),
                ),
              ),
            ),
          ),
          Expanded(
            child: _kw.isEmpty ? _idle() : _list(),
          ),
        ],
      ),
    );
  }

  Widget _idle() {
    final p = Progress.I;
    final picks = <Word>[];
    for (final w in WordBank.I.words) {
      if (p.states.containsKey(w.en)) picks.add(w);
      if (picks.length >= 8) break;
    }
    if (picks.isEmpty) {
      picks.addAll(WordBank.I.words.take(8));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      children: [
        const Text('随便看看',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 10),
        ...picks.map((w) => _tile(w)),
        const SizedBox(height: 18),
        Text('词库共 ${WordBank.I.words.length} 词 · A1–C1 五级 · 60 个主题',
            style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }

  Widget _list() {
    if (_res.isEmpty) {
      return const Center(
        child: Text('没找到，换个词试试',
            style: TextStyle(fontSize: 13, color: kMuted)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: _res.length,
      itemBuilder: (_, i) => _tile(_res[i]),
    );
  }

  Widget _tile(Word w) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _sheet(w),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(w.en,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: kInk)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EEF8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(w.levelName,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: kMuted)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(w.zh,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: kMuted)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Voice.say(w.en),
              icon: const Icon(Icons.volume_up_rounded,
                  size: 18, color: kPrimary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
          ],
        ),
      ),
    );
  }

  void _sheet(Word w) {
    Voice.say(w.en);
    final st = Progress.I.states[w.en];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(w.en,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                const SizedBox(width: 10),
                if (w.phUs.isNotEmpty)
                  Text(w.phUs,
                      style: const TextStyle(fontSize: 13, color: kMuted)),
                const Spacer(),
                IconButton(
                  onPressed: () => Voice.say(w.en),
                  icon: const Icon(Icons.volume_up_rounded, color: kPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(w.zh,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: kInk)),
            if (w.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(w.detail,
                    style: const TextStyle(
                        fontSize: 13, color: kMuted, height: 1.6)),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(w.levelName, kPrimary),
                for (final t in w.cefr) _chip(t, kMuted),
                for (final t in w.topic.take(3)) _chip(t, kGreen),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              st == null
                  ? '还没学这个词'
                  : '已练 ${st.seen} 次 · 对 ${st.right} 错 ${st.wrong} · ${st.mastered ? "已掌握" : "巩固中"}',
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            const SizedBox(height: 6),
            const Text('例句与词形变化尚未录入，是下一步要补的内容。',
                style: TextStyle(fontSize: 11, color: Color(0xFFB8B4C8))),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
