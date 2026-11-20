import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 6 套配色，与 design/wb-theme.js 一一对应；每套都有亮色 / 暗色两版。
///
/// 每套只定义 8 个基准色，其余（已学底、描边、深色底边、轨道、中性灰、卡片面）
/// 全部由同一套公式推出来 —— 12 套共用一个公式，才不会出现「这套调过、
/// 那套忘了」。派生值第一次取用时算好并缓存。
///
/// 暗色不是把亮色反相：8 个基准色是人工挑的（背景带主色相、主色提亮一档），
/// 派生公式只有一处按 [isDark] 分支，其余复用。
class AppPalette {
  final String key;
  final String name;
  final String tag;

  /// 暗色版
  final bool isDark;

  /// 主色：按钮、当前节点、进度条、选中描边
  final Color pri;

  /// 主色深：渐变暗端、按下态、文字强调
  final Color deep;

  /// 主色浅底：已学完的方块底、胶囊底（暗色下是主色的深色薄雾）
  final Color soft;

  /// 页面 / 手机机身底色
  final Color bg;

  /// 正文墨色
  final Color ink;

  /// 次要文字
  final Color muted;

  /// 卡片描边
  final Color line;

  /// 没走到的虚线路径（比 line 深一档才看得见）
  final Color dash;

  AppPalette({
    required this.key,
    required this.name,
    required this.tag,
    required this.pri,
    required this.deep,
    required this.soft,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.line,
    required this.dash,
    this.isDark = false,
  });

  late final Color heroA = pri;
  late final Color heroB = deep;

  /// 卡片 / 弹层 / 输入框的「面」。亮色是纯白，暗色是把底色往墨色抬 6%。
  /// 页面里所有原本写死 `Colors.white` 当背景的地方都要换用它。
  late final Color card = isDark ? _mix(bg, ink, .06) : Colors.white;

  /// 比 [card] 再抬一档：分段控件、列表交替行、输入框内底
  late final Color cardAlt = isDark ? _mix(bg, ink, .10) : _mix(Colors.white, bg, .55);

  /// 选中描边 / hover 描边
  late final Color priLine =
      isDark ? _mix(bg, pri, .62) : _mix(Colors.white, pri, .28);

  /// 已学完方块的底与描边
  late final Color doneBg =
      isDark ? _mix(bg, pri, .22) : _mix(Colors.white, pri, .07);
  late final Color doneLine =
      isDark ? _mix(bg, pri, .46) : _mix(Colors.white, pri, .20);

  /// 已学完方块上的字：亮色往黑压，暗色往白提
  late final Color doneText =
      isDark ? _mix(ink, pri, .35) : _mix(deep, Colors.black, .20);

  /// 实心方块底下那条「厚度」边
  late final Color curEdge =
      _mix(deep, Colors.black, isDark ? .32 : .16);

  /// 进度条 / 滑块的未填充轨道
  late final Color track = _mix(bg, pri, isDark ? .20 : .10);

  /// 桌面预览时机身外的那圈底色
  late final Color edge = _mix(bg, ink, .10);

  /// 中性阶：n1 最浅（分段底、按下态），n5 最深（禁用/占位字）。
  /// 暗色下 ink 是浅色，所以 n1..n5 变成「由暗到亮的灰阶」——语义不变（离底色越远越弱）。
  late final Color n1 = _mix(bg, ink, .05);
  late final Color n2 = _mix(bg, ink, .10);
  late final Color n3 = _mix(bg, ink, .26);
  late final Color n4 = _mix(bg, ink, .52);
  late final Color n5 = _mix(bg, ink, .72);

  /// 阴影在暗色下要更深才看得出层次
  late final Color shadow = isDark
      ? Colors.black.withValues(alpha: .45)
      : const Color(0x1A000000);

  static Color _mix(Color a, Color b, double w) {
    // 在 sRGB 上线性插值，够用且和 CSS 的混色观感一致
    double l(double x, double y) => x + (y - x) * w;
    return Color.fromARGB(
      255,
      l(a.r * 255, b.r * 255).round(),
      l(a.g * 255, b.g * 255).round(),
      l(a.b * 255, b.b * 255).round(),
    );
  }
}

const _indigo = 0xFF4B6FF0;

