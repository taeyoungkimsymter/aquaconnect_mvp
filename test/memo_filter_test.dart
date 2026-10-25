import 'package:aquaconnect_mvp/data/logic/memo_filter.dart';
import 'package:aquaconnect_mvp/data/models/memo.dart';
import 'package:flutter_test/flutter_test.dart';

Memo memo(String id, String content,
        {List<String> tags = const [], String? farmId, bool done = false, bool mention = false, int daysAgo = 0}) =>
    Memo(
      id: id,
      orgId: 'o',
      authorType: MemoAuthorType.institute,
      authorName: '수산질병관리원 · 김',
      content: content,
      tags: tags,
      createdAt: DateTime(2026, 10, 25).subtract(Duration(days: daysAgo)),
      farmId: farmId,
      farmName: farmId,
      completedAt: done ? DateTime(2026, 10, 25) : null,
      mentionsMe: mention,
    );

List<String> ids(Iterable<Memo> ms) => [for (final m in ms) m.id];

void main() {
  final memos = [
    memo('t1', '사료 점검', tags: ['할일'], farmId: 'A'),
    memo('t2', '할일: 그물 교체', farmId: 'B', daysAgo: 40), // 오래된 미완료
    memo('t3', '약품 주문', tags: ['할일'], farmId: 'A', done: true, mention: true),
    memo('t4', '수조 청소', tags: ['할일'], mention: true),
    memo('l1', '오늘 점검 완료했어요', farmId: 'A'), // '완료' 단어만 있는 일반 메모
    memo('l2', '폐사 3마리', tags: ['폐사'], farmId: 'B', done: true, mention: true),
  ];
  List<Memo> run(MemoTab tab, {MemoTaskStatus status = MemoTaskStatus.open, bool mention = false, String farm = memoAllFarms, String q = ''}) =>
      filterMemos(memos, tab: tab, status: status, mentionOnly: mention, farm: farm, query: q);

  test('전체는 업무 기록과 남은 할 일만 — 완료된 할 일은 숨긴다', () {
    expect(ids(run(MemoTab.all)), ['t1', 't2', 't4', 'l1', 'l2']);
    expect(ids(run(MemoTab.all)), isNot(contains('t3')));
  });

  test('업무 기록은 할 일이 아닌 메모만 — "완료" 단어로 분류하지 않는다', () {
    expect(ids(run(MemoTab.log)), ['l1', 'l2']);
    expect(ids(run(MemoTab.task, status: MemoTaskStatus.any)), isNot(contains('l1')));
  });

  test('할 일 탭의 상태: 미완료(기본)/완료/전체', () {
    expect(ids(run(MemoTab.task)), ['t1', 't2', 't4']);
    expect(ids(run(MemoTab.task, status: MemoTaskStatus.done)), ['t3']);
    expect(ids(run(MemoTab.task, status: MemoTaskStatus.any)), ['t1', 't2', 't3', 't4']);
  });

  test('홈의 남은 할 일은 할 일 › 미완료 목록과 같고 오래된 건도 포함', () {
    final home = openTasks(memos);
    expect(ids(home), ids(run(MemoTab.task)));
    expect(ids(home), contains('t2'));
  });

  test('나를 언급은 탭·상태와 독립적으로 겹쳐 적용', () {
    expect(ids(run(MemoTab.all, mention: true)), ['t4', 'l2']);
    expect(ids(run(MemoTab.log, mention: true)), ['l2']);
    expect(ids(run(MemoTab.task, mention: true)), ['t4']);
    expect(ids(run(MemoTab.task, status: MemoTaskStatus.any, mention: true)), ['t3', 't4']);
  });

  test('양식장·검색이 함께 적용되고 상단 필터가 홈 건수를 바꾸지 않는다', () {
    expect(ids(run(MemoTab.task, farm: 'A')), ['t1']);
    expect(ids(run(MemoTab.task, farm: memoNoFarm)), ['t4']);
    expect(ids(run(MemoTab.task, q: '그물')), ['t2']);
    expect(openTasks(memos), hasLength(3));
  });

  test('완료/완료 취소가 미완료 목록에 반영', () {
    final done = [for (final m in memos) m.id == 't1' ? m.copyWith(completed: true) : m];
    expect(ids(openTasks(done)), ['t2', 't4']);
    final undone = [for (final m in done) m.id == 't3' ? m.copyWith(completed: false) : m];
    expect(ids(openTasks(undone)), ['t2', 't3', 't4']);
  });

  test('AI 정리는 규칙 기반 문장만 만든다', () {
    final now = DateTime(2026, 10, 25);
    final lines = summarizeOpenTasks(openTasks(memos), now);
    expect(lines, contains('7일 넘게 끝나지 않은 일이 1건 있어요.'));
    expect(lines, contains('나를 호출한 업무가 1건 있어요.'));
    expect(summarizeOpenTasks(const [], now), isEmpty);
  });
}
