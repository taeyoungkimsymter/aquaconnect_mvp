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
    this.mentionedMe = false,
    this.doneAt,
    this.doneByMemberId,
    this.doneByName,
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

  /// A 댓글 on it calls (호출) the signed-in member.
  final bool mentionedMe;

  /// 완료: when the task was marked done, and by whom (null = open).
  final DateTime? doneAt;
  final String? doneByMemberId;
  final String? doneByName;

  bool get isDone => doneAt != null;

  String get farmLabel => farmName ?? '미지정';

  /// The 담당자 picked in the composer ('담당:<이름>' tag), if any.
  String? get assigneeName {
    for (final t in tags) {
      if (t.startsWith('담당:')) return t.substring(3);
    }
    return null;
  }

  /// A 할일 (tag or '할일:' in the text) or a memo with a 담당자 — something
  /// to get done, so it can be marked 완료.
  bool get isTask => tags.contains('할일') || content.contains('할일:') || assigneeName != null;

  /// Counts toward this member's 오늘의 업무: open, and it calls them (@),
  /// is assigned to them, or is an unassigned 할일 they wrote. Must match
  /// memberOpenTasks in server/src/lib/digest.js.
  bool isOpenTaskFor({required String memberId, required String memberName}) {
    if (isDone) return false;
    if (mentionedMe) return true;
    final assignee = assigneeName;
    if (assignee != null) return assignee == memberName;
    final isTodo = tags.contains('할일') || content.contains('할일:');
    return isTodo && authorMemberId == memberId;
  }

  Memo copyWith({String? content, List<MemoEdit>? edits, int? commentCount, bool? readByMe}) => Memo(
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
        mentionedMe: mentionedMe,
        doneAt: doneAt,
        doneByMemberId: doneByMemberId,
        doneByName: doneByName,
      );

  /// This memo marked done by [by] at [at], or reopened when [at] is null.
  Memo withDone(DateTime? at, {String? byId, String? byName}) => Memo(
        id: id,
        orgId: orgId,
        farmId: farmId,
        farmName: farmName,
        authorType: authorType,
        authorName: authorName,
        content: content,
        tags: tags,
        createdAt: createdAt,
        photoCount: photoCount,
        photoIds: photoIds,
        readByFarm: readByFarm,
        editCount: editCount,
        edits: edits,
        authorMemberId: authorMemberId,
        commentCount: commentCount,
        readCount: readCount,
        readByMe: readByMe,
        mentionedMe: mentionedMe,
        doneAt: at,
        doneByMemberId: at == null ? null : byId,
        doneByName: at == null ? null : byName,
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
        mentionedMe: json['mentionedMe'] as bool? ?? false,
        doneAt: json['doneAt'] == null ? null : DateTime.parse(json['doneAt'] as String),
        doneByMemberId: json['doneByMemberId'] as String?,
        doneByName: json['doneByName'] as String?,
      );
}

/// A photo taken/picked in the composer, already downscaled on-device.
class MemoPhotoUpload {
  const MemoPhotoUpload({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}
