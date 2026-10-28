import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../data/models/memo.dart';
import '../../data/models/memo_comment.dart';
import '../../data/models/org_member.dart';
import '../../data/services/file_transfer.dart';
import '../../data/services/photo_capture.dart';
import '../providers/memo_read_tracker.dart';
import '../providers/repository_providers.dart';
import '../providers/data_providers.dart';
import '../theme/app_colors.dart';
import 'camera_capture_screen.dart';

class MemoCard extends ConsumerWidget {
  const MemoCard({super.key, required this.memo, this.showFarmTag = true});

  final Memo memo;
  final bool showFarmTag;

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
    final canComplete = memo.isTask || memo.mentionedMe || memo.isDone;
    final isInstitute = memo.authorType == MemoAuthorType.institute;
    final authorBg = isInstitute ? AppColors.brandTint : AppColors.goodTint;
    final authorFg = isInstitute ? AppColors.brand : AppColors.goodDark;
    final displayTags = <String>{
      ...memo.tags,
      if (memo.content.contains('할일:')) '할일',
    }.toList();

    // Tapping the card (outside its footer actions) opens 메모 상세.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE3E8EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  if (memo.mentionedMe && !memo.isDone)
                    const _Pill(text: '@나 호출됨', bg: AppColors.warning, fg: Colors.white, bold: true),
                  if (memo.isDone)
                    _Pill(
                      text: '✓ 완료${memo.doneByName == null || memo.doneByName!.isEmpty ? '' : ' · ${memo.doneByName}'}'
                          ' ${DateFormat('M/d HH:mm').format(memo.doneAt!.toLocal())}',
                      bg: AppColors.goodTint,
                      fg: AppColors.goodDark,
                      bold: true,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (canComplete) ...[
                    DoneCheckButton(done: memo.isDone, onTap: () => toggleDone(context, ref)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      memo.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: memo.isDone ? AppColors.textMuted : AppColors.textPrimary,
                        height: 1.55,
                        decoration: memo.isDone ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(DateFormat('M/d HH:mm').format(memo.createdAt.toLocal()) + (memo.isEdited ? ' · 수정됨' : ''),
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
                        if (canComplete)
                          memo.isDone
                              ? _FooterAction(label: '완료 취소', color: AppColors.textMuted, onTap: () => toggleDone(context, ref))
                              : _CompleteButton(onTap: () => toggleDone(context, ref)),
                        _FooterAction(
                          label: memo.commentCount > 0 ? '댓글 ${memo.commentCount}' : '댓글 달기',
                          onTap: () => showComments(context),
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
      ),
    );
  }

  /// Opens 메모 상세: the full memo plus its 최근 이력 (등록·수정·댓글·완료).
  void showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MemoDetailSheet(memo: memo),
    );
  }

  /// Opens the system share sheet with the memo as text — the user picks
  /// 카카오톡 and then the farm's chat. (A direct send to the farm would need a
  /// Kakao business channel; the share sheet needs no key.) Photos aren't
  /// included.
  void _share(BuildContext context) {
    final when = DateFormat('M월 d일 HH:mm').format(memo.createdAt.toLocal());
    final text = [
      '[${memo.farmLabel}] 현장 메모',
      '',
      memo.content,
      '',
      '${memo.authorName} · $when',
    ].join('\n');
    Share.share(text, subject: '${memo.farmLabel} 현장 메모');
  }

  /// 완료 / 완료 취소, with a 되돌리기 snackbar after completing.
  Future<void> toggleDone(BuildContext context, WidgetRef ref) async {
    final done = !memo.isDone;
    try {
      await ref.read(memoRepositoryProvider).setMemoDone(id: memo.id, done: done);
      if (done && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
          content: const Text('완료했어요'),
          duration: const Duration(seconds: 3),
          persist: false, // action이 있으면 기본적으로 사라지지 않음
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () => ref.read(memoRepositoryProvider).setMemoDone(id: memo.id, done: false),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('완료 처리하지 못했어요: $e')));
      }
    }
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

  /// Opens this memo's 댓글 sheet (also used when a comment notification is tapped).
  void showComments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MemoCommentsSheet(memo: memo),
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

