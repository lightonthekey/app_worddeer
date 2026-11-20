import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'backend.dart';
import 'ui.dart';

/// 会员权益：**App 里所有付费墙的唯一数据源**。
///
/// 铁律：客户端不写 `if (vip)` 这种业务判断，也不硬编码"免费几关"。
/// 界面只问三件事 —— 这个级别能学吗、第 i 关能进吗、第 i 个主题能进吗，
/// 答案全部来自后台 `/entitlement` 下发的 limits（后台 plan 表可随时改，不用发版）。
///
/// 离线策略：用上一次成功拉取的缓存；没有缓存就用内置的保守免费档。
/// 本地已知到期时间已过时，即使缓存写着会员也按免费算，避免"改系统时间白嫖"。
class Limits {
  final List<String> levels;
  final int unitsPerLevel;
  final int themesPerLevel;
  final int newPerDayMax;
  final int reviewPerDayMax;
  final bool cloudSync;
  final bool offlineAudio;
  final bool wrongBook;
  final List<String> desc;

  const Limits({
    required this.levels,
    required this.unitsPerLevel,
    required this.themesPerLevel,
    required this.newPerDayMax,
    required this.reviewPerDayMax,
    required this.cloudSync,
    required this.offlineAudio,
    required this.wrongBook,
    this.desc = const [],
  });

  /// 兜底：与后台 sql/005 里 free 档一致
  static const free = Limits(
    levels: ['A1', 'A2'],
    unitsPerLevel: 2,
    themesPerLevel: 1,
    newPerDayMax: 10,
    reviewPerDayMax: 40,
    cloudSync: true,
    offlineAudio: false,
    wrongBook: true,
    desc: ['A1、A2 两个级别', '每个级别前 2 关', '每个级别 1 个主题', '学习进度云同步'],
  );

