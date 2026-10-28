import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/ai_report.dart';
import 'ai_report_list_screen.dart';

/// One AI 관리 리포트: the (possibly expert-edited) body, the evidence-check
/// warnings, the memos it was built from, and 수정 / 확정.
class AiReportScreen extends ConsumerStatefulWidget {
  const AiReportScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends ConsumerState<AiReportScreen> {
  bool _busy = false;

  Future<void> _run(Future<AiReport> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      ref.invalidate(aiReportProvider(r.id));
      ref.invalidate(aiReportsProvider(r.farmId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('처리하지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(AiReport r) async {
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _BodyEditor(initial: r.body ?? '')),
    );
    if (edited == null || edited.trim() == (r.body ?? '').trim()) return;
    await _run(() => ref.read(aiReportRepositoryProvider).updateBody(r.id, edited), '수정 내용을 저장했어요.');
  }

  Future<void> _confirm(AiReport r) async {
    if (r.checkCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('확인 필요 항목이 있어요'),
          content: Text('근거 검증에서 걸린 문장 ${r.checkCount}개가 있습니다. 검토를 마쳤다면 확정해 주세요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('확정하기')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => ref.read(aiReportRepositoryProvider).setConfirmed(r.id, confirmed: true), '리포트를 확정했어요.');
  }

  Future<void> _delete(AiReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AI 리포트를 삭제할까요?'),
        content: const Text('삭제하면 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(aiReportRepositoryProvider).delete(r.id);
      ref.invalidate(aiReportsProvider(r.farmId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제하지 못했어요: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(aiReportProvider(widget.reportId));
    final r = reportAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('AI 관리 리포트', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
        actions: [
          if (r != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'copy') {
                  Clipboard.setData(ClipboardData(text: r.body ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리포트 내용을 복사했어요.')));
                } else if (v == 'delete') {
                  _delete(r);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('내용 복사')),
                PopupMenuItem(value: 'delete', child: Text('삭제', style: TextStyle(color: AppColors.danger))),
              ],
            ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('리포트를 불러오지 못했어요.\n$e', textAlign: TextAlign.center)),
        data: (r) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _MetaCard(report: r),
                  if (r.checks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ChecksCard(checks: r.checks),
                  ],
                  const SizedBox(height: 12),
                  for (final section in parseAiReportBody(r.body ?? '')) ...[
                    _SectionCard(section: section),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  _SourceMemosCard(memos: r.memos),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
              child: r.isConfirmed
                  ? OutlineButton(
                      label: '확정 취소',
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref.read(aiReportRepositoryProvider).setConfirmed(r.id, confirmed: false), '확정을 취소했어요.'),
                    )
                  : Row(
                      children: [
                        Expanded(child: OutlineButton(label: '수정', onPressed: _busy ? null : () => _edit(r))),
                        const SizedBox(width: 10),
                        Expanded(child: PrimaryButton(label: '확정', onPressed: _busy ? null : () => _confirm(r))),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends ConsumerWidget {
  const _MetaCard({required this.report});
  final AiReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final farm = ref.watch(farmByIdProvider(r.farmId)).valueOrNull;
    final fmt = DateFormat('M/d HH:mm');
    final lines = <String>[
      'AI 작성 · ${r.model} · ${r.createdByName.isEmpty ? '' : '${r.createdByName} · '}${fmt.format(r.createdAt.toLocal())}',
      if (r.editedAt != null) '전문가 수정 · ${r.editedByName ?? ''} · ${fmt.format(r.editedAt!.toLocal())}',
      if (r.confirmedAt != null) '확정 · ${r.confirmedByName ?? ''} · ${fmt.format(r.confirmedAt!.toLocal())}',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AiReportStatusChip(report: r),
              const SizedBox(width: 8),
              Expanded(
                child: Text(farm?.name ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${aiReportPeriodLabel(r)} · 메모 ${r.memoCount}건${r.commentCount > 0 ? ' · 댓글 ${r.commentCount}개' : ''}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          for (final l in lines) Text(l, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, height: 1.5)),
          if (!r.isConfirmed) ...[
            const SizedBox(height: 8),
            const Text('AI 초안입니다. 메모에 없는 내용이 없는지 검토한 뒤 확정해 주세요.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warningInk)),
          ],
        ],
      ),
    );
  }
}

class _ChecksCard extends StatelessWidget {
  const _ChecksCard({required this.checks});
  final List<AiReportCheck> checks;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warningDark, size: 20),
          title: Text('확인 필요 ${checks.length}개',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.warningTintInk)),
          subtitle: const Text('근거 검증에서 걸린 문장이에요. 메모와 대조해 주세요.',
              style: TextStyle(fontSize: 11, color: AppColors.warningTintInk)),
          children: [
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.section, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.warningInk)),
                    Text(c.text, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.45)),
                    Text('→ ${c.problem}', style: const TextStyle(fontSize: 11, color: AppColors.dangerDark, height: 1.45)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────── body parsing ─────────

class AiReportSection {
  AiReportSection(this.title);
  final String title;
  final List<String> lines = [];
}

/// "## 제목" starts a section; every other non-empty line belongs to it.
List<AiReportSection> parseAiReportBody(String body) {
  final out = <AiReportSection>[];
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('## ')) {
      out.add(AiReportSection(line.substring(3).trim()));
    } else {
      if (out.isEmpty) out.add(AiReportSection(''));
      out.last.lines.add(line);
    }
  }
  return out;
}

final _tagRe = RegExp(r'〔([^〕]*)〕');
const _kindTags = {
  '현장 실측': (AppColors.good, AppColors.goodTint),
  '외부 관측·공공데이터': (AppColors.brand, AppColors.brandTint),
  '제안·전문가 검토 필요': (AppColors.warningDark, AppColors.warningTint),
};

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final AiReportSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(section.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
          ],
          for (final line in section.lines) _ItemLine(line: line),
        ],
      ),
    );
  }
}

/// One "- 항목" line: kind label (실측/공공데이터/제안) on top, the sentence
/// with inline 〔수량 확인 필요〕 highlighted, then 근거 and 확인 필요 notes.
class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final bullet = line.startsWith('- ');
    var text = bullet ? line.substring(2) : line;
    String? kind;
    for (final k in _kindTags.keys) {
      if (text.startsWith('〔$k〕')) {
        kind = k;
        text = text.substring(k.length + 2).trimLeft();
        break;
      }
    }
    final cites = <String>[];
    final flags = <String>[];
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _tagRe.allMatches(text)) {
      final tag = m.group(1)!;
      if (tag.startsWith('근거')) {
        cites.add(tag);
      } else if (tag.startsWith('확인 필요:')) {
        flags.add(tag.substring('확인 필요:'.length).trim());
      } else {
        spans.add(TextSpan(text: text.substring(last, m.start)));
        spans.add(TextSpan(
          text: '〔$tag〕',
          style: const TextStyle(color: AppColors.dangerDark, fontWeight: FontWeight.w700),
        ));
        last = m.end;
        continue;
      }
      spans.add(TextSpan(text: text.substring(last, m.start)));
      last = m.end;
    }
    spans.add(TextSpan(text: text.substring(last)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bullet)
            const Padding(
              padding: EdgeInsets.only(top: 7, right: 8),
              child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.textTertiary),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _kindTags[kind]!.$2, borderRadius: BorderRadius.circular(6)),
                    child: Text(kind, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kindTags[kind]!.$1)),
                  ),
                Text.rich(
                  TextSpan(children: spans),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.55),
                ),
                for (final c in cites)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(c, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  ),
                for (final f in flags)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(6)),
                    child: Text('확인 필요: $f', style: const TextStyle(fontSize: 10.5, color: AppColors.warningTintInk, height: 1.4)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceMemosCard extends StatelessWidget {
  const _SourceMemosCard({required this.memos});
  final List<AiReportMemo> memos;

  @override
  Widget build(BuildContext context) {
    if (memos.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text('근거 메모 ${memos.length}건',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          subtitle: const Text('리포트를 만들 때 AI에 보낸 그대로예요', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          children: [
            for (final m in memos)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.date} · ${m.kind} · ${m.author}', style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary)),
                    Text(m.body, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.45)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BodyEditor extends StatefulWidget {
  const _BodyEditor({required this.initial});
  final String initial;

  @override
  State<_BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<_BodyEditor> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('리포트 수정', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.neutralCard,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: const Text('"## 제목"은 섹션, "- "로 시작하는 줄은 항목이에요. AI 원문은 따로 보관됩니다.',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 13, height: 1.55, color: AppColors.textPrimary),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
