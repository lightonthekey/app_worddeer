import 'package:flutter/material.dart';

import '../audio.dart';
import '../auth.dart';
import '../backend.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../pay.dart';
import '../progress.dart';
import '../progress_sync.dart';
import '../ui.dart';
import 'login.dart';
import 'paywall.dart';

/// 设置页：账号、数据、关于。原来散在「我的」底部的
/// 退出/清空/删除账号收进这里，避免首页一屏全是危险操作。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
                ),
              _row(
                icon: Icons.workspace_premium_outlined,
                label: '会员',
                value: Ent.I.ent.vip ? Ent.I.ent.tierName : '未开通',
                onTap: () => showPaywall(context),
              ),
            ]),
            const SizedBox(height: 20),
            _section('数据与存储'),
            _card([
              _row(
                icon: Icons.cloud_sync_outlined,
                label: '云端同步',
                value: _syncText(),
                onTap: () => ProgressSync.I.syncNow(),
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
            _section('关于'),
            _card([
              _row(icon: Icons.menu_book_outlined, label: '词库', value: bankSummary()),
              _row(
                icon: Icons.repeat_rounded,
                label: '记忆算法',
                value: '间隔重复（10 分钟 → 30 天，7 档）',
              ),
              _row(
                icon: Icons.volume_up_outlined,
                label: '发音',
                value: kAudioBase.contains('127.0.0.1') ? '本地服务（开发）' : '在线音频',
              ),
              _row(icon: Icons.info_outline_rounded, label: '版本', value: 'v$kAppVersion'),
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

  String _syncText() {
    final s = ProgressSync.I.status;
    if (s == ProgressSync.statusSyncing) return '同步中…';
    if (s == ProgressSync.statusError) return '同步失败 · 点此重试';
    if (s == ProgressSync.statusOk) return '已同步';
    return Auth.I.loggedIn ? '待同步' : '登录后可用';
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
              Divider(height: 1, thickness: 1, color: kLine, indent: 14, endIndent: 14),
          ],
        ]),
      );

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    bool danger = false,
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
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: kN4),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 16, color: kN3),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 动作

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) setState(() {});
  }

  /// 改昵称：后台暂无改名接口，先本地生效（会随会话一起持久化）
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
    await Auth.I.renameLocal(name);
    if (mounted) setState(() {});
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
        content: Text('所有单词的掌握状态和打卡记录都会被删除，且无法恢复。',
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
              if (mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text('学习记录已清空', style: TextStyle(fontSize: 13)),
                    behavior: SnackBarBehavior.floating,
                  ));
              }
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
