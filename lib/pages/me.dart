import 'package:flutter/material.dart';

import '../auth.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../progress.dart';
import '../progress_sync.dart';
import '../theme.dart';
import '../ui.dart';
import 'login.dart';
import 'paywall.dart';
import 'settings.dart';

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
    // 主题换了也要重建，所以再套一层 AppTheme 监听。
    return ValueListenableBuilder<int>(
      valueListenable: appTick,
      builder: (_, _, _) => AnimatedBuilder(
        animation: AppTheme.I,
        builder: (_, _) {
          final p = Progress.I;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                Row(
                  children: [
                    Text('我的',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const Spacer(),
                    _settingsButton(),
                  ],
                ),
                const SizedBox(height: 14),
                _accountCard(),
                const SizedBox(height: 12),
                _memberBanner(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
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
                const SizedBox(height: 22),
                const _Section('外观主题'),
                _themeCard(),
                const SizedBox(height: 22),
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
                      Divider(height: 1, color: kLine),
                      _slider(
                        label: '每次复习上限',
                        value: p.reviewPerDay
                            .clamp(10, Ent.I.ent.limits.reviewPerDayMax),
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
                const SizedBox(height: 18),
                Center(
                  child: Text('词鹿英语 v$kAppVersion',
                      style: TextStyle(fontSize: 11, color: kN4)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 右上角设置入口：昵称 / 账号 / 数据 / 关于都在里面
  Widget _settingsButton() {
    return GestureDetector(
      onTap: _openSettings,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: kLine),
        ),
        child: Icon(Icons.settings_outlined, size: 18, color: kN4),
      ),
    );
  }

  // ---------------------------------------------------------------- 主题

  Widget _themeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('换颜色不影响学习记录',
                  style: TextStyle(fontSize: 11, color: kMuted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: kPrimary50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(AppTheme.I.pal.name,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: kPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (_, box) {
            const gap = 8.0;
            final w = (box.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in kPalettes)
                  _ThemeTile(
                    palette: t,
                    width: w,
                    selected: t.key == AppTheme.I.key,
                    onTap: () => AppTheme.I.set(t.key),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 账号

  /// 账号卡：未登录显示登录入口，已登录显示昵称与登录名
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
              style: TextStyle(fontSize: 16, color: kPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: u == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('未登录',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                      const SizedBox(height: 2),
                      Text('登录后学习进度换机不丢',
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
                                style: TextStyle(
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
                              style: TextStyle(fontSize: 12, color: kMuted)),
                          const SizedBox(width: 8),
                          Flexible(child: _syncLine()),
                        ],
                      ),
                    ],
                  ),
          ),
          TextButton(
            onPressed: u == null ? _openLogin : _openSettings,
            child: Text(
              u == null ? '登录 / 注册' : '编辑资料',
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
                : [kHeroA, kHeroB],
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
                        fontSize: 11, color: gold ? kMuted : Colors.white70),
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

  /// 账号卡里的同步状态：同步中 / 已同步 / 失败可点重试
  Widget _syncLine() {
    return StreamBuilder<void>(
      stream: ProgressSync.I.changes,
      builder: (_, _) {
        final s = ProgressSync.I.status;
        if (s == ProgressSync.statusSyncing) {
          return Text('同步中…', style: TextStyle(fontSize: 11, color: kMuted));
        }
        if (s == ProgressSync.statusError) {
          return GestureDetector(
            onTap: () => ProgressSync.I.syncNow(),
            child: Text('同步失败 · 点此重试',
                style: TextStyle(fontSize: 11, color: kRed)),
          );
        }
        if (s == ProgressSync.statusOk) {
          return Text('已同步 · ${_ago(ProgressSync.I.lastAt)}',
              style: TextStyle(fontSize: 11, color: kMuted));
        }
        return Text('本地进度', style: TextStyle(fontSize: 11, color: kMuted));
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (mounted) setState(() {});
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
              Text(label, style: TextStyle(fontSize: 13.5, color: kInk)),
              const Spacer(),
              Text('$value',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kPrimary)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: kPrimary,
              inactiveTrackColor: kTrack,
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
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: kPrimaryDeep)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: kLine);
}

/// 一个主题选项：双色圆点 + 名字 + 一句定位
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.palette,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? kPrimary50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? kPrimary : kLine,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [palette.pri, palette.deep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: palette.soft, spreadRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(palette.name,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                const SizedBox(height: 1),
                Text(palette.tag,
                    style: TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
            if (selected)
              Positioned(
                top: -4,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 9, color: Colors.white),
                ),
              ),
          ],
        ),
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
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
    );
  }
}
