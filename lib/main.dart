import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'audio.dart';
import 'auth.dart';
import 'bank.dart';
import 'content_sync.dart';
import 'curriculum.dart';
import 'entitlement.dart';
import 'pages/dict.dart';
import 'pages/home.dart';
import 'pages/me.dart';
import 'pages/review.dart';
import 'progress.dart';
import 'progress_sync.dart';
import 'theme.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _boot();
  runApp(const EngApp());
  // 内容检查与会话恢复都放后台跑：不阻塞首屏，失败静默降级。
  // 下载到新版词库后热替换，正在进行的对局用的是旧数据，下一局生效。
  unawaited(ContentSync.I.sync().then((_) async {
    if (ContentSync.I.updated) {
      await WordBank.I.load();
      Curriculum.I.invalidateCache();
    }
  }));
  // 权益与套餐：游客也要拉（付费墙得能显示价格与锁），失败沿用缓存
  unawaited(Ent.I.refresh());
  unawaited(Auth.I.restore().then((_) {
    // 登录态恢复后再同步进度与权益：游客启动时不会白发进度请求
    if (Auth.I.loggedIn) {
      ProgressSync.I.onAuthChanged();
      Ent.I.onAuthChanged();
    }
  }));
}

/// 逐项初始化，单项失败不影响其余模块、更不影响 runApp。
///
/// 之前这里是串行 `await`：词库文件被换成结构不对的包、或者某台机器上
/// prefs 读写异常，都会在 `runApp` 之前抛出，用户看到的是**永久白屏**。
/// 现在最坏情况是某个模块没数据（词库为空 → 首页显示空态），但 App 打得开。
Future<void> _boot() async {
  // 先把系统亮暗记下来，否则「跟随系统」的设备首帧会闪一下亮色
  AppTheme.I.setSystemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness);
  final steps = <String, Future<void> Function()>{
    '词库': WordBank.I.load,
    '学习进度': Progress.I.load,
    '课程进度': Curriculum.I.load,
    '进度同步': ProgressSync.I.init,
    '会员权益': Ent.I.load,
    '外观主题': AppTheme.I.load,
    '本地偏好': AppSettings.I.load,
  };
  for (final e in steps.entries) {
    try {
      await e.value();
    } catch (err, st) {
      debugPrint('[boot] ${e.key}初始化失败：$err\n$st');
    }
  }
}

class EngApp extends StatelessWidget {
  const EngApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题一变，整棵树重建：颜色 token 都是 getter，重建即换色
    return AnimatedBuilder(
      animation: AppTheme.I,
      builder: (_, _) => MaterialApp(
        title: '词鹿英语',
        debugShowCheckedModeBanner: false,
        // 亮/暗两套色板都交给 MaterialApp：跟随系统时由 Flutter 自己切，
        // 我们用 themeMode 表达「跟随/强制亮/强制暗」。
        theme: buildTheme(AppTheme.I.lightPal),
        darkTheme: buildTheme(AppTheme.I.darkPal),
        themeMode: AppTheme.I.flutterThemeMode,
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _idx = 0;

  /// 首页下拉面板里的「去复习」要能切到复习 tab，所以把切换入口传进去。
  /// 每次 build 重新构造（而不是存成 late final）：切主题时要让每个页面
  /// 都重新 build 一次，颜色 token 才会跟着换。
  List<Widget> _buildPages() => [
        HomePage(onNavigate: (i) => setState(() => _idx = i)),
        const ReviewPage(),
        const DictPage(),
        const MePage(),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 发音失败统一在这里提示一次：各页面调用点只管调 Voice.say，
    // 弱网/无声时用户至少知道是加载失败，不是 App 卡住。
    Voice.failTick.addListener(_onVoiceFail);
  }
  @override
  void dispose() {
    Voice.failTick.removeListener(_onVoiceFail);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onVoiceFail() {
    if (!mounted) return;
    final w = Voice.lastFailWord;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(w.isEmpty ? '发音加载失败，请检查网络后重试' : '「$w」发音加载失败，请检查网络'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: w.isEmpty
            ? null
            : SnackBarAction(label: '重试', onPressed: () => Voice.say(w)),
      ));
  }

  /// 切后台前补一次同步：手机上用户很少主动 "退出"，
  /// 趁着还在前台把没推的进度推掉，避免下次打开时数据落后太多
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ProgressSync.I.syncNow();
  }

  /// 系统切深/浅色：AppTheme 只在「跟随系统」时通知重建
  @override
  void didChangePlatformBrightness() {
    AppTheme.I
        .setSystemBrightness(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppTheme.I,
      builder: (_, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    // 没有 AppBar，状态栏图标要自己声明亮/暗，否则深色模式下顶上是黑字贴黑底
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.I.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: IndexedStack(index: _idx, children: _buildPages()),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: kCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: kPrimary.withValues(alpha: 0.12),
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department, color: kPrimary),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.replay_outlined),
            selectedIcon: Icon(Icons.replay, color: kPrimary),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: kPrimary),
            label: '词典',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: kPrimary),
            label: '我的',
          ),
        ],
      ),
      ),
    );
  }
}
