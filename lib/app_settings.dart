import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 与账号无关的本地偏好：发音口音、答题震动。
///
/// 这些设置只影响这台设备（换手机重设一次即可），所以不参与云同步，
/// 也不写进 Progress —— 进度模块要保持零 UI 依赖，单测能单独跑。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  static const _kAccent = 'ui.accent';
  static const _kHaptic = 'ui.haptic';

  /// 'us' 美式 / 'uk' 英式；后台音频服务的 type 参数直接用它
  String accent = 'us';

  /// 答题时是否震动（配对成功/失败）
  bool haptic = true;

  bool get uk => accent == 'uk';

  String get accentName => uk ? '英式' : '美式';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final a = sp.getString(_kAccent);
      if (a == 'us' || a == 'uk') accent = a!;
      haptic = sp.getBool(_kHaptic) ?? true;
    } catch (e) {
      debugPrint('[settings] 读取本地偏好失败：$e');
    }
  }

  Future<void> setAccent(String v) async {
    if (v != 'us' && v != 'uk') return;
    if (v == accent) return;
    accent = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kAccent, v);
    } catch (_) {
      // 写盘失败只影响下次启动的默认值，不影响本次使用
    }
  }

  Future<void> setHaptic(bool v) async {
    if (v == haptic) return;
    haptic = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kHaptic, v);
    } catch (_) {}
  }
}
