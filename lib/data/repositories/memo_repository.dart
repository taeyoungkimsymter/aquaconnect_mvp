import 'dart:typed_data';

import '../models/memo.dart';
import '../models/memo_comment.dart';

abstract class MemoRepository {
  /// Live-updating memo feed, newest first. [farmId] filters to one farm;
  /// null returns every memo across the org.
  Stream<List<Memo>> watchMemos({String? farmId});

  /// One memo by its id, or null when it no longer exists (deleted) or isn't
  /// visible to the signed-in member. Network failures throw.
  Future<Memo?> getMemo(String id);

  Future<Memo> addMemo({
    String? farmId,
    String? farmName,
    required String content,
    required List<String> tags,
    List<MemoPhotoUpload> photos,
  });

  /// Replaces an institute memo's content and logs the previous content as an
  /// edit by the signed-in member. Only its author or an owner/director may.
  Future<Memo> updateMemo({required String id, required String content});

  /// Deletes a memo (and its photos).
  Future<void> deleteMemo(String id);

  /// Image bytes for one of a memo's [Memo.photoIds].
  Future<Uint8List> loadPhoto(String photoId);

  /// Records that the signed-in member has seen these memos (읽음 표시).
  Future<void> markRead(List<String> memoIds);

  /// A memo's 댓글, oldest first.
  Future<List<MemoComment>> listComments(String memoId);

  Future<MemoComment> addComment({required String memoId, required String content});

  /// Only the comment's author or an owner/director may.
  Future<void> deleteComment({required String memoId, required String commentId});
}
