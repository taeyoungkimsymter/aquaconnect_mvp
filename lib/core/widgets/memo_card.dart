import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../data/models/member.dart';
import '../../data/models/memo.dart';
import 'memo_comments_sheet.dart';
import '../providers/memo_read_tracker.dart';
import '../providers/repository_providers.dart';
import '../providers/data_providers.dart';
import '../theme/app_colors.dart';

/// Checks a memo off or reopens it (완료 / 완료 취소). Shared by the card's
/// button and the memo detail screen's button.
Future<void> toggleMemoCompleted(BuildContext context, WidgetRef ref, Memo memo) async {
  final repo = ref.read(memoRepositoryProvider);
  final completing = !memo.isCompleted;
  try {
    await repo.setCompleted(memo.id, completing);
    if (context.mounted && completing) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('완료 처리했어요'),
          duration: const Duration(seconds: 3),
          persist: false, // action이 있으면 기본적으로 사라지지 않음
          action: SnackBarAction(label: '되돌리기', onPressed: () => repo.setCompleted(memo.id, false)),
        ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('처리하지 못했어요: $e')));
    }
  }
}

class MemoCard extends ConsumerWidget {
  const MemoCard({super.key, required this.memo, this.showFarmTag = true, this.onTap, this.showCompleteButton = true});

  final Memo memo;
  final bool showFarmTag;

  /// Tapping the card body (e.g. open the memo's detail screen).
  final VoidCallback? onTap;

