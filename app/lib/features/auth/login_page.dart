import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

/// 登录页：手机号 + 验证码。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode(AuthController auth) async {
    final phone = _phoneController.text.trim();
    if (phone.length != 11) {
      _toast('请输入 11 位手机号');
      return;
    }
    try {
      await auth.sendSmsCode(phone);
      _toast('验证码已发送（dev 固定验证码 123456）');
    } on AppError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('网络异常，请稍后重试');
    }
  }

  Future<void> _login(AuthController auth) async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.length != 11) {
      _toast('请输入 11 位手机号');
      return;
    }
    if (code.length != 6) {
      _toast('请输入 6 位验证码');
      return;
    }
    try {
      await auth.login(phone, code);
    } on AppError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('网络异常，请稍后重试');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 72),
              // Logo 区
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.wb_sunny_outlined,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 20),
              const Text(
                '拾光 ShinePick',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '把运动、阅读、旅行、小聚和毛孩子的日常，\n一点一点拾起来。',
                style: TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.6),
              ),
              const SizedBox(height: 40),
              // 手机号
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  hintText: '请输入 11 位手机号',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              // 验证码 + 发送按钮
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '验证码',
                        hintText: '6 位验证码',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: (auth.cooldownSeconds > 0 || auth.sendingCode)
                          ? null
                          : () => _sendCode(auth),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        auth.cooldownSeconds > 0
                            ? '${auth.cooldownSeconds}s'
                            : '获取验证码',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _login(auth),
                child: const Text('登录 / 注册'),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '登录即代表同意《用户协议》与《隐私政策》',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
