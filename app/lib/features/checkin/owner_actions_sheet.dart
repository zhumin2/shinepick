import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/app_sheet.dart';
import '../../shared/widgets/toast.dart';

/// 作者管理自己的打卡：长按卡片弹出，可改可见范围（隐藏/公开）或删除。
/// 通过回调注入数据操作，便于测试；返回是否发生了变更（供页面刷新）。
Future<bool> showOwnerActions(
  BuildContext context,
  Checkin checkin, {
  required Future<void> Function(int visibility) onVisibility,
  required Future<void> Function() onDelete,
}) async {
  return await AppSheet.show<bool>(
        context,
        title: '管理这条拾光',
        builder: (_) => _OwnerActionsSheet(
          checkin: checkin,
          onVisibility: onVisibility,
          onDelete: onDelete,
        ),
      ) ??
      false;
}

class _OwnerActionsSheet extends StatefulWidget {
  final Checkin checkin;
  final Future<void> Function(int visibility) onVisibility;
  final Future<void> Function() onDelete;

  const _OwnerActionsSheet({
    required this.checkin,
    required this.onVisibility,
    required this.onDelete,
  });

  @override
  State<_OwnerActionsSheet> createState() => _OwnerActionsSheetState();
}

class _OwnerActionsSheetState extends State<_OwnerActionsSheet> {
  bool _busy = false;

  Future<void> _changeVisibility(int v) async {
    if (_busy || v == widget.checkin.visibility) return;
    setState(() => _busy = true);
    try {
      await widget.onVisibility(v);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, '操作失败，请稍后重试');
    }
  }

  Future<void> _confirmDelete() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条拾光？'),
        content: const Text('删除后无法恢复，树上的这颗光点仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFD9534F))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, '操作失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.checkin.visibility;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text('谁可以看到',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textFaint)),
        ),
        for (final opt in const [
          (1, '仅自己', '只有自己能看到'),
          (2, '同路人', '出现在发现页，互为同路人的伙伴可见'),
          (3, '小树洞', '仅留作记录，不在公开流展示'),
        ])
          _VisOption(
            value: opt.$1,
            title: opt.$2,
            subtitle: opt.$3,
            selected: current == opt.$1,
            enabled: !_busy,
            onTap: () => _changeVisibility(opt.$1),
          ),
        const Divider(height: 16, indent: 20, endIndent: 20),
        ListTile(
          leading: const Icon(Icons.delete_outline,
              size: 20, color: Color(0xFFD9534F)),
          title: const Text('删除打卡',
              style: TextStyle(fontSize: 15, color: Color(0xFFD9534F))),
          subtitle: const Text('删除后无法恢复',
              style: TextStyle(fontSize: 11, color: AppTheme.textFaint)),
          onTap: _busy ? null : _confirmDelete,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 可见范围选项行（选中打勾 + 当前项不可重复点）。
class _VisOption extends StatelessWidget {
  final int value;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _VisOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 20,
        color: selected ? AppTheme.primary : AppTheme.textFaint,
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: AppTheme.textMain)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, color: AppTheme.textFaint)),
      onTap: onTap,
    );
  }
}
