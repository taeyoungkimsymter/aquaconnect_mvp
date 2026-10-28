import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/memo_card.dart';
import '../../data/models/memo.dart';

/// 오늘의 업무 at the top of Home — the first thing seen on opening the app,
/// so "오늘 뭐 해야 하지?" is answered without a tap. Shows what's left (a
/// few rows, each opening 메모 상세) and today's progress; 모두 보기 opens the
/// memo tab's 오늘의 업무 view.
class TodayTasksCard extends ConsumerWidget {
  const TodayTasksCard({super.key});

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTodayTasksProvider);
    if (tasks == null) return const SizedBox.shrink();
    final open = tasks.open;
    final doneToday = tasks.doneToday;
    final total = open.length + doneToday;
    // Called-in (호출) first, then oldest first: the longest-waiting job on top.
    final sorted = [...open]
      ..sort((a, b) {
        if (a.mentionedMe != b.mentionedMe) return a.mentionedMe ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    String dateLabel;
    try {
      dateLabel = DateFormat('M월 d일 (E)', 'ko_KR').format(DateTime.now());
    } catch (_) {
      dateLabel = DateFormat('M/d').format(DateTime.now());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.brandTintBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              const Text('오늘의 업무', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(dateLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
              InkWell(
                onTap: () => context.go('/memo?view=today'),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('모두 보기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.brand),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            open.isEmpty
                ? (doneToday > 0 ? '오늘 업무를 모두 끝냈어요! 수고하셨어요 👏' : '오늘 남은 업무가 없어요.')
                : '남은 업무 ${open.length}건${doneToday > 0 ? ' · 오늘 $doneToday건 완료' : ''}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: open.isEmpty ? AppColors.good : AppColors.textPrimary,
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: doneToday / total,
                minHeight: 6,
                backgroundColor: AppColors.neutralChip,
                color: AppColors.good,
              ),
            ),
          ],
          if (sorted.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final memo in sorted.take(_previewCount)) _TaskRow(memo: memo),
            if (sorted.length > _previewCount)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('외 ${sorted.length - _previewCount}건',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              ),
          ] else if (total == 0) ...[
            const SizedBox(height: 4),
            const Text('할일 태그·담당자를 지정하거나 댓글로 호출받은 메모가 여기에 모여요.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// One open task: tap the circle to finish it right here, the text to open
/// 메모 상세.
class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.memo});

  final Memo memo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = memo.content.trim().split('\n').first.replaceFirst(RegExp(r'^할일\s*:\s*'), '');
    return InkWell(
      onTap: () => MemoCard(memo: memo).showDetail(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            DoneCheckButton(done: false, size: 22, onTap: () => MemoCard(memo: memo).toggleDone(context, ref)),
            const SizedBox(width: 2),
            if (memo.mentionedMe)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.alternate_email, size: 14, color: AppColors.warningDark),
              ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  if (memo.farmName != null)
                    TextSpan(text: '${memo.farmName}  ', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                  TextSpan(text: line),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 6),
            Text(DateFormat('M/d').format(memo.createdAt.toLocal()),
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
