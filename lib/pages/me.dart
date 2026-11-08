import 'package:flutter/material.dart';

import '../audio.dart';
import '../progress.dart';
import '../ui.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  @override
  Widget build(BuildContext context) {
    final p = Progress.I;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text('我的',
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kLine),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('${p.learnedCount}', '学过'),
                _divider(),
                _stat('${p.masteredCount}', '已掌握'),
                _divider(),
                _stat('${p.streak}', '连续天'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _Section('学习设置'),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kLine),
            ),
            child: Column(
              children: [
                _slider(
                  label: '每天新词',
                  value: p.newPerDay,
                  min: 5,
                  max: 40,
                  step: 5,
                  onChanged: (v) => setState(() => p.newPerDay = v),
                  onEnd: p.save,
                ),
                const Divider(height: 1, color: kLine),
                _slider(
                  label: '每次复习上限',
                  value: p.reviewPerDay,
                  min: 10,
                  max: 100,
                  step: 10,
                  onChanged: (v) => setState(() => p.reviewPerDay = v),
                  onEnd: p.save,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _Section('关于'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('词库', '7201 词 · A1–C1 · 60 主题'),
                _row('记忆算法', '间隔重复（10 分钟 → 30 天，7 档）'),
                _row('发音',
                    kAudioBase.contains('127.0.0.1') ? '本地服务（开发）' : '在线音频'),
                const SizedBox(height: 6),
                const Text('打包上线前需替换为自有授权音频，并把 AUDIO_BASE 指向正式域名。',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB8B4C8), height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _confirmReset,
            child: const Text('清空学习记录',
                style: TextStyle(fontSize: 13, color: kRed)),
          ),
          const Center(
            child: Text('词鹿英语 v0.1 · MVP',
                style: TextStyle(fontSize: 11, color: Color(0xFFC4C0D6))),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    required VoidCallback onEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 13.5, color: kInk)),
              const Spacer(),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kPrimary)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: kPrimary,
              inactiveTrackColor: const Color(0xFFF0EEF8),
              thumbColor: kPrimary,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: ((max - min) ~/ step).clamp(1, 100),
              onChanged: (v) => onChanged(v.round()),
              onChangeEnd: (_) => onEnd(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String v, String label) {
    return Column(
      children: [
        Text(v,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: kLine);

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 68,
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: kMuted))),
          Expanded(
            child: Text(v,
                style: const TextStyle(fontSize: 12.5, color: kInk, height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('清空学习记录？', style: TextStyle(fontSize: 16)),
        content: const Text('所有单词的掌握状态和打卡记录都会被删除，且无法恢复。',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await Progress.I.reset();
              if (mounted) {
                setState(() {});
                appTick.value++;
              }
              nav.pop();
            },
            child: const Text('清空', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
    );
  }
}
