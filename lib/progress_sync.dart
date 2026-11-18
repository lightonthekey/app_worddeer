import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'backend.dart';
import 'curriculum.dart';
import 'progress.dart';
import 'ui.dart';

/// 学习进度云同步（本地优先 + 异步增量）。
///
/// 三条铁律与内容同步一致：
/// 1. **本地优先** —— 任何学习行为先落本地，联网只是"顺手备份"；请求失败不弹窗、不回滚。
/// 2. **静默降级** —— 未登录、断网、后台没起，全部安静跳过，下次再说。
/// 3. **可合并** —— 合并规则与后台完全一致（见 backend/service/progress），
///    两端重复合并幂等，所以断点续传、重复推送都不会把数据搞坏。
///
/// 触发时机：登录成功后立刻同步一次（把本机历史带上去）、
/// 有改动后防抖 3 秒、App 切后台前补一次。
class ProgressSync {
  ProgressSync._();
  static final ProgressSync I = ProgressSync._();

  /// 未登录 / 空闲 / 同步中 / 成功 / 失败
  static const statusOff = 'off';
  static const statusIdle = 'idle';
  static const statusSyncing = 'syncing';
  static const statusOk = 'ok';
  static const statusError = 'error';

  String status = statusIdle;
  String? lastError;

  /// 本机最后一次同步成功的时间（epoch ms），仅用于界面展示
  int lastAt = 0;

  final _changes = StreamController<void>.broadcast();

  /// 同步状态变化通知（我的页订阅刷新）
  Stream<void> get changes => _changes.stream;

  /// 每批推送的卡片数：800 × 约 60 字节 ≈ 48KB，够小不易超时，也够快
  static const _batch = 800;

  static const _kAtPrefix = 'progress_sync_at_';
  static const _kDirtyWords = 'progress_dirty_words';
  static const _kDirtyCur = 'progress_dirty_cur';
  static const _kLastAt = 'progress_sync_last_at';

  final Set<String> _dirty = <String>{};
  bool _dirtyCur = false;

  /// 课程进度的改动版本号：同步期间又有改动时，靠它判断这份数据推没推过。
  /// 只用一个 bool 的话「同步中又学了一关」会和「同步前就是脏的」混在一起，
  /// 收尾时被一起清掉，那部分进度就永远上不了云。
  int _curVersion = 0;
  bool _loaded = false;
  bool _running = false;
  Timer? _debounce;

