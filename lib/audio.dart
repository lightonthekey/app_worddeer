import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'backend.dart';

/// 发音服务地址。缺省跟随后台域名（发音文件已经迁到 platform_meta 的
/// resource/public/audio/eng 下，和内容接口同源）；本地联调可覆盖：
///   flutter run --dart-define=AUDIO_BASE=http://10.0.2.2:12445
const String _kAudioBaseOverride = String.fromEnvironment('AUDIO_BASE');

String get audioBase =>
    _kAudioBaseOverride.isEmpty ? backendBase() : _kAudioBaseOverride;

/// 回源地址（按顺序尝试）。platform 是正式源；tooldeer 主站保留为兜底，
/// 万一 platform 域名当日没部署好，发音仍能用。稳定后可以只留第一条。
List<String> _audioUrls(String word, String type) {
  final w = Uri.encodeComponent(word);
  return [
    '$audioBase/api/v1/worddeer/audio?word=$w&type=$type',
    'https://tooldeer.com/api/v1/engmatch/audio?word=$w&type=$type',
  ];
}

/// 单文件小于这个字节数视为坏文件（发音源出错时会回一段 HTML）
const int _minAudioBytes = 2000;

/// 缓存总量上限：超过就按最久未播放清理。7201 词 × 2 口音全下也只有 ~300MB，
/// 但没必要常驻，50MB 已经能覆盖几千个常听词。
const int _cacheLimitBytes = 50 * 1024 * 1024;
const int _cacheTrimToBytes = 35 * 1024 * 1024;

class Voice {
  static final AudioPlayer _p = AudioPlayer();

  /// 发音失败信号。UI 层（Shell）监听它弹一次提示，调用点不用各自 try/catch。
  /// 值是递增的序号而不是 bool，连续失败才能每次都触发。
  static final ValueNotifier<int> failTick = ValueNotifier<int>(0);

  /// 最近一次失败涉及的生词，提示里可以带上（也可留空只说"网络"）
  static String lastFailWord = '';

  static DateTime _lastFailAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _trimmed = false;

  /// 正在下载的文件，避免同一词连点几次发多个请求
  static final Map<String, Future<File?>> _inflight = {};

  /// 发音。[type] 不传时用「设置 → 发音」里选的口音。
  ///
  /// 顺序：本地缓存 → 下载落盘 → 直接流式播放（兜底）。
  /// 三步都失败才发 [failTick]，因为发音失败不该打断答题。
  static Future<void> say(String word, {String? type}) async {
    if (word.isEmpty) return;
    final t = type ?? AppSettings.I.accent;
    try {
      await _p.stop();
      final file = await _cached(word, t);
      if (file != null) {
        try {
          await _p.play(DeviceFileSource(file.path));
          return;
        } catch (e) {
          // 缓存文件坏了（下载中断 / 存储损坏）：删掉重下一次，仍失败就走流式
          debugPrint('[audio] 本地缓存无法播放，重取：$e');
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      // 下载不到（离线 / 服务端没这个词）时仍然试着直接播流，
      // 有些平台对 302/流式更宽容，比直接报错多一次机会。
      for (final url in _audioUrls(word, t)) {
        try {
          await _p.play(UrlSource(url));
          return;
        } catch (_) {
          continue;
        }
      }
      _fail(word);
    } catch (e) {
      debugPrint('[audio] 发音失败：$e');
      _fail(word);
    }
  }

  /// 预取一组词的音频（进入一关时调，20 词 ≈ 1MB）。
  /// 失败静默：这只是优化，不该让开局的动画等它。
  static Future<void> prefetch(Iterable<String> words, {String? type}) async {
    final t = type ?? AppSettings.I.accent;
    for (final w in words) {
      if (w.isEmpty) continue;
      unawaited(_cached(w, t));
    }
  }

  static void _fail(String word) {
    lastFailWord = word;
    final now = DateTime.now();
    // 弱网下连点会连着失败，3 秒内只提示一次，避免刷屏
    if (now.difference(_lastFailAt) < const Duration(seconds: 3)) return;
    _lastFailAt = now;
    failTick.value = failTick.value + 1;
  }

  // ---------------------------------------------------------------- 缓存

  static Directory? _dir;

  static Future<Directory?> _cacheDir() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationCacheDirectory();
      final d = Directory('${base.path}/audio');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      return d;
    } catch (e) {
      debugPrint('[audio] 缓存目录不可用：$e');
      return null;
    }
  }

  /// 文件名规则必须与后台 tools/fetch_eng_audio.py 保持一致：
  /// 非 [A-Za-z0-9] 一律换下划线，再 trim('_')。
  static String cacheName(String word, String type) {
    final s = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final t = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return '${t.isEmpty ? 'word' : t}_$type.mp3';
  }

  /// 返回可播放的本地文件；缓存未命中则下载（失败返回 null）。
  static Future<File?> _cached(String word, String type) {
    final key = cacheName(word, type);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final fut = _loadOrFetch(word, type, key);
    _inflight[key] = fut;
    return fut.whenComplete(() => _inflight.remove(key));
  }

  static Future<File?> _loadOrFetch(String word, String type, String key) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final f = File('${dir.path}/$key');
    try {
      if (await f.exists() && await f.length() > _minAudioBytes) {
        await _touch(f);
        return f;
      }
    } catch (_) {}

    for (final url in _audioUrls(word, type)) {
      final ok = await _download(url, f);
      if (ok) {
        unawaited(_trimIfNeeded(dir));
        return f;
      }
    }
    return null;
  }

  static Future<bool> _download(String url, File dest) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      final resp = await req.close().timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return false;
      final type = resp.headers.contentType;
      if (type != null && !type.mimeType.startsWith('audio')) return false;
      final tmp = File('${dest.path}.part');
      final sink = tmp.openWrite();
      var n = 0;
      await for (final chunk in resp.timeout(const Duration(seconds: 12))) {
        n += chunk.length;
        sink.add(chunk);
        // 正常单个 mp3 几十 KB，超过 5MB 一定是服务端回了别的东西
        if (n > 5 * 1024 * 1024) {
          await sink.close();
          await tmp.delete();
          return false;
        }
      }
      await sink.close();
      if (n <= _minAudioBytes) {
        await tmp.delete();
        return false;
      }
      await tmp.rename(dest.path);
      return true;
    } catch (e) {
      debugPrint('[audio] 下载失败 $url：$e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 更新 mtime 当作「最近使用」，清理时按它排 LRU
  static Future<void> _touch(File f) async {
    try {
      await f.setLastModified(DateTime.now());
    } catch (_) {}
  }

  static Future<void> _trimIfNeeded(Directory dir) async {
    if (_trimmed) return;
    _trimmed = true;
    try {
      final files = <FileSystemEntity>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        total += st.size;
        files.add(e);
      }
      if (total <= _cacheLimitBytes) return;
      files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final e in files) {
        if (total <= _cacheTrimToBytes) break;
        final size = e.statSync().size;
        try {
          await e.delete();
          total -= size;
        } catch (_) {}
      }
      debugPrint('[audio] 缓存已清理到 ${total ~/ 1024}KB');
    } catch (e) {
      debugPrint('[audio] 缓存清理失败：$e');
    }
  }
}
