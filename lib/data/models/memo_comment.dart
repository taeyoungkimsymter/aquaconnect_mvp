import 'dart:typed_data';

/// A 댓글 on a memo, written by an institute member.
class MemoComment {
  const MemoComment({
    required this.id,
    required this.memoId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.authorMemberId,
    this.attachments = const [],
    this.mentions = const [],
  });

  final String id;
  final String memoId;

  /// Null once the author's account is gone.
  final String? authorMemberId;
  final String authorName;

  /// May be empty when the comment only carries attachments or a 호출.
  final String content;
  final DateTime createdAt;
  final List<CommentAttachment> attachments;

  /// Members this comment calls in (호출 / @).
  final List<CommentMention> mentions;

  factory MemoComment.fromJson(Map<String, dynamic> json) => MemoComment(
        id: json['id'] as String,
        memoId: json['memoId'] as String,
        authorMemberId: json['authorMemberId'] as String?,
        authorName: json['authorName'] as String? ?? '',
        content: json['content'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map((e) => CommentAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        mentions: (json['mentions'] as List<dynamic>? ?? const [])
            .map((e) => CommentMention.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

enum CommentAttachmentKind { photo, file }

/// A stored 댓글 첨부 (metadata — bytes via MemoRepository.loadCommentAttachment).
class CommentAttachment {
  const CommentAttachment({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.size,
  });

  final String id;
  final CommentAttachmentKind kind;
  final String fileName;
  final String contentType;
  final int size;

  bool get isPhoto => kind == CommentAttachmentKind.photo;

  factory CommentAttachment.fromJson(Map<String, dynamic> json) => CommentAttachment(
        id: json['id'] as String,
        kind: json['kind'] == 'photo' ? CommentAttachmentKind.photo : CommentAttachmentKind.file,
        fileName: json['fileName'] as String? ?? '',
        contentType: json['contentType'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class CommentMention {
  const CommentMention({required this.memberId, required this.name});

  final String memberId;
  final String name;

  factory CommentMention.fromJson(Map<String, dynamic> json) =>
      CommentMention(memberId: json['memberId'] as String, name: json['name'] as String? ?? '');
}

/// A photo or file picked in the 댓글 sheet, not yet uploaded.
class CommentAttachmentUpload {
  const CommentAttachmentUpload({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final CommentAttachmentKind kind;
  final String fileName;
  final String contentType;
  final Uint8List bytes;

  bool get isPhoto => kind == CommentAttachmentKind.photo;

  Map<String, dynamic> toJson(String Function(Uint8List) encode) => {
        'kind': isPhoto ? 'photo' : 'file',
        'fileName': fileName,
        'contentType': contentType,
        'dataBase64': encode(bytes),
      };
}

/// "1.2MB" / "340KB" for a file tile.
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()}KB';
  return '${bytes}B';
}
