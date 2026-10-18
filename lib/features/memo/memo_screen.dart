import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/memo.dart';

class MemoScreen extends ConsumerStatefulWidget {
  const MemoScreen({super.key});

  @override
  ConsumerState<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends ConsumerState<MemoScreen> {
  String _filter = '전체';
  bool _searching = false;

  /// 완료된 메모를 목록에 보일지 (기본: 숨김).
  bool _showCompleted = false;
  String _query = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

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
                  if (_searching)
                    _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      onClose: _closeSearch,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('메모', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
                        IconButton(
                          tooltip: '메모 검색',
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search, size: 20, color: AppColors.neutralIconStrong),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
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
                          FilterPillChip(
                            label: '완료 보기',
                            selected: _showCompleted,
                            onTap: () => setState(() => _showCompleted = !_showCompleted),
                          ),
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
                    return Center(
                      child: Text(
                        _query.trim().isEmpty
                            ? (!_showCompleted && memos.any((m) => m.isCompleted) ? '완료되지 않은 메모가 없습니다.' : '아직 메모가 없습니다.')
                            : "'${_query.trim()}'에 해당하는 메모가 없습니다.",
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    children: [
                      if (_query.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                          child: Text('검색 결과 ${filtered.length}건',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
                        ),
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                          child: Text(entry.key,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        ),
                        const SizedBox(height: 8),
                        for (final memo in entry.value) ...[
                          MemoCard(memo: memo, onTap: () => context.push('/memos/${memo.id}')),
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
            const MemoComposerBar(
              caption: '자세히 기록하기 · 양식장 태그·표현·사진을 한 번에',
              hintText: "/ 로 양식장 지정",
            ),
          ],
        ),
      ),
    );
  }

  List<Memo> _applyFilter(List<Memo> allMemos) {
    final memos = _showCompleted ? allMemos : allMemos.where((m) => !m.isCompleted).toList();
    final byFarm = switch (_filter) {
      '전체' => memos,
      '할일' => memos.where((m) => m.tags.contains('할일') || m.content.contains('할일:')).toList(),
      '미지정' => memos.where((m) => m.farmId == null).toList(),
      _ => memos.where((m) => m.farmId == _filter).toList(),
    };
    return byFarm.where(_matchesQuery).toList();
  }

  /// Every whitespace-separated word must appear somewhere in the memo's
  /// content, tags, farm name or author (case-insensitive).
  bool _matchesQuery(Memo memo) {
    final words = _query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final haystack = [memo.content, ...memo.tags, memo.farmLabel, memo.authorName].join(' ').toLowerCase();
    return words.every(haystack.contains);
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: '내용, 태그, 양식장, 작성자 검색',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '지우기',
                        icon: const Icon(Icons.cancel, size: 16, color: AppColors.textMuted),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        TextButton(
          onPressed: onClose,
          child: const Text('취소', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
