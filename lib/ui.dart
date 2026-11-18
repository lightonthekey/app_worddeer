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

/// 带透明度的主题色：`ta(kPrimary, 0x3D)` 等价于 CSS 的 rgba(主色, 24%)
Color ta(Color c, int alpha) => c.withValues(alpha: alpha / 255);

/// 语义色不跟主题走：绿=对，红=错，火焰=连胜
const kGreen = Color(0xFF2E9E63);
const kRed = Color(0xFFD9534F);
const kAmber = Color(0xFFE0A020);
const kFlame = Color(0xFFE8674A);
const kGreen50 = Color(0xFFEAF7F0);
const kAmber50 = Color(0xFFFDF3E6);

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
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: t.pri).copyWith(
      primary: t.pri,
      surface: Colors.white,
      onSurface: t.ink,
    ),
    scaffoldBackgroundColor: t.bg,
    textSelectionTheme: TextSelectionThemeData(cursorColor: t.pri),
  );
}