/// 댓글 sheet: the thread, oldest first, with an input at the bottom. A
/// comment can carry photos/files (첨부) and call members in (호출 / '@'),
/// so a job can be handed over in the thread itself.
class _MemoCommentsSheet extends ConsumerStatefulWidget {
  const _MemoCommentsSheet({required this.memo});

  final Memo memo;

  @override
  ConsumerState<_MemoCommentsSheet> createState() => _MemoCommentsSheetState();
}

class _MemoCommentsSheetState extends ConsumerState<_MemoCommentsSheet> {
  static const _maxAttachments = 5;
  static const _maxFileBytes = 10 * 1024 * 1024;
  static const _maxTotalBytes = 20 * 1024 * 1024;

  final _controller = TextEditingController();
  List<MemoComment>? _comments;
  String? _loadError;
  String? _sendError;
  bool _sending = false;
  final List<CommentAttachmentUpload> _attachments = [];
  final List<CommentMention> _mentions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await ref.read(memoRepositoryProvider).listComments(widget.memo.id);
      if (mounted) setState(() => _comments = comments);
    } catch (e) {
      if (mounted) setState(() => _loadError = '댓글을 불러오지 못했어요: $e');
    }
  }

  bool get _canSend =>
      !_sending && (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty || _mentions.isNotEmpty);

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _controller.text.trim();
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final comment = await ref.read(memoRepositoryProvider).addComment(
            memoId: widget.memo.id,
            content: text,
            mentions: List.of(_mentions),
            attachments: List.of(_attachments),
          );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _comments = [...?_comments, comment];
        _attachments.clear();
        _mentions.clear();
        _sending = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendError = '댓글을 남기지 못했어요: $e';
        });
      }
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Adds [items] if they fit the per-comment limits; reports what didn't.
  void _addAttachments(List<CommentAttachmentUpload> items) {
    var total = _attachments.fold<int>(0, (sum, a) => sum + a.bytes.length);
    for (final item in items) {
      if (_attachments.length >= _maxAttachments) {
        _snack('첨부는 최대 $_maxAttachments개까지 가능해요.');
        break;
      }
      if (!item.isPhoto && item.bytes.length > _maxFileBytes) {
        _snack("'${item.fileName}'은(는) 10MB를 넘어 첨부할 수 없어요.");
        continue;
      }
      if (total + item.bytes.length > _maxTotalBytes) {
        _snack('첨부 파일은 합쳐서 20MB 이하여야 해요.');
        break;
      }
      total += item.bytes.length;
      setState(() => _attachments.add(item));
    }
  }

  CommentAttachmentUpload _photoUpload(MemoPhotoUpload photo) => CommentAttachmentUpload(
        kind: CommentAttachmentKind.photo,
        fileName: '사진_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg',
        contentType: photo.contentType,
        bytes: photo.bytes,
      );

  Future<void> _openAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.brand),
              title: const Text('사진 촬영'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.brand),
              title: const Text('앨범에서 사진 선택'),
              onTap: () => Navigator.of(sheetContext).pop('album'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: AppColors.brand),
              title: const Text('파일 첨부'),
              subtitle: const Text('문서·엑셀·PDF 등 (파일당 10MB 이하)'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'camera':
          final photo = await CameraCaptureScreen.open(context);
          if (photo != null && mounted) _addAttachments([_photoUpload(photo)]);
        case 'album':
          final photo = await pickPhotoFromAlbum();
          if (photo != null && mounted) _addAttachments([_photoUpload(photo)]);
        case 'file':
          final files = await pickFiles();
          if (mounted) {
            _addAttachments([
              for (final f in files)
                CommentAttachmentUpload(
                  kind: CommentAttachmentKind.file,
                  fileName: f.name,
                  contentType: f.contentType,
                  bytes: f.bytes,
                ),
            ]);
          }
      }
    } catch (e) {
      if (mounted) _snack('첨부하지 못했어요: $e');
    }
  }

  /// 호출: pick members to call in. Typing '@' opens this too.
  Future<void> _openMentionPicker() async {
    final picked = await showModalBottomSheet<List<CommentMention>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MentionPickerSheet(initial: _mentions),
    );
    if (picked != null && mounted) {
      setState(() => _mentions
        ..clear()
        ..addAll(picked));
    }
  }

  void _onTextChanged(String text) {
    // A freshly typed trailing '@' opens the 호출 picker and is dropped.
    if (text.endsWith('@') && _controller.selection.baseOffset == text.length) {
      _controller.text = text.substring(0, text.length - 1);
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      _openMentionPicker();
    }
    setState(() {});
  }

  Future<void> _delete(MemoComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: Text(comment.attachments.isEmpty ? '이 댓글을 삭제할까요?' : '이 댓글과 첨부 파일을 삭제할까요?'),
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
      await ref.read(memoRepositoryProvider).deleteComment(memoId: widget.memo.id, commentId: comment.id);
      if (mounted) setState(() => _comments = _comments?.where((c) => c.id != comment.id).toList());
    } catch (e) {
      if (mounted) _snack('삭제하지 못했어요: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(authStateProvider).valueOrNull?.member;
    final isPrivileged = member?.role == MemberRole.owner || member?.role == MemberRole.director;
    final fmt = DateFormat('M/d HH:mm');
    final comments = _comments;

    final Widget body;
    if (_loadError != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    } else if (comments == null) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
    } else if (comments.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('아직 댓글이 없어요. 첫 댓글을 남겨 보세요.\n사진·파일을 첨부하거나 @로 담당자를 호출할 수 있어요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5)),
      );
    } else {
      body = Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: comments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = comments[i];
            final canDelete = member != null && (isPrivileged || c.authorMemberId == member.id);
            final callsMe = member != null && c.mentions.any((m) => m.memberId == member.id);
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: callsMe ? AppColors.warningTint : AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: callsMe ? Border.all(color: AppColors.warning) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.authorName} · ${fmt.format(c.createdAt.toLocal())}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand)),
                        if (c.mentions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final m in c.mentions)
                                _MentionChip(name: m.name, highlight: m.memberId == member?.id),
                            ],
                          ),
                        ],
                        if (c.content.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(c.content, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.45)),
                        ],
                        if (c.attachments.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final a in c.attachments) if (a.isPhoto) _CommentPhotoThumb(attachment: a)],
                          ),
                          for (final a in c.attachments)
                            if (!a.isPhoto) ...[const SizedBox(height: 6), _CommentFileTile(attachment: a)],
                        ],
                      ],
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: '댓글 삭제',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted),
                      onPressed: () => _delete(c),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('댓글', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(widget.memo.content,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            body,
            const SizedBox(height: 12),
            if (_sendError != null) ...[
              Text(_sendError!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              const SizedBox(height: 6),
            ],
            if (_mentions.isNotEmpty || _attachments.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final m in _mentions)
                    _MentionChip(
                      name: m.name,
                      onRemove: _sending ? null : () => setState(() => _mentions.remove(m)),
                    ),
                  for (final a in _attachments)
                    _PendingAttachment(
                      attachment: a,
                      onRemove: _sending ? null : () => setState(() => _attachments.remove(a)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                IconButton(
                  tooltip: '사진·파일 첨부',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _openAttachMenu,
                  icon: const Icon(Icons.attach_file, size: 20, color: AppColors.brand),
                ),
                IconButton(
                  tooltip: '담당자 호출',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _openMentionPicker,
                  icon: const Icon(Icons.alternate_email, size: 20, color: AppColors.brand),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '댓글 남기기 (@ 호출)',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '보내기',
                  onPressed: _canSend ? _send : null,
                  icon: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-select list of active members (not yourself) to call in a 댓글.
class _MentionPickerSheet extends ConsumerStatefulWidget {
  const _MentionPickerSheet({required this.initial});

  final List<CommentMention> initial;

  @override
  ConsumerState<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends ConsumerState<_MentionPickerSheet> {
  late final Map<String, CommentMention> _selected = {for (final m in widget.initial) m.memberId: m};

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('담당자 호출', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('호출한 사람에게 바로 알림이 가고, 알림을 누르면 이 댓글로 이동해요.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Flexible(
                child: membersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('구성원을 불러오지 못했어요: $e',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  ),
                  data: (members) {
                    final candidates = members.where((m) => m.status == MemberStatus.active && !m.isMe).toList();
                    if (candidates.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('호출할 수 있는 구성원이 없어요.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in candidates)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _selected.containsKey(m.id),
                            title: Text(m.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            subtitle: Text(m.role.label, style: const TextStyle(fontSize: 11.5)),
                            onChanged: (checked) => setState(() {
                              checked == true
                                  ? _selected[m.id] = CommentMention(memberId: m.id, name: m.name)
                                  : _selected.remove(m.id);
                            }),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected.values.toList()),
                child: Text(_selected.isEmpty ? '호출 안 함' : '${_selected.length}명 호출'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MentionChip extends StatelessWidget {
  const _MentionChip({required this.name, this.highlight = false, this.onRemove});

  final String name;

  /// The chip names the signed-in member.
  final bool highlight;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 2, onRemove == null ? 8 : 2, 2),
      decoration: BoxDecoration(
        color: highlight ? AppColors.warning : AppColors.brandTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('@$name${highlight ? ' (나)' : ''}',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: highlight ? Colors.white : AppColors.brand)),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.close, size: 14, color: AppColors.brand),
              ),
            ),
        ],
      ),
    );
  }
}

/// A picked-but-unsent attachment above the 댓글 input.
class _PendingAttachment extends StatelessWidget {
  const _PendingAttachment({required this.attachment, this.onRemove});

  final CommentAttachmentUpload attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove == null
        ? const SizedBox.shrink()
        : InkWell(onTap: onRemove, child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary));
    if (attachment.isPhoto) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(attachment.bytes, width: 44, height: 44, fit: BoxFit.cover),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              padding: const EdgeInsets.all(1),
              child: remove,
            ),
          ),
        ],
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(color: AppColors.neutralChip, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.neutralIcon),
          const SizedBox(width: 4),
          Flexible(
            child: Text('${attachment.fileName} · ${formatFileSize(attachment.bytes.length)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 4),
          remove,
        ],
      ),
    );
  }
}