/// 亮色 6 套（顺序与「我的 → 外观主题」里的排列一致）
final List<AppPalette> kPalettes = [
  AppPalette(
    key: 'indigo',
    name: '靛蓝',
    tag: '冷静专注',
    pri: const Color(_indigo),
    deep: const Color(0xFF3A5AD8),
    soft: const Color(0xFFEEF3FF),
    bg: const Color(0xFFF7F9FF),
    ink: const Color(0xFF1C2231),
    muted: const Color(0xFF7C87A3),
    line: const Color(0xFFE4EAF8),
    dash: const Color(0xFFCCD8FB),
  ),
  AppPalette(
    key: 'teal',
    name: '青绿',
    tag: '清爽护眼',
    pri: const Color(0xFF109E90),
    deep: const Color(0xFF0A7A70),
    soft: const Color(0xFFE5F6F3),
    bg: const Color(0xFFF0F8F7),
    ink: const Color(0xFF1B2B29),
    muted: const Color(0xFF6E8A86),
    line: const Color(0xFFDCEBE8),
    dash: const Color(0xFFBCE2DC),
  ),
  AppPalette(
    key: 'bamboo',
    name: '竹绿',
    tag: '亲切自然',
    pri: const Color(0xFF4FA845),
    deep: const Color(0xFF3A7F33),
    soft: const Color(0xFFEBF6E7),
    bg: const Color(0xFFF4F9F1),
    ink: const Color(0xFF22301E),
    muted: const Color(0xFF7B8F74),
    line: const Color(0xFFE1EDDB),
    dash: const Color(0xFFC4E3BB),
  ),
  AppPalette(
    key: 'orange',
    name: '暖橙',
    tag: '有精神',
    pri: const Color(0xFFEE7A2B),
    deep: const Color(0xFFC75C12),
    soft: const Color(0xFFFDF0E3),
    bg: const Color(0xFFFDF7F1),
    ink: const Color(0xFF33261B),
    muted: const Color(0xFF9C8874),
    line: const Color(0xFFF2E5D8),
    dash: const Color(0xFFF5D2B0),
  ),
  AppPalette(
    key: 'coral',
    name: '珊瑚',
    tag: '少见好记',
    pri: const Color(0xFFE8604C),
    deep: const Color(0xFFC4432F),
    soft: const Color(0xFFFDECE9),
    bg: const Color(0xFFFDF5F3),
    ink: const Color(0xFF33221F),
    muted: const Color(0xFF9B8078),
    line: const Color(0xFFF2E0DC),
    dash: const Color(0xFFF4C9C3),
  ),
  AppPalette(
    key: 'purple',
    name: '经典紫',
    tag: '原来那版',
    pri: const Color(0xFF6D5AE0),
    deep: const Color(0xFF4A41C4),
    soft: const Color(0xFFF1EFFC),
    bg: const Color(0xFFF4F2FA),
    ink: const Color(0xFF22202B),
    muted: const Color(0xFF8A86A0),
    line: const Color(0xFFE8E5F4),
    dash: const Color(0xFFCFC8F3),
  ),
];

