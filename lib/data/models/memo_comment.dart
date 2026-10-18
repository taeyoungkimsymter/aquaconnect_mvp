import 'dart:typed_data';

/// A photo or file attached to a 댓글 (metadata only — bytes are loaded on
/// demand via MemoRepository.loadCommentAttachment).
class CommentAttachment {
  const CommentAttachment({
    required this.id,
    required this.isPhoto,
    required this.fileName,
    required this.contentType,
    required this.size,
  });

  final String id;
  final bool isPhoto;
  final String fileName;
  final String contentType;
  final int size;

  factory CommentAttachment.fromJson(Map<String, dynamic> json) => CommentAttachment(
        id: json['id'] as String,
        isPhoto: json['kind'] == 'photo',
        fileName: json['fileName'] as String? ?? '',
        contentType: json['contentType'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// A photo/file picked in the comment composer, not yet sent.
class CommentAttachmentUpload {
  const CommentAttachmentUpload({
    required this.isPhoto,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final bool isPhoto;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
}

/// A member a comment called with "@이름" (사람 호출).
class CommentMention {
  const CommentMention({required this.memberId, required this.name});

  final String memberId;
  final String name;

  factory CommentMention.fromJson(Map<String, dynamic> json) =>
      CommentMention(memberId: json['id'] as String, name: json['name'] as String? ?? '');
}

/// A 댓글 on a memo, written by an institute member.
class MemoComment {
  const MemoComment({
    required this.id,
    required this.memoId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.authorMemberId,
    this.mentions = const [],
    this.attachments = const [],
  });

  final String id;
  final String memoId;

  /// Null once the author's account is gone.
  final String? authorMemberId;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final List<CommentMention> mentions;
  final List<CommentAttachment> attachments;

  factory MemoComment.fromJson(Map<String, dynamic> json) => MemoComment(
        id: json['id'] as String,
        memoId: json['memoId'] as String,
        authorMemberId: json['authorMemberId'] as String?,
        authorName: json['authorName'] as String? ?? '',
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        mentions: (json['mentions'] as List<dynamic>? ?? const [])
            .map((e) => CommentMention.fromJson(e as Map<String, dynamic>))
            .toList(),
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map((e) => CommentAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
