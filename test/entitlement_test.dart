import 'dart:convert';
import 'dart:io';

import 'package:app_worddeer/auth.dart';
import 'package:app_worddeer/backend.dart';
import 'package:app_worddeer/curriculum.dart';
import 'package:app_worddeer/entitlement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会员权益测试：解析/兜底/过期降级/离线缓存，以及"付费墙只认 limits"这条约定。
void main() {
  late HttpServer server;
  Map<String, dynamic>? replyData;
  bool failNext = false;

  Map<String, dynamic> freeBody({List<Map<String, dynamic>>? plans}) => {
        'tier': 1,
        'tier_name': '免费版',
        'vip': false,
        'expire_at': '',
        'trial_used': false,
        'limits': {
          'levels': ['A1', 'A2'],
          'units_per_level': 2,
          'themes_per_level': 1,
          'new_per_day_max': 10,
          'review_per_day_max': 40,
          'cloud_sync': true,
          'offline_audio': false,
          'wrong_book': true,
          'desc': ['A1、A2 两个级别'],
        },
        'plans': plans ??
            [
              {
                'code': 'vip_month',
                'name': '月度会员',
                'tier': 2,
                'price': 18,
                'period_days': 30,
                'product_id': 'worddeer.vip.month',
                'badge': '',
                'limits': {'desc': ['全部关卡']},
              },
              {
                'code': 'vip_year',
                'name': '年度会员',
                'tier': 2,
                'price': 98,
                'period_days': 365,
                'product_id': 'worddeer.vip.year',
                'badge': '省 55%',
                'limits': {'desc': ['全部关卡', '离线发音']},
              },
            ],
        'version': 1794892799,
        'server_time': 1794892799000,
      };

  void resetEnt() {
    Ent.I.ent = const Entitlement();
    Ent.I.fetchedAt = 0;
  }

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Auth.I.resetLocal();
    resetEnt();
    replyData = freeBody();
    failNext = false;

    server = await HttpServer.bind('127.0.0.1', 0);
    debugBaseOverride = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      Future<void> reply(int status, String text) async {
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(text);
        await req.response.close();
      }

      if (req.uri.path != '/api/v1/worddeer/entitlement') {
        return reply(404, jsonEncode({'code': 50, 'message': 'not found'}));
      }
      if (failNext) {
        return reply(200, jsonEncode({'code': 50, 'message': '服务异常'}));
      }
      return reply(200, jsonEncode({'code': 0, 'data': replyData}));
    });
  });

  tearDown(() async {
    debugBaseOverride = null;
    resetEnt();
    await server.close(force: true);
  });

  // ------------------------------------------------------------ 解析

  test('limits 缺字段 / 越界：落到安全默认值', () {
    final l = Limits.fromJson(const {'units_per_level': 99, 'themes_per_level': -3});
    // 以前上限写 12（「每级 12 关」时代），A1 现在 63 关，会员档填「全部」会被截成 12，
    // 所以上限放到 999；99 属于正常配置，原样保留
    expect(l.unitsPerLevel, 99, reason: '不再被 12 截断');
    expect(Limits.fromJson(const {'units_per_level': 9999}).unitsPerLevel, 999,
        reason: '防止脏数据算出天量队列');
    expect(l.themesPerLevel, 1, reason: '下限 1 个主题');
    expect(l.levels, Limits.free.levels, reason: '没给级别用免费档');
    expect(l.newPerDayMax, 10);
    expect(l.cloudSync, isTrue);
  });

  test('主题解锁：免费按限额，会员直通（后台配小了也不锁付费用户）', () {
    resetEnt();
    expect(Ent.I.canTheme(0), isTrue, reason: '免费档第 1 个主题开放');
    expect(Ent.I.canTheme(1), isFalse, reason: '免费档每级只开 1 个');
    expect(Ent.I.canTheme(-1), isFalse);

    Ent.I.ent = const Entitlement(
      tier: 2,
      tierName: '会员',
      vip: true,
      limits: Limits(
        levels: ['A1', 'A2', 'B1', 'B2', 'C1'],
        unitsPerLevel: 2,
        themesPerLevel: 1,
        newPerDayMax: 40,
        reviewPerDayMax: 100,
        cloudSync: true,
        offlineAudio: false,
        wrongBook: true,
      ),
    );
    // 与 canUnit 一致：会员不受「每级开放几个」限制，否则运营新增主题就把会员挡在外面
    expect(Ent.I.canTheme(1), isTrue);
    expect(Ent.I.canTheme(30), isTrue);
    expect(Ent.I.canUnit(60), isTrue);
  });

  test('解析套餐：价格、周期、角标', () {
    final e = Entitlement.fromJson(freeBody());
    expect(e.plans.length, 2);
    final year = e.plans[1];
    expect(year.name, '年度会员');
    expect(year.priceText, '¥98');
    expect(year.badge, '省 55%');
    expect(year.periodText, '每年');
    expect(year.perMonthText, contains('/月'));
    expect(e.plans[0].perMonthText, '', reason: '月付本身就是按月，不显示折合价');
    expect(year.desc, ['全部关卡', '离线发音']);
  });

  // ------------------------------------------------------------ 拉取

  testWidgets('拉取成功：写缓存，付费墙拿到套餐', (tester) async {
    await tester.runAsync(() async {
      await Ent.I.refresh();
      expect(Ent.I.ent.tier, 1);
      expect(Ent.I.canUnit(1), isTrue);
      expect(Ent.I.canUnit(2), isFalse, reason: '免费只有前 2 关');
      expect(Ent.I.canTheme(0), isTrue);
      expect(Ent.I.canTheme(1), isFalse);
      expect(Ent.I.canLevel('A1'), isTrue);
      expect(Ent.I.canLevel('B1'), isFalse);
      expect(Ent.I.ent.plans.length, 2);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('entitlement_json'), contains('vip_year'));
      expect(prefs.getInt('entitlement_at'), greaterThan(0));
    });
  });

  testWidgets('拉取失败：沿用缓存，不清空权益', (tester) async {
    await tester.runAsync(() async {
      await Ent.I.refresh();
      expect(Ent.I.ent.plans.length, 2);

      failNext = true;
      await Ent.I.refresh();
      expect(Ent.I.ent.plans.length, 2, reason: '失败不能把套餐清空');
      expect(Ent.I.ent.tier, 1);
    });
  });

  // ------------------------------------------------------------ 缓存与过期

  testWidgets('启动读缓存：会员身份还在', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'entitlement_json': jsonEncode({
          'tier': 2,
          'tier_name': '年度会员',
          'vip': true,
          'expire_at': '2099-01-01 00:00:00',
          'trial_used': false,
          'limits': {
            'levels': ['A1', 'A2', 'B1', 'B2', 'C1'],
            'units_per_level': 12,
            'themes_per_level': 12,
            'new_per_day_max': 40,
            'review_per_day_max': 100,
            'cloud_sync': true,
            'offline_audio': true,
            'wrong_book': true,
            'desc': [],
          },
          'plans': [],
          'version': 1,
        }),
      });
      resetEnt();
      await Ent.I.load();
      expect(Ent.I.vip, isTrue);
      expect(Ent.I.canUnit(11), isTrue);
      expect(Ent.I.canLevel('C1'), isTrue);
    });
  });

  testWidgets('缓存里的会员已过期：本地立即按免费算', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'entitlement_json': jsonEncode({
          'tier': 2,
          'tier_name': '年度会员',
          'vip': true,
          'expire_at': '2020-01-01 00:00:00',
          'trial_used': false,
          'limits': {
            'levels': ['A1', 'A2', 'B1', 'B2', 'C1'],
            'units_per_level': 12,
            'themes_per_level': 12,
            'new_per_day_max': 40,
            'review_per_day_max': 100,
            'cloud_sync': true,
            'offline_audio': true,
            'wrong_book': true,
            'desc': [],
          },
          'plans': [],
          'version': 1,
        }),
      });
      resetEnt();
      await Ent.I.load();
      expect(Ent.I.vip, isFalse);
      expect(Ent.I.canUnit(5), isFalse, reason: '过期后回到免费额度');
    });
  });

  // ------------------------------------------------------------ 付费墙接线

  test('课程锁跟随 limits：免费用户锁 B1，第 3 关起锁', () {
    final c = Curriculum.I;
    c.curLv = 'A1';
    expect(c.isOpen('A1', 0), isTrue);
    expect(c.isOpen('A1', 2), isFalse, reason: '第 3 关超出免费额度');
    expect(c.lockedByPlan('A1', 2), isTrue);
    expect(c.isOpen('B1', 0), isFalse, reason: 'B1 不在免费级别里');
    expect(c.lockedByPlan('B1', 0), isTrue);
    expect(c.themeUnlocked(0), isTrue);
    expect(c.themeUnlocked(3), isFalse);
  });
}
