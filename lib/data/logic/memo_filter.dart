import '../models/memo.dart';

/// 메모 화면의 주 탭 — 업무 기록은 할 일이 아닌 메모.
enum MemoTab { all, log, task }

/// 할 일 탭 안의 상태 필터. 완료 여부는 completedAt만 본다(읽음·'완료' 단어와 무관).
enum MemoTaskStatus { open, done, any }

const memoAllFarms = '전체';
const memoNoFarm = '미지정';

/// 홈의 남은 할 일 = 메모의 할 일 › 미완료. 두 화면이 같은 기준을 쓴다.
List<Memo> openTasks(Iterable<Memo> memos) => [
      for (final m in memos)
        if (m.isTask && !m.isCompleted) m,
    ];

/// 메모 상단의 탭·상태·언급·양식장·검색어를 한꺼번에 적용한다.
/// [farm]은 memoAllFarms, memoNoFarm 또는 양식장 id.
List<Memo> filterMemos(
  Iterable<Memo> memos, {
  required MemoTab tab,
  required MemoTaskStatus status,
  required bool mentionOnly,
  required String farm,
  String query = '',
}) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return [
    for (final m in memos)
      if (_tabOk(m, tab, status) &&
          (farm == memoAllFarms || (farm == memoNoFarm ? m.farmId == null : m.farmId == farm)) &&
          (!mentionOnly || m.mentionsMe) &&
          _matches(m, words))
        m,
  ];
}

bool _tabOk(Memo m, MemoTab tab, MemoTaskStatus status) => switch (tab) {
      // 전체 = 업무 기록 + 남은 할 일. 끝난 할 일은 할 일 탭의 '완료'에서 본다.
      MemoTab.all => !(m.isTask && m.isCompleted),
      MemoTab.log => !m.isTask,
      MemoTab.task => m.isTask &&
          switch (status) {
            MemoTaskStatus.open => !m.isCompleted,
            MemoTaskStatus.done => m.isCompleted,
            MemoTaskStatus.any => true,
          },
    };

/// Every whitespace-separated word must appear somewhere in the memo's
/// content, tags, farm name or author (case-insensitive).
bool _matches(Memo memo, List<String> words) {
  if (words.isEmpty) return true;
  final haystack = [memo.content, ...memo.tags, memo.farmLabel, memo.authorName].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

/// 홈 업무 현황의 'AI 정리' — 규칙 기반 요약(기존 'AI 정리 소견'과 같은 방식, LLM 호출 없음).
/// [open]은 [openTasks]의 결과. 말할 거리가 없으면 빈 목록.
List<String> summarizeOpenTasks(List<Memo> open, DateTime now, {int staleDays = 7}) {
  if (open.isEmpty) return const [];
  final lines = <String>[];
  final stale = open.where((m) => now.difference(m.createdAt).inDays >= staleDays).length;
  if (stale > 0) lines.add('$staleDays일 넘게 끝나지 않은 일이 $stale건 있어요.');
  final mine = open.where((m) => m.mentionsMe).length;
  if (mine > 0) lines.add('나를 호출한 업무가 $mine건 있어요.');
  final byFarm = <String, int>{};
  for (final m in open) {
    byFarm.update(m.farmLabel, (n) => n + 1, ifAbsent: () => 1);
  }
  final top = byFarm.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (byFarm.length > 1 && top.value > 1) lines.add('${top.key}에 남은 일이 가장 많아요 (${top.value}건).');
  return lines;
}
