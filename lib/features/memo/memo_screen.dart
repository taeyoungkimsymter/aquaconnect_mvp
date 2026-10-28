import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/korean_search.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/farm_search_field.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/farm.dart';
import '../../data/models/memo.dart';

class MemoScreen extends ConsumerStatefulWidget {
  const MemoScreen({super.key, this.focusMemoId, this.openComments = false, this.view});

  /// Memo to pin at the top, from a tapped memo/comment notification.
  final String? focusMemoId;

  /// Also open [focusMemoId]'s 댓글 sheet (a comment notification).
  final bool openComments;

  /// `?view=today`: open on 오늘의 업무 (from the daily notification).
  final String? view;

  @override
  ConsumerState<MemoScreen> createState() => _MemoScreenState();
}

/// Memo tab categories (the chips); the farm is picked separately.
enum _MemoView { all, today, todo, mentioned, done }

/// Farm filter: every farm, memos without a farm, or one farm id.
const _allFarms = '';
const _noFarm = '미지정';

class _MemoScreenState extends ConsumerState<MemoScreen> {
  _MemoView _view = _MemoView.all;
  String _farm = _allFarms;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  String? _focusId;
  bool _commentsPending = false;

  @override
  void initState() {
    super.initState();
    _takeFocus();
  }

  @override
  void didUpdateWidget(MemoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusMemoId != oldWidget.focusMemoId || widget.view != oldWidget.view) _takeFocus();
  }

  /// Picks up `?memo=` / `?view=` from the route, then clears it from the
  /// location so the same notification tapped again (or the 메모 tab
  /// restoring its last location) is seen as a fresh request.
  void _takeFocus() {
    final id = widget.focusMemoId;
    if (id == null && widget.view == null) return;
    if (id != null) {
      _focusId = id;
      _commentsPending = widget.openComments;
    }
    _view = widget.view == 'today' ? _MemoView.today : _MemoView.all;
    _farm = _allFarms;
    _searching = false;
    _query = '';
    _searchController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/memo');
    });
  }

  /// Opens the pending 댓글 sheet once the focused memo is in the list.
  void _openPendingComments(Memo memo) {
    _commentsPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MemoCard(memo: memo).showComments(context);
    });
  }

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
    final me = ref.watch(authStateProvider).valueOrNull?.member;

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
                      children: [
                        const Text('메모', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
                        const Spacer(),
                        _FarmPickerButton(
                          farms: farmsAsync.valueOrNull ?? const [],
                          selected: _farm,
                          onSelected: (farm) => setState(() => _farm = farm),
                        ),
                        const SizedBox(width: 4),
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
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final (view, label) in const [
                                (_MemoView.all, '전체'),
                                (_MemoView.today, '오늘의 업무'),
                                (_MemoView.todo, '할일'),
                                (_MemoView.mentioned, '나를 호출'),
                                (_MemoView.done, '완료'),
                              ]) ...[
                                FilterPillChip(label: label, selected: _view == view, onTap: () => setState(() => _view = view)),
                                const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // The search field takes the title row, so the farm
                      // filter (still applied to the results) shows here.
                      if (_searching) ...[
                        const SizedBox(width: 4),
                        _FarmPickerButton(
                          farms: farmsAsync.valueOrNull ?? const [],
                          selected: _farm,
                          onSelected: (farm) => setState(() => _farm = farm),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: memosAsync.when(
                data: (memos) {
                  // Not found (yet, or deleted): just the normal list.
                  final focused = memos.where((m) => m.id == _focusId).firstOrNull;
                  if (focused != null && _commentsPending) _openPendingComments(focused);
                  bool isMine(Memo m) => me != null && m.isOpenTaskFor(memberId: me.id, memberName: me.name);
                  final filtered = _applyFilter(memos, isMine).where((m) => m.id != focused?.id).toList();
                  final groups = _groupByDay(filtered);
                  final showToday = _query.trim().isEmpty && me != null;
                  if (filtered.isEmpty && focused == null && !showToday) {
                    return Center(
                      child: Text(
                        _emptyMessage(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    children: [
                      if (showToday) ...[
                        _TodayCard(
                          open: memos.where(isMine).toList(),
                          doneToday: memos.where((m) => m.isDone && m.doneByMemberId == me.id && _isToday(m.doneAt!)).length,
                          selected: _view == _MemoView.today,
                          onTap: () => setState(() => _view = _view == _MemoView.today ? _MemoView.all : _MemoView.today),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (filtered.isEmpty && focused == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            _emptyMessage(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
                          ),
                        ),

                      if (focused != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.notifications_active_outlined, size: 14, color: AppColors.brand),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text('알림에서 연 메모',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => setState(() => _focusId = null),
                              icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.brandTintBorder, width: 2),
                          ),
                          child: MemoCard(memo: focused),
                        ),
                        const SizedBox(height: 10),
                      ],
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
            const MemoComposerBar(
              caption: '자세히 기록하기 · 양식장 태그·표현·사진을 한 번에',
              hintText: "/ 로 양식장 지정",
            ),
          ],
        ),
      ),
    );
  }

  List<Memo> _applyFilter(List<Memo> memos, bool Function(Memo) isMine) {
    final byView = switch (_view) {
      _MemoView.all => memos,
      _MemoView.today => memos.where(isMine).toList(),
      _MemoView.todo => memos.where((m) => m.isTask && !m.isDone).toList(),
      _MemoView.mentioned => memos.where((m) => m.mentionedMe).toList(),
      _MemoView.done => memos.where((m) => m.isDone).toList(),
    };
    final byFarm = switch (_farm) {
      _allFarms => byView,
      _noFarm => byView.where((m) => m.farmId == null).toList(),
      _ => byView.where((m) => m.farmId == _farm).toList(),
    };
    return byFarm.where(_matchesQuery).toList();
  }

  String _emptyMessage() {
    if (_query.trim().isNotEmpty) return "'${_query.trim()}'에 해당하는 메모가 없습니다.";
    return switch (_view) {
      _MemoView.today => '오늘 남은 업무가 없어요.\n할일·담당자를 지정하거나 호출받은 메모가 여기에 모여요.',
      _MemoView.todo => '남은 할일이 없어요.',
      _MemoView.mentioned => '나를 호출한 메모가 없어요.',
      _MemoView.done => '완료한 메모가 없어요.',
      _MemoView.all => '아직 메모가 없습니다.',
    };
  }

  static bool _isToday(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    return local.year == now.year && local.month == now.month && local.day == now.day;
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
      final label = _safeFormat(formatter, memo.createdAt.toLocal());
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

/// 오늘의 업무: what's left for me today (my 할일 / 담당 / 호출), at the top
/// of the memo tab so opening the app answers "오늘 뭐 해야 하지?". Tap to
/// show just those memos.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.open, required this.doneToday, required this.selected, required this.onTap});

  final List<Memo> open;
  final int doneToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mentioned = open.where((m) => m.mentionedMe).length;
    final total = open.length + doneToday;
    String dateLabel;
    try {
      dateLabel = DateFormat('M/d (E)', 'ko_KR').format(DateTime.now());
    } catch (_) {
      dateLabel = DateFormat('M/d').format(DateTime.now());
    }
    return Material(
      color: selected ? AppColors.brandTint : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.brand : AppColors.brandTintBorder, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist_rtl, size: 18, color: AppColors.brand),
                  const SizedBox(width: 6),
                  const Text('오늘의 업무', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(dateLabel,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ),
                  const Spacer(),
                  Text(selected ? '전체 보기' : '모아 보기',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.brand),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _TodayStat(label: '남은 업무', value: open.length, color: open.isEmpty ? AppColors.textMuted : AppColors.brand),
                  _TodayStat(label: '나를 호출', value: mentioned, color: mentioned == 0 ? AppColors.textMuted : AppColors.warningDark),
                  _TodayStat(label: '오늘 완료', value: doneToday, color: doneToday == 0 ? AppColors.textMuted : AppColors.good),
                ],
              ),
              if (total > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneToday / total,
                    minHeight: 6,
                    backgroundColor: AppColors.neutralChip,
                    color: AppColors.good,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  open.isEmpty ? '오늘 업무를 모두 끝냈어요!' : '메모 왼쪽 동그라미(✓)를 누르면 완료돼서 여기서 빠져요.',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ] else ...[
                const SizedBox(height: 8),
                const Text('할일 태그·담당자를 지정하거나 댓글로 호출받은 메모가 여기에 모여요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayStat extends StatelessWidget {
  const _TodayStat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// "양식장 ▾" chip: opens a scrollable list (양식장 전체 / 미지정 / each farm)
/// instead of one chip per farm in the header.
class _FarmPickerButton extends StatelessWidget {
  const _FarmPickerButton({required this.farms, required this.selected, required this.onSelected});

  final List<Farm> farms;
  final String selected;
  final ValueChanged<String> onSelected;

  String get _label {
    if (selected == _allFarms) return '양식장 전체';
    if (selected == _noFarm) return '미지정';
    return farms.where((f) => f.id == selected).firstOrNull?.name ?? '양식장 전체';
  }

  Future<void> _open(BuildContext context) async {
    var query = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final searching = query.trim().isNotEmpty;
          final options = [
            if (!searching) ...[(_allFarms, '양식장 전체', null), (_noFarm, '미지정', null)],
            for (final f in searchFarms(farms, query)) (f.id, f.name, f.address),
          ];
          return Padding(
            // Keep the list above the on-screen keyboard while typing.
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Text('양식장 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: FarmSearchField(
                        fillColor: AppColors.background,
                        onChanged: (q) => setSheetState(() => query = q),
                      ),
                    ),
                    if (searching && options.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Text('맞는 양식장이 없어요', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final (value, label, address) in options)
                            ListTile(
                              dense: true,
                              subtitle: address == null || address.isEmpty
                                  ? null
                                  : Text(address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                              title: Text(label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: value == selected ? FontWeight.w800 : FontWeight.w500,
                                    color: value == selected ? AppColors.brand : AppColors.textPrimary,
                                  )),
                              trailing: value == selected ? const Icon(Icons.check, size: 18, color: AppColors.brand) : null,
                              onTap: () => Navigator.of(sheetContext).pop(value),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = selected != _allFarms;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.brandTint : AppColors.surface,
          border: Border.all(color: active ? AppColors.brand : AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(_label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? AppColors.brand : AppColors.textSecondary)),
            ),
            Icon(Icons.expand_more, size: 16, color: active ? AppColors.brand : AppColors.textSecondary),
          ],
        ),
      ),
    );
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
