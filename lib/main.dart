import 'package:flutter/material.dart';

import 'bank.dart';
import 'curriculum.dart';
import 'pages/dict.dart';
import 'pages/home.dart';
import 'pages/me.dart';
import 'pages/review.dart';
import 'progress.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordBank.I.load();
  await Progress.I.load();
  await Curriculum.I.load();
  runApp(const EngApp());
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

class _ShellState extends State<Shell> {
  int _idx = 0;

  static const _pages = [HomePage(), ReviewPage(), DictPage(), MePage()];

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
