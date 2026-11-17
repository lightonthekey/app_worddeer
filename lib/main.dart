import 'dart:async';

import 'package:flutter/material.dart';

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
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordBank.I.load();
  await Progress.I.load();
  await Curriculum.I.load();
  await ProgressSync.I.init();
  await Ent.I.load();
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

class EngApp extends StatelessWidget {
  const EngApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '词鹿英语',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
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

  static const _pages = [HomePage(), ReviewPage(), DictPage(), MePage()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 切后台前补一次同步：手机上用户很少主动 "退出"，
  /// 趁着还在前台把没推的进度推掉，避免下次打开时数据落后太多
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ProgressSync.I.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: IndexedStack(index: _idx, children: _pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: Colors.white,
        indicatorColor: kPrimary.withValues(alpha: 0.12),
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
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
    );
  }
}
