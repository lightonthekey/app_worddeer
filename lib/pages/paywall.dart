import 'dart:async';

import 'package:flutter/material.dart';

import '../auth.dart';
import '../entitlement.dart';
import '../ui.dart';

/// 付费墙。全 App 的价格、权益、解锁额度都来自 [Ent]，这里只负责展示与引导。
///
/// 当前阶段（第 4 项）只做"界面 + 权益校验"，点开通会提示内购尚未接入；
/// 第 5 项接 IAP 后，把 `_buy` 里的提示换成调起支付、支付回调后 refresh 即可。
Future<void> showPaywall(BuildContext context, {String? reason}) {
  // 打开时顺手拉一次：用户可能刚在别的设备开通，或者后台刚调过价
  Ent.I.refresh();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaywallSheet(reason: reason),
  );
}

class _PaywallSheet extends StatefulWidget {
  final String? reason;
  const _PaywallSheet({this.reason});

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  int _sel = -1;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Ent.I.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ent = Ent.I.ent;
    final plans = ent.plans;
    if (_sel < 0 && plans.isNotEmpty) {
      // 默认选中"最划算"的：有角标的优先，否则年度优先
      var idx = plans.indexWhere((p) => p.badge.isNotEmpty);
      if (idx < 0) idx = plans.indexWhere((p) => p.periodDays >= 360);
      _sel = idx < 0 ? 0 : idx;
    }
    final plan = (_sel >= 0 && _sel < plans.length) ? plans[_sel] : null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kLine,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _header(ent),
              const SizedBox(height: 16),
              _benefits(ent, plan),
              const SizedBox(height: 16),
              if (ent.vip) _memberBox(ent) else _planList(plans),
              const SizedBox(height: 18),
              if (!ent.vip) _buyButton(plan),
              const SizedBox(height: 10),
              _footNote(ent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Entitlement ent) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFF7D488), Color(0xFFE0A02A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ent.vip ? '你已是${ent.tierName}' : '解锁全部课程',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
              ),
              const SizedBox(height: 3),
              Text(
                widget.reason ??
                    (ent.vip
                        ? '感谢支持，所有内容已为你开放'
                        : '5 个级别 · 60 个主题 · 全部关卡'),
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, size: 20, color: kMuted),
        ),
      ],
    );
  }

  /// 权益对比：优先用套餐自带的 desc（后台可改），没有就用标准四条
  Widget _benefits(Entitlement ent, PlanInfo? plan) {
    final items = plan?.desc.isNotEmpty == true
        ? plan!.desc
        : (ent.vip
            ? const ['全部级别全部关卡', '全部主题解锁', '离线发音', '后续新增内容免费']
            : const ['5 个级别全部关卡', '60 个主题全部解锁', '每天最多 40 个新词', '离线发音']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 17, color: kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s,
                      style: const TextStyle(
                          fontSize: 13, height: 1.35, color: kInk)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _planList(List<PlanInfo> plans) {
    if (plans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text('暂时拿不到套餐信息，请检查网络后重试',
                  style: TextStyle(fontSize: 12.5, color: kMuted)),
            ),
            TextButton(
              onPressed: () => Ent.I.refresh(),
              child: const Text('重试', style: TextStyle(color: kPrimary)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < plans.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _planTile(plans[i], i),
        ],
      ],
    );
  }

  Widget _planTile(PlanInfo p, int i) {
    final on = i == _sel;
    return GestureDetector(
      onTap: () => setState(() => _sel = i),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: on ? kPrimary50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? kPrimary : kLine, width: on ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(
              on
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 19,
              color: on ? kPrimary : const Color(0xFFC8C4DA),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                      if (p.badge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: kAmber50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(p.badge,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: kAmber)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.perMonthText.isEmpty
                        ? p.periodText
                        : '${p.periodText} · ${p.perMonthText}',
                    style: const TextStyle(fontSize: 11, color: kMuted),
                  ),
                ],
              ),
            ),
            Text(p.priceText,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
          ],
        ),
      ),
    );
  }

  Widget _memberBox(Entitlement ent) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kGreen50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ent.tierName,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: kGreen)),
            const SizedBox(height: 4),
            Text(
              ent.expireAt.isEmpty ? '永久有效' : '有效期至 ${ent.expireAt}',
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ),
      );

  Widget _buyButton(PlanInfo? plan) {
    final label = plan == null ? '暂不可购买' : '立即开通 ${plan.priceText}';
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: kPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: plan == null ? null : () => _buy(plan),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _buy(PlanInfo plan) {
    // 第 5 项接 IAP：这里换成调起 App Store / 微信支付，
    // 支付成功回调后端写 account_profile.role/expire_at，再 Ent.I.refresh()
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          Auth.I.loggedIn
              ? '内购即将开放（${plan.name}），开通后会立即生效'
              : '请先登录，再开通${plan.name}',
          style: const TextStyle(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF3A3550),
      ));
    if (!Auth.I.loggedIn) {
      Navigator.of(context).pop();
    }
  }

  Widget _footNote(Entitlement ent) {
    return Column(
      children: [
        Text(
          ent.vip
              ? '到期后自动回到免费版，学习记录不受影响'
              : '开通即表示同意《会员服务协议》；虚拟商品不支持退款',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFFB8B4C8), height: 1.5),
        ),
        if (!ent.vip)
          TextButton(
            onPressed: () {
              Ent.I.refresh();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('恢复购买将在接入内购后可用', style: TextStyle(fontSize: 13)),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Color(0xFF3A3550),
                ));
            },
            child: const Text('恢复购买',
                style: TextStyle(fontSize: 12, color: kMuted)),
          ),
      ],
    );
  }
}
