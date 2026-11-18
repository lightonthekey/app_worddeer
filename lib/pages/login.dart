import 'package:flutter/material.dart';

import '../auth.dart';
import '../entitlement.dart';
import '../progress_sync.dart';
import '../ui.dart';

/// 登录 / 注册二合一页。
/// 返回 true 表示登录/注册成功（pop 传给上一个页面刷新状态）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  bool _isRegister = false; // false 登录 / true 注册
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isRegister) {
        await Auth.I.register(username, password, _nickname.text.trim());
      } else {
        await Auth.I.login(username, password);
      }
      // 登录成功立刻同步一次：把本机已有的学习进度带到账号上，并刷新会员权益
      ProgressSync.I.onAuthChanged();
      Ent.I.onAuthChanged();
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      setState(() {
        _error = '出错了，请稍后再试';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: Text(_isRegister ? '注册账号' : '登录',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
        centerTitle: true,
        iconTheme: IconThemeData(color: kInk),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isRegister ? '创建账号，学习进度云端同步' : '欢迎回来 👋',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk),
                  ),
                  const SizedBox(height: 4),
                  Text('进度会存在本地，登录是为换机同步做准备',
                      style: TextStyle(fontSize: 12, color: kMuted)),
                  const SizedBox(height: 18),
                  _field(
                    controller: _username,
                    label: '用户名',
                    hint: '2-24 位中文、字母、数字或下划线',
                    inputAction: TextInputAction.next,
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 12),
                    _field(
                      controller: _nickname,
                      label: '昵称（可选）',
                      hint: '给别人看的名字',
                      inputAction: TextInputAction.next,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _passwordField(),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(fontSize: 12.5, color: kRed)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isRegister ? '注册并登录' : '登录',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : () {
                      setState(() {
                        _isRegister = !_isRegister;
                        _error = null;
                      });
                    },
                    child: Text(
                      _isRegister ? '已有账号？去登录' : '没有账号？注册一个',
                      style: TextStyle(fontSize: 13, color: kPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputAction? inputAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textInputAction: inputAction,
          style: TextStyle(fontSize: 15, color: kInk),
          decoration: _deco(hint),
        ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('密码', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          onSubmitted: (_) => _submit(),
          style: TextStyle(fontSize: 15, color: kInk),
          decoration: _deco('至少 6 位').copyWith(
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20, color: kMuted),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12.5, color: kMuted),
        filled: true,
        fillColor: kBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kPrimary, width: 1.4),
        ),
      );
}
