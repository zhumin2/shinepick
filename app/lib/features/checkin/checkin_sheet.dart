import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/toast.dart';
import 'checkin_controller.dart';

/// 打卡弹层（S3-05）：选品类 → 一句话 → 配图（可选）→ 可见范围 → 发布。
/// 目标 30 秒内完成；发布成功 pop(true) 触发首页光点动画。
class CheckinSheet extends StatefulWidget {
  const CheckinSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: CheckinSheet(),
      ),
    );
    return ok ?? false;
  }

  @override
  State<CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends State<CheckinSheet> {
  final _content = TextEditingController();
  CheckinCategory _category = CheckinCategory.sport;
  CheckinVisibility _visibility = CheckinVisibility.companion;
  final _uploading = <String>[]; // 本地路径，上传中
  final _imageUrls = <String>[]; // 已上传 URL
  final _failed = <String>[]; // 上传失败的本地路径

  CheckinController get _checkin => context.read<CheckinController>();

  static const _hints = {
    CheckinCategory.sport: '今天跑了 3 公里，风很舒服',
    CheckinCategory.read: '今天读到第 42 页，这段写得太好了',
    CheckinCategory.travel: '今天去了一个没去过的咖啡馆',
    CheckinCategory.social: '今天和朋友吃了顿火锅',
    CheckinCategory.pet: '今天猫第一次玩新玩具',
    CheckinCategory.custom: '今天拾起了一点小光阴',
  };

  @override
  void initState() {
    super.initState();
    // 恢复草稿（S4-06：上次没发出去的内容不丢）
    Future.microtask(() async {
      final draft = await _checkin.readDraft();
      if (draft.isNotEmpty && mounted && _content.text.isEmpty) {
        _content.text = draft;
      }
    });
    _content.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    _checkin.saveDraft(_content.text); // 即时保存，无需防抖（本地写很快）
  }

  @override
  void dispose() {
    _content.removeListener(_onContentChanged);
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remain = 9 - _imageUrls.length - _uploading.length - _failed.length;
    if (remain <= 0) {
      Toast.show(context, '最多 9 张图片');
      return;
    }
    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.image,
    );
    if (files.isEmpty || !mounted) return;
    for (final f in files.take(remain)) {
      final name = f.name;
      setState(() => _uploading.add(name));
      try {
        // Web 上 file_picker 只给 bytes（无本地路径），统一按字节上传
        final bytes = await f.readAsBytes();
        final url = await _checkin.uploadImage(bytes, name);
        if (!mounted) return;
        setState(() {
          _uploading.remove(name);
          _imageUrls.add(url);
        });
      } on AppError catch (e) {
        if (!mounted) return;
        setState(() {
          _uploading.remove(name);
          _failed.add(name);
        });
        Toast.show(context, e.message);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _uploading.remove(name);
          _failed.add(name);
        });
        Toast.show(context, '图片上传失败：$e');
      }
    }
  }

  Future<void> _publish() async {
    final text = _content.text.trim();
    if (text.isEmpty) {
      Toast.show(context, '写一句话再发布吧');
      return;
    }
    try {
      await _checkin.publish(PublishCheckinReq(
        category: _category,
        content: text,
        imageUrls: List.unmodifiable(_imageUrls),
        visibility: _visibility,
      ));
      await _checkin.clearDraft();
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '发布失败，请重试（内容已存草稿）');
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkin = context.watch<CheckinController>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text('今日打卡',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain)),
          ),
          const SizedBox(height: 16),
          // 品类（原型 cat-grid：3 列网格，含「自定义」v2 占位）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                for (final c in CheckinCategory.values)
                  _CategoryTile(
                    category: c,
                    selected: _category == c,
                    onTap: c == CheckinCategory.custom
                        ? () => Toast.show(context, '自定义品类 v2 开放，敬请期待')
                        : () => setState(() => _category = c),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 内容
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _content,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '今天______（如：${_hints[_category]}）',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 配图
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in _imageUrls)
                  _Thumb(
                    child: Image.network(url, fit: BoxFit.cover),
                    onRemove: () => setState(() => _imageUrls.remove(url)),
                  ),
                for (final _ in _uploading)
                  const _Thumb(
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                for (final p in _failed)
                  _Thumb(
                    child: const Icon(Icons.error_outline,
                        color: AppTheme.textSub, size: 20),
                    onRemove: () => setState(() => _failed.remove(p)),
                  ),
                if (_imageUrls.length + _uploading.length + _failed.length < 9)
                  _Thumb(
                    onTap: _pickImages,
                    child: const Icon(Icons.add,
                        color: AppTheme.textSub, size: 22),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 可见范围（原型 vis-opt：选中墨色底白字）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                for (final v in CheckinVisibility.values) ...[
                  if (v != CheckinVisibility.values.first)
                    const SizedBox(width: 8),
                  Expanded(child: _VisOption(
                    label: v.label,
                    selected: _visibility == v,
                    onTap: () => setState(() => _visibility = v),
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 发布
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: checkin.publishing ? null : _publish,
                child: checkin.publishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('拾起今天'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 品类网格项（原型 cat-item：emoji 位置用品类色圆点 + 名）。
class _CategoryTile extends StatelessWidget {
  final CheckinCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = category == CheckinCategory.custom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.sand : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCustom ? AppTheme.divider : category.color,
              ),
              child: isCustom
                  ? const Icon(Icons.add, size: 14, color: AppTheme.textSub)
                  : null,
            ),
            const SizedBox(height: 3),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? AppTheme.primaryDark : AppTheme.textSub,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可见范围选项（原型 vis-opt：选中墨色底白字）。
class _VisOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VisOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.textMain : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.textMain : AppTheme.divider,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : AppTheme.textSub,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Widget child;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const _Thumb({required this.child, this.onRemove, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
              color: AppTheme.bg,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: child,
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: -4,
            top: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: AppTheme.textMain, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
