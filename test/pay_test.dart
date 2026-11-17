import 'dart:convert';
import 'dart:io';

import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/backend.dart';
import 'package:app_worddeer/pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支付模块测试：本地 mock 后台，校验请求组装、凭证留存与错误透传。
void main() {
  late HttpServer server;
  final calls = <Map<String, dynamic>>[];
  final replies = <String, Map<String, dynamic>>{};

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Auth.I.resetLocal();
    calls.clear();
    replies.clear();

    server = await HttpServer.bind('127.0.0.1', 0);
    debugBaseOverride = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      calls.add({
        'path': req.uri.path,
        'method': req.method,
        'token': req.headers.value('Authorization'),
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      final path = req.uri.path;
      final reply = replies[path];
      final out = reply != null
          ? jsonEncode(reply)
          : jsonEncode({'code': 0, 'data': {}});
      req.response.headers.contentType = ContentType.json;
      req.response.write(out);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    debugBaseOverride = null;
  });

  Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
  const token = 'test-token';
  // token 由 setUp 里的 resetLocal 清掉，这里手动写回
  Future<void> login() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    Auth.I.user = const UserInfo(id: 7, username: 'deer', nickname: '小鹿');
    await Auth.I.restore();
  }

  test('下单：路径、平台、套餐码组装正确', () async {
    await login();
    replies['/api/v1/worddeer/pay/order'] = {
      'code': 0,
      'data': {'order_no': 'WD123', 'plan_code': 'vip_year', 'price': 98},
    };
    final orderNo = await Pay.I.createOrder('vip_year', 'ios', token);
    expect(orderNo, 'WD123');
    final c = calls.last;
    expect(c['path'], '/api/v1/worddeer/pay/order');
    expect(c['body'], containsPair('plan_code', 'vip_year'));
    expect(c['body'], containsPair('platform', 'ios'));
    expect(c['token'], 'Bearer $token');
  });

  test('购买占位凭证可被服务端 mock 约定解析，并留存供恢复购买', () async {
    final payload = await Pay.I.purchase('WD123', 'worddeer.vip.year');
    expect(payload.startsWith('mock:'), isTrue);
    final parts = payload.split(':');
    expect(parts, hasLength(4));
    expect(parts[3], 'worddeer.vip.year');

    final saved = await Pay.I.savedReceipts();
    expect(saved, contains(payload), reason: '购买成功后凭证要留存，恢复购买要用');
  });

  test('校验：把凭证交服务端，成功后凭证留存', () async {
    await login();
    replies['/api/v1/worddeer/pay/verify'] = {
      'code': 0,
      'data': {'tier': 2, 'expire_at': '2027-01-01 00:00:00', 'granted': true},
    };
    final r = await Pay.I.verify('WD123', 'mock:tx:tx:worddeer.vip.year', token);
    expect(r['tier'], 2);
    final c = calls.last;
    expect(c['path'], '/api/v1/worddeer/pay/verify');
    expect(c['body'],
        containsPair('payload', 'mock:tx:tx:worddeer.vip.year'));
    expect((await Pay.I.savedReceipts()), contains('mock:tx:tx:worddeer.vip.year'));
  });

  test('校验失败：服务端错误透传给用户', () async {
    await login();
    replies['/api/v1/worddeer/pay/verify'] = {
      'code': 51,
      'message': '该交易已被其他账号使用',
    };
    expect(
      () => Pay.I.verify('WD123', 'mock:tx:tx:p', token),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', '该交易已被其他账号使用')),
    );
  });

  test('恢复购买：本机留存的凭证批量上交', () async {
    await login();
    await Pay.I.purchase('o1', 'worddeer.vip.year');
    replies['/api/v1/worddeer/pay/restore'] = {
      'code': 0,
      'data': {'tier': 2, 'granted': true},
    };
    final r = await Pay.I.restore(token);
    expect(r['granted'], isTrue);
    final c = calls.last;
    expect(c['path'], '/api/v1/worddeer/pay/restore');
    final payloads = (c['body'] as Map)['payloads'] as List;
    expect(payloads, isNotEmpty);
  });

  test('恢复购买：没有历史凭证时给出可读提示', () async {
    await login();
    expect(
      () => Pay.I.restore(token),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('没有可恢复'))),
    );
  });

  test('删除账号：调专用接口，带 token', () async {
    await login();
    await Pay.I.deleteAccount(token);
    final c = calls.last;
    expect(c['path'], '/api/v1/worddeer/account/delete');
    expect(c['token'], 'Bearer $token');
  });
}
