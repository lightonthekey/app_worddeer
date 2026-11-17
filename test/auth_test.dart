import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/backend.dart';

/// 账号客户端逻辑测试：起本地 mock 后台，走真实 HTTP。
/// 覆盖注册、登录、错误处理、会话恢复（token 失效清空）、登出。
///
/// 注意：flutter test 默认跑在 FakeAsync 假时钟里，真实 socket 不会推进，
/// 所以每个用例都必须包在 tester.runAsync 里。
void main() {
  late HttpServer server;

  Map<String, dynamic> user([String nickname = '小鹿']) =>
      {'id': 7, 'username': 'deer', 'nickname': nickname, 'role': 1};

  Map<String, dynamic> session(String token, [String nickname = '小鹿']) =>
      {'token': token, 'expire_at': '2026-12-17 12:00:00', 'user': user(nickname)};

  setUp(() async {
    // flutter_test 默认把所有 HttpClient 劫持成 400（连真实网络），
    // 这里解掉，让用例走真实 socket 访问本地 mock 服务
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Auth.I.resetLocal(); // 清掉上一个用例残留的单例登录态
    server = await HttpServer.bind('127.0.0.1', 0);
    debugBaseOverride = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final path = req.uri.path;
      String ok(Object data) => jsonEncode({'code': 0, 'data': data});
      String fail(String msg) => jsonEncode({'code': 50, 'message': msg});

      Future<void> reply(int status, String text) async {
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(text);
        await req.response.close();
      }

      switch (path) {
        case '/api/v1/worddeer/auth/register':
          final j = jsonDecode(body) as Map;
          if (j['username'] == 'taken') return reply(200, fail('用户名已被占用'));
          return reply(200, ok(session('reg-token', (j['nickname'] as String?) ?? '小鹿')));
        case '/api/v1/worddeer/auth/login':
          final j = jsonDecode(body) as Map;
          if (j['username'] == 'deer' && j['password'] == 'pass123') {
            return reply(200, ok(session('login-token')));
          }
          return reply(200, fail('用户名或密码错误'));
        case '/api/v1/worddeer/auth/me':
          if (req.headers.value('Authorization') == 'Bearer good-token') {
            return reply(200, ok(user()));
          }
          return reply(401, fail('登录已过期'));
        case '/api/v1/worddeer/auth/logout':
          return reply(200, ok({}));
        default:
          return reply(404, fail('not found'));
      }
    });
  });

  tearDown(() async {
    debugBaseOverride = null;
    await server.close(force: true);
  });

  testWidgets('登录成功：token 与用户信息持久化', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      expect(Auth.I.loggedIn, isTrue);
      expect(Auth.I.user!.username, 'deer');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'login-token');
      expect(prefs.getString('auth_user_json'), contains('deer'));
    });
  });

  testWidgets('登录失败：抛出后台返回的错误文案', (tester) async {
    await tester.runAsync(() async {
      try {
        await Auth.I.login('deer', 'bad');
        fail('应当抛 AuthException');
      } on AuthException catch (e) {
        expect(e.message, '用户名或密码错误');
      }
      expect(Auth.I.loggedIn, isFalse);
    });
  });

  testWidgets('注册重名：透传后台文案', (tester) async {
    await tester.runAsync(() async {
      try {
        await Auth.I.register('taken', 'pass123', '');
        fail('应当抛 AuthException');
      } on AuthException catch (e) {
        expect(e.message, '用户名已被占用');
      }
    });
  });

  testWidgets('注册成功即登录', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.register('newdeer', 'pass123', '新手小鹿');
      expect(Auth.I.loggedIn, isTrue);
      expect(Auth.I.user!.nickname, '新手小鹿');
    });
  });

  testWidgets('会话恢复：token 有效则登录态回归', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'good-token',
        'auth_user_json': jsonEncode(user()),
      });
      await Auth.I.restore();
      expect(Auth.I.loggedIn, isTrue);
      expect(Auth.I.user!.username, 'deer');
    });
  });

  testWidgets('会话恢复：token 失效则清空登录态', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'expired-token',
        'auth_user_json': jsonEncode(user()),
      });
      await Auth.I.restore();
      expect(Auth.I.loggedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
    });
  });

  testWidgets('登出：本地登录态清空', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      await Auth.I.logout();
      expect(Auth.I.loggedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
    });
  });

  testWidgets('网络不可达：给用户看得懂的报错', (tester) async {
    await tester.runAsync(() async {
      debugBaseOverride = 'http://127.0.0.1:1'; // 不存在的端口
      try {
        await Auth.I.login('deer', 'pass123');
        fail('应当抛 AuthException');
      } on AuthException catch (e) {
        expect(e.message, contains('连不上服务器'));
      }
    });
  });
}
