import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/feed_card.dart';
import '../../shared/widgets/toast.dart';
import '../checkin/checkin_controller.dart';
import '../comment/comment_sheet.dart';
import '../social/social_controller.dart';

/// 发现页（S6-05）：品类 Tab + 大卡片列表（游标分页加载更多）。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  int _category = 0; // 0=全部
  final _items = <FeedItem>[];
  int _nextCursor = 0;
  bool _loading = false;
  bool _exhausted = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }


  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _nextCursor = 0;
      _exhausted = false;
      _loading = true;
    });
    await _fetch(reset: true);
  }

  Future<void> _loadMore() async {
    if (_loading || _exhausted || _nextCursor == 0) return;
    await _fetch(reset: false);
  }

  Future<void> _fetch({required bool reset}) async {
    setState(() => _loading = true);
    try {
      final data = await context
          .read<CheckinController>()
          .auth
          .api
          .get<Map<String, dynamic>>(
        '/explore?category=$_category${_nextCursor > 0 ? '&cursor=$_nextCursor' : ''}',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      if (!mounted) return;
      final raw = data['items'] as List<dynamic>? ?? const [];
      final list = raw
          .map((e) => FeedItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        _items.addAll(list);
        _nextCursor = (data['next_cursor'] as num?)?.toInt() ?? 0;
        _exhausted = _nextCursor == 0 || list.isEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (reset && _items.isEmpty) Toast.show(context, '加载失败，请下拉重试');
    }
  }

  Future<void> _onAction(String action, FeedItem item) async {
    if (action == 'comment') {
      await CommentSheet.show(
        context,
        checkinId: item.checkin.id,
        checkinOwnerId: item.user.id,
      );
      return;
    }
    final type = switch (action) {
      'light' => 1,
      'hug' => 2,
      'companion' => 3,
      _ => 0,
    };
    if (type == 0) return;
    try {
      await context.read<CheckinController>().toggleReaction(
            item.checkin.id,
            type,
          );
      if (type == 3 && mounted) Toast.show(context, '已加入同路');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请稍后重试');
    }
  }

  /// 长按卡片：举报 / 拉黑（S6-03 入口）。
  Future<void> _longPress(FeedItem item) async {
    final social = context.read<SocialController>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppTheme.textSub),
              title: const Text('举报这条拾光',
                  style: TextStyle(fontSize: 15, color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'report'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.block_outlined, color: AppTheme.textSub),
              title: Text('拉黑 ${item.user.nickname}',
                  style: const TextStyle(fontSize: 15, color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'report') {
        await social.report(
          targetType: 1,
          targetId: item.checkin.id,
          reason: 1,
        );
        if (mounted) Toast.show(context, '已收到举报，我们会在 24 小时内处理');
      } else if (action == 'block') {
        await social.block(item.user.id);
        if (mounted) {
          Toast.show(context, '已拉黑，之后不会看到 Ta 的内容');
          _reload();
        }
      }
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
      ),
      body: Column(
        children: [
          // 品类 Tab
          Container(
            height: 44,
            color: AppTheme.bg,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _tab(0, '全部'),
                for (final c in CheckinCategory.values.where((c) => c != CheckinCategory.custom))
                  _tab(c.code, c.label),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _reload,
              child: _items.isEmpty && _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primary))
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('这个品类还没有内容，去发第一条吧',
                                  style: TextStyle(
                                      fontSize: 13, color: AppTheme.textSub)),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _items.length + (_exhausted ? 0 : 1),
                          itemBuilder: (_, i) {
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.textSub),
                                  ),
                                ),
                              );
                            }
                            final item = _items[i];
                            return GestureDetector(
                              onLongPress: () => _longPress(item),
                              child: FeedCard(
                                checkin: item.checkin,
                                nickname: item.user.nickname,
                                avatarUrl: item.user.avatarUrl,
                                onAction: (a) => _onAction(a, item),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(int code, String label) {
    final selected = _category == code;
    return GestureDetector(
      onTap: () {
        if (selected) return;
        setState(() => _category = code);
        _nextCursor = 0;
        _reload();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.textMain : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.textMain : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppTheme.textSub,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
