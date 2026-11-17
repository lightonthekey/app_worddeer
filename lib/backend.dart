import 'dart:io';

import 'package:flutter/foundation.dart';

/// 测试重定向：单测里指向本地 mock 服务，生产代码不要动它
String? debugBaseOverride;

/// 后台服务地址。全 App 只此一处定义，登录与内容同步共用。
/// 上线前把域名反代到 admin_platform 服务，改这里即可。
/// Android 模拟器访问宿主机要用 10.0.2.2；真机调试时改成电脑的局域网 IP。
String backendBase() {
  if (debugBaseOverride != null) return debugBaseOverride!;
  if (kReleaseMode) {
    // TODO 上线前改为正式域名（https）
    return 'https://tooldeer.com';
  }
  return Platform.isAndroid ? 'http://10.0.2.2:12445' : 'http://127.0.0.1:12445';
}
