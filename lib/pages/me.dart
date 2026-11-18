import 'package:flutter/material.dart';

import '../audio.dart';
import '../auth.dart';
import '../backend.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../progress.dart';
import '../pay.dart';
import '../progress_sync.dart';
import '../ui.dart';
import 'login.dart';
import 'paywall.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  @override
  Widget build(BuildContext context) {
    // 学完词切回「我的」时，学过 / 已掌握 / 连续天要跟着变。
    // IndexedStack 会保活页面状态，不监听 appTick 就永远停在进入那一刻的数字。
    return ValueListenableBuilder<int>(
      valueListenable: appTick,
      builder: (_, _, _) {
        final p = Progress.I;
        return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text('我的',
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 18),
          _accountCard(),
          const SizedBox(height: 12),
          _memberBanner(),
          const SizedBox(height: 12),
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
                  value: p.newPerDay.clamp(5, Ent.I.ent.limits.newPerDayMax),
                  min: 5,
                  max: Ent.I.ent.limits.newPerDayMax,
                  step: 5,
                  onChanged: (v) => setState(() => p.newPerDay = v),
                  onEnd: () {
                    p.save();
                    ProgressSync.I.markCurriculum();
                  },
                ),
                const Divider(height: 1, color: kLine),
                _slider(
                  label: '每次复习上限',
                  value: p.reviewPerDay.clamp(10, Ent.I.ent.limits.reviewPerDayMax),
                  min: 10,
                  max: Ent.I.ent.limits.reviewPerDayMax,
                  step: 10,
                  onChanged: (v) => setState(() => p.reviewPerDay = v),
                  onEnd: () {
                    p.save();
                    ProgressSync.I.markCurriculum();
                  },
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
                _row('词库', bankSummary()),
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
          if (Auth.I.loggedIn)
            TextButton(
              onPressed: _confirmDeleteAccount,
              child: const Text('删除账号',
                  style: TextStyle(fontSize: 13, color: kRed)),
            ),
          Center(
            child: Text('词鹿英语 v$kAppVersion',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFC4C0D6))),
          ),
        ],
      ),
    );
      },
    );
  }

  /// 账号卡：未登录显示登录入口，已登录显示昵称与退出按钮
  Widget _accountCard() {
    final u = Auth.I.user;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: kPrimary50,
            child: Text(
              u == null ? '👤' : u.initial,
              style: const TextStyle(fontSize: 16, color: kPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: u == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('未登录',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 2),
                      const Text('登录后学习进度换机不丢',
                          style: TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(u.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: kInk)),
                          ),
                          if (Ent.I.vip) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: kAmber50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(Ent.I.ent.tierName,
                                  style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: kAmber)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('@${u.username}',
                              style: const TextStyle(fontSize: 12, color: kMuted)),
                          const SizedBox(width: 8),
                          Flexible(child: _syncLine()),
                        ],
                      ),
                    ],
                  ),
          ),
          TextButton(
            onPressed: u == null ? _openLogin : _confirmLogout,
            child: Text(
              u == null ? '登录 / 注册' : '退出登录',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: u == null ? kPrimary : kMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// 会员横幅：免费版是开通入口，会员是有效期说明。价格与权益全部来自后台。
  Widget _memberBanner() {
    final ent = Ent.I.ent;
    final gold = ent.vip;
    return GestureDetector(
      onTap: () => showPaywall(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gold
                ? const [Color(0xFFFFF6E2), Color(0xFFFFEFD0)]
                : const [Color(0xFF6D5AE0), Color(0xFF4A41C4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_rounded,
                size: 22, color: gold ? kAmber : const Color(0xFFF7D488)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ent.vip ? ent.tierName : '开通会员',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: gold ? kInk : Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ent.vip
                        ? (ent.expireAt.isEmpty
                            ? '永久有效 · 全部内容已开放'
                            : '有效期至 ${ent.expireAt}')
                        : '5 个级别 · ${themeCount()} 个主题 · 全部关卡',
                    style: TextStyle(
                        fontSize: 11,
                        color: gold ? kMuted : Colors.white70),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: gold ? Colors.white : const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ent.vip ? '查看权益' : '了解详情',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: gold ? kAmber : Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 账号卡里的同步状态：同步中 / 已同步 · x 分钟前 / 失败可点重试
  Widget _syncLine() {
    return StreamBuilder<void>(
      stream: ProgressSync.I.changes,
      builder: (_, _) {
        final s = ProgressSync.I.status;
        if (s == ProgressSync.statusSyncing) {
          return const Text('同步中…',
              style: TextStyle(fontSize: 11, color: kMuted));
        }
        if (s == ProgressSync.statusError) {
          return GestureDetector(
            onTap: () => ProgressSync.I.syncNow(),
            child: const Text('同步失败 · 点此重试',
                style: TextStyle(fontSize: 11, color: kRed)),
          );
        }
        if (s == ProgressSync.statusOk) {
          return Text('已同步 · ${_ago(ProgressSync.I.lastAt)}',
              style: const TextStyle(fontSize: 11, color: kMuted));
        }
        return const Text('本地进度',
            style: TextStyle(fontSize: 11, color: kMuted));
      },
    );
  }

  String _ago(int ms) {
    if (ms <= 0) return '刚刚';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) setState(() {});
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('退出登录？', style: TextStyle(fontSize: 16)),
        content: const Text('学习进度仍保存在本机，下次登录可以继续同步。',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await Auth.I.logout();
              ProgressSync.I.onAuthChanged();
              Ent.I.onAuthChanged();
              if (mounted) setState(() {});
              nav.pop();
            },
            child: const Text('退出', style: TextStyle(color: kRed)),
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
              await ProgressSync.I.resetRemote();
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

  /// 删除账号（Apple 审核硬性要求）：服务端清账号/进度/权益，
  /// 本地清全部状态回到未登录；订单匿名保留（防收据重放薅权益）
  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除账号？', style: TextStyle(fontSize: 16)),
        content: const Text(
            '账号、学习进度、会员权益会被永久删除，且无法恢复。'
            '已支付的订单记录会按法规要求匿名保留。',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Pay.I.deleteAccount(Auth.I.token);
              } on ApiException catch (e) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text(e.message, style: const TextStyle(fontSize: 13)),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xFF3A3550),
                  ));
                if (mounted) nav.pop();
                return;
              } catch (_) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text('删除失败，请检查网络后重试',
                        style: TextStyle(fontSize: 13)),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF3A3550),
                  ));
                if (mounted) nav.pop();
                return;
              }
              await Auth.I.resetLocal();
              ProgressSync.I.onAuthChanged();
              Ent.I.onAuthChanged();
              if (mounted) setState(() {});
              appTick.value++;
              nav.pop();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('账号已删除，学习数据已清空',
                      style: TextStyle(fontSize: 13)),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Color(0xFF3A3550),
                ));
            },
            child: const Text('永久删除', style: TextStyle(color: kRed)),
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
