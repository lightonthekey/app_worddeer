import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// 内容包同步：启动后问一次后台"词库有没有新版"，有就下载、校验、原子替换本地文件。
///
/// 三条铁律：
/// 1. **本地优先** —— 任何请求都放在后台线程做，绝不阻塞首屏；失败绝不弹窗。
/// 2. **静默降级** —— 断网、后台没起、md5 不符，一律沿用上一次的词库，
///    连文件都没有就退回 assets/words.json。App 任何情况下都打得开。
/// 3. **原子替换** —— 先写 .tmp 再改名，下载中断不会留下半个词库文件。
class ContentSync {
  ContentSync._();
  static final ContentSync I = ContentSync._();

  /// 本地已生效的内容包版本号（0 = 还在用内置词库）
  int localVersion = 0;

  /// 本次启动是否下载到了新版本（main.dart 据此决定要不要热替换词库）
  bool updated = false;

  File? _localFile; // 缓存已解析的本地词库路径

  static const _kVersionKey = 'content_version_wordbank';
  static const _fileName = 'wordbank.json';

  /// 本地词库文件。null 表示还没有，用内置 asset。
  Future<File?> localFile() async {
    if (_localFile != null) return _localFile;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File(_join(dir.path, _fileName));
      if (await f.exists()) {
        _localFile = f;
        return f;
      }
    } catch (_) {
      // 拿不到目录（极少数 ROM 限制）就退回 asset
    }
    return null;
  }

  /// 启动后调用一次。全程不抛异常。
  Future<void> sync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      localVersion = prefs.getInt(_kVersionKey) ?? 0;

      // 版本号在但文件不在（清过数据 / 换了目录）：当作没有本地包，重新下载
      if (localVersion > 0 && await localFile() == null) {
        localVersion = 0;
      }

      final latest = await _fetchLatest();
      if (latest == null) return;
      if (latest['up_to_date'] == true) {
        debugPrint('[content] 词库已是最新 v$localVersion');
        return;
      }

      final version = (latest['version'] as num?)?.toInt() ?? 0;
      final expectMd5 = (latest['md5'] as String?) ?? '';
      final url = (latest['url'] as String?) ?? '';
      if (version <= localVersion || expectMd5.isEmpty || url.isEmpty) return;

      final bytes = await _download(url);
      if (bytes == null || bytes.isEmpty) return;
      final actual = md5.convert(bytes).toString();
      if (actual != expectMd5) {
        debugPrint('[content] md5 不符，丢弃本次更新（期望 $expectMd5 实际 $actual）');
        return;
      }

      final file = await _targetFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path); // 原子替换
      await prefs.setInt(_kVersionKey, version);
      localVersion = version;
      updated = true;
      debugPrint('[content] 词库已更新到 v$version（${bytes.length} 字节）');
    } catch (e) {
      debugPrint('[content] 同步跳过：$e');
    }
  }

  Future<Map<String, dynamic>?> _fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('${backendBase()}/api/v1/worddeer/content/latest?version=$localVersion'))
          .timeout(const Duration(seconds: 6));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 6));
      final data = jsonDecode(body);
      if (data is Map && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>?> _download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _targetFile() async {
    if (_localFile != null) return _localFile!;
    final dir = await getApplicationSupportDirectory();
    return File(_join(dir.path, _fileName));
  }

  /// dir.path 在 Windows 上不带尾分隔符，必须自己补上
  /// （实测漏写会把文件拼成 "app_worddeerwordbank.json"）
  static String _join(String dir, String name) =>
      dir.endsWith(Platform.pathSeparator) ? '$dir$name' : '$dir${Platform.pathSeparator}$name';
}
