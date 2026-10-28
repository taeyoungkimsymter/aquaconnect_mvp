import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/ai_report.dart';
import '../../data/models/memo.dart';

final _ymd = DateFormat('yyyy-MM-dd');

String aiReportPeriodLabel(AiReport r) {
  String md(String ymd) => '${int.parse(ymd.substring(5, 7))}/${int.parse(ymd.substring(8))}';
  return r.periodStart == r.periodEnd ? md(r.periodStart) : '${md(r.periodStart)} ~ ${md(r.periodEnd)}';
}

/// 리포트 상세 > AI 관리 리포트 — the farm's AI drafts (ported from
/// symterAI's 관리 리포트), newest first, plus the entry to make a new one.
class AiReportListScreen extends ConsumerWidget {
  const AiReportListScreen({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(farmByIdProvider(farmId)).valueOrNull;
    final reportsAsync = ref.watch(aiReportsProvider(farmId));
    final status = ref.watch(aiModelStatusProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: Text(farm == null ? 'AI 관리 리포트' : '${farm.name} · AI 리포트',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(aiReportsProvider(farmId));
          ref.invalidate(aiModelStatusProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _IntroCard(status: status),
            if (status != null && status.configured && status.models.isNotEmpty) ...[
              const SizedBox(height: 12),
              AiUsageCard(status: status),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              label: '새 AI 리포트 만들기',
              icon: Icons.auto_awesome,
              onPressed: status?.configured == true ? () => context.push('/reports/$farmId/ai/new') : null,
            ),
            const SizedBox(height: 20),
            const Text('지난 AI 리포트', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            reportsAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('불러오지 못했어요: $e', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              data: (reports) => reports.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('아직 만든 AI 리포트가 없어요', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ),
                    )
                  : Column(
                      children: [
                        for (final r in reports) ...[
                          _ReportTile(report: r),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.status});
  final AiModelStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.brandTintStrong,
        border: Border.all(color: AppColors.brandTintBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.brandDark),
              SizedBox(width: 8),
              Text('메모로 만드는 관리 리포트', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.brandDark)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '기간과 메모를 고르면 AI가 현장 메모·댓글을 1순위 근거로 리포트 초안을 씁니다. '
            '폐사 마릿수 같은 숫자는 코드가 집계하고, 근거가 맞지 않는 문장은 "확인 필요"로 표시돼요. '
            '확정 전에 꼭 검토·수정해 주세요.',
            style: TextStyle(fontSize: 12, color: AppColors.brandInk, height: 1.5),
          ),
          const SizedBox(height: 8),
          if (s == null)
            const Text('AI 연결 상태 확인 중…', style: TextStyle(fontSize: 11, color: AppColors.brandInkFaint))
          else
            Row(
              children: [
                Icon(s.configured ? Icons.check_circle : Icons.cloud_off,
                    size: 13, color: s.configured ? AppColors.good : AppColors.warningDark),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(s.configured ? 'AI 연결됨 · 기본 모델 ${s.model}' : '미연결 — ${s.note}',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: s.configured ? AppColors.goodDark : AppColors.warningDark)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _resetLabel(DateTime? resetsAt) {
  if (resetsAt == null) return '';
  return '${DateFormat('M/d HH:mm').format(resetsAt.toLocal())} 초기화';
}

/// 모델별 오늘 사용량 — counted from this server's own requests, since
/// Gemini doesn't report the real remaining quota.
class AiUsageCard extends StatelessWidget {
  const AiUsageCard({super.key, required this.status});
  final AiModelStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('오늘 남은 사용량', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              Text(_resetLabel(status.resetsAt), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          for (final m in status.models) ...[
            AiModelUsageRow(option: m),
            const SizedBox(height: 10),
          ],
          const Text('이 앱에서 보낸 요청 기준이에요. 같은 키를 다른 곳에서 쓰면 실제로 남은 양은 더 적을 수 있어요.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, height: 1.4)),
        ],
      ),
    );
  }
}

class AiModelUsageRow extends StatelessWidget {
  const AiModelUsageRow({super.key, required this.option, this.dense = false});
  final AiModelOption option;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final m = option;
    final ratio = m.dailyLimit == 0 ? 1.0 : (m.usedToday / m.dailyLimit).clamp(0.0, 1.0);
    final color = m.exhausted
        ? AppColors.danger
        : ratio >= 0.75
            ? AppColors.warning
            : AppColors.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!dense)
              Expanded(
                child: Text(m.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              )
            else
              const Spacer(),
            Text(
              m.exhausted ? '오늘 소진 (${m.usedToday}/${m.dailyLimit})' : '남은 ${m.remaining}회 · ${m.usedToday}/${m.dailyLimit}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: m.exhausted ? AppColors.dangerDark : AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: ratio, minHeight: 5, backgroundColor: AppColors.neutralChip, color: color),
        ),
        if (m.limited && !m.exhausted)
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text('최근 요청이 한도 초과로 거절됐어요. 잠시 후 다시 시도해 주세요.',
                style: TextStyle(fontSize: 10.5, color: AppColors.warningInk)),
          ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final AiReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/ai-reports/${r.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AiReportStatusChip(report: r),
                        const SizedBox(width: 8),
                        Text(aiReportPeriodLabel(r),
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        '메모 ${r.memoCount}건',
                        if (r.commentCount > 0) '댓글 ${r.commentCount}개',
                        if (r.checkCount > 0) '확인 필요 ${r.checkCount}',
                        if (r.edited) '전문가 수정됨',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 2),
                    Text('${r.createdByName.isEmpty ? '' : '${r.createdByName} · '}${DateFormat('M/d HH:mm').format(r.createdAt.toLocal())} 생성',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.neutralArrow),
            ],
          ),
        ),
      ),
    );
  }
}

class AiReportStatusChip extends StatelessWidget {
  const AiReportStatusChip({super.key, required this.report});
  final AiReport report;

  @override
  Widget build(BuildContext context) {
    final confirmed = report.isConfirmed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: confirmed ? AppColors.goodTint : AppColors.warningTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(confirmed ? '확정' : '초안',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: confirmed ? AppColors.goodDark : AppColors.warningTintInk)),
    );
  }
}

// ───────── 새 AI 리포트 ─────────

enum _Preset {
  last7('최근 7일'),
  last14('최근 14일'),
  last30('최근 30일'),
  thisMonth('이번 달'),
  lastMonth('지난 달');

