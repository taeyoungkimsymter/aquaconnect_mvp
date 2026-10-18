import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/memo.dart';
import '../../data/models/memo_comment.dart';
import '../../data/models/org_member.dart';
import '../../data/services/file_transfer.dart';
import '../../data/services/photo_capture.dart';
import '../providers/data_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

const _maxPhotos = 5;
const _maxFiles = 3;
const _maxFileBytes = 10 * 1024 * 1024;

/// 댓글 sheet: the thread, oldest first, with an input at the bottom that can
/// attach photos / files and call (@) members.
class MemoCommentsSheet extends ConsumerStatefulWidget {
  const MemoCommentsSheet({super.key, required this.memo});

  final Memo memo;

  @override
  ConsumerState<MemoCommentsSheet> createState() => _MemoCommentsSheetState();
}

class _MemoCommentsSheetState extends ConsumerState<MemoCommentsSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<MemoComment>? _comments;
  String? _loadError;
  String? _sendError;
  bool _sending = false;
  final _pending = <CommentAttachmentUpload>[];

  /// Members picked from the @ list, by name — only those whose "@이름" is
  /// still in the text when sending are actually called.
  final _picked = <String, String>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
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

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  int get _photoCount => _pending.where((a) => a.isPhoto).length;
  int get _fileCount => _pending.length - _photoCount;

  Future<void> _addPhoto() async {
    if (_photoCount >= _maxPhotos) return _toast('사진은 최대 $_maxPhotos장까지 첨부할 수 있어요.');
    try {
      final photo = await pickPhotoFromAlbum();
      if (photo == null || !mounted) return;
      setState(() => _pending.add(CommentAttachmentUpload(
            isPhoto: true,
            fileName: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
            contentType: photo.contentType,
            bytes: photo.bytes,
          )));
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  Future<void> _addFile() async {
    if (_fileCount >= _maxFiles) return _toast('파일은 최대 $_maxFiles개까지 첨부할 수 있어요.');
    try {
      final file = await pickDocument();
      if (file == null || !mounted) return;
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      if (!commentFileExtensions.contains(ext)) {
        return _toast('첨부할 수 없는 파일이에요. (${commentFileExtensions.join(', ')})');
      }
      if (file.bytes.length > _maxFileBytes) return _toast('파일 하나는 10MB 이하여야 해요.');
      setState(() => _pending.add(CommentAttachmentUpload(
            isPhoto: false,
            fileName: file.name,
            contentType: 'application/octet-stream',
            bytes: file.bytes,
          )));
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  // ── 사람 호출 ──
  /// The "@글자" the cursor is currently inside, if any.
  RegExpMatch? get _mentionToken {
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0 || cursor > _controller.text.length) return null;
    return RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(_controller.text.substring(0, cursor));
  }

  List<OrgMember> _suggestions(List<OrgMember> members, String? meId, String query) {
    return members
        .where((m) => m.status == MemberStatus.active && m.id != meId && m.name.contains(query))
        .take(6)
        .toList();
  }

  void _insertMention(OrgMember member, RegExpMatch token) {
    final cursor = _controller.selection.baseOffset;
    final text = _controller.text;
    final start = token.start + token.group(1)!.length; // keep the leading space
    final inserted = '@${member.name} ';
    _picked[member.name] = member.id;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, cursor, inserted),
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    _focus.requestFocus();
  }

  void _startMention() {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset.clamp(0, text.length);
    final needsSpace = cursor > 0 && !RegExp(r'\s').hasMatch(text[cursor - 1]);
    final inserted = needsSpace ? ' @' : '@';
    _controller.value = TextEditingValue(
      text: text.replaceRange(cursor, cursor, inserted),
      selection: TextSelection.collapsed(offset: cursor + inserted.length),
    );
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    final called = [
      for (final e in _picked.entries)
        if (text.contains('@${e.key}')) e.value,
    ];
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final comment = await ref.read(memoRepositoryProvider).addComment(
            memoId: widget.memo.id,
            content: text,
            mentionedMemberIds: called,
            attachments: List.of(_pending),
          );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _comments = [...?_comments, comment];
        _pending.clear();
        _picked.clear();
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

  Future<void> _delete(MemoComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('이 댓글을 삭제할까요?'),
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
      if (mounted) _toast('삭제하지 못했어요: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(authStateProvider).valueOrNull?.member;
    final isPrivileged = member?.role == MemberRole.owner || member?.role == MemberRole.director;
    final fmt = DateFormat('M/d HH:mm');
    final comments = _comments;
    final token = _mentionToken;
    final roster = token == null ? null : ref.watch(orgMembersProvider);

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
        child: Text('아직 댓글이 없어요. 첫 댓글을 남겨 보세요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
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
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.authorName} · ${fmt.format(c.createdAt.toLocal())}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand)),
                        if (c.content.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _CommentText(content: c.content, mentions: c.mentions, meId: member?.id),
                        ],
                        if (c.attachments.any((a) => a.isPhoto)) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final a in c.attachments.where((a) => a.isPhoto))
                                _CommentPhoto(memoId: widget.memo.id, commentId: c.id, attachment: a),
                            ],
                          ),
                        ],
                        for (final a in c.attachments.where((a) => !a.isPhoto))
                          _CommentFile(memoId: widget.memo.id, commentId: c.id, attachment: a),
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

    final canSend = _controller.text.trim().isNotEmpty || _pending.isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
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
            if (token != null)
              _MentionList(
                roster: roster!,
                suggestionsFor: (members) => _suggestions(members, member?.id, token.group(2) ?? ''),
                onPick: (m) => _insertMention(m, token),
              ),
            if (_pending.isNotEmpty) ...[
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final a in _pending)
                      _PendingChip(attachment: a, onRemove: _sending ? null : () => setState(() => _pending.remove(a))),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                IconButton(
                  tooltip: '사진 첨부',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _addPhoto,
                  icon: const Icon(Icons.image_outlined, size: 20, color: AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: '파일 첨부',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _addFile,
                  icon: const Icon(Icons.attach_file, size: 20, color: AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: '사람 호출',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _startMention,
                  icon: const Icon(Icons.alternate_email, size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '댓글 남기기 (@로 사람 호출)',
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
                  onPressed: (_sending || !canSend) ? null : _send,
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

/// Comment text with each called "@이름" highlighted (yours in a stronger colour).
class _CommentText extends StatelessWidget {
  const _CommentText({required this.content, required this.mentions, required this.meId});

  final String content;
  final List<CommentMention> mentions;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.45);
    final names = {for (final m in mentions) if (m.name.isNotEmpty) m.name: m.memberId};
    if (names.isEmpty) return Text(content, style: base);
    final pattern = RegExp('@(${names.keys.map(RegExp.escape).join('|')})');
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(content)) {
      if (m.start > last) spans.add(TextSpan(text: content.substring(last, m.start)));
      final mine = names[m.group(1)] == meId;
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(
          color: AppColors.brand,
          fontWeight: FontWeight.w800,
          backgroundColor: mine ? AppColors.brandTint : null,
        ),
      ));
      last = m.end;
    }
    if (last < content.length) spans.add(TextSpan(text: content.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _MentionList extends StatelessWidget {
  const _MentionList({required this.roster, required this.suggestionsFor, required this.onPick});

  final AsyncValue<List<OrgMember>> roster;
  final List<OrgMember> Function(List<OrgMember>) suggestionsFor;
  final ValueChanged<OrgMember> onPick;

  @override
  Widget build(BuildContext context) {
    final Widget child = roster.when(
      loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => const _MentionHint('구성원 목록을 불러오지 못했어요.'),
      data: (members) {
        final list = suggestionsFor(members);
        if (list.isEmpty) return const _MentionHint('호출할 수 있는 구성원이 없어요.');
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in list)
              InkWell(
                onTap: () => onPick(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                      Text(m.role.label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _MentionHint extends StatelessWidget {
  const _MentionHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.attachment, required this.onRemove});

  final CommentAttachmentUpload attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (a.isPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(a.bytes, width: 48, height: 48, fit: BoxFit.cover),
            )
          else
            Container(
              height: 48,
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Flexible(child: Text(a.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                ],
              ),
            ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: const CircleAvatar(radius: 9, backgroundColor: AppColors.textSecondary, child: Icon(Icons.close, size: 12, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentPhoto extends ConsumerWidget {
  const _CommentPhoto({required this.memoId, required this.commentId, required this.attachment});

  final String memoId;
  final String commentId;
  final CommentAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (memoId: memoId, commentId: commentId, attachmentId: attachment.id);
    Widget placeholder(Widget child) => Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: child,
        );
    return ref.watch(commentAttachmentProvider(key)).when(
          data: (bytes) => GestureDetector(
            onTap: () => _openViewer(context, bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
            ),
          ),
          loading: () => placeholder(const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, _) => placeholder(const Icon(Icons.broken_image_outlined, size: 20, color: AppColors.textMuted)),
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
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(dialogContext).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentFile extends ConsumerStatefulWidget {
  const _CommentFile({required this.memoId, required this.commentId, required this.attachment});

  final String memoId;
  final String commentId;
  final CommentAttachment attachment;

  @override
  ConsumerState<_CommentFile> createState() => _CommentFileState();
}

class _CommentFileState extends ConsumerState<_CommentFile> {
  bool _loading = false;

  Future<void> _download() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await ref.read(commentAttachmentProvider((
        memoId: widget.memoId,
        commentId: widget.commentId,
        attachmentId: widget.attachment.id,
      )).future);
      saveFile(widget.attachment.fileName, bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('파일을 받지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: _download,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(a.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Text(formatFileSize(a.size), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              const SizedBox(width: 6),
              _loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined, size: 16, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }
}
