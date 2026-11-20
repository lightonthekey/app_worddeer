import 'package:app_worddeer/crash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 这些用例跑在没有 SENTRY_DSN 的环境里（测试进程不会注入 dart-define），
  // 正好覆盖「没配 DSN」这条最容易被忽略的路径：SDK 不启动，但也不能崩。
  test('没有 DSN 时按未启用处理', () {
    expect(Crash.enabled, isFalse);
  });

  test('init 装好兜底 handler：框架异常被记下来且不抛出', () async {
    await Crash.init();
    expect(FlutterError.onError, isNotNull);

    // 模拟一帧里的渲染异常：兜底 handler 应该吃掉它（debug 下走默认红屏逻辑）
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('渲染炸了')));
  });

  test('report 在未启用时只打日志，不抛异常', () async {
    await Crash.init();
    await Crash.report(StateError('boom'), StackTrace.current, where: 'test');
  });

  test('未启用时 setUser 是空操作', () {
    Crash.setUser(42);
    Crash.setUser(null);
  });
}