  const _Preset(this.label);
  final String label;

  /// Inclusive local-date range.
  (DateTime, DateTime) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Preset.last7 => (today.subtract(const Duration(days: 6)), today),
      _Preset.last14 => (today.subtract(const Duration(days: 13)), today),
      _Preset.last30 => (today.subtract(const Duration(days: 29)), today),
      _Preset.thisMonth => (DateTime(now.year, now.month, 1), today),
      _Preset.lastMonth => (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
    };
  }
}

/// Pick a period and which of its memos go in, then ask the server's AI for
/// a draft. Memos default to all selected — unchecking one keeps it out of
/// the AI input entirely (the report then treats it as 기록 없음).
class AiReportCreateScreen extends ConsumerStatefulWidget {
  const AiReportCreateScreen({super.key, required this.farmId});

  final String farmId;

  @override
  ConsumerState<AiReportCreateScreen> createState() => _AiReportCreateScreenState();
}

class _AiReportCreateScreenState extends ConsumerState<AiReportCreateScreen> {
  _Preset _preset = _Preset.last30;
  final Set<String> _excluded = {};
  bool _includeComments = true;
  bool _busy = false;
  String? _model;

  /// The picked model, else the server default, else the first with
  /// requests left today.
  AiModelOption? _effectiveModel(AiModelStatus? status) {
    final models = status?.models ?? const <AiModelOption>[];
    if (status == null || models.isEmpty) return null;
    AiModelOption? byId(String? id) => models.where((m) => m.id == id).firstOrNull;
    return byId(_model) ??
        [byId(status.model), ...models].whereType<AiModelOption>().where((m) => !m.exhausted).firstOrNull ??
        byId(status.model) ??
        models.first;
  }

