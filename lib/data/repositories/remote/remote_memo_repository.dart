import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/memo.dart';
import '../../models/memo_comment.dart';
import '../../services/api_client.dart';
import '../memo_repository.dart';

/// REST has no push channel, so this polls `GET /api/memos` on an interval
/// and fans the result out to every listener. Good enough for an MVP where
/// a handful of staff refresh a shared list — swap for SSE/websockets later
/// if live co-editing becomes a real requirement.
class RemoteMemoRepository implements MemoRepository {
  RemoteMemoRepository({required ApiClient apiClient, this.pollInterval = const Duration(seconds: 15)})
      : _api = apiClient;

  final ApiClient _api;
  final Duration pollInterval;

  // Lets addMemo() nudge every active watcher to re-fetch immediately
  // instead of waiting out the poll interval, without needing a shared
  // in-memory cache layer.
  final _refresh = StreamController<void>.broadcast();

  Future<List<Memo>> _fetchAll() async {
    final json = await _api.get('/api/memos') as List<dynamic>;
    return json.map((e) => Memo.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Stream<List<Memo>> watchMemos({String? farmId}) {
    late final StreamController<List<Memo>> controller;
    Timer? timer;
    StreamSubscription<void>? refreshSub;
    var hasData = false;

    Future<void> tick() async {
      try {
        final memos = await _fetchAll();
        if (!controller.isClosed) {
          hasData = true;
          controller.add(farmId == null ? memos : memos.where((m) => m.farmId == farmId).toList());
        }
      } catch (e) {
        // Once a list has loaded, a failed poll (app resumed from background,
        // network switch, server restarting on deploy) keeps showing it and
        // waits for the next tick — only a failed first load is an error.
        if (!controller.isClosed && !hasData) controller.addError(e);
      }
    }

    controller = StreamController<List<Memo>>.broadcast(
      onListen: () {
        tick();
        timer ??= Timer.periodic(pollInterval, (_) => tick());
        refreshSub ??= _refresh.stream.listen((_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        refreshSub?.cancel();
        refreshSub = null;
      },
    );

    return controller.stream;
  }

  @override
  Future<Memo> addMemo({
    String? farmId,
    String? farmName,
    required String content,
    required List<String> tags,
    List<MemoPhotoUpload> photos = const [],
  }) async {
    final json = await _api.post(
      '/api/memos',
      body: {
        'farmId': farmId,
        'content': content,
        'tags': tags,
        'photos': [
          for (final p in photos) {'contentType': p.contentType, 'dataBase64': base64Encode(p.bytes)},
        ],
      },
    ) as Map<String, dynamic>;
    _refresh.add(null);
    return Memo.fromJson(json);
  }

  @override
  Future<Memo> updateMemo({required String id, required String content}) async {
    final json = await _api.patch('/api/memos/$id', body: {'content': content}) as Map<String, dynamic>;
    _refresh.add(null);
    return Memo.fromJson(json);
  }

  @override
  Future<Memo> setMemoDone({required String id, required bool done}) async {
    final json = await _api.put('/api/memos/$id/done', body: {'done': done}) as Map<String, dynamic>;
    _refresh.add(null);
    return Memo.fromJson(json);
  }

  @override
  Future<void> deleteMemo(String id) async {
    await _api.delete('/api/memos/$id');
    _refresh.add(null);
  }

  @override
  Future<Uint8List> loadPhoto(String photoId) => _api.getBytes('/api/memos/photos/$photoId');

  @override
  Future<void> markRead(List<String> memoIds) async {
    if (memoIds.isEmpty) return;
    await _api.post('/api/memos/read', body: {'ids': memoIds});
    _refresh.add(null);
  }

  @override
  Future<List<MemoComment>> listComments(String memoId) async {
    final json = await _api.get('/api/memos/$memoId/comments') as List<dynamic>;
    return json.map((e) => MemoComment.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<MemoComment> addComment({
    required String memoId,
    required String content,
    List<CommentMention> mentions = const [],
    List<CommentAttachmentUpload> attachments = const [],
  }) async {
    final json = await _api.post('/api/memos/$memoId/comments', body: {
      'content': content,
      'mentionMemberIds': [for (final m in mentions) m.memberId],
      'attachments': [for (final a in attachments) a.toJson(base64Encode)],
    }) as Map<String, dynamic>;
    _refresh.add(null);
    return MemoComment.fromJson(json);
  }

  @override
  Future<Uint8List> loadCommentAttachment(String attachmentId) =>
      _api.getBytes('/api/memos/comment-attachments/$attachmentId');

  @override
  Future<void> deleteComment({required String memoId, required String commentId}) async {
    await _api.delete('/api/memos/$memoId/comments/$commentId');
    _refresh.add(null);
  }
}
