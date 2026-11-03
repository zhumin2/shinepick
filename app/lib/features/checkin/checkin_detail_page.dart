import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/emoji_text.dart';
import '../../shared/widgets/feed_card.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';
import '../comment/comment_sheet.dart';

/// 打卡详情页：完整内容 + 全部留言（分页）+ 互动。
/// 入口：Feed 卡片点击、通知点击跳转（/checkin/:id）。
class CheckinDetailPage extends StatefulWidget {
  final int checkinId;
  const CheckinDetailPage({super.key, required this.checkinId});

  @override
  State<CheckinDetailPage> createState() => _CheckinDetailPageState();
}

class _CheckinDetailPageState extends State<CheckinDetailPage> {
  Checkin? _checkin;
  Map<String, dynamic>? _author;
  final List<CommentVO> _comments = [];
  int _nextCursor = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<Map<String, dynamic>> _get(String path) =>
      context.read<AuthController>().api.get<Map<String, dynamic>>(
            path,
            parser: (d) => Map<String, dynamic>.from(d as Map),
          );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _get('/checkins/${widget.checkinId}'),
        _get('/checkins/${widget.checkinId}/comments'),
      ]);
      if (!mounted) return;
      setState(() {
        _checkin = Checkin.fromJson(
            Map<String, dynamic>.from(results[0]['checkin'] as Map));
        _author = Map<String, dynamic>.from(results[0]['user'] as Map? ?? {});
        _comments
          ..clear()
          ..addAll(_parseComments(results[1]));
        _nextCursor = (results[1]['next_cursor'] as num?)?.toInt() ?? 0;
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
        _error = '内容不存在或已被删除';
      });
    }
  }

  Future<void> _loadMoreComments() async {
    if (_loadingMore || _nextCursor == 0) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _get(
          '/checkins/${widget.checkinId}/comments?cursor=$_nextCursor');
      if (!mounted) return;
      setState(() {
        _comments.addAll(_parseComments(data));
        _nextCursor = (data['next_cursor'] as num?)?.toInt() ?? 0;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  List<CommentVO> _parseComments(Map<String, dynamic> data) {
    final raw = data['items'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => CommentVO.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _onAction(String action) async {
    final c = _checkin;
    if (c == null) return;
    if (action == 'comment') {
      await CommentSheet.show(
        context,
        checkinId: c.id,
        checkinOwnerId: c.userId,
      );
      // 留言后刷新详情与留言列表
      _load();
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
      final reactions = Set<int>.from(c.myReactions);
      active ? reactions.remove(type) : reactions.add(type);
      setState(() {
        _checkin = c.copyWith(myReactions: reactions.toList()..sort());
      });
      if (type == 3 && !active) Toast.show(context, '已加入同路');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorName = _author?['nickname'] as String? ?? '';
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('拾光详情'),
      ),
      body: _buildBody(authorName),
    );
  }

  Widget _buildBody(String authorName) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null || _checkin == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '内容不存在',
                style: const TextStyle(color: AppTheme.textSub)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
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
          FeedCard(
            // 详情页下方有完整留言列表，卡片不再显示预览块
            checkin: _checkin!.copyWith(previewComments: const []),
            nickname: authorName,
            avatarUrl: _author?['avatar_url'] as String?,
            onAction: _onAction,
          ),
          const SizedBox(height: 8),
          _CommentsBlock(
            comments: _comments,
            nextCursor: _nextCursor,
            loadingMore: _loadingMore,
            onLoadMore: _loadMoreComments,
          ),
        ],
      ),
    );
  }
}

/// 全部留言块：列表 + 加载更多 + 空态引导。
class _CommentsBlock extends StatelessWidget {
  final List<CommentVO> comments;
  final int nextCursor;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  const _CommentsBlock({
    required this.comments,
    required this.nextCursor,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('留言',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain)),
          const SizedBox(height: 4),
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('还没有留言，点下方「留言」送出第一句鼓励吧',
                    style: TextStyle(fontSize: 12, color: AppTheme.textFaint)),
              ),
            )
          else ...[
            for (var i = 0; i < comments.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppTheme.divider),
              _CommentRow(comment: comments[i]),
            ],
            if (nextCursor > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))
                      : TextButton(
                          onPressed: onLoadMore,
                          child: const Text('查看更多留言',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textSub)),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 留言行：头像 + 昵称/时间 + 内容（可换行）+ 作者图钉。
class _CommentRow extends StatelessWidget {
  final CommentVO comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
              url: comment.avatarUrl, nickname: comment.nickname, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.nickname,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSub)),
                    const SizedBox(width: 6),
                    Text(comment.timeLabel,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textFaint)),
                    if (comment.isFeatured) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.push_pin,
                          size: 12, color: AppTheme.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                EmojiText(comment.content,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textMain)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
