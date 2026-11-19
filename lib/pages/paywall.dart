import 'dart:async';

import 'package:flutter/material.dart';

import '../auth.dart';
import '../backend.dart';
import '../curriculum.dart';
import '../entitlement.dart';
import '../legal.dart';
import '../pay.dart';
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
  bool _busy = false;
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
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
              ),
              const SizedBox(height: 3),
              Text(
                widget.reason ??
                    (ent.vip
                        ? '感谢支持，所有内容已为你开放'
                        : '5 个级别 · ${themeCount()} 个主题 · 全部关卡'),
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, size: 20, color: kMuted),
        ),
      ],
    );
  }

  /// 权益对比：优先用套餐自带的 desc（后台可改），没有就用标准四条。
  ///
  /// 这里不写死数字：主题数按当前词库算，新词上限只说「提升」——
  /// 后端调整额度后，写死的「60 个主题 / 40 个新词」就成了假宣传。
  /// 也不写「离线发音」：发音目前是在线音频，没有做离线缓存。
  Widget _benefits(Entitlement ent, PlanInfo? plan) {
    final items = plan?.desc.isNotEmpty == true
        ? plan!.desc
        : (ent.vip
            ? const ['全部级别全部关卡', '全部主题解锁', '高清真人发音', '后续新增内容免费']
            : [
                '5 个级别全部关卡',
                '${themeCount()} 个主题全部解锁',
                '每天新词额度提升',
                '高清真人发音',
              ]);
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
                      style: TextStyle(
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
            Expanded(
              child: Text('暂时拿不到套餐信息，请检查网络后重试',
                  style: TextStyle(fontSize: 12.5, color: kMuted)),
            ),
            TextButton(
              onPressed: () => Ent.I.refresh(),
              child: Text('重试', style: TextStyle(color: kPrimary)),
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
              color: on ? kPrimary : kN3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(p.name,
                          style: TextStyle(
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
                    style: TextStyle(fontSize: 11, color: kMuted),
                  ),
                ],
              ),
            ),
            Text(p.priceText,
                style: TextStyle(
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
              style: TextStyle(fontSize: 12, color: kMuted),
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
        onPressed: plan == null || _busy ? null : () => _buy(plan),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _toast(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? kGreen : kInk,
      ));
  }

  /// 开通：下单 →（扣款）→ 凭证校验 → 刷新权益。
  /// 全程服务端判定，客户端任何一步失败都拿不到会员。
  Future<void> _buy(PlanInfo plan) async {
    if (!Auth.I.loggedIn) {
      _toast('请先登录，再开通${plan.name}');
      Navigator.of(context).pop();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = Auth.I.token;
      final orderNo =
          await Pay.I.createOrder(plan.code, Pay.I.platformName(), token);
      // 真实 IAP：这里调起 StoreKit/微信支付，拿支付凭证
      final payload = await Pay.I.purchase(orderNo, plan.productId);
      final r = await Pay.I.verify(orderNo, payload, token);
      await Ent.I.refresh();
      if (!mounted) return;
      final expire = r['expire_at'] as String? ?? '';
      Navigator.of(context).pop();
      _toast(
        expire.isEmpty ? '已开通${plan.name}，永久有效' : '已开通${plan.name}，有效期至 $expire',
        ok: true,
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('开通失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 恢复购买：换机/重装后把本机记录过的凭证交回服务端补录权益
  Future<void> _restore() async {
    if (!Auth.I.loggedIn) {
      _toast('请先登录后再恢复购买');
      Navigator.of(context).pop();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Pay.I.restore(Auth.I.token);
      await Ent.I.refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(Ent.I.ent.vip
          ? '已恢复${Ent.I.ent.tierName}，欢迎回来'
          : '没有找到有效购买记录', ok: Ent.I.ent.vip);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('恢复失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 底部说明。Apple 3.1.2 要求付费页内直接呈现：订阅周期与续订规则、
  /// 取消方式，以及**可点击的**隐私政策与用户协议（EULA）链接——
  /// 只写「开通即表示同意《会员服务协议》」而对不上任何链接，是常见被拒点。
  Widget _footNote(Entitlement ent) {
    return Column(
      children: [
        Text(
          ent.vip
              ? '到期后自动回到免费版，学习记录不受影响'
              : '订阅为自动续期：到期前 24 小时内自动扣费，'
                  '可在「设置 → Apple ID → 订阅」中随时取消，取消后当期仍然有效',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: kN3, height: 1.5),
        ),
        if (!ent.vip) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _legalLink('隐私政策', kPrivacyUrl),
              Text(' · ', style: TextStyle(fontSize: 11, color: kN3)),
              _legalLink('用户协议', kTermsUrl),
              Text(' · ', style: TextStyle(fontSize: 11, color: kN3)),
              _legalLink('帮助', kSupportUrl),
            ],
          ),
          TextButton(
            onPressed: _busy ? null : () => _restore(),
            child: Text('恢复购买',
                style: TextStyle(fontSize: 12, color: kMuted)),
          ),
        ],
      ],
    );
  }

  /// 付费页里的法务链接：小字 + 下划线，点开系统浏览器
  Widget _legalLink(String text, String url) {
    return GestureDetector(
      onTap: () async {
        final ok = await openLegal(url);
        if (!ok) _toast('链接已复制，可粘贴到浏览器打开');
      },
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: kMuted,
          decoration: TextDecoration.underline,
          decorationColor: kN3,
        ),
      ),
    );
  }
}
