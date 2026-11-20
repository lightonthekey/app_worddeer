import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'ui.dart';

/// 崩溃上报。
///
/// 为什么用 Sentry 不用 Firebase：Crashlytics 依赖 Google Play 服务，
/// 中国大陆的安卓机基本没装 GMS，崩溃根本发不出去（而且 firebase 域名也不稳）；
/// Sentry 是纯 HTTP 上报，DSN 还能指向自建实例，换区、备案都不受影响。
/// 这里只上报崩溃与关键失败，不开性能追踪（tracesSampleRate = 0）省额度。
///
/// DSN 不写进仓库：`--dart-define=SENTRY_DSN=...` 注入。没注入时整套 SDK 不启动，
/// 只装一个把错误打到 console 的兜底 handler —— 本地开发、内测包、
/// 还没建 Sentry 项目的阶段都不会因为缺配置而报错，也不会白屏。
class Crash {
  Crash._();

  static const String _dsn = String.fromEnvironment('SENTRY_DSN');

  /// 配了 DSN 才真正上报
  static bool get enabled => _dsn.isNotEmpty;

  static bool _ready = false;

  /// 启动时调用一次。有 DSN 就交给 Sentry（它会自己接管
  /// FlutterError.onError 和 PlatformDispatcher.onError），否则只装兜底 handler。
  static Future<void> init() async {
    if (!enabled) {
      _installFallback();
      return;
    }
    try {
      await SentryFlutter.init((o) {
        o.dsn = _dsn;
        o.environment = kReleaseMode ? 'production' : 'debug';
        o.release = 'app_worddeer@$kAppVersion';
        o.attachStacktrace = true;
        // 只收崩溃：性能追踪、会话统计都关掉，免费额度留给真问题
        o.tracesSampleRate = 0;
        o.enableAutoSessionTracking = false;
        o.maxBreadcrumbs = 40;
        o.sendDefaultPii = false; // 不自动带 IP / 设备标识
        // 学习内容（单词、释义）可能出现在界面文案里，别跟着事件发出去
        o.beforeBreadcrumb = (crumb, hint) {
          if (crumb == null) return crumb;
          // 点击/页面跳转的面包屑会带上控件文字（可能就是正在学的词）
          if (crumb.category == 'ui.click' || crumb.category == 'navigation') {
            crumb.data?.remove('text');
          }
          return crumb;
        };
      });
      _ready = true;
    } catch (err) {
      // SDK 起不来也不能让 App 起不来：退回本地日志
      debugPrint('[crash] Sentry 初始化失败，本次运行只记录到 console：$err');
      _installFallback();
    }
  }

  /// 登录态变化时把人挂到事件上：只发账号数字 id，不发用户名（不落 PII）。
  static void setUser(int? id) {
    if (!_ready) return;
    Sentry.configureScope(
      (scope) => scope.setUser(id == null ? null : SentryUser(id: '$id')),
    );
  }

  /// 非致命错误（启动项失败、同步失败这类）：不影响用户，但要能看见。
  static Future<void> report(
    Object error,
    StackTrace? stack, {
    String? where,
    Map<String, Object?>? extra,
  }) async {
    if (!_ready) {
      debugPrint('[crash]${where == null ? '' : ' $where'} $error');
      return;
    }
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        if (where != null) scope.setTag('where', where);
        if (extra != null) scope.setContexts('extra', extra);
      },
    );
  }

  /// 没有 DSN 时的兜底：release 包只打日志不崩，debug 保留红屏方便定位。
  static void _installFallback() {
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      if (kDebugMode) {
        prev?.call(details);
        return;
      }
      debugPrint('[crash] ${details.exceptionAsString()}\n${details.stack}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[crash] $error\n$stack');
      return true; // 已经记下来了，别让学习中的用户因为一个渲染异常闪退
    };
  }
}
