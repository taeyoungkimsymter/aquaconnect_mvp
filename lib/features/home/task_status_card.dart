import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/memo_view_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ai_insight_card.dart';
import '../../core/widgets/memo_card.dart' show toggleMemoCompleted;
import '../../data/logic/memo_filter.dart' show summarizeOpenTasks;
import '../../data/models/memo.dart';

const _previewCount = 3;

/// 홈의 업무 현황 — 완료되지 않은 모든 할 일(이전 날짜 포함)의 건수와 미리보기.
class TaskStatusCard extends ConsumerWidget {
  const TaskStatusCard({super.key});

  void _open(BuildContext context, WidgetRef ref, {String? focusMemoId}) {
    ref.read(memoViewRequestProvider.notifier).state = MemoViewRequest.openTasks(focusMemoId: focusMemoId);
    context.go('/memo');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(openTasksProvider);
    final tasks = tasksAsync.valueOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('업무 현황', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              TextButton(
                onPressed: () => _open(context, ref),
                style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('모두 보기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (tasks == null)
            tasksAsync.hasError
                ? const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('업무를 불러오지 못했어요.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
          else if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('남은 할 일이 없어요.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            )
          else ...[
            if (summarizeOpenTasks(tasks, DateTime.now()).isNotEmpty) ...[
              AiInsightCard(title: 'AI 정리', bullets: summarizeOpenTasks(tasks, DateTime.now())),
              const SizedBox(height: 10),
            ],
            InkWell(
              onTap: () => _open(context, ref),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: '남은 할 일 '),
                    TextSpan(text: '${tasks.length}건', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800)),
                  ]),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
            for (final memo in tasks.take(_previewCount)) _TaskRow(memo: memo, onOpen: () => _open(context, ref, focusMemoId: memo.id)),
            if (tasks.length > _previewCount)
              TextButton(
                onPressed: () => _open(context, ref),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: Text('외 ${tasks.length - _previewCount}건 더 보기', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              )
            else
              const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// 업무 본문 — "할일:" 표시를 떼고 첫 줄만.
String _taskText(Memo memo) {
  for (final line in memo.content.split('\n')) {
    final t = line.replaceFirst(RegExp(r'^\s*할일\s*[:：]\s*'), '').trim();
    if (t.isNotEmpty) return t;
  }
  return memo.content.trim();
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.memo, required this.onOpen});

  final Memo memo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = _taskText(memo);
    return Row(
      children: [
        // 체크는 이동 없이 완료 처리만 — 행의 탭과 영역이 겹치지 않게 따로 둔다.
        Semantics(
          button: true,
          label: '완료 처리',
          child: InkWell(
            onTap: () => toggleMemoCompleted(context, ref, memo),
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.radio_button_unchecked, size: 22, color: AppColors.neutralIconStrong),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(memo.farmLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                        ),
                        if (memo.mentionsMe) ...[
                          const SizedBox(width: 6),
                          const Text('@ 나', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.warningDark)),
                        ],
                        const Spacer(),
                        Text(DateFormat('M.d').format(memo.createdAt.toLocal()),
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, height: 1.3)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
