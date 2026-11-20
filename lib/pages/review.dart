import 'package:flutter/material.dart';

import '../audio.dart';
import '../bank.dart';
import '../progress.dart';
import '../ui.dart';
import 'session.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appTick,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final p = Progress.I;
    final due = p.dueWords();
    final wrong = p.wrongBook();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text('复习',
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 4),
          Text('按记忆曲线安排，到期才出现',
              style: TextStyle(
                  fontSize: 12, color: kMuted.withValues(alpha: 0.9))),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kLine),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${due.length}',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: kPrimary)),
                      Text('个词待复习',
                          style: TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: due.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SessionPage(
                                items: SessionPlan.build(reviewOnly: true),
                                title: '今日复习',
                              ),
                            ),
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kN2,
                    disabledForegroundColor: kMuted,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(due.isEmpty ? '暂无到期' : '开始复习',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('易错词',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
              const Spacer(),
              Text('${wrong.length} 个',
                  style: TextStyle(fontSize: 11, color: kMuted)),
            ],
          ),
          const SizedBox(height: 12),
          if (wrong.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kLine),
              ),
              child: Column(
                children: [
                  Icon(Icons.emoji_events_outlined, size: 28, color: kMuted),
                  SizedBox(height: 8),
                  Text('还没有错词，继续保持',
                      style: TextStyle(fontSize: 12, color: kMuted)),
                ],
              ),
            )
          else
            ...wrong.map((w) => _wordTile(w, p)),
          if (due.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text('排队中',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
                const Spacer(),
                Text('${due.length} 个',
                    style: TextStyle(fontSize: 11, color: kMuted)),
              ],
            ),
            const SizedBox(height: 12),
            ...due.take(30).map((w) => _wordTile(w, p)),
            // 只渲染前 30 条，剩下的要说清楚还在队列里，
            // 否则「排队中 100 个」和列表里 30 条对不上，像丢数据
            if (due.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('还有 ${due.length - 30} 个在队列里，学完这批再继续',
                    style: TextStyle(fontSize: 11, color: kMuted)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _wordTile(Word w, Progress p) {
    final st = p.states[w.en];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCard,
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
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kInk)),
                    const SizedBox(width: 6),
                    if (w.phUs.isNotEmpty)
                      Text(w.phUs,
                          style: TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(w.zh,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: kMuted)),
              ],
            ),
          ),
          if (st != null && st.wrong > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: kRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('错${st.wrong}',
                  style: const TextStyle(fontSize: 10, color: kRed)),
            ),
          IconButton(
            onPressed: () => Voice.say(w.en),
            tooltip: '播放「${w.en}」发音',
            icon: Icon(Icons.volume_up_rounded, size: 18, color: kPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        ],
      ),
    );
  }
}
