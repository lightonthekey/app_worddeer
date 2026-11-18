import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 6 套配色，与 design/wb-theme.js 一一对应。
///
/// 每套只定义 8 个基准色，其余（已学底、描边、深色底边、轨道、中性灰）
/// 全部由同一套公式推出来 —— 6 套共用一个公式，才不会出现「这套调过、
/// 那套忘了」。派生值第一次取用时算好并缓存。
class AppPalette {
  final String key;
  final String name;
  final String tag;

  /// 主色：按钮、当前节点、进度条、选中描边
  final Color pri;

  /// 主色深：渐变暗端、按下态、文字强调
  final Color deep;

  /// 主色浅底：已学完的方块底、胶囊底
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
  });

  late final Color heroA = pri;
  late final Color heroB = deep;

  /// 选中描边 / hover 描边
  late final Color priLine = _mix(Colors.white, pri, .28);

  /// 已学完方块的底与描边
  late final Color doneBg = _mix(Colors.white, pri, .07);
  late final Color doneLine = _mix(Colors.white, pri, .20);

  /// 已学完方块上的字
  late final Color doneText = _mix(deep, Colors.black, .20);

  /// 实心方块底下那条「厚度」边
  late final Color curEdge = _mix(deep, Colors.black, .16);

  /// 进度条 / 滑块的未填充轨道
  late final Color track = _mix(bg, pri, .10);

  /// 桌面预览时机身外的那圈底色
  late final Color edge = _mix(bg, ink, .10);

  /// 中性阶：n1 最浅（分段底、按下态），n5 最深（禁用/占位字）
  late final Color n1 = _mix(bg, ink, .05);
  late final Color n2 = _mix(bg, ink, .10);
  late final Color n3 = _mix(bg, ink, .26);
  late final Color n4 = _mix(bg, ink, .52);
  late final Color n5 = _mix(bg, ink, .72);

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

/// 6 套主题（顺序与「我的 → 外观主题」里的排列一致）
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

AppPalette paletteOf(String key) =>
    kPalettes.firstWhere((p) => p.key == key, orElse: () => kPalettes.first);

/// 全局主题状态。用 ValueListenable 而不是 Provider，
/// 是为了让 MaterialApp 直接重建、不需要在每个页面里插 InheritedWidget。
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme I = AppTheme._();

  static const _prefsKey = 'ui.theme';

  AppPalette _pal = kPalettes.first;
  AppPalette get pal => _pal;
  String get key => _pal.key;

  /// 启动时读一次本地记忆；读失败就用默认靛蓝
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = p.getString(_prefsKey);
      if (k != null && k != _pal.key) {
        _pal = paletteOf(k);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 切主题：先改内存立刻生效，再异步落盘（写失败不影响使用）
  void set(String key) {
    final next = paletteOf(key);
    if (next.key == _pal.key) return;
    _pal = next;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKey, key))
        .catchError((_) => false);
  }
}
