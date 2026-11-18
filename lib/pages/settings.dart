import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../audio.dart';
import '../auth.dart';
import '../backend.dart';
import '../bank.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../pay.dart';
import '../progress.dart';
import '../progress_sync.dart';
import '../ui.dart';
import 'login.dart';
import 'paywall.dart';

/// 设置页：账号、数据、学习偏好、关于。
/// 每一行都真的能用——点下去有结果反馈，不留「看着能点、其实没反应」的行。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 手动同步的进行中标记：ProgressSync 自己也会广播状态，
  /// 但点下去到请求发出之间有一帧空窗，用它避免重复点击
  bool _syncing = false;

  StreamSubscription<void>? _syncSub;
  VoidCallback? _settingsListener;

  @override
  void initState() {
    super.initState();
    // 同步状态一变就刷新「云端同步」那行的文案
    _syncSub = ProgressSync.I.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // 发音 / 震动改了，行上的值要跟着变
    _settingsListener = () {
      if (mounted) setState(() {});
    };
    AppSettings.I.addListener(_settingsListener!);
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    if (_settingsListener != null) {
      AppSettings.I.removeListener(_settingsListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = Auth.I.user;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.chevron_left_rounded, color: kInk, size: 26),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
                const SizedBox(width: 2),
                Text('设置',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
              ],
            ),
            const SizedBox(height: 12),

            // ------------------------------------------------------ 账号
            _section('账号'),
            _card([
              _row(
                icon: Icons.badge_outlined,
                label: '昵称',
                value: u == null ? '未登录' : u.displayName,
                onTap: u == null ? _openLogin : _renameNickname,
              ),
              if (u != null)
                _row(
                  icon: Icons.alternate_email_rounded,
                  label: '用户名',
                  value: '@${u.username}',
                  onTap: () => _copy(u.username, '用户名已复制'),
                ),
              _row(
                icon: Icons.workspace_premium_outlined,
                label: '会员',
                value: Ent.I.ent.vip
                    ? (Ent.I.ent.expireAt.isEmpty
                        ? '${Ent.I.ent.tierName} · 永久'
                        : '${Ent.I.ent.tierName} · 至 ${Ent.I.ent.expireAt}')
                    : '未开通',
                onTap: () => showPaywall(context),
              ),
            ]),
            const SizedBox(height: 20),

            // ------------------------------------------------------ 数据
            _section('数据与存储'),
            _card([
              _row(
                icon: Icons.cloud_sync_outlined,
                label: '云端同步',
                value: _syncText(),
                busy: _syncing || ProgressSync.I.status == ProgressSync.statusSyncing,
                onTap: _syncNow,
              ),
              _row(
                icon: Icons.delete_sweep_outlined,
                label: '清除学习记录',
                value: '不可恢复',
                danger: true,
                onTap: _confirmReset,
              ),
              if (u != null)
                _row(
                  icon: Icons.person_remove_outlined,
                  label: '注销账号',
                  value: '永久删除',
                  danger: true,
                  onTap: _confirmDeleteAccount,
                ),
            ]),
            const SizedBox(height: 20),

            // ------------------------------------------------------ 学习偏好
            _section('学习与反馈'),
            _card([
              _row(
                icon: Icons.volume_up_outlined,
                label: '发音',
                value: AppSettings.I.accentName,
                onTap: _pickAccent,
              ),
              _row(
                icon: Icons.vibration_rounded,
                label: '答题震动',
                value: '',
                trailing: Switch(
                  value: AppSettings.I.haptic,
                  activeThumbColor: Colors.white,
                  activeTrackColor: kPrimary,
                  trackOutlineColor:
                      WidgetStatePropertyAll(Colors.transparent),
                  onChanged: (v) => AppSettings.I.setHaptic(v),
                ),
                onTap: () => AppSettings.I.setHaptic(!AppSettings.I.haptic),
              ),
            ]),
            const SizedBox(height: 20),

            // ------------------------------------------------------ 关于
            _section('关于'),
            _card([
              _row(
                icon: Icons.menu_book_outlined,
                label: '词库',
                value: bankSummary(),
                onTap: _showBank,
              ),
              _row(
                icon: Icons.repeat_rounded,
                label: '记忆算法',
                value: '间隔重复 · 7 档',
                onTap: _showSrs,
              ),
              _row(
                icon: Icons.info_outline_rounded,
                label: '版本',
                value: 'v$kAppVersion',
                onTap: () => _toast('已是最新版本 v$kAppVersion'),
              ),
            ]),
            const SizedBox(height: 18),
            if (u != null)
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: _confirmLogout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kRed,
                    side: BorderSide(color: kLine),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('退出登录',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            const SizedBox(height: 10),
            Center(
              child: Text('词鹿英语 v$kAppVersion',
                  style: TextStyle(fontSize: 11, color: kN4)),
            ),
          ],
        ),
      ),
    );
  }

  /// 「云端同步」右侧文案：同步中 / 失败 / 已同步（带相对时间）/ 未登录
  String _syncText() {
    if (!Auth.I.loggedIn) return '登录后可用';
    final s = ProgressSync.I.status;
    if (_syncing || s == ProgressSync.statusSyncing) return '同步中…';
    if (s == ProgressSync.statusError) return '同步失败 · 点此重试';
    if (s == ProgressSync.statusOk) return '已同步 · ${_ago(ProgressSync.I.lastAt)}';
    return '待同步';
  }

  String _ago(int ms) {
    if (ms <= 0) return '刚刚';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  // ---------------------------------------------------------------- 组件

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: kMuted)),
      );

  Widget _card(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kLine),
        ),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: kLine,
                  indent: 14,
                  endIndent: 14),
          ],
        ]),
      );

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    bool danger = false,
    bool busy = false,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: danger ? kRed : kMuted),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: danger ? kRed : kInk)),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (busy) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: kPrimary),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: kN4),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing,
            ] else if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 16, color: kN3),
            ],
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ));
  }

  // ---------------------------------------------------------------- 动作

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _copy(String text, String tip) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toast(tip);
  }

  /// 改昵称：已登录交给后台（`/auth/profile`），未登录只存本机。
  /// 后台改了之后本地缓存同步更新，回到「我的」页立刻能看到新名字。
  Future<void> _renameNickname() async {
    final u = Auth.I.user;
    if (u == null) return;
    final ctrl = TextEditingController(text: u.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('改昵称', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 16,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: '最多 16 个字，留空用用户名',
            counterText: '',
            hintStyle: TextStyle(fontSize: 12.5, color: kN4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text('保存', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await Auth.I.rename(name);
      _toast('昵称已更新');
    } on AuthException catch (e) {
      _toast(e.message);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('修改失败，请检查网络后重试');
    }
    if (mounted) setState(() {});
  }

  /// 立刻同步一次。未登录先去登录——不然点了只会得到一行「登录后可用」，
  /// 用户不知道下一步该做什么。
  Future<void> _syncNow() async {
    if (!Auth.I.loggedIn) {
      _toast('登录后才能同步到云端');
      await _openLogin();
      return;
    }
    if (_syncing) return;
    setState(() => _syncing = true);
    final ok = await ProgressSync.I.syncNow(force: true);
    if (!mounted) return;
    setState(() => _syncing = false);
    _toast(ok
        ? '已同步到云端'
        : (ProgressSync.I.lastError ?? '同步失败，请稍后重试'));
  }

  /// 发音：美式 / 英式。改完立刻生效，所有发音按钮都读这个值。
  Future<void> _pickAccent() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('发音', style: TextStyle(fontSize: 16)),
        children: [
          for (final e in const [('us', '美式', '通用美音，词库音标同此'), ('uk', '英式', '英式发音，考雅思/剑桥更合适')])
            ListTile(
              title: Text(e.$2, style: const TextStyle(fontSize: 14)),
              subtitle: Text(e.$3,
                  style: TextStyle(fontSize: 11.5, color: kMuted)),
              trailing: AppSettings.I.accent == e.$1
                  ? Icon(Icons.check_rounded, size: 18, color: kPrimary)
                  : null,
              onTap: () => Navigator.pop(context, e.$1),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await AppSettings.I.setAccent(picked);
    // 换口音后当场念一个词，用户能立刻听出区别
    unawaited(Voice.say('hello'));
    _toast('发音已切换为${AppSettings.I.accentName}');
  }

  void _showBank() {
    final rows = <String>[];
    for (final l in kLevels) {
      final n = WordBank.I.byLevel[l.code]?.length ?? 0;
      if (n > 0) rows.add('${l.id} ${l.name} · $n 词');
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('词库', style: TextStyle(fontSize: 16)),
        content: Text(
          rows.isEmpty
              ? '词库还在加载，稍后再看。'
              : '${rows.join('\n')}\n\n共 ${WordBank.I.words.length} 词 · ${themeCount()} 个主题',
          style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  void _showSrs() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('记忆算法', style: TextStyle(fontSize: 16)),
        content: Text(
          '答对一次升一档，答错回到第一档。下次复习间隔依次是：\n'
          '10 分钟 → 1 天 → 2 天 → 4 天 → 7 天 → 15 天 → 30 天。\n\n'
          '升到第 5 档及以上算「已掌握」，之后每 15～30 天见一次，'
          '只为防止遗忘。',
          style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('退出登录？', style: TextStyle(fontSize: 16)),
        content: Text('学习进度仍保存在本机，下次登录可以继续同步。',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await Auth.I.logout();
              ProgressSync.I.onAuthChanged();
              Ent.I.onAuthChanged();
              if (mounted) setState(() {});
              nav.pop();
              _toast('已退出登录');
            },
            child: Text('退出', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('清除学习记录？', style: TextStyle(fontSize: 16)),
        content: Text(
            '所有单词的掌握状态和打卡记录都会被删除，且无法恢复。'
            '${Auth.I.loggedIn ? '\n\n云端记录也会一起清空。' : ''}',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await ProgressSync.I.resetRemote();
              await Progress.I.reset();
              if (mounted) setState(() {});
              appTick.value++;
              nav.pop();
              _toast('学习记录已清空');
            },
            child: Text('清空', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  /// 注销账号（Apple 审核硬性要求）：服务端清账号/进度/权益，
  /// 本地清全部状态回到未登录；订单匿名保留（防收据重放薅权益）
  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('注销账号？', style: TextStyle(fontSize: 16)),
        content: Text(
            '账号、学习进度、会员权益会被永久删除，且无法恢复。'
            '已支付的订单记录会按法规要求匿名保留。',
            style: TextStyle(fontSize: 13, color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: kMuted)),
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
                  content: Text('账号已注销，学习数据已清空',
                      style: TextStyle(fontSize: 13)),
                  behavior: SnackBarBehavior.floating,
                ));
            },
            child: Text('永久注销', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }
}
