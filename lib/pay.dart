import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// 支付：下单 →（客户端扣款）→ 凭证校验 → 发权益，全部走服务端判定。
///
/// 当前阶段（第 5 项，沙箱联调）：扣款用 mock 凭证占位。
/// 接真实 IAP 时只改 [purchase]：换成 StoreKit/in_app_purchase 拉起支付，
/// 把 App 返回的 JWS 凭证交给 [verify]，其余流程不变。
class Pay {
  Pay._();
  static final Pay I = Pay._();

  /// 本机购买过的凭证（恢复购买用）。真实 IAP 下 StoreKit 能取回历史交易，
  /// 沙箱下把每次 verify 成功的凭证记在这里。
  static const _kReceipts = 'pay_receipts';

  /// 当前支付平台标识（服务端按它记订单来源）
  String platformName() =>
      Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'mp');

  /// 创建订单，返回 order_no
  Future<String> createOrder(String planCode, String platform, String token) async {
    final r = await apiJson('/api/v1/worddeer/pay/order',
        body: {'plan_code': planCode, 'platform': platform}, token: token);
    return r['order_no'] as String? ?? '';
  }

  /// 发起扣款（占位）：真实 IAP 在这里调起支付并返回凭证。
  /// 沙箱约定：凭证格式 `mock:txid:original:product_id`，服务端仅
  /// pay.sandbox=true 时接受。
  Future<String> purchase(String orderNo, String productId) async {
    final tx = 'mock:p${DateTime.now().millisecondsSinceEpoch}'
        ':o${DateTime.now().millisecondsSinceEpoch}:$productId';
    await _rememberReceipt(tx);
    return tx;
  }

  /// 校验凭证并发放权益；成功后调用方应刷新 Entitlement
  Future<Map<String, dynamic>> verify(String orderNo, String payload, String token) async {
    final r = await apiJson('/api/v1/worddeer/pay/verify',
        body: {'order_no': orderNo, 'payload': payload}, token: token);
    await _rememberReceipt(payload);
    return r;
  }

  /// 恢复购买：把本机保存过的凭证批量交给服务端补录权益
  Future<Map<String, dynamic>> restore(String token) async {
    final receipts = await savedReceipts();
    if (receipts.isEmpty) {
      throw const ApiException('本机没有可恢复的购买记录');
    }
    return apiJson('/api/v1/worddeer/pay/restore',
        body: {'payloads': receipts}, token: token);
  }

  /// 删除账号（Apple 硬性要求）：服务端清账号/进度/权益，订单匿名保留
  Future<void> deleteAccount(String token) =>
      apiJson('/api/v1/worddeer/account/delete', body: {}, token: token);

  Future<List<String>> savedReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kReceipts) ?? <String>[];
  }

  Future<void> _rememberReceipt(String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kReceipts) ?? <String>[];
      if (!list.contains(payload)) {
        list.add(payload);
        await prefs.setStringList(_kReceipts, list);
      }
    } catch (_) {
      // 记凭证失败不影响购买主流程（真机上有 StoreKit 兜底）
    }
  }
}
