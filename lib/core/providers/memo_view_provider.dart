import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/logic/memo_filter.dart' as logic;
import '../../data/models/memo.dart';
import 'data_providers.dart';

/// 홈 ↔ 메모: 메모 화면을 어떤 상태로 열지에 대한 한 번짜리 요청.
/// MemoScreen이 읽어서 적용한 뒤 null로 비운다.
class MemoViewRequest {
  const MemoViewRequest._({required this.tasksOnly, this.focusMemoId});

  /// 하단 메뉴로 들어온 일반 진입 — 전체 탭, 기본 필터.
  factory MemoViewRequest.general() => const MemoViewRequest._(tasksOnly: false);

  /// 홈의 업무 현황에서 온 진입 — 할 일 › 미완료, 나머지 필터는 기본값.
  /// [focusMemoId]가 있으면 그 업무로 스크롤해 잠시 강조한다.
  factory MemoViewRequest.openTasks({String? focusMemoId}) => MemoViewRequest._(tasksOnly: true, focusMemoId: focusMemoId);

  final bool tasksOnly;
  final String? focusMemoId;
}

final memoViewRequestProvider = StateProvider<MemoViewRequest?>((ref) => null);

/// 홈과 메모가 함께 쓰는 '남은 할 일' — 완료되지 않은 할 일 메모, 최신순.
/// 메모 목록이 한 번에 전체 조회되므로 길이가 곧 전체 건수다.
final openTasksProvider = Provider<AsyncValue<List<Memo>>>((ref) {
  return ref.watch(memosProvider(null)).whenData(logic.openTasks);
});
