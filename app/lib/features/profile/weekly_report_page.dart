import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/feed_card.dart' show categoryVisual;
import '../../shared/widgets/image_saver.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';

/// 拾光周报：本周打卡次数/天数/连续 + 7 日柱状 + 品类分布 + 与上周对比。
/// 入口：我的页「本周拾光」卡片。
class WeeklyReportPage extends StatefulWidget {
  const WeeklyReportPage({super.key});

  @override
  State<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends State<WeeklyReportPage> {
  WeeklyReportVO? _report;
  final GlobalKey _shareKey = GlobalKey();
  bool _loading = true;
  bool _sharing = false;
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
      final data = await context.read<AuthController>().api
          .get<Map<String, dynamic>>(
        '/users/me/weekly',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      if (!mounted) return;
      setState(() {
        _report = WeeklyReportVO.fromJson(data);
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

  Future<void> _share() async {
    final r = _report;
    if (r == null || _sharing || _shareKey.currentContext == null) return;
    setState(() => _sharing = true);
    Toast.show(context, '正在生成周报卡片…');
    try {
      final boundary =
          _shareKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final message = await saveImageBytes(
          bytes, 'shinepick-weekly-${r.startDate}.png', '');
      if (mounted) Toast.show(context, message);
    } catch (_) {
      if (mounted) Toast.show(context, '生成失败，请重试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nickname = context.watch<AuthController>().user?.nickname ?? '我';
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('拾光周报'),
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.ios_share_outlined, size: 20),
            tooltip: '保存周报卡片',
            onPressed: _share,
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          Offstage(
            child: RepaintBoundary(
              key: _shareKey,
              child: _WeeklyShareCard(report: _report, nickname: nickname),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    final r = _report;
    if (_error != null || r == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '加载失败',
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text('${r.startDate} ~ ${r.endDate}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textFaint)),
          const SizedBox(height: 10),
          _SummaryCard(report: r),
          const SizedBox(height: 14),
          _DailyBars(report: r),
          const SizedBox(height: 14),
          if (r.categories.isNotEmpty) _CategoryBreakdown(report: r),
          const SizedBox(height: 14),
          _ClosingLine(report: r),
        ],
      ),
    );
  }
}

/// 概要卡：三次大数字 + 与上周对比。
class _SummaryCard extends StatelessWidget {
  final WeeklyReportVO report;
  const _SummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final delta = report.delta;
    final (deltaText, deltaColor, deltaIcon) = delta > 0
        ? ('比上周多 $delta 次', const Color(0xFF4C956C), Icons.trending_up)
        : delta < 0
            ? ('比上周少 ${-delta} 次', const Color(0xFFC25B4E), Icons.trending_down)
            : ('与上周持平', AppTheme.textSub, Icons.trending_flat);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BigStat('${report.count}', '打卡次数'),
              _vline(),
              _BigStat('${report.days}', '打卡天数'),
              _vline(),
              _BigStat('${report.streakDays}', '连续天数'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(deltaIcon, size: 15, color: deltaColor),
              const SizedBox(width: 5),
              Text(deltaText,
                  style: TextStyle(fontSize: 12, color: deltaColor)),
              const SizedBox(width: 8),
              Text('上周 ${report.lastCount} 次',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textFaint)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _vline() =>
      Container(width: 1, height: 30, color: AppTheme.divider);
}

class _BigStat extends StatelessWidget {
  final String value;
  final String label;
  const _BigStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
      ],
    );
  }
}

/// 7 日柱状图：柱高按当日次数，颜色取主品类。
class _DailyBars extends StatelessWidget {
  final WeeklyReportVO report;
  const _DailyBars({required this.report});

  @override
  Widget build(BuildContext context) {
    final maxCount = report.daily.fold<int>(
        1, (m, d) => d.count > m ? d.count : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每天的光点',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain)),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in report.daily)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(d.count > 0 ? '${d.count}' : '',
                            style: const TextStyle(
                                fontSize: 10, color: AppTheme.textSub)),
                        const SizedBox(height: 3),
                        Container(
                          height: 8 + 64 * (d.count / maxCount),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: d.count == 0
                                ? AppTheme.divider
                                : (d.categoryEnum != null
                                    ? categoryVisual(d.categoryEnum!).$1
                                    : AppTheme.primary),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(d.weekdayLabel,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSub)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 品类分布：按次数降序的横条。
class _CategoryBreakdown extends StatelessWidget {
  final WeeklyReportVO report;
  const _CategoryBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final maxCount = report.categories.first.count;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('这一周的色调',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain)),
          const SizedBox(height: 12),
          for (final c in report.categories) ...[
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(c.categoryEnum.label,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSub)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: maxCount == 0 ? 0 : c.count / maxCount,
                      minHeight: 8,
                      backgroundColor: AppTheme.bg,
                      valueColor: AlwaysStoppedAnimation(
                          categoryVisual(c.categoryEnum).$1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text('${c.count} 次',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSub)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// 结语：按本周状态给一句温和的鼓励（不制造焦虑）。
class _ClosingLine extends StatelessWidget {
  final WeeklyReportVO report;
  const _ClosingLine({required this.report});

  @override
  Widget build(BuildContext context) {
    final text = report.count == 0
        ? '这周还没拾起光点，随时可以开始。'
        : report.days >= 5
            ? '这周几乎每天都在拾光，树又茂盛了一些。'
            : report.delta > 0
                ? '比上周多拾起了 ${report.delta} 次，慢慢来就很好。'
                : '保持节奏，每一颗光点都算数。';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12, height: 1.6, color: AppTheme.textSub)),
    );
  }
}

/// 周报分享卡（离屏渲染，375 宽）。
class _WeeklyShareCard extends StatelessWidget {
  final WeeklyReportVO? report;
  final String nickname;
  const _WeeklyShareCard({required this.report, required this.nickname});

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null) return const SizedBox(width: 375, height: 200);
    final maxCount =
        r.daily.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    return Container(
      width: 375,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5D8A8), Color(0xFFE89B3C)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('拾光周报',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('${r.startDate} ~ ${r.endDate}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _shareStat('${r.count}', '次打卡'),
                _shareStat('${r.days}', '天有拾光'),
                _shareStat('${r.streakDays}', '天连续'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
            child: SizedBox(
              height: 72,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in r.daily)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 6 + 44 * (d.count / maxCount),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: d.count == 0
                                  ? AppTheme.divider
                                  : (d.categoryEnum != null
                                      ? categoryVisual(d.categoryEnum!).$1
                                      : AppTheme.primary),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(d.weekdayLabel,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSub)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(nickname.isEmpty ? '拾光用户' : '$nickname 的拾光',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textMain)),
                ),
                const Text('拾光 ShinePick',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSub)),
      ],
    );
  }
}