  /// The 완료 button in the card footer. The detail screen has its own.
  final bool showCompleteButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(authStateProvider).valueOrNull?.member;
    final isPrivileged = member?.role == MemberRole.owner || member?.role == MemberRole.director;
    // Memos record their author's member id; older ones are matched by the
    // "기관명 · 이름" signature — the same rule the server enforces.
    final isMine = memo.authorType == MemoAuthorType.institute &&
        member != null &&
        (memo.authorMemberId != null
            ? memo.authorMemberId == member.id
            : memo.authorName.endsWith(' · ${member.name}'));
    // Editable/deletable by the author or an owner/director. A farm's 문의
    // memo is never editable.
    final canModify = memo.authorType == MemoAuthorType.institute && member != null && (isPrivileged || isMine);
    // Being shown on screen counts as read (읽음 표시) — except your own memo.
    if (member != null && !isMine && !memo.readByMe) {
      final tracker = ref.read(memoReadTrackerProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) => tracker.seen(memo.id));
    }
    final canSeeHistory = isPrivileged && memo.edits.isNotEmpty;
    final isInstitute = memo.authorType == MemoAuthorType.institute;
    final authorBg = isInstitute ? AppColors.brandTint : AppColors.goodTint;
    final authorFg = isInstitute ? AppColors.brand : AppColors.goodDark;
    final displayTags = <String>{
      ...memo.tags,
      if (memo.content.contains('할일:')) '할일',
    }.toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: memo.isCompleted ? AppColors.background : AppColors.surface,
        border: Border.all(color: const Color(0xFFE3E8EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              if (showFarmTag) _Pill(text: memo.farmLabel, bg: AppColors.neutralChipStrong, fg: AppColors.textSecondary),
              _Pill(text: memo.authorName, bg: authorBg, fg: authorFg, bold: true),
              if (memo.isCompleted) const _Pill(text: '완료', bg: AppColors.goodTint, fg: AppColors.goodDark, bold: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  memo.content,
                  style: TextStyle(
                    fontSize: 13,
                    color: memo.isCompleted ? AppColors.textMuted : AppColors.textPrimary,
                    decoration: memo.isCompleted ? TextDecoration.lineThrough : null,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(DateFormat('M/d HH:mm').format(memo.createdAt) + (memo.isEdited ? ' · 수정됨' : ''),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ],
          ),
          if (memo.photoIds.isNotEmpty || memo.photoCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in memo.photoIds) _MemoPhotoThumb(photoId: id),
                // Seed memos only carry a count, not stored images.
                for (var i = memo.photoIds.length; i < memo.photoCount; i++) const _PhotoPlaceholder(),
              ],
            ),
          ],
          if (displayTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: displayTags
                  .map((t) => _Pill(text: t, bg: AppColors.neutralChip, fg: AppColors.neutralIcon, small: true))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showCompleteButton)
                      _FooterAction(
                        label: memo.isCompleted ? '완료 취소' : '✓ 완료',
                        onTap: () => toggleMemoCompleted(context, ref, memo),
                      ),
                    _FooterAction(
                      label: memo.commentCount > 0 ? '댓글 ${memo.commentCount}' : '댓글 달기',
                      onTap: () => _showComments(context),
                    ),
                    _FooterAction(label: '공유', onTap: () => _share(context)),
                    if (canModify) _FooterAction(label: '수정', onTap: () => _showEditSheet(context)),
                    if (canSeeHistory)
                      _FooterAction(label: '수정 이력 ${memo.edits.length}', onTap: () => _showHistorySheet(context)),
                    if (canModify) _FooterAction(label: '삭제', onTap: () => _confirmDelete(context, ref), danger: true),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                memo.readCount > 0 ? '읽음 ${memo.readCount}' : '안 읽음',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: memo.readCount > 0 ? FontWeight.w600 : FontWeight.w400,
                  color: memo.readCount > 0 ? AppColors.textMuted : AppColors.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  /// Opens the system share sheet with the memo as text — the user picks
  /// 카카오톡 and then the farm's chat. (A direct send to the farm would need a
  /// Kakao business channel; the share sheet needs no key.) Photos aren't
  /// included.
  void _share(BuildContext context) {
    final when = DateFormat('M월 d일 HH:mm').format(memo.createdAt);
    final text = [
      '[${memo.farmLabel}] 현장 메모',
      '',
      memo.content,
      '',
      '${memo.authorName} · $when',
    ].join('\n');
    Share.share(text, subject: '${memo.farmLabel} 현장 메모');
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('메모 삭제'),
        content: Text(memo.photoCount > 0 ? '이 메모와 첨부 사진을 삭제할까요? 되돌릴 수 없어요.' : '이 메모를 삭제할까요? 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(memoRepositoryProvider).deleteMemo(memo.id);
      // The farm's risk / 최근 방문 can change when a memo goes away.
      if (memo.farmId != null) ref.invalidate(farmsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제하지 못했어요: $e')));
      }
    }
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => MemoCommentsSheet(memo: memo),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MemoEditSheet(memo: memo),
    );
  }

  void _showHistorySheet(BuildContext context) {
    final fmt = DateFormat('M/d HH:mm');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            children: [
              const Text('수정 이력', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              // Newest edit first; each row shows the text as it stood before that edit.
              for (final e in memo.edits.reversed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.editorName} · ${fmt.format(e.editedAt.toLocal())}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                      const SizedBox(height: 4),
                      const Text('수정 전', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      Text(e.previousContent,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Text('현재 내용', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              Text(memo.content, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for 메모 수정. Stays open (with the error shown) if saving
/// fails, so the edited text isn't lost.
class _MemoEditSheet extends ConsumerStatefulWidget {
  const _MemoEditSheet({required this.memo});

  final Memo memo;

  @override
  ConsumerState<_MemoEditSheet> createState() => _MemoEditSheetState();
}

class _MemoEditSheetState extends ConsumerState<_MemoEditSheet> {
  late final _controller = TextEditingController(text: widget.memo.content);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '메모 내용을 입력해주세요.');
      return;
    }
    if (text == widget.memo.content) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(memoRepositoryProvider).updateMemo(id: widget.memo.id, content: text);
      // An edited 폐사 count can change the farm's risk.
      if (widget.memo.farmId != null) ref.invalidate(farmsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했어요: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('메모 수정', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('수정 전 내용은 원장·소유자가 이력으로 확인할 수 있어요.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            enabled: !_saving,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.label, required this.onTap, this.danger = false});

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: danger ? AppColors.danger : AppColors.brand)),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.child = const Icon(Icons.image_outlined, size: 20, color: AppColors.textMuted)});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _MemoPhotoThumb extends ConsumerWidget {
  const _MemoPhotoThumb({required this.photoId});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(memoPhotoProvider(photoId)).when(
          data: (bytes) => GestureDetector(
            onTap: () => _openViewer(context, bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
            ),
          ),
          loading: () => const _PhotoPlaceholder(
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => const _PhotoPlaceholder(
            child: Icon(Icons.broken_image_outlined, size: 20, color: AppColors.textMuted),
          ),
        );
  }

  void _openViewer(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.memory(bytes))),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg, this.bold = false, this.small = false});

  final String text;
  final Color bg;
  final Color fg;
  final bool bold;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: small ? 10 : 10.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