/// 暗色 6 套：主色比亮色提亮一档（暗底上要够跳），底色带主色相但不刺眼，
/// 正文用近白而不是纯白（纯白在 OLED 上发闷、长时间读会累）。
final List<AppPalette> kDarkPalettes = [
  AppPalette(
    key: 'indigo',
    name: '靛蓝',
    tag: '冷静专注',
    isDark: true,
    pri: const Color(0xFF6B87F7),
    deep: const Color(0xFF4A63D8),
    soft: const Color(0xFF1A2242),
    bg: const Color(0xFF0F1320),
    ink: const Color(0xFFE7EAF4),
    muted: const Color(0xFF8A93AE),
    line: const Color(0xFF232A40),
    dash: const Color(0xFF3A4363),
  ),
  AppPalette(
    key: 'teal',
    name: '青绿',
    tag: '清爽护眼',
    isDark: true,
    pri: const Color(0xFF1EB3A3),
    deep: const Color(0xFF0F8C80),
    soft: const Color(0xFF102C28),
    bg: const Color(0xFF0C1716),
    ink: const Color(0xFFE3F0EE),
    muted: const Color(0xFF7EA5A0),
    line: const Color(0xFF1D3632),
    dash: const Color(0xFF2B534C),
  ),
  AppPalette(
    key: 'bamboo',
    name: '竹绿',
    tag: '亲切自然',
    isDark: true,
    pri: const Color(0xFF6DBE5C),
    deep: const Color(0xFF4E9A3F),
    soft: const Color(0xFF172A12),
    bg: const Color(0xFF111A0E),
    ink: const Color(0xFFE8F2E3),
    muted: const Color(0xFF8CA484),
    line: const Color(0xFF22371D),
    dash: const Color(0xFF35532C),
  ),
  AppPalette(
    key: 'orange',
    name: '暖橙',
    tag: '有精神',
    isDark: true,
    pri: const Color(0xFFF58A3C),
    deep: const Color(0xFFCE6A1E),
    soft: const Color(0xFF2B1E12),
    bg: const Color(0xFF191310),
    ink: const Color(0xFFF5EAE0),
    muted: const Color(0xFFAC937B),
    line: const Color(0xFF33251A),
    dash: const Color(0xFF51371F),
  ),
  AppPalette(
    key: 'coral',
    name: '珊瑚',
    tag: '少见好记',
    isDark: true,
    pri: const Color(0xFFF4695A),
    deep: const Color(0xFFD14C38),
    soft: const Color(0xFF2C1917),
    bg: const Color(0xFF1A1211),
    ink: const Color(0xFFF6E8E5),
    muted: const Color(0xFFAC8B83),
    line: const Color(0xFF35201C),
    dash: const Color(0xFF55302A),
  ),
  AppPalette(
    key: 'purple',
    name: '经典紫',
    tag: '原来那版',
    isDark: true,
    pri: const Color(0xFF8B78F0),
    deep: const Color(0xFF6A55D8),
    soft: const Color(0xFF1F1A38),
    bg: const Color(0xFF13101D),
    ink: const Color(0xFFEBE8F8),
    muted: const Color(0xFF9892B0),
    line: const Color(0xFF272340),
    dash: const Color(0xFF3D3563),
  ),
];

/// 取亮色版（设置页的色块预览固定用亮色，否则六张卡在暗色下全是黑块）
AppPalette paletteOf(String key) =>
    kPalettes.firstWhere((p) => p.key == key, orElse: () => kPalettes.first);

AppPalette darkPaletteOf(String key) => kDarkPalettes
    .firstWhere((p) => p.key == key, orElse: () => kDarkPalettes.first);

/// 外观模式。system 跟随系统，其余两条强制。
enum AppThemeMode { system, light, dark }

/// 全局主题状态。用 ChangeNotifier 而不是 Provider，
/// 是为了让 MaterialApp 直接重建、不需要在每个页面里插 InheritedWidget。
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme I = AppTheme._();

  static const _prefsKey = 'ui.theme';
  static const _prefsModeKey = 'ui.themeMode';

  String _key = kPalettes.first.key;
  AppThemeMode _mode = AppThemeMode.system;
  Brightness _sys = Brightness.light;

  String get key => _key;

  AppThemeMode get mode => _mode;

  bool get isDark =>
      _mode == AppThemeMode.dark ||
      (_mode == AppThemeMode.system && _sys == Brightness.dark);

  /// 当前生效的色板（可能来自亮色表，也可能来自暗色表）
  AppPalette get pal => isDark ? darkPaletteOf(_key) : paletteOf(_key);

  /// MaterialApp 用：显式给出两种色板，让 Flutter 自己做切换动画与系统栏适配
  AppPalette get lightPal => paletteOf(_key);
  AppPalette get darkPal => darkPaletteOf(_key);

  ThemeMode get flutterThemeMode => switch (_mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// 启动时读一次本地记忆；读失败就用默认靛蓝 + 跟随系统
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = p.getString(_prefsKey);
      if (k != null && kPalettes.any((e) => e.key == k)) _key = k;
      final m = p.getString(_prefsModeKey);
      _mode = AppThemeMode.values.firstWhere(
        (e) => e.name == m,
        orElse: () => AppThemeMode.system,
      );
    } catch (_) {}
  }

  /// 系统亮暗切换：只在「跟随系统」时才有实际效果，但仍要记录，
  /// 否则用户从系统深色切回 App 时拿到的是旧值。
  void setSystemBrightness(Brightness b) {
    if (_sys == b) return;
    _sys = b;
    if (_mode == AppThemeMode.system) notifyListeners();
  }

  /// 切主题：先改内存立刻生效，再异步落盘（写失败不影响使用）
  void set(String key) {
    if (!kPalettes.any((e) => e.key == key) || key == _key) return;
    _key = key;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKey, key))
        .catchError((_) => false);
  }

  void setMode(AppThemeMode m) {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsModeKey, m.name))
        .catchError((_) => false);
  }
}
