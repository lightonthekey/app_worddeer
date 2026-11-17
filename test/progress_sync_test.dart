import 'dart:convert';
import 'dart:io';

import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/backend.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/progress.dart';
import 'package:app_worddeer/progress_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 进度云同步测试：纯合并规则 + 真实 HTTP（本地 mock 后台）。
///
/// 和 auth_test 一样必须 `HttpOverrides.global = null` + `tester.runAsync`，
/// 否则 HttpClient 被 flutter_test 劫持、真实 socket 推进不了。
void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> syncBodies;
  Map<String, dynamic>? syncReply;
  bool resetCalled = false;

  Map<String, dynamic> user() =>
      {'id': 7, 'username': 'deer', 'nickname': '小鹿', 'role': 1};

  void clearState() {
    Progress.I.states.clear();
    Progress.I.streak = 0;
    Progress.I.lastActiveDay = '';
    Progress.I.newPerDay = 10;
    Progress.I.reviewPerDay = 40;
    Progress.I.updatedAt = 0;

    Curriculum.I.passed.clear();
    Curriculum.I.part.clear();
    Curriculum.I.themes.clear();
    Curriculum.I.curLv = 'A1';
    Curriculum.I.todayWords = 0;
    Curriculum.I.dayKey = '';
    Curriculum.I.updatedAt = 0;

    ProgressSync.I.resetForTest();
  }

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Auth.I.resetLocal();
    clearState();
    syncBodies = [];
    syncReply = null;
    resetCalled = false;

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
        case '/api/v1/worddeer/auth/login':
          return reply(200, ok({
            'token': 'login-token',
            'expire_at': '2026-12-17 12:00:00',
            'user': user(),
          }));
        case '/api/v1/worddeer/progress/sync':
          syncBodies.add(jsonDecode(body) as Map<String, dynamic>);
          return reply(200, ok(syncReply ?? {'server_time': 111, 'saved': 0, 'cards': []}));
        case '/api/v1/worddeer/progress/reset':
          resetCalled = true;
          return reply(200, ok({}));
        default:
          return reply(404, fail('not found'));
      }
    });

    await ProgressSync.I.init();
  });

  tearDown(() async {
    ProgressSync.I.resetForTest();
    debugBaseOverride = null;
    await server.close(force: true);
  });

  // ------------------------------------------------------------ 合并规则

  test('合并：计数取大，档位跟最后作答更晚的一方', () {
    final older = CardState(box: 0, due: 1, seen: 9, right: 1, wrong: 8, last: 1000);
    final newer = CardState(box: 4, due: 9999, seen: 3, right: 3, wrong: 0, last: 2000);
    final m = CardState.merge(newer, older);
    expect(m.box, 4, reason: '档位不能被更早的记录覆盖');
    expect(m.due, 9999);
    expect(m.seen, 9, reason: '计数只增不减');
    expect(m.wrong, 8);
    expect(m.last, 2000);

    // 反过来传入顺序不影响结果
    final m2 = CardState.merge(older, newer);
    expect(m2.box, 4);
    expect(m2.seen, 9);
  });

  // ------------------------------------------------------------ 首同步

  testWidgets('首次同步：本机全部进度都推上去，并带回服务端快照', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      final now = DateTime.now().millisecondsSinceEpoch;
      Progress.I.states['apple'] = CardState(box: 3, due: now, seen: 5, right: 5, last: now);
      Progress.I.states['banana'] = CardState(box: 1, due: now, seen: 2, right: 1, wrong: 1, last: now);
      Progress.I.streak = 3;
      Curriculum.I.markPassed('A1', 'U1');
      Curriculum.I.markTheme('A1', 0, 12);

      syncReply = {
        'server_time': 111,
        'saved': 2,
        'cards': [
          {'w': 'cherry', 'b': 2, 'd': now, 's': 4, 'r': 4, 'x': 0, 't': now - 5000},
        ],
        'curriculum': {
          'level': 'A2', 'today': 40, 'day': '2026-11-17', 'streak': 9,
          'last_day': '2026-11-17', 'new_per_day': 10, 'review_per_day': 40,
          'ts': now + 10000, 'passed': ['A1:U2'], 'part': {'A1:U3': 32},
          'themes': {'A1:t1': 5},
        },
      };

      final done = await ProgressSync.I.syncNow();
      expect(done, isTrue);

      final body = syncBodies.first;
      expect(body['since'], 0);
      expect(body['pull'], isTrue);
      expect((body['cards'] as List).length, 2);
      final cur = body['curriculum'] as Map;
      expect(cur['passed'], contains('A1:U1'));
      expect(cur['themes']['A1:t0'], 12);
      expect(cur['streak'], 3);

      // 服务端快照合并进本地
      expect(Progress.I.states.containsKey('cherry'), isTrue);
      expect(Progress.I.streak, 9, reason: 'streak 取大');
      expect(Curriculum.I.passed.keys, containsAll(['A1:U1', 'A1:U2']));
      expect(Curriculum.I.part['A1:U3'], 32);
      expect(Curriculum.I.themes['A1:t1'], 5);
      expect(Curriculum.I.curLv, 'A2', reason: '服务端更新，级别跟它走');
      expect(ProgressSync.I.status, ProgressSync.statusOk);

      // 游标按账号落盘
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('progress_sync_at_7'), 111);
    });
  });

  // ------------------------------------------------------------ 增量

  testWidgets('增量同步：只推改动过的单词，带上上次游标', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      final now = DateTime.now().millisecondsSinceEpoch;
      Progress.I.states['apple'] = CardState(box: 1, due: now, seen: 1, right: 1, last: now);

      await ProgressSync.I.syncNow(); // 首次
      syncBodies.clear();

      // 模拟答了两题
      Progress.I.states['apple']!.seen = 2;
      ProgressSync.I.markWord('apple');
      Progress.I.states['durian'] = CardState(box: 0, due: now, seen: 1, wrong: 1, last: now);
      ProgressSync.I.markWord('durian');

      await ProgressSync.I.syncNow();
      final body = syncBodies.first;
      expect(body['since'], 111);
      expect(body['pull'], isTrue);
      final cards = (body['cards'] as List).cast<Map>();
      expect(cards.length, 2);
      expect(cards.map((c) => c['w']), containsAll(['apple', 'durian']));
      // 没有课程改动时不必重复上传整份课程进度
      expect(body.containsKey('curriculum'), isFalse);

      // 推成功后脏标记清空
      syncBodies.clear();
      await ProgressSync.I.syncNow();
      expect((syncBodies.first['cards'] as List).isEmpty, isTrue);
    });
  });

  // ------------------------------------------------------------ 失败

  testWidgets('同步失败：保留脏标记，下次还能重推', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      final now = DateTime.now().millisecondsSinceEpoch;
      Progress.I.states['apple'] = CardState(box: 1, due: now, seen: 1, right: 1, last: now);

      // 后台报错
      final original = syncReply;
      syncReply = null;
      // 用不存在的端口模拟断网
      debugBaseOverride = 'http://127.0.0.1:1';
      await ProgressSync.I.syncNow();
      expect(ProgressSync.I.status, ProgressSync.statusError);
      debugBaseOverride = 'http://127.0.0.1:${server.port}';

      syncReply = original;
      syncBodies.clear();
      expect(ProgressSync.I.status == ProgressSync.statusError, isTrue);

      // 重新联网：不能因为上次失败就把进度丢掉
      await ProgressSync.I.syncNow();
      final cards = (syncBodies.first['cards'] as List).cast<Map>();
      expect(cards.length, 1, reason: '失败时的脏标记要保留到成功为止');
      expect(ProgressSync.I.status, ProgressSync.statusOk);
    });
  });

  // ------------------------------------------------------------ 清空

  testWidgets('清空记录：云端一起清，游标归零', (tester) async {
    await tester.runAsync(() async {
      await Auth.I.login('deer', 'pass123');
      await ProgressSync.I.syncNow();
      expect((await SharedPreferences.getInstance()).getInt('progress_sync_at_7'), 111);

      await ProgressSync.I.resetRemote();
      expect(resetCalled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('progress_sync_at_7'), 0);
    });
  });

  // ------------------------------------------------------------ 未登录

  testWidgets('未登录：直接跳过，不发请求', (tester) async {
    await tester.runAsync(() async {
      final done = await ProgressSync.I.syncNow();
      expect(done, isFalse);
      expect(syncBodies, isEmpty);
      expect(ProgressSync.I.status, ProgressSync.statusOff);
    });
  });
}
