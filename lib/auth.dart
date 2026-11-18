import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// 账号体系：用户名+密码登录，token 持久化，退出可撤销。
///
/// 与内容同步同一个原则：启动时的会话恢复放在后台做，失败静默降级为未登录，
/// App 功能不依赖登录也能用（学习进度本地保存，登录是为后面的云同步做准备）。
class Auth {
  Auth._();
  static final Auth I = Auth._();

  /// 当前登录用户；null = 未登录
  UserInfo? user;

  /// token 持久化在本地；请求失败过期的会在下次 me 校验时清掉
  String _token = '';

  /// 通知 UI 刷新（登录/登出后）
  final _changes = StreamController<UserInfo?>.broadcast();
  Stream<UserInfo?> get changes => _changes.stream;

  bool get loggedIn => user != null && _token.isNotEmpty;

  /// 当前 token（进度同步等带鉴权请求用）；未登录为空串
  String get token => _token;

  static const _kTokenKey = 'auth_token';
  static const _kUserKey = 'auth_user_json';

  /// 启动时恢复会话：本地有 token 就向后台校验一次，失效则清掉。
  /// 不阻塞首屏、不抛异常。
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_kTokenKey) ?? '';
      final cached = prefs.getString(_kUserKey);
      if (cached != null) {
        user = UserInfo.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
      if (_token.isEmpty) return;
      Map<String, dynamic>? data;
      try {
        data = await _get('/api/v1/worddeer/auth/me');
      } on AuthException {
        // token 过期/被撤销：清掉本地登录态，让 UI 回到未登录
        await _clear(prefs);
        return;
      }
      if (data == null) {
        await _clear(prefs);
        return;
      }
      final u = UserInfo.fromJson(data);
      user = u;
      await prefs.setString(_kUserKey, jsonEncode(u.toJson()));
      _changes.add(u);
      debugPrint('[auth] 会话已恢复：${u.username}');
    } catch (e) {
      debugPrint('[auth] 会话恢复跳过：$e');
    }
  }

  /// 登录。失败抛 [AuthException]，UI 捕获后展示 message。
  Future<void> login(String username, String password) async {
    final r = await _post('/api/v1/worddeer/auth/login',
        {'username': username, 'password': password});
    await _saveSession(r);
  }

  /// 注册（注册成功即登录）。失败抛 [AuthException]。
  Future<void> register(String username, String password, String nickname) async {
    final r = await _post('/api/v1/worddeer/auth/register', {
      'username': username,
      'password': password,
      if (nickname.isNotEmpty) 'nickname': nickname,
    });
    await _saveSession(r);
  }

  /// 退出登录：后台撤销 token，本地清登录态。后台不可达也照样清本地。
  Future<void> logout() async {
    try {
      await _post('/api/v1/worddeer/auth/logout', {});
    } catch (_) {
      // 撤销失败不阻塞本地登出，token 过期后服务端会自然失效
    }
    final prefs = await SharedPreferences.getInstance();
    await _clear(prefs);
    _changes.add(null);
  }

  /// 只清本地登录态，不调后台（离线登出 / 单测隔离用）
  Future<void> resetLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await _clear(prefs);
  }

  // ---------------------------------------------------------------- 内部

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    _token = data['token'] as String? ?? '';
    user = UserInfo.fromJson((data['user'] as Map).cast<String, dynamic>());
    await prefs.setString(_kTokenKey, _token);
    await prefs.setString(_kUserKey, jsonEncode(user!.toJson()));
    _changes.add(user);
  }

  Future<void> _clear(SharedPreferences prefs) async {
    _token = '';
    user = null;
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kUserKey);
  }

  /// 统一 POST：解出后台 {code,data} 包裹；code!=0 抛 AuthException
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final raw = await _request('POST', path, jsonEncode(body));
    return _unwrap(raw);
  }

  /// 统一 GET（带 token）
  Future<Map<String, dynamic>?> _get(String path) async {
    final raw = await _request('GET', path, null);
    final data = _unwrap(raw);
    return data.isEmpty ? null : data;
  }

  Future<String> _request(String method, String path, String? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .openUrl(method, Uri.parse('${backendBase()}$path'))
          .timeout(const Duration(seconds: 8));
      req.headers.contentType = ContentType.json;
      if (_token.isNotEmpty) req.headers.set('Authorization', 'Bearer $_token');
      if (body != null) req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final text = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      if (resp.statusCode == 401) {
        throw const AuthException('登录已过期，请重新登录');
      }
      if (resp.statusCode != 200) {
        throw AuthException('服务异常（${resp.statusCode}），稍后再试');
      }
      return text;
    } on SocketException {
      throw const AuthException('连不上服务器，请检查网络');
    } on TimeoutException {
      throw const AuthException('请求超时，请稍后再试');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _unwrap(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map || data['code'] != 0) {
      throw AuthException((data is Map && data['message'] is String && (data['message'] as String).isNotEmpty)
          ? data['message'] as String
          : '操作失败，请稍后再试');
    }
    final d = data['data'];
    return d == null ? <String, dynamic>{} : Map<String, dynamic>.from(d as Map);
  }
}

/// 业务错误：message 直接给用户看
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// 用户信息（与后台 auth.User 对应）
class UserInfo {
  final int id;
  final String username;
  final String nickname;
  final int role; // 1 免费 2 VIP 3 永久

  const UserInfo({required this.id, required this.username, required this.nickname, this.role = 1});

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: j['username'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        role: (j['role'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'nickname': nickname, 'role': role};

  /// 界面显示名：昵称是选填的，留空时退回用户名，避免出现空标题
  String get displayName {
    final n = nickname.trim();
    return n.isNotEmpty ? n : username;
  }

  /// 头像用的首字：显示名也拿不到时退回人形图标。
  /// 直接 `characters.first` 在空串上会抛 StateError（昵称可选，空串是常态）；
  /// 用 runes 取首个码点，emoji 昵称也不会被切成半个代理对。
  String get initial {
    final n = displayName.trim();
    if (n.isEmpty) return '👤';
    return String.fromCharCode(n.runes.first).toUpperCase();
  }
}
