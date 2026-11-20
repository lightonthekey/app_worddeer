import 'package:flutter/material.dart';

import 'theme.dart';

/// 颜色 token —— 全部读当前主题（`AppTheme.I.pal`），所以任何页面只要
/// 在 build 里引用这些 token，切主题时重建就能换色，不需要逐个传参。
/// 注意：这些是 getter，**不能放在 const 构造里**。
AppPalette get pal => AppTheme.I.pal;

Color get kPrimary => pal.pri;
Color get kPrimaryDeep => pal.deep;
Color get kPrimary50 => pal.soft;
Color get kBg => pal.bg;
Color get kInk => pal.ink;
Color get kMuted => pal.muted;
Color get kLine => pal.line;
Color get kDash => pal.dash;
Color get kHeroA => pal.heroA;
Color get kHeroB => pal.heroB;

Color get kPriLine => pal.priLine;
Color get kDoneBg => pal.doneBg;
Color get kDoneLine => pal.doneLine;
Color get kDoneText => pal.doneText;
Color get kCurEdge => pal.curEdge;
Color get kTrack => pal.track;
Color get kEdge => pal.edge;

/// 中性阶 n1..n5（浅 → 深）
Color get kN1 => pal.n1;
Color get kN2 => pal.n2;
Color get kN3 => pal.n3;
Color get kN4 => pal.n4;
Color get kN5 => pal.n5;

/// 卡片 / 弹层 / 输入框的「面」。亮色纯白，暗色是把底色抬一档的深灰。
/// 页面里凡是「白底」当容器用的地方都用它，别直接写 Colors.white ——
/// 那在深色模式下会变成一块刺眼的白板。
Color get kCard => pal.card;
Color get kCardAlt => pal.cardAlt;

/// 阴影色：暗色下要加深才看得出层次
Color get kShadow => pal.shadow;

/// 当前是否深色（少量地方需要按亮度微调，比如给图片加一层暗化）
bool get isDarkUI => pal.isDark;

/// 带透明度的主题色：`ta(kPrimary, 0x3D)` 等价于 CSS 的 rgba(主色, 24%)
Color ta(Color c, int alpha) => c.withValues(alpha: alpha / 255);

/// 语义色不跟主题走：绿=对，红=错，火焰=连胜
const kGreen = Color(0xFF2E9E63);
const kRed = Color(0xFFD9534F);
const kAmber = Color(0xFFE0A020);
const kFlame = Color(0xFFE8674A);
/// 语义色的浅底：深色下要换成「主色的暗雾」，否则会变成一块发光的小白板。
/// 注意这几个是 getter，不能写进 const 构造。
Color get kGreen50 => isDarkUI ? const Color(0xFF122A1C) : const Color(0xFFEAF7F0);
Color get kAmber50 => isDarkUI ? const Color(0xFF2A1F0E) : const Color(0xFFFDF3E6);

/// 会话结束后通知首页/复习页刷新
final ValueNotifier<int> appTick = ValueNotifier<int>(0);

/// 展示用版本号，务必与 pubspec.yaml 的 version 一致
const String kAppVersion = '1.0.0';

String greet() {
  final h = DateTime.now().hour;
  if (h < 6) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

ThemeData buildTheme([AppPalette? p]) {
  final t = p ?? pal;
  final brightness = t.isDark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: t.pri, brightness: brightness)
        .copyWith(
      primary: t.pri,
      onPrimary: Colors.white,
      surface: t.card,
      onSurface: t.ink,
      outline: t.line,
    ),
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.card,
    cardColor: t.card,
    dividerColor: t.line,
    dialogTheme: DialogThemeData(backgroundColor: t.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.isDark ? t.cardAlt : t.ink,
      contentTextStyle: TextStyle(color: t.isDark ? t.ink : Colors.white),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.pri,
      selectionColor: t.pri.withValues(alpha: .28),
      selectionHandleColor: t.pri,
    ),
  );
}
