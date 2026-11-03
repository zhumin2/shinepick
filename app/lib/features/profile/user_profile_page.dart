import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/error/app_error.dart';
import '../auth/auth_controller.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/feed_card.dart';

/// 他人公开主页（S9）：资料 + TA 的同路人可见拾光列表。
class UserProfilePage extends StatefulWidget {
  final int userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? _profile;
  List<Checkin> _checkins = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = context.read<AuthController>();
      final api = auth.api;

      // 并行获取资料和打卡列表
      final results = await Future.wait([
        api.get<Map<String, dynamic>>('/users/${widget.userId}',
            parser: (d) => Map<String, dynamic>.from(d as Map)),
        api.get<Map<String, dynamic>>('/users/${widget.userId}/checkins',
            parser: (d) => Map<String, dynamic>.from(d as Map)),
      ]);

      if (!mounted) return;
      setState(() {
        _profile = results[0];
        final raw = results[1]['items'] as List<dynamic>? ?? const [];
        _checkins = raw
            .map((e) => Checkin.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '加载失败，请稍后重试'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('个人主页')),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('个人主页')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppTheme.textSub)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final p = _profile!;
    final nickname = p['nickname'] as String? ?? '';
    final avatarUrl = p['avatar_url'] as String? ?? '';
    final bio = p['bio'] as String? ?? '';
    final stats = p['stats'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(nickname),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // 横排头部（同原型 profile-head）
            Row(
              children: [
                Avatar(url: avatarUrl, nickname: nickname, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nickname,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain)),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSub)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 统计（打卡次数 / 连续天数 / 同路人）
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat('${stats['checkin_count'] ?? 0}', '打卡次数'),
                  _divider(),
                  _Stat('${stats['checkin_days'] ?? 0}', '打卡天数'),
                  _divider(),
                  _Stat('${stats['streak_days'] ?? 0}', '连续天数'),
                  _divider(),
                  // 同路人可点：查看 TA 的同路人列表
                  GestureDetector(
                    onTap: () => context.push('/companions/${widget.userId}'),
                    child: _Stat('${stats['companions'] ?? 0}', '同路人'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // TA 的拾光
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('TA 的拾光',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain)),
            ),
            const SizedBox(height: 10),
            if (_checkins.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('还没有公开的拾光',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
              )
            else
              for (final c in _checkins)
                FeedCard(
                  checkin: c,
                  nickname: nickname,
                  avatarUrl: avatarUrl,
                ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 24, color: AppTheme.divider);
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
      ],
    );
  }
}
