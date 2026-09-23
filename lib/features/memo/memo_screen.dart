import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/memo_composer.dart';
import '../../data/models/memo.dart';

class MemoScreen extends ConsumerStatefulWidget {
  const MemoScreen({super.key});

  @override
  ConsumerState<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends ConsumerState<MemoScreen> {
  String _filter = '전체';

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(farmsProvider);
    final memosAsync = ref.watch(memosProvider(null));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('메모', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
                      Icon(Icons.search, size: 20, color: AppColors.neutralIconStrong),
                    ],
                  ),
                  const SizedBox(height: 12),
                  farmsAsync.when(
                    data: (farms) => SizedBox(
                      height: 30,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          FilterPillChip(label: '전체', selected: _filter == '전체', onTap: () => setState(() => _filter = '전체')),
                          const SizedBox(width: 6),
                          FilterPillChip(label: '할일', selected: _filter == '할일', onTap: () => setState(() => _filter = '할일')),
                          const SizedBox(width: 6),
                          FilterPillChip(label: '미지정', selected: _filter == '미지정', onTap: () => setState(() => _filter = '미지정')),
                          const SizedBox(width: 6),
                          for (final farm in farms) ...[
                            FilterPillChip(label: farm.name, selected: _filter == farm.id, onTap: () => setState(() => _filter = farm.id)),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: memosAsync.when(
                data: (memos) {
                  final filtered = _applyFilter(memos);
                  final groups = _groupByDay(filtered);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('아직 메모가 없습니다.', style: TextStyle(color: AppColors.textMuted)),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                          child: Text(entry.key,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        ),
                        const SizedBox(height: 8),
                        for (final memo in entry.value) ...[
                          MemoCard(memo: memo),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('불러오기 실패: $e')),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 9, 20, 14),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 9),
                    child: Text(
                      '자세히 기록하기 · 양식장 태그·표현·사진을 한 번에',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                    ),
                  ),
                  farmsAsync.when(
                    data: (farms) => MemoComposer(
                      farms: farms,
                      showExpressionChips: true,
                      hintText: "3수조 폐사, 유영 이상... ('/' 로 양식장 지정)",
                      onSubmit: ({required content, farm, tags = const []}) {
                        ref.read(memoRepositoryProvider).addMemo(
                              farmId: farm?.id,
                              farmName: farm?.name,
                              content: content,
                              tags: tags,
                            );
                      },
                    ),
                    loading: () => const SizedBox(height: 44),
                    error: (e, _) => Text('$e'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Memo> _applyFilter(List<Memo> memos) {
    switch (_filter) {
      case '전체':
        return memos;
      case '할일':
        return memos.where((m) => m.tags.contains('할일') || m.content.contains('할일:')).toList();
      case '미지정':
        return memos.where((m) => m.farmId == null).toList();
      default:
        return memos.where((m) => m.farmId == _filter).toList();
    }
  }

  Map<String, List<Memo>> _groupByDay(List<Memo> memos) {
    final formatter = DateFormat('M월 d일 EEEE', 'ko_KR');
    final map = <String, List<Memo>>{};
    for (final memo in memos) {
      final label = _safeFormat(formatter, memo.createdAt);
      map.putIfAbsent(label, () => []).add(memo);
    }
    return map;
  }

  String _safeFormat(DateFormat formatter, DateTime dt) {
    try {
      return formatter.format(dt);
    } catch (_) {
      return DateFormat('M/d').format(dt);
    }
  }
}
