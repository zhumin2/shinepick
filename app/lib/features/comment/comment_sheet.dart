import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';

/// 小便签留言弹层（S5-05）：列表（新→旧，不显示总数）+ 输入行 + 发送置顶 + 删除。
class CommentSheet extends StatefulWidget {
  final int checkinId;
  final int checkinOwnerId;

  const CommentSheet({
    super.key,
    required this.checkinId,
    required this.checkinOwnerId,
  });

  static Future<void> show(
    BuildContext context, {
    required int checkinId,
    required int checkinOwnerId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CommentSheet(
        checkinId: checkinId,
        checkinOwnerId: checkinOwnerId,
      ),
    );
  }

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CommentVO> _comments = [];
  bool _loading = true;
  bool _sending = false;

  CheckinController get _ctrl => context.read<CheckinController>();

  /// 能否删除：本人留言，或我是打卡作者。
  bool _canDelete(CommentVO c) {
    final me = context.read<AuthController>().user?.id;
    return me == c.userId || me == widget.checkinOwnerId;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _ctrl.loadComments(widget.checkinId).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('留言加载超时'),
      );
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('[comment] load failed: $e');
      Toast.show(context, '留言加载失败：$e');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      Toast.show(context, '请先输入留言内容再发送');
      return;
    }
    if (text.characters.length > 80) {
      Toast.show(context, '留言最多 80 字');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    // 加超时保护：网络挂起时不让「发送」按钮永久禁用
    final api = _ctrl.addComment(widget.checkinId, text).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('请求超时，请检查网络后重试'),
    );
    try {
      final c = await api;
      if (!mounted) return;
      setState(() {
        _comments.insert(0, c); // 发送成功即置顶（产品 4.6）
        _input.clear();
      });
      Toast.show(context, '已发送');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } on TimeoutException catch (e) {
      if (mounted) Toast.show(context, e.message ?? '请求超时，请重试');
    } catch (e, st) {
      debugPrint('[comment] send failed: $e\n$st');
      if (mounted) Toast.show(context, '发送失败：$e');
    } finally {
      // 任何路径都复位，避免按钮卡在禁用态
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CommentVO c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除这条留言？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _ctrl.deleteComment(c.id);
      if (!mounted) return;
      setState(() => _comments.removeWhere((e) => e.id == c.id));
      Toast.show(context, '已删除');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text('留言',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain)),
            const SizedBox(height: 4),
            const Text('一句温暖的话，不用等回复',
                style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppTheme.divider),
            Expanded(child: _buildList()),
            const Divider(height: 1, color: AppTheme.divider),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 32, color: AppTheme.textSub.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            const Text('还没有留言',
                style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
            const SizedBox(height: 4),
            const Text('做第一个对 Ta 说句话的人',
                style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final c = _comments[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(url: c.avatarUrl, nickname: c.nickname, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.nickname,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMain)),
                      ),
                      Text(c.timeLabel,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSub)),
                      if (_canDelete(c))
                        GestureDetector(
                          onTap: () => _delete(c),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.close,
                                size: 14, color: AppTheme.textSub),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(c.content,
                      style: const TextStyle(
                          fontSize: 14, height: 1.5, color: AppTheme.textMain)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              maxLines: 1,
              maxLength: 80,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: '想对 Ta 说一句…',
                counterText: '',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('发送', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
