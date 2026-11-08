import 'package:flutter/material.dart';

const kPrimary = Color(0xFF6D5AE0);
const kBg = Color(0xFFFAF9FE);
const kInk = Color(0xFF22202B);
const kMuted = Color(0xFF8A86A0);
const kLine = Color(0xFFEDEAF7);
const kGreen = Color(0xFF2E9E63);
const kRed = Color(0xFFD9534F);
const kAmber = Color(0xFFE0A020);

/// 设计稿（design/demo.html）里的辅助色
const kPrimaryDeep = Color(0xFF4A41C4);
const kPrimary50 = Color(0xFFF1EFFC);
const kGreen50 = Color(0xFFEAF7F0);
const kAmber50 = Color(0xFFFDF3E6);
const kFlame = Color(0xFFE8674A);
const kHeroA = Color(0xFF655CE8);
const kHeroB = Color(0xFF4A41C4);

/// 会话结束后通知首页/复习页刷新
final ValueNotifier<int> appTick = ValueNotifier<int>(0);

String greet() {
  final h = DateTime.now().hour;
  if (h < 6) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kPrimary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: kBg,
    );

