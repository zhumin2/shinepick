import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/avatar.dart';
import '../auth/auth_controller.dart';

/// 同路人列表页：TA 与谁互为同路人，点击头像行进入对方公开主页。
class CompanionsPage extends StatefulWidget {
  final int userId;
  const CompanionsPage({super.key, required this.userId});

  @override
  State<CompanionsPage> createState() => _CompanionsPageState();
}

class _CompanionsPageState extends State<CompanionsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<AuthController>().api.get<Map<String, dynamic>>(
            '/users/${widget.userId}/companions',
            parser: (d) => Map<String, dynamic>.from(d as Map),
          );
      if (!mounted) return;
      setState(() {
        final raw = data['items'] as List<dynamic>? ?? const [];
        _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('同路人'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.textSub)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_outlined,
                size: 40, color: AppTheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('还没有同路人',
                style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
            const SizedBox(height: 4),
            const Text('去发现页给同频的人点一个「同路」吧',
                style: TextStyle(fontSize: 12, color: AppTheme.textFaint)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${_items.length} 位同路人',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textFaint)),
          ),
          const SizedBox(height: 8),
          for (final item in _items)
            _CompanionRow(
              id: (item['id'] as num).toInt(),
              nickname: item['nickname'] as String? ?? '拾光用户',
              avatarUrl: item['avatar_url'] as String? ?? '',
              since: DateTime.tryParse(item['since'] as String? ?? ''),
            ),
        ],
      ),
    );
  }
}

class _CompanionRow extends StatelessWidget {
  final int id;
  final String nickname;
  final String avatarUrl;
  final DateTime? since;

  const _CompanionRow({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    this.since,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Avatar(url: avatarUrl, nickname: nickname, size: 44),
        title: Text(nickname,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain)),
        subtitle: Text(_sinceLabel(),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
        trailing: const Icon(Icons.chevron_right,
            size: 18, color: AppTheme.textFaint),
        onTap: () => context.push('/user/$id'),
      ),
    );
  }

  String _sinceLabel() {
    final t = since;
    if (t == null) return '同行中';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} 同路';
  }
}
