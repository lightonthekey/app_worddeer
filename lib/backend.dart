import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 测试重定向：单测里指向本地 mock 服务，生产代码不要动它
String? debugBaseOverride;

/// 后台服务地址。全 App 只此一处定义，登录、内容同步、进度同步共用。
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

/// 后台业务错误：message 可以直接展示给用户
class ApiException implements Exception {
  final String message;
  final int code;
  const ApiException(this.message, [this.code = -1]);
  @override
  String toString() => message;
}

/// 带鉴权的 JSON 请求，统一解出后台 `{code,message,data}` 里的 data。
///
/// 约定（与 admin_platform_v2 一致）：HTTP 恒为 200，业务错误放在 code 里；
/// code != 0 抛 [ApiException]，网络问题抛同样类型的异常（文案面向用户）。
Future<Map<String, dynamic>> apiJson(
  String path, {
  String method = 'POST',
  Map<String, dynamic>? body,
  String? token,
  Duration connectTimeout = const Duration(seconds: 6),
  Duration readTimeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient()..connectionTimeout = connectTimeout;
  try {
    final req = await client
        .openUrl(method, Uri.parse('${backendBase()}$path'))
        .timeout(connectTimeout);
    req.headers.contentType = ContentType.json;
    if (token != null && token.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer $token');
    }
    if (body != null) req.write(jsonEncode(body));
    final resp = await req.close().timeout(readTimeout);
    final text =
        await resp.transform(utf8.decoder).join().timeout(readTimeout);
    if (resp.statusCode == 401) {
      throw const ApiException('登录已过期，请重新登录', 401);
    }
    if (resp.statusCode != 200) {
      throw ApiException('服务异常（${resp.statusCode}），稍后再试', resp.statusCode);
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const ApiException('服务返回格式异常');
    }
    final code = (decoded['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final msg = decoded['message'];
      throw ApiException(
        (msg is String && msg.isNotEmpty) ? msg : '操作失败，请稍后再试',
        code,
      );
    }
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  } on SocketException {
    throw const ApiException('连不上服务器，请检查网络');
  } on TimeoutException {
    throw const ApiException('请求超时，请稍后再试');
  } finally {
    client.close(force: true);
  }
}
