import 'dart:async';
import 'dart:typed_data';

import '../../mock/mock_seed.dart';
import '../../models/memo.dart';
import '../../models/memo_comment.dart';
import '../memo_repository.dart';

class MockMemoRepository implements MemoRepository {
  MockMemoRepository() {
    _memos = MockSeed.initialMemos(DateTime.now());
  }

  late List<Memo> _memos;
  final _photos = <String, Uint8List>{};
  final _comments = <String, List<MemoComment>>{};
  final _controller = StreamController<List<Memo>>.broadcast();

  List<Memo> get _sorted => [..._memos]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _emit() => _controller.add(_sorted);

  @override
  Stream<List<Memo>> watchMemos({String? farmId}) {
    // Stream.multi replays the current list to every new subscriber (not
    // just the very first one ever) — see MockAuthRepository for why a
    // plain broadcast controller's onListen isn't enough here.
    return Stream<List<Memo>>.multi((controller) {
      controller.add(_sorted);
      final sub = _controller.stream.listen(controller.add, onDone: controller.close);
      controller.onCancel = sub.cancel;
    }).map((List<Memo> memos) => farmId == null ? memos : memos.where((m) => m.farmId == farmId).toList());
  }

  @override
  Future<Memo?> getMemo(String id) async {
    for (final m in _memos) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<Uint8List> loadPhoto(String photoId) async {
    final bytes = _photos[photoId];
    if (bytes == null) throw Exception('사진을 찾을 수 없습니다.');
    return bytes;
  }

  @override
  Future<Memo> addMemo({
    String? farmId,
    String? farmName,
    required String content,
    required List<String> tags,
    List<MemoPhotoUpload> photos = const [],
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final photoIds = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final id = 'photo-$stamp-$i';
      _photos[id] = photos[i].bytes;
      photoIds.add(id);
    }
    final memo = Memo(
      id: 'memo-$stamp',
      orgId: MockSeed.orgId,
      farmId: farmId,
      farmName: farmName,
      authorType: MemoAuthorType.institute,
      authorName: '수산질병관리원 · ${MockSeed.currentMember.name}',
      authorMemberId: MockSeed.currentMember.id,
      content: content,
      tags: tags,
      createdAt: DateTime.now(),
      photoCount: photoIds.length,
      photoIds: photoIds,
    );
    _memos = [memo, ..._memos];
    _emit();
    return memo;
  }

  @override
  Future<Memo> updateMemo({required String id, required String content}) async {
    final index = _memos.indexWhere((m) => m.id == id);
    if (index == -1) throw Exception('메모를 찾을 수 없습니다.');
    final old = _memos[index];
    final text = content.trim();
    if (text.isEmpty) throw Exception('메모 내용을 입력해주세요.');
    if (text == old.content) return old;
    final updated = old.copyWith(
      content: text,
      edits: [
        ...old.edits,
        MemoEdit(editorName: MockSeed.currentMember.name, editedAt: DateTime.now(), previousContent: old.content),
      ],
    );
    _memos = [..._memos]..[index] = updated;
    _emit();
    return updated;
  }

  @override
  Future<void> deleteMemo(String id) async {
    _memos = _memos.where((m) => m.id != id).toList();
    _emit();
  }

  void _replace(String id, Memo Function(Memo) update) {
    final index = _memos.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _memos = [..._memos]..[index] = update(_memos[index]);
    _emit();
  }

  @override
  Future<void> markRead(List<String> memoIds) async {
    for (final id in memoIds) {
      _replace(id, (m) => m.copyWith(readByMe: true));
    }
  }

  @override
  Future<List<MemoComment>> listComments(String memoId) async => List.unmodifiable(_comments[memoId] ?? const []);

  @override
  Future<MemoComment> addComment({required String memoId, required String content}) async {
    final text = content.trim();
    if (text.isEmpty) throw Exception('댓글 내용을 입력해주세요.');
    final comment = MemoComment(
      id: 'comment-${DateTime.now().microsecondsSinceEpoch}',
      memoId: memoId,
      authorMemberId: MockSeed.currentMember.id,
      authorName: MockSeed.currentMember.name,
      content: text,
      createdAt: DateTime.now(),
    );
    final list = _comments.putIfAbsent(memoId, () => [])..add(comment);
    _replace(memoId, (m) => m.copyWith(commentCount: list.length, readByMe: true));
    return comment;
  }

  @override
  Future<void> deleteComment({required String memoId, required String commentId}) async {
    final list = _comments[memoId];
    if (list == null) return;
    list.removeWhere((c) => c.id == commentId);
    _replace(memoId, (m) => m.copyWith(commentCount: list.length));
  }
}