class _CommentPhotoThumb extends ConsumerWidget {
  const _CommentPhotoThumb({required this.attachment});

  final CommentAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(commentAttachmentProvider(attachment.id)).when(
          data: (bytes) => GestureDetector(
            onTap: () => _openPhotoViewer(context, bytes, onSave: () => saveFile(bytes, attachment.fileName, attachment.contentType)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
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
}

/// A 댓글's attached file; tap downloads it.
class _CommentFileTile extends ConsumerStatefulWidget {
  const _CommentFileTile({required this.attachment});

  final CommentAttachment attachment;

  @override
  ConsumerState<_CommentFileTile> createState() => _CommentFileTileState();
}

class _CommentFileTileState extends ConsumerState<_CommentFileTile> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final a = widget.attachment;
    try {
      final bytes = await ref.read(memoRepositoryProvider).loadCommentAttachment(a.id);
      saveFile(bytes, a.fileName, a.contentType);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('내려받지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _download,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 20, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(formatFileSize(a.size), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              _downloading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.label, required this.onTap, this.danger = false, this.color});

  final String label;
  final VoidCallback onTap;
  final bool danger;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color ?? (danger ? AppColors.danger : AppColors.brand))),
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
            onTap: () => _openPhotoViewer(context, bytes),
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
}

/// Full-screen photo viewer; [onSave] adds a 저장 button.
void _openPhotoViewer(BuildContext context, Uint8List bytes, {VoidCallback? onSave}) {
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
            child: Row(
              children: [
                if (onSave != null)
                  IconButton(
                    tooltip: '저장',
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: onSave,
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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

/// 메모 상세: the whole memo (no line clamp), its facts at a glance, and
/// 최근 이력 — 등록, 수정, 댓글, 완료 merged newest first.
class _MemoDetailSheet extends ConsumerStatefulWidget {
  const _MemoDetailSheet({required this.memo});

  final Memo memo;

  @override
  ConsumerState<_MemoDetailSheet> createState() => _MemoDetailSheetState();
}

class _HistoryEntry {
  const _HistoryEntry({required this.at, required this.icon, required this.color, required this.title, this.body});

  final DateTime at;
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
}

class _MemoDetailSheetState extends ConsumerState<_MemoDetailSheet> {
  List<MemoComment>? _comments;
  String? _commentsError;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ref.read(memoRepositoryProvider).listComments(widget.memo.id);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      if (mounted) setState(() => _commentsError = '댓글 이력을 불러오지 못했어요');
    }
  }

  List<_HistoryEntry> _history(Memo memo) {
    final entries = <_HistoryEntry>[
      _HistoryEntry(at: memo.createdAt, icon: Icons.edit_note, color: AppColors.brand, title: '${memo.authorName} 등록'),
      for (final e in memo.edits)
        _HistoryEntry(
          at: e.editedAt,
          icon: Icons.edit_outlined,
          color: AppColors.warningDark,
          title: '${e.editorName.isEmpty ? '구성원' : e.editorName} 수정',
          body: '수정 전: ${e.previousContent}',
        ),
      for (final c in _comments ?? const <MemoComment>[])
        _HistoryEntry(
          at: c.createdAt,
          icon: Icons.chat_bubble_outline,
          color: AppColors.neutralIconStrong,
          title: '${c.authorName} 댓글',
          body: [
            if (c.mentions.isNotEmpty) c.mentions.map((m) => '@${m.name}').join(' '),
            if (c.content.isNotEmpty) c.content,
            if (c.attachments.isNotEmpty) '첨부 ${c.attachments.length}개',
          ].join(' · '),
        ),
      if (memo.doneAt != null)
        _HistoryEntry(
          at: memo.doneAt!,
          icon: Icons.check_circle_outline,
          color: AppColors.good,
          title: memo.doneByName == null || memo.doneByName!.isEmpty ? '완료 처리' : '${memo.doneByName} 완료 처리',
        ),
    ];
    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  Future<void> _openComments(Memo memo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MemoCommentsSheet(memo: memo),
    );
    _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    // Follow the live list so 완료·수정 made from here show up at once.
    var memo = widget.memo;
    for (final m in ref.watch(memosProvider(null)).valueOrNull ?? const <Memo>[]) {
      if (m.id == memo.id) memo = m;
    }
    final card = MemoCard(memo: memo);
    final member = ref.watch(authStateProvider).valueOrNull?.member;
    final isPrivileged = member?.role == MemberRole.owner || member?.role == MemberRole.director;
    final isMine = memo.authorType == MemoAuthorType.institute &&
        member != null &&
        (memo.authorMemberId != null ? memo.authorMemberId == member.id : memo.authorName.endsWith(' · ${member.name}'));
    final canModify = memo.authorType == MemoAuthorType.institute && member != null && (isPrivileged || isMine);
    final fmt = DateFormat('yyyy.M.d (E) HH:mm', 'ko_KR');
    final history = _history(memo);
    // Non-privileged members get only the count, not the edit log itself.
    final hiddenEdits = memo.editCount - memo.edits.length;
    final doneBy = memo.doneByName == null || memo.doneByName!.isEmpty ? '' : ' · ${memo.doneByName}';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('메모 상세', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
                IconButton(
                  tooltip: '닫기',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    memo.content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: memo.isDone ? AppColors.textMuted : AppColors.textPrimary,
                      decoration: memo.isDone ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textMuted,
                    ),
                  ),
                  if (memo.photoIds.isNotEmpty || memo.photoCount > 0) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in memo.photoIds) _MemoPhotoThumb(photoId: id),
                        for (var i = memo.photoIds.length; i < memo.photoCount; i++) const _PhotoPlaceholder(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _DetailRow(label: '양식장', value: memo.farmLabel),
            _DetailRow(label: '작성자', value: memo.authorName),
            if (memo.assigneeName != null) _DetailRow(label: '담당자', value: memo.assigneeName!),
            _DetailRow(label: '등록', value: fmt.format(memo.createdAt.toLocal())),
            _DetailRow(
              label: '상태',
              value: memo.isDone
                  ? '완료 · ${fmt.format(memo.doneAt!.toLocal())}$doneBy'
                  : (memo.isTask || memo.mentionedMe ? '진행 중' : '일반 메모'),
              valueColor: memo.isDone ? AppColors.good : null,
            ),
            _DetailRow(label: '읽음', value: memo.readCount > 0 ? '${memo.readCount}명' : '아직 없음'),
            if (memo.tags.isNotEmpty) _DetailRow(label: '태그', value: memo.tags.join(', ')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (memo.isTask || memo.mentionedMe || memo.isDone)
                  _DetailAction(
                    icon: memo.isDone ? Icons.undo : Icons.check,
                    label: memo.isDone ? '완료 취소' : '완료',
                    color: memo.isDone ? AppColors.textMuted : AppColors.good,
                    onTap: () => card.toggleDone(context, ref),
                  ),
                _DetailAction(
                  icon: Icons.chat_bubble_outline,
                  label: memo.commentCount > 0 ? '댓글 ${memo.commentCount}' : '댓글 달기',
                  onTap: () => _openComments(memo),
                ),
                _DetailAction(icon: Icons.ios_share, label: '공유', onTap: () => card._share(context)),
                if (canModify) _DetailAction(icon: Icons.edit_outlined, label: '수정', onTap: () => card._showEditSheet(context)),
              ],
            ),
            const SizedBox(height: 20),
            const Text('최근 이력', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            if (_comments == null && _commentsError == null)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
            for (var i = 0; i < history.length; i++)
              _HistoryTile(entry: history[i], last: i == history.length - 1),
            if (hiddenEdits > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('수정 $hiddenEdits회 · 수정 전 내용은 원장·소유자만 볼 수 있어요.',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            if (_commentsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_commentsError!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color ?? AppColors.brand,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// One step of the 최근 이력 timeline: a dot on a vertical line, then what
/// happened and when.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.last});

  final _HistoryEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: entry.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(entry.icon, size: 13, color: entry.color),
                ),
                if (!last) Expanded(child: Container(width: 1.5, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(entry.title,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                      Text(DateFormat('M/d HH:mm').format(entry.at.toLocal()),
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                    ],
                  ),
                  if (entry.body != null && entry.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(entry.body!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round ✓ at the start of a task memo — a big target (44px) so 완료 is
/// one easy tap; filled green once done (tap again to reopen).
class DoneCheckButton extends StatelessWidget {
  const DoneCheckButton({super.key, required this.done, required this.onTap, this.size = 26});

  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: done ? '완료 취소' : '완료하기',
      child: Tooltip(
        message: done ? '완료 취소' : '완료하기',
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.good : Colors.white,
                  border: Border.all(color: AppColors.good, width: 2),
                ),
                child: Icon(Icons.check, size: size * 0.62, color: done ? Colors.white : AppColors.good.withValues(alpha: 0.35)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer "✓ 완료하기" — a filled pill rather than a text link.
class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.good,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 14, color: Colors.white),
              SizedBox(width: 3),
              Text('완료하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
