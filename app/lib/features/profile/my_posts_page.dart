import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/feed_card.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';
import '../checkin/owner_actions_sheet.dart';
import '../comment/comment_sheet.dart';

/// 我的发帖（全部打卡）：GET /users/{uid}/checkins 自己视角=全部可见范围，
/// 游标分页 + 互动（点亮/拥抱/同路/留言）。
class MyPostsPage extends StatefulWidget {
  const MyPostsPage({super.key});

  @override
  State<MyPostsPage> createState() => _MyPostsPageState();
}

class _MyPostsPageState extends State<MyPostsPage> {
  final List<Checkin> _items = [];
  int _nextCursor = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _fetch();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(_parseItems(data));
        _nextCursor = _parseCursor(data);
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

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _nextCursor == 0) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _fetch(cursor: _nextCursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(_parseItems(data));
        _nextCursor = _parseCursor(data);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      Toast.show(context, '加载更多失败，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> _fetch({int cursor = 0}) async {
    final uid = context.read<AuthController>().user?.id;
    if (uid == null) throw StateError('未登录');
    final q = cursor > 0 ? '?cursor=$cursor' : '';
    return context.read<AuthController>().api.get<Map<String, dynamic>>(
          '/users/$uid/checkins$q',
          parser: (d) => Map<String, dynamic>.from(d as Map),
        );
  }

  List<Checkin> _parseItems(Map<String, dynamic> data) {
    final raw = data['items'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => Checkin.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  int _parseCursor(Map<String, dynamic> data) =>
      (data['next_cursor'] as num?)?.toInt() ?? 0;

  Future<void> _onAction(String action, Checkin c) async {
    if (action == 'comment') {
      await CommentSheet.show(
        context,
        checkinId: c.id,
        checkinOwnerId: c.userId,
      );
      // 留言弹层关闭后刷新（卡片预览需要最新留言）
      _reload();
      return;
    }
    final type = switch (action) {
      'light' => 1,
      'hug' => 2,
      'companion' => 3,
      _ => 0,
    };
    if (type == 0) return;
    final active = c.hasReaction(type);
    try {
      await context
          .read<CheckinController>()
          .toggleReaction(c.id, type, currentlyActive: active);
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((e) => e.id == c.id);
        if (idx >= 0) {
          final reactions = Set<int>.from(_items[idx].myReactions);
          active ? reactions.remove(type) : reactions.add(type);
          final sorted = reactions.toList()..sort();
          _items[idx] = _items[idx].copyWith(myReactions: sorted);
        }
      });
      if (type == 3 && !active) Toast.show(context, '已加入同路');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请稍后重试');
    }
  }

  /// 长按自己的打卡：管理可见范围 / 删除（本地列表不走 Controller，变更后刷新）。
  Future<void> _ownerActions(Checkin c) async {
    final changed = await showOwnerActions(
      context,
      c,
      onVisibility: (v) =>
          context.read<CheckinController>().setVisibility(c.id, v),
      onDelete: () => context.read<CheckinController>().delete(c.id),
    );
    if (changed && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('我的拾光'),
      ),
      body: _buildBody(auth),
    );
  }

  Widget _buildBody(AuthController auth) {
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
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 40, color: AppTheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('还没有发布过内容',
                style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
            const SizedBox(height: 4),
            const Text('点首页下方的 +，拾起今天的第一束光',
                style: TextStyle(fontSize: 12, color: AppTheme.textFaint)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) _loadMore();
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i >= _items.length) {
              return _nextCursor > 0
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('没有更多了',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textFaint)),
                    );
            }
            final c = _items[i];
            return GestureDetector(
              // 长按自己的打卡：改可见范围 / 删除
              onLongPress: () => _ownerActions(c),
              child: FeedCard(
                checkin: c,
                nickname: auth.user?.nickname ?? '我',
                avatarUrl: auth.user?.avatarUrl,
                onAction: (a) => _onAction(a, c),
              ),
            );
          },
        ),
      ),
    );
  }
}
