import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_sheet.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';

/// 我的页（S2-03）：资料展示 + 编辑 + 头像上传；统计为骨架，S3 起填充。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;

  AuthController get _auth => context.read<AuthController>();

  @override
  void initState() {
    super.initState();
    // 打开我的页即拉最新资料（统计随打卡变化，缓存可能过期）
    final auth = _auth;
    Future.microtask(() async {
      try {
        await auth.refreshProfile();
      } catch (_) {
        // 弱网时静默使用缓存
      }
    });
  }

  Future<void> _changeAvatar() async {
    if (_uploading) return;
    // file_picker 13.x：FilePickerPlatform.instance（返回文件列表）
    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.image,
    );
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    setState(() => _uploading = true);
    try {
      // Web 上无本地路径，统一按字节上传
      final bytes = await file.readAsBytes();
      await _auth.uploadAvatar(bytes, file.name);
      if (mounted) Toast.show(context, '头像已更新');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (e) {
      if (mounted) Toast.show(context, '上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openEdit() async {
    final ok = await AppSheet.show<bool>(
      context,
      title: '编辑资料',
      scrollable: true,
      builder: (_) => const _EditForm(),
    );
    if (ok == true && mounted) Toast.show(context, '资料已保存');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final u = auth.user;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '编辑资料',
            onPressed: _openEdit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // 头像 + 昵称 + 简介
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      Avatar(
                        url: u?.avatarUrl,
                        nickname: u?.nickname ?? '',
                        size: 84,
                        onTap: _changeAvatar,
                      ),
                      if (_uploading)
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.primary,
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                      if (!_uploading)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_outlined,
                                size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(u?.nickname ?? '',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain)),
                  if ((u?.bio ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(u!.bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: AppTheme.textSub)),
                  ],
                  const SizedBox(height: 4),
                  Text(u?.phoneMasked ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSub)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 统计（打卡天数/连续天数来自 /users/me；同路人 S5 上线）
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
                  _StatItem(
                      value: '${u?.checkinCount ?? 0}', label: '打卡次数'),
                  const _VerticalDivider(),
                  _StatItem(
                      value: '${u?.checkinDays ?? 0}', label: '打卡天数'),
                  const _VerticalDivider(),
                  _StatItem(
                      value: '${u?.streakDays ?? 0}', label: '连续天数'),
                  const _VerticalDivider(),
                  _StatItem(
                      value: '${u?.companions ?? 0}', label: '同路人'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 资料明细
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: [
                  _InfoRow(label: '城市', value: _cityLabel(u?.city)),
                  const _Divider(),
                  _InfoRow(label: '生日', value: u?.birthday ?? '未填写'),
                  const _Divider(),
                  _InfoRow(label: '性别', value: _genderLabel(u?.gender ?? 0)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _cityLabel(String? city) =>
      (city == null || city.isEmpty) ? '未填写' : city;

  static String _genderLabel(int g) {
    switch (g) {
      case 1:
        return '男';
      case 2:
        return '女';
      default:
        return '保密';
    }
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

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
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppTheme.divider);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppTheme.divider),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSub)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textMain)),
        ],
      ),
    );
  }
}

/// 编辑表单：昵称/简介/性别/城市/生日 → PATCH /users/me。
class _EditForm extends StatefulWidget {
  const _EditForm();

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  late final TextEditingController _city;
  late int _gender;
  late DateTime? _birthday;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthController>().user;
    _nickname = TextEditingController(text: u?.nickname ?? '');
    _bio = TextEditingController(text: u?.bio ?? '');
    _city = TextEditingController(text: u?.city ?? '');
    _gender = u?.gender ?? 0;
    _birthday = (u?.birthday != null)
        ? DateTime.tryParse('${u!.birthday}T00:00:00')
        : null;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20),
      firstDate: DateTime(1920),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final auth = context.read<AuthController>();
    final patch = <String, dynamic>{
      'nickname': _nickname.text.trim(),
      'bio': _bio.text.trim(),
      'gender': _gender,
      'city': _city.text.trim(),
      if (_birthday != null)
        'birthday':
            '${_birthday!.year.toString().padLeft(4, '0')}-'
            '${_birthday!.month.toString().padLeft(2, '0')}-'
            '${_birthday!.day.toString().padLeft(2, '0')}',
    };
    try {
      await auth.updateProfile(patch);
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        Toast.show(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        Toast.show(context, '保存失败，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nickname,
          maxLength: 30,
          decoration: const InputDecoration(
              labelText: '昵称', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bio,
          maxLines: 2,
          maxLength: 140,
          decoration: const InputDecoration(
              labelText: '简介', hintText: '一句话介绍自己', counterText: ''),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('保密')),
            ButtonSegment(value: 1, label: Text('男')),
            ButtonSegment(value: 2, label: Text('女')),
          ],
          selected: {_gender},
          onSelectionChanged: (s) => setState(() => _gender = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          maxLength: 50,
          decoration: const InputDecoration(
              labelText: '城市', counterText: ''),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickBirthday,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
                labelText: '生日', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
            child: Text(
              _birthday == null
                  ? '点击选择'
                  : '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 15,
                color: _birthday == null ? AppTheme.textSub : AppTheme.textMain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('保存'),
          ),
        ),
      ],
    );
  }
}