  factory Limits.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v, int def) => (v as num?)?.toInt() ?? def;
    bool asBool(dynamic v, bool def) => v is bool ? v : def;
    final levels = (j['levels'] as List?)
            ?.map((e) => e.toString())
            .where((e) => const ['A1', 'A2', 'B1', 'B2', 'C1'].contains(e))
            .toList() ??
        const [];
    return Limits(
      levels: levels.isEmpty ? free.levels : levels,
      // 上限不能写 12：现在一关 20 词、A1 就有 63 关，主题也有 40+，
      // 后台想放开全部内容只能填个很大的数，写成 12 会把「全部关卡」悄悄截成 12 关。
      unitsPerLevel: asInt(j['units_per_level'], free.unitsPerLevel).clamp(1, 999),
      themesPerLevel: asInt(j['themes_per_level'], free.themesPerLevel).clamp(1, 999),
      newPerDayMax: asInt(j['new_per_day_max'], free.newPerDayMax).clamp(5, 40),
      reviewPerDayMax: asInt(j['review_per_day_max'], free.reviewPerDayMax).clamp(10, 100),
      cloudSync: asBool(j['cloud_sync'], free.cloudSync),
      offlineAudio: asBool(j['offline_audio'], free.offlineAudio),
      wrongBook: asBool(j['wrong_book'], free.wrongBook),
      desc: (j['desc'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'levels': levels,
        'units_per_level': unitsPerLevel,
        'themes_per_level': themesPerLevel,
        'new_per_day_max': newPerDayMax,
        'review_per_day_max': reviewPerDayMax,
        'cloud_sync': cloudSync,
        'offline_audio': offlineAudio,
        'wrong_book': wrongBook,
        'desc': desc,
      };
}

/// 付费墙展示用的套餐
class PlanInfo {
  final String code;
  final String name;
  final int tier;
  final double price;
  final int periodDays;
  final String productId;
  final String badge;
  final List<String> desc;

  const PlanInfo({
    required this.code,
    required this.name,
    this.tier = 2,
    this.price = 0,
    this.periodDays = 0,
    this.productId = '',
    this.badge = '',
    this.desc = const [],
  });

  String get periodText {
    if (periodDays >= 360) return '每年';
    if (periodDays >= 28) return '每月';
    return '一次性';
  }

  String get priceText => price <= 0 ? '免费' : '¥${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)}';

  /// 折合每月多少钱，用于"省 55%"这类文案；本身就是月付的不再折算
  String get perMonthText {
    if (periodDays < 28 || periodDays <= 31) return '';
    final months = periodDays / 30.0;
    final m = price / months;
    return '≈ ¥${m.toStringAsFixed(1)}/月';
  }

  factory PlanInfo.fromJson(Map<String, dynamic> j) {
    final lim = j['limits'];
    return PlanInfo(
      code: j['code'] as String? ?? '',
      name: j['name'] as String? ?? '',
      tier: (j['tier'] as num?)?.toInt() ?? 2,
      price: (j['price'] as num?)?.toDouble() ?? 0,
      periodDays: (j['period_days'] as num?)?.toInt() ?? 0,
      productId: j['product_id'] as String? ?? '',
      badge: j['badge'] as String? ?? '',
      desc: lim is Map ? Limits.fromJson(Map<String, dynamic>.from(lim)).desc : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'tier': tier,
        'price': price,
        'period_days': periodDays,
        'product_id': productId,
        'badge': badge,
        'limits': {'desc': desc},
      };
}

/// 一次完整的权益快照
class Entitlement {
  final int tier;
  final String tierName;
  final bool vip;
  final String expireAt;
  final bool trialUsed;
  final Limits limits;
  final List<PlanInfo> plans;
  final int version;

  const Entitlement({
    this.tier = 1,
    this.tierName = '免费版',
    this.vip = false,
    this.expireAt = '',
    this.trialUsed = false,
    this.limits = Limits.free,
    this.plans = const [],
    this.version = 0,
  });

  factory Entitlement.fromJson(Map<String, dynamic> j) {
    final lim = j['limits'];
    return Entitlement(
      tier: (j['tier'] as num?)?.toInt() ?? 1,
      tierName: j['tier_name'] as String? ?? '免费版',
      vip: j['vip'] == true,
      expireAt: j['expire_at'] as String? ?? '',
      trialUsed: j['trial_used'] == true,
      limits: lim is Map ? Limits.fromJson(Map<String, dynamic>.from(lim)) : Limits.free,
      plans: (j['plans'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PlanInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      version: (j['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier,
        'tier_name': tierName,
        'vip': vip,
        'expire_at': expireAt,
        'trial_used': trialUsed,
        'limits': limits.toJson(),
        'plans': [for (final p in plans) p.toJson()],
        'version': version,
      };

  Entitlement copyWith({Limits? limits, bool? vip}) => Entitlement(
        tier: tier,
        tierName: tierName,
        vip: vip ?? this.vip,
        expireAt: expireAt,
        trialUsed: trialUsed,
        limits: limits ?? this.limits,
        plans: plans,
        version: version,
      );
}

class Ent {
  Ent._();
  static final Ent I = Ent._();

  static const _kCache = 'entitlement_json';
  static const _kFetchedAt = 'entitlement_at';

  Entitlement ent = const Entitlement();

  /// 上次成功拉取时间（0=从未）
  int fetchedAt = 0;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  bool get vip => ent.vip;

  /// 该级别是否可学（免费用户通常只有 A1/A2）
  bool canLevel(String lv) => ent.limits.levels.contains(lv);

  /// 第 index 关（0 基）是否在会员额度内；进度锁由 Curriculum 另行判断。
  ///
  /// 会员直接放行：`units_per_level` 这个字段是后台按「每级 12 关」的时代填的，
  /// 现在一关 20 词、每级 50+ 关，照 12 卡会把会员挡在 U13。
  /// 后台把这一栏改成足够大的值之后，这段判断也不再产生影响。
  bool canUnit(int index) {
    if (index < 0) return false;
    if (vip) return true;
    return index < ent.limits.unitsPerLevel;
  }

  /// 第 index 个主题是否解锁。
  ///
  /// 和 [canUnit] 一样：会员直接放行。后台 `themes_per_level` 是「每级免费开放几个」
  /// 的配置，一旦运营加主题（或把付费档写成具体数字），没有这条的话
  /// 付了钱的用户反而会被挡在新增主题外面。
  bool canTheme(int index) {
    if (index < 0) return false;
    if (vip) return true;
    return index < ent.limits.themesPerLevel;
  }

  /// 启动时读缓存（不阻塞首屏、不抛异常）
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      fetchedAt = prefs.getInt(_kFetchedAt) ?? 0;
      final raw = prefs.getString(_kCache);
      if (raw != null && raw.isNotEmpty) {
        ent = _expireCheck(Entitlement.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      }
    } catch (e) {
      debugPrint('[ent] 缓存读取失败，用内置免费档：$e');
      ent = const Entitlement();
    }
    notify();
  }

  /// 拉取最新权益：启动、登录/登出、进付费墙前调用。失败静默保留缓存。
  Future<void> refresh() async {
    try {
      final data = await apiJson(
        '/api/v1/worddeer/entitlement',
        method: 'GET',
        token: Auth.I.token,
      );
      ent = _expireCheck(Entitlement.fromJson(data));
      fetchedAt = DateTime.now().millisecondsSinceEpoch;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kCache, jsonEncode(ent.toJson()));
        await prefs.setInt(_kFetchedAt, fetchedAt);
      } catch (_) {
        // 缓存写不进去不影响本次使用
      }
      notify();
      debugPrint('[ent] ${ent.tierName} 每级 ${ent.limits.unitsPerLevel} 关 / ${ent.limits.themesPerLevel} 主题');
    } on ApiException catch (e) {
      debugPrint('[ent] 拉取失败（沿用缓存）：${e.message}');
    } catch (e) {
      debugPrint('[ent] 拉取失败：$e');
    }
  }

  /// 登录态变化：重新拉一次（游客 → 会员，或者退出后回到免费）
  void onAuthChanged() => unawaited(refresh());

  /// 本地已知到期时间已过：立即按免费算，不等服务器
  Entitlement _expireCheck(Entitlement e) {
    if (!e.vip || e.expireAt.isEmpty) return e;
    final t = DateTime.tryParse(e.expireAt.replaceFirst(' ', 'T'));
    if (t != null && t.isBefore(DateTime.now())) {
      return Entitlement(
        tier: 1,
        tierName: '免费版',
        vip: false,
        trialUsed: e.trialUsed,
        limits: Limits.free,
        plans: e.plans,
        version: e.version,
      );
    }
    return e;
  }

  void notify() {
    if (!_changes.isClosed) _changes.add(null);
    appTick.value++;
  }
}
