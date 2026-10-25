import 'dart:typed_data';

enum MemoAuthorType {
  institute,
  farm;

  static MemoAuthorType fromKey(String key) =>
      key == 'farm' ? MemoAuthorType.farm : MemoAuthorType.institute;

  String get key => this == MemoAuthorType.farm ? 'farm' : 'institute';
}

/// One entry in a memo's edit log: who changed it, when, and what the
/// content said *before* that edit.
class MemoEdit {
  const MemoEdit({required this.editorName, required this.editedAt, required this.previousContent});

  final String editorName;
  final DateTime editedAt;
  final String previousContent;

  factory MemoEdit.fromJson(Map<String, dynamic> json) => MemoEdit(
        editorName: json['editorName'] as String? ?? '',
        editedAt: DateTime.parse(json['editedAt'] as String),
        previousContent: json['previousContent'] as String,
      );
}

class Memo {
  const Memo({
    required this.id,
    required this.orgId,
    required this.authorType,
    required this.authorName,
    required this.content,
    required this.tags,
    required this.createdAt,
    this.farmId,
    this.farmName,
    this.photoCount = 0,
    this.photoIds = const [],
    this.readByFarm = false,
    this.editCount = 0,
    this.edits = const [],
    this.authorMemberId,
    this.commentCount = 0,
    this.readCount = 0,
    this.readByMe = false,
    this.completedAt,
    this.mentionsMe = false,
  });

  final String id;
  final String orgId;
  final String? farmId;

  /// Denormalized display name — "미지정" when [farmId] is null.
  final String? farmName;
  final MemoAuthorType authorType;
  final String authorName;
  final String content;
  final List<String> tags;
  /// Total photos attached. Seed memos predate real photo storage, so this
  /// can exceed [photoIds].length — those extras render as placeholders.
  final int photoCount;

  /// IDs of stored photos, loadable via MemoRepository.loadPhoto.
  final List<String> photoIds;
  final bool readByFarm;
  final DateTime createdAt;

  /// How many times the memo was edited — sent to every member.
  final int editCount;

  /// Edit log, oldest first. The server only fills this in for
  /// owners/directors; others just see [editCount].
  final List<MemoEdit> edits;

  bool get isEdited => editCount > 0;

  /// The member who wrote it (null for a farm's 문의 and very old memos).
  final String? authorMemberId;
  final int commentCount;

  /// Members other than the author who have seen this memo.
  final int readCount;

  /// Whether the signed-in member has seen it (reported via markRead).
  final bool readByMe;

  /// When it was checked off (완료); null while still open. Any memo can be completed.
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  /// A 댓글 on this memo called the signed-in member (@이름).
  final bool mentionsMe;

  /// A 할일 memo — the tag, or a "할일:" line in the text.
  bool get isTask => tags.contains('할일') || content.contains('할일:');

  String get farmLabel => farmName ?? '미지정';

  Memo copyWith({String? content, List<MemoEdit>? edits, int? commentCount, bool? readByMe, bool? completed, bool? mentionsMe}) => Memo(
        id: id,
        orgId: orgId,
        farmId: farmId,
        farmName: farmName,
        authorType: authorType,
        authorName: authorName,
        content: content ?? this.content,
        tags: tags,
        createdAt: createdAt,
        photoCount: photoCount,
        photoIds: photoIds,
        readByFarm: readByFarm,
        editCount: edits?.length ?? editCount,
        edits: edits ?? this.edits,
        authorMemberId: authorMemberId,
        commentCount: commentCount ?? this.commentCount,
        readCount: readCount,
        readByMe: readByMe ?? this.readByMe,
        completedAt: completed == null ? completedAt : (completed ? (completedAt ?? DateTime.now()) : null),
        mentionsMe: mentionsMe ?? this.mentionsMe,
      );

  factory Memo.fromJson(Map<String, dynamic> json) => Memo(
        id: json['id'] as String,
        orgId: json['orgId'] as String,
        farmId: json['farmId'] as String?,
        farmName: json['farmName'] as String?,
        authorType: MemoAuthorType.fromKey(json['authorType'] as String),
        authorName: json['authorName'] as String,
        content: json['content'] as String,
        tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
        photoCount: json['photoCount'] as int? ?? 0,
        photoIds: (json['photoIds'] as List<dynamic>? ?? const []).cast<String>(),
        readByFarm: json['readByFarm'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        editCount: json['editCount'] as int? ?? 0,
        edits: (json['edits'] as List<dynamic>? ?? const [])
            .map((e) => MemoEdit.fromJson(e as Map<String, dynamic>))
            .toList(),
        authorMemberId: json['authorMemberId'] as String?,
        commentCount: json['commentCount'] as int? ?? 0,
        readCount: json['readCount'] as int? ?? 0,
        readByMe: json['readByMe'] as bool? ?? false,
        completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
        mentionsMe: json['mentionsMe'] as bool? ?? false,
      );
}

/// A photo taken/picked in the composer, already downscaled on-device.
class MemoPhotoUpload {
  const MemoPhotoUpload({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}
