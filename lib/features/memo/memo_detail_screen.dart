import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/memo_card.dart';
import '../../data/models/memo.dart';

/// One memo, opened from a 새 메모 notification by the memo's id. Loading,
/// 삭제됨/접근 불가 and network errors each get their own state so the screen
/// is never blank.
class MemoDetailScreen extends ConsumerWidget {
  const MemoDetailScreen({super.key, required this.memoId});

  final String memoId;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/notifications');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoAsync = ref.watch(memoByIdProvider(memoId));

    // Edits / comments / deletes made on this screen update the shared memo
    // stream, not the one-shot fetch above: show the stream's copy when it has
    // this memo, and re-check when the memo drops out of it (deleted).
    bool has(List<Memo>? list) => list?.any((m) => m.id == memoId) ?? false;
    ref.listen(memosProvider(null), (prev, next) {
      if (has(prev?.valueOrNull) && !has(next.valueOrNull) && next.hasValue) {
        ref.invalidate(memoByIdProvider(memoId));
      }
    });
    final live = ref.watch(memosProvider(null)).valueOrNull?.where((m) => m.id == memoId).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        leading: BackButton(onPressed: () => _back(context)),
        title: const Text('메모', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      body: memoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Notice(
          icon: Icons.wifi_off_rounded,
          message: '메모를 불러오지 못했어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(memoByIdProvider(memoId)),
          secondaryLabel: '돌아가기',
          onSecondary: () => _back(context),
        ),
        data: (fetched) {
          final memo = live ?? fetched;
          return memo == null
            ? _Notice(
                icon: Icons.delete_outline,
                message: '삭제되었거나 볼 수 없는 메모예요.',
                actionLabel: '돌아가기',
                onAction: () => _back(context),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [MemoCard(memo: memo)],
              );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null) TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}