  /// 启动时调用一次：装载未落盘的脏标记，并把两个进度模块的变更回调接上
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    Progress.I.onChanged = markWord;
    Curriculum.I.onChanged = markCurriculum;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDirtyWords);
      if (raw != null && raw.isNotEmpty) {
        for (final w in jsonDecode(raw) as List) {
          _dirty.add(w as String);
        }
      }
      _dirtyCur = prefs.getBool(_kDirtyCur) ?? false;
      lastAt = prefs.getInt(_kLastAt) ?? 0;
    } catch (e) {
      debugPrint('[sync] 脏标记读取失败：$e');
    }
    _set(Auth.I.loggedIn ? statusIdle : statusOff);
  }

  /// 某个单词有改动
  void markWord(String en) {
    if (en.isEmpty) return;
    _dirty.add(en);
    _persistDirty();
    schedule();
  }

  /// 课程进度（关卡/主题/今日）有改动
  void markCurriculum() {
    _dirtyCur = true;
    _curVersion++;
    _persistDirty();
    schedule();
  }

  /// 防抖同步：学习过程中每答一题都会触发，攒 3 秒再发一次
  void schedule() {
    if (!Auth.I.loggedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(syncNow());
    });
  }

  /// 立即同步。返回是否真的完成了一轮（未登录/正在同步返回 false）。
  Future<bool> syncNow({bool force = false}) async {
    if (!Auth.I.loggedIn) {
      _set(statusOff);
      return false;
    }
    if (_running) return false;
    _running = true;
    _set(statusSyncing);
    var pushedAll = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = Auth.I.user!.id;
      final atKey = '$_kAtPrefix$uid';
      final since = prefs.getInt(atKey) ?? 0;

      // 首次在这个账号下同步（游标为 0）：把本机已有的全部进度都推上去，
      // 否则"先离线学了半年、后来才注册"的用户历史永远上不了云。
      final first = since == 0;
      final words = first
          ? Progress.I.states.keys
              .where((w) => (Progress.I.states[w]?.seen ?? 0) > 0)
              .toList()
          : _dirty.toList();

      // 推送时的快照：多批同步最长可能跑 20 秒，这期间用户还在学。
      // 只有「推上去的就是此刻的最新状态」才算推过，否则脏标记必须留着，
      // 不能像以前那样在收尾时整体 clear() —— 那会把同步期间的进度直接抹掉。
      final sentLast = <String, int>{
        for (final w in words) w: Progress.I.states[w]?.last ?? 0,
      };
      final curVersionAtStart = _curVersion;

      final batches = <List<String>>[];
      for (var i = 0; i < words.length; i += _batch) {
        batches.add(words.sublist(i, math.min(i + _batch, words.length)));
      }
      if (batches.isEmpty) batches.add(const <String>[]);

      final pushCur = first || _dirtyCur;
      var serverTime = since;

      for (var i = 0; i < batches.length; i++) {
        final res = await apiJson(
          '/api/v1/worddeer/progress/sync',
          token: Auth.I.token,
          body: {
            'since': since,
            // 只有第一批需要拉增量：后续批次只是把剩下的卡片推完
            'pull': i == 0,
            if (i == 0 && pushCur) 'curriculum': _curriculumJson(),
            'cards': [
              for (final w in batches[i])
                if (Progress.I.states[w] != null)
                  Progress.I.states[w]!.toSyncJson(w),
            ],
          },
        );
        // 游标只取第一批的 server_time：第一批才是"拉增量"的时间点，
        // 用后面批次的时间当游标会把这期间别的设备写入的行跳过
        if (i == 0) {
          serverTime = (res['server_time'] as num?)?.toInt() ?? serverTime;
          await _apply(res);
        }
      }

      await prefs.setInt(atKey, serverTime);
      lastAt = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_kLastAt, lastAt);
      // 只清掉本轮真正推成功的标记，同步期间的新改动原样留下
      for (final e in sentLast.entries) {
        if ((Progress.I.states[e.key]?.last ?? 0) <= e.value) {
          _dirty.remove(e.key);
        }
      }
      if (pushCur && _curVersion == curVersionAtStart) _dirtyCur = false;
      pushedAll = true;
      await _persistDirty();
      lastError = null;
      _set(statusOk);
      debugPrint('[sync] 完成：推送 ${words.length} 张，游标 $serverTime');
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      _set(statusError);
      debugPrint('[sync] 失败（保留脏标记，下次重试）：${e.message}');
      return false;
    } catch (e) {
      lastError = '同步失败，稍后重试';
      _set(statusError);
      debugPrint('[sync] 失败：$e');
      return false;
    } finally {
      _running = false;
      // 这一轮没推完（同步期间又有改动）：立刻再排一轮，别等用户下次操作。
      // 只在成功时重排 —— 失败时重排会变成断网下每几秒打一次接口。
      if (pushedAll && (_dirty.isNotEmpty || _dirtyCur)) {
        _debounce?.cancel();
        _debounce =
            Timer(const Duration(seconds: 1), () => unawaited(syncNow()));
      }
    }
  }

  /// 「清空学习记录」时连云端一起清，否则下次同步会把刚删的进度原样拉回来
  Future<void> resetRemote() async {
    if (!Auth.I.loggedIn) return;
    _debounce?.cancel();
    try {
      await apiJson('/api/v1/worddeer/progress/reset', token: Auth.I.token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_kAtPrefix${Auth.I.user!.id}', 0);
      _dirty.clear();
      _dirtyCur = false;
      await _persistDirty();
      _set(statusIdle);
    } on ApiException catch (e) {
      // 清不了云端也不该阻止本地清空：下次同步会重新推一份干净的上去
      debugPrint('[sync] 云端重置失败：${e.message}');
    }
  }

  /// 登录/登出后重置内存态（游标按账号存，不受影响）
  void onAuthChanged() {
    _set(Auth.I.loggedIn ? statusIdle : statusOff);
    if (Auth.I.loggedIn) unawaited(syncNow());
  }

  /// 单测用：清掉内存态（游标与脏标记仍按账号存在 prefs 里，用例各自重置 mock）
  @visibleForTesting
  void resetForTest() {
    _debounce?.cancel();
    _debounce = null;
    _dirty.clear();
    _dirtyCur = false;
    _curVersion = 0;
    _loaded = false;
    _running = false;
    lastAt = 0;
    lastError = null;
    status = statusIdle;
  }

  // ---------------------------------------------------------------- 内部

  void _set(String s) {
    status = s;
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _persistDirty() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDirtyWords, jsonEncode(_dirty.toList()));
      await prefs.setBool(_kDirtyCur, _dirtyCur);
    } catch (_) {
      // 写不进去只影响"下次启动补同步"，不影响当前学习
    }
  }

  /// 课程进度整份上传：字段与后台 progress.Curriculum 一一对应
  Map<String, dynamic> _curriculumJson() {
    final c = Curriculum.I;
    final p = Progress.I;
    return {
      'level': c.curLv,
      'today': c.todayWords,
      'day': c.dayKey,
      'streak': p.streak,
      'last_day': p.lastActiveDay,
      'new_per_day': p.newPerDay,
      'review_per_day': p.reviewPerDay,
      'ts': _payloadTs(),
      'passed': c.passed.keys.toList(),
      'part': Map<String, int>.from(c.part),
      'themes': Map<String, int>.from(c.themes),
    };
  }

  /// 课程与打卡分属两个对象，取两者较新的时间作为整份的版本
  int _payloadTs() {
    final a = Curriculum.I.updatedAt;
    final b = Progress.I.updatedAt;
    return a > b ? a : b;
  }

  Future<void> _apply(Map<String, dynamic> res) async {
    final cards = res['cards'];
    if (cards is List && cards.isNotEmpty) {
      for (final raw in cards) {
        if (raw is! Map) continue;
        final j = Map<String, dynamic>.from(raw);
        final w = j['w'] as String? ?? '';
        if (w.isEmpty) continue;
        Progress.I.mergeRemote(w, CardState.fromSyncJson(j));
      }
      await Progress.I.save();
    }
    final cur = res['curriculum'];
    if (cur is Map) {
      final changed = _applyCurriculum(Map<String, dynamic>.from(cur));
      if (changed) await Curriculum.I.save();
    }
    // 远端合并进来的数据可能改变界面上的数字
    appTick.value++;
  }

  /// 合并服务端课程快照，返回是否有变化。规则与后台一致：标量听更新的，其余取大/并集。
  bool _applyCurriculum(Map<String, dynamic> j) {
    final c = Curriculum.I;
    final p = Progress.I;
    final rts = (j['ts'] as num?)?.toInt() ?? 0;
    var changed = false;

    final serverDay = j['day'] as String? ?? '';
    final serverToday = (j['today'] as num?)?.toInt() ?? 0;
    if (serverDay == c.dayKey) {
      if (serverToday > c.todayWords) {
        c.todayWords = serverToday;
        changed = true;
      }
    } else if (serverDay.isNotEmpty && serverDay.compareTo(c.dayKey) > 0) {
      c.dayKey = serverDay;
      c.todayWords = serverToday;
      changed = true;
    }

    final streak = (j['streak'] as num?)?.toInt() ?? 0;
    if (streak > p.streak) {
      p.streak = streak;
      changed = true;
    }
    final lastDay = j['last_day'] as String? ?? '';
    if (lastDay.compareTo(p.lastActiveDay) > 0) {
      p.lastActiveDay = lastDay;
      changed = true;
    }

    // 标量（当前级别、每日新词数）只有服务端更新时才采用
    if (rts > c.updatedAt) {
      c.updatedAt = rts;
      final lv = j['level'] as String? ?? '';
      if (lv.isNotEmpty && kLevels.any((l) => l.id == lv) && lv != c.curLv) {
        c.curLv = lv;
        changed = true;
      }
      final np = (j['new_per_day'] as num?)?.toInt() ?? 0;
      if (np >= 5 && np <= 40 && np != p.newPerDay) {
        p.newPerDay = np;
        changed = true;
      }
      final rp = (j['review_per_day'] as num?)?.toInt() ?? 0;
      if (rp >= 10 && rp <= 100 && rp != p.reviewPerDay) {
        p.reviewPerDay = rp;
        changed = true;
      }
    }

    for (final k in (j['passed'] as List? ?? const [])) {
      final key = k as String;
      if (c.passed[key] != true) {
        c.passed[key] = true;
        c.part.remove(key);
        changed = true;
      }
    }
    (j['part'] as Map?)?.forEach((k, v) {
      final key = k as String;
      final n = (v as num).toInt();
      if (c.passed[key] == true) return;
      if (n > (c.part[key] ?? 0)) {
        c.part[key] = n;
        changed = true;
      }
    });
    (j['themes'] as Map?)?.forEach((k, v) {
      final key = k as String;
      final n = (v as num).toInt();
      if (n > (c.themes[key] ?? 0)) {
        c.themes[key] = n;
        changed = true;
      }
    });
    return changed;
  }
}