  List<Memo> _inRange(List<Memo> memos, DateTime from, DateTime to) {
    final end = to.add(const Duration(days: 1));
    return memos.where((m) {
      final at = m.createdAt.toLocal();
      return !at.isBefore(from) && at.isBefore(end);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _generate(List<Memo> picked, DateTime from, DateTime to, bool allPicked, String? model) async {
    setState(() => _busy = true);
    try {
      final report = await ref.read(aiReportRepositoryProvider).generate(
            farmId: widget.farmId,
            from: _ymd.format(from),
            to: _ymd.format(to),
            memoIds: allPicked ? null : picked.map((m) => m.id).toList(),
            includeComments: _includeComments,
            model: model,
          );
      ref.invalidate(aiReportsProvider(widget.farmId));
      ref.invalidate(aiModelStatusProvider);
      if (mounted) context.pushReplacement('/ai-reports/${report.id}');
    } catch (e) {
      ref.invalidate(aiModelStatusProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI 리포트를 만들지 못했어요: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final memosAsync = ref.watch(memosProvider(widget.farmId));
    final status = ref.watch(aiModelStatusProvider).valueOrNull;
    final model = _effectiveModel(status);
    final (from, to) = _preset.range(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('새 AI 리포트', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      body: memosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('메모를 불러오지 못했어요.\n$e', textAlign: TextAlign.center)),
        data: (memos) {
          final inRange = _inRange(memos, from, to);
          final picked = inRange.where((m) => !_excluded.contains(m.id)).toList();
          final comments = picked.fold<int>(0, (sum, m) => sum + m.commentCount);
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        const Text('기간', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final p in _Preset.values)
                              ChoiceChip(
                                label: Text(p.label),
                                selected: p == _preset,
                                onSelected: _busy ? null : (_) => setState(() => _preset = p),
                                selectedColor: AppColors.brandTint,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: p == _preset ? AppColors.brand : AppColors.textSecondary,
                                ),
                                side: BorderSide(color: p == _preset ? AppColors.brandTintBorder : AppColors.border),
                                backgroundColor: AppColors.surface,
                                showCheckmark: false,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${DateFormat('yyyy.M.d').format(from)} ~ ${DateFormat('yyyy.M.d').format(to)}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text('넣을 메모 ${picked.length}/${inRange.length}건',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            ),
                            if (inRange.isNotEmpty)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          if (picked.length == inRange.length) {
                                            _excluded.addAll(inRange.map((m) => m.id));
                                          } else {
                                            _excluded.removeAll(inRange.map((m) => m.id));
                                          }
                                        }),
                                child: Text(picked.length == inRange.length ? '모두 해제' : '모두 선택',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (inRange.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('이 기간에 남긴 메모가 없어요', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                for (final (i, m) in inRange.indexed) ...[
                                  if (i > 0) const Divider(height: 1, color: AppColors.divider),
                                  _MemoPickTile(
                                    memo: m,
                                    selected: !_excluded.contains(m.id),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() => v ? _excluded.remove(m.id) : _excluded.add(m.id)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _includeComments,
                          onChanged: _busy ? null : (v) => setState(() => _includeComments = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppColors.brand,
                          title: const Text('메모에 달린 댓글도 근거로 넣기',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          subtitle: Text('선택한 메모의 댓글 $comments개 · 폐사 집계에는 넣지 않아요',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                        ),
                        if (status != null && status.models.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('AI 모델', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                              ),
                              Text(_resetLabel(status.resetsAt), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final m in status.models) ...[
                            _ModelTile(
                              option: m,
                              selected: m.id == model?.id,
                              isDefault: m.id == status.model,
                              onTap: _busy || m.exhausted ? null : () => setState(() => _model = m.id),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const Text('남은 횟수는 이 앱에서 보낸 요청 기준이에요.',
                              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
                    child: PrimaryButton(
                      label: model == null ? 'AI 리포트 만들기' : 'AI 리포트 만들기 · ${model.label}',
                      icon: Icons.auto_awesome,
                      onPressed: _busy || picked.isEmpty || (model?.exhausted ?? false)
                          ? null
                          : () => _generate(picked, from, to, picked.length == inRange.length, model?.id),
                    ),
                  ),
                ],
              ),
              if (_busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.scrim,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('AI가 리포트를 쓰고 있어요',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            SizedBox(height: 6),
                            Text('메모 양에 따라 1분 정도 걸릴 수 있어요.\n화면을 닫지 말고 기다려 주세요.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MemoPickTile extends StatelessWidget {
  const _MemoPickTile({required this.memo, required this.selected, required this.onChanged});

  final Memo memo;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final m = memo;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false), activeColor: AppColors.brand),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        DateFormat('M/d HH:mm').format(m.createdAt.toLocal()),
                        m.authorName,
                        if (m.tags.isNotEmpty) m.tags.map((t) => '#$t').join(' '),
                        if (m.commentCount > 0) '댓글 ${m.commentCount}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 3),
                    Text(m.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, height: 1.45, color: selected ? AppColors.textPrimary : AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.option, required this.selected, required this.isDefault, required this.onTap});

  final AiModelOption option;
  final bool selected;
  final bool isDefault;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = option;
    return Material(
      color: selected ? AppColors.brandTint : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Opacity(
            opacity: m.exhausted ? 0.5 : 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18, color: selected ? AppColors.brand : AppColors.textFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            const Text('기본', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brand)),
                          ],
                        ],
                      ),
                      Text(m.description, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      const SizedBox(height: 6),
                      AiModelUsageRow(option: m, dense: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
