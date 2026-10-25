import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/memo_view_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/farm.dart';
import '../../data/logic/memo_filter.dart';
import '../../data/models/memo.dart';

class MemoScreen extends ConsumerStatefulWidget {
  const MemoScreen({super.key});

  @override
  ConsumerState<MemoScreen> createState() => _MemoScreenState();
}


class _MemoScreenState extends ConsumerState<MemoScreen> {
  MemoTab _tab = MemoTab.all;
  MemoTaskStatus _status = MemoTaskStatus.open;
  bool _mentionOnly = false;

  /// '전체', '미지정', or a farm id.
  String _farm = memoAllFarms;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// 홈에서 눌러 들어온 업무 — 목록에서 찾아 스크롤하고 잠시 강조한다.
  String? _focusId;
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 메모 탭이 처음 열리는 순간에 이미 요청이 와 있을 수 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyRequest(ref.read(memoViewRequestProvider));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _applyRequest(MemoViewRequest? request) {
    if (request == null) return;
    ref.read(memoViewRequestProvider.notifier).state = null;
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _query = '';
      _farm = memoAllFarms;
      _mentionOnly = false;
      _status = MemoTaskStatus.open;
      _tab = request.tasksOnly ? MemoTab.task : MemoTab.all;
      _focusId = request.focusMemoId;
    });
    if (_focusId == null) return;
    // 목록이 지연 생성이라 대상이 화면 밖이면 context가 없다 — 다음 프레임에 다시 시도.
    var tries = 0;
    void reveal() {
      if (!mounted || _focusId == null) return;
      final ctx = _focusKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.15, curve: Curves.easeOut);
        Future.delayed(const Duration(milliseconds: 2200), () {
          if (mounted) setState(() => _focusId = null);
        });
      } else if (++tries < 20) {
        WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
      } else {
        setState(() => _focusId = null);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
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
    ref.listen<MemoViewRequest?>(memoViewRequestProvider, (_, next) => _applyRequest(next));
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
                  // 주 탭 — 세 개를 균등 분할해 좁은 화면에서도 잘리지 않게.
                  Row(
                    children: [
                      for (final (tab, label) in const [(MemoTab.all, '전체'), (MemoTab.log, '업무 기록'), (MemoTab.task, '할 일')]) ...[
                        if (tab != MemoTab.all) const SizedBox(width: 6),
                        Expanded(child: _TabPill(label: label, selected: _tab == tab, onTap: () => setState(() => _tab = tab))),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    switch (_tab) {
                      MemoTab.all => "업무 기록과 남은 할 일을 모아 봐요. 끝낸 할 일은 할 일 탭의 '완료'에서 볼 수 있어요.",
                      MemoTab.log => '할 일이 아닌 일반 메모예요. 방문·폐사·접종 같은 현장 기록이 여기에 있어요.',
                      MemoTab.task => "'할일' 태그나 '할일:' 줄이 있는 메모예요. 완료할 때까지 홈의 업무 현황에 남아요.",
                    },
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
                  ),
                  if (_tab == MemoTab.task) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (st, label) in const [(MemoTaskStatus.open, '미완료'), (MemoTaskStatus.done, '완료'), (MemoTaskStatus.any, '상태 전체')]) ...[
                          if (st != MemoTaskStatus.open) const SizedBox(width: 6),
                          Expanded(child: _TabPill(label: label, selected: _status == st, onTap: () => setState(() => _status = st), small: true)),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterPillChip(label: '@ 나를 언급', selected: _mentionOnly, onTap: () => setState(() => _mentionOnly = !_mentionOnly)),
                      // One chip instead of a chip per farm (the row used to grow
                      // without end): it opens a scrollable list to pick from.
                      FilterPillChip(
                        label: '${_selectedFarmName(farmsAsync.valueOrNull ?? const []) ?? '양식장'} ▾',
                        selected: _farm != memoAllFarms,
                        onTap: () => _pickFarm(farmsAsync.valueOrNull ?? const []),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('업무 내용', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
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
                        _query.trim().isEmpty ? '해당하는 내용이 없어요.' : "'${_query.trim()}'에 해당하는 메모가 없습니다.",
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    // 강조할 업무가 아직 화면 밖이어도 위젯이 만들어져 있어야 스크롤할 수 있다.
                    scrollCacheExtent: _focusId != null ? const ScrollCacheExtent.pixels(100000) : null,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                        child: Text(
                          _query.trim().isNotEmpty ? '검색 결과 ${filtered.length}건' : '${filtered.length}건',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand),
                        ),
                      ),
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                          child: Text(entry.key,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        ),
                        const SizedBox(height: 8),
                        for (final memo in entry.value) ...[
                          _Highlight(
                            key: memo.id == _focusId ? _focusKey : ValueKey(memo.id),
                            on: memo.id == _focusId,
                            child: MemoCard(memo: memo, onTap: () => context.push('/memos/${memo.id}')),
                          ),
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

  /// Name of the farm currently filtered on, or null when the filter is not a farm.
  String? _selectedFarmName(List<Farm> farms) {
    if (_farm == memoNoFarm) return memoNoFarm;
    for (final f in farms) {
      if (f.id == _farm) return f.name;
    }
    return null;
  }

  Future<void> _pickFarm(List<Farm> farms) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('양식장 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              Flexible(
                child: farms.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('등록된 양식장이 없어요.', style: TextStyle(color: AppColors.textMuted))),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('전체 양식장'),
                            trailing: _farm == memoAllFarms ? const Icon(Icons.check, size: 18, color: AppColors.brand) : null,
                            onTap: () => Navigator.of(sheetContext).pop(memoAllFarms),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text(memoNoFarm),
                            trailing: _farm == memoNoFarm ? const Icon(Icons.check, size: 18, color: AppColors.brand) : null,
                            onTap: () => Navigator.of(sheetContext).pop(memoNoFarm),
                          ),
                          for (final farm in farms)
                            ListTile(
                              dense: true,
                              title: Text(farm.name),
                              trailing: _farm == farm.id ? const Icon(Icons.check, size: 18, color: AppColors.brand) : null,
                              onTap: () => Navigator.of(sheetContext).pop(farm.id),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _farm = picked);
  }

  List<Memo> _applyFilter(List<Memo> memos) => filterMemos(
        memos,
        tab: _tab,
        status: _status,
        mentionOnly: _mentionOnly,
        farm: _farm,
        query: _query,
      );

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

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap, this.small = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: small ? 32 : 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? (small ? AppColors.brandTint : AppColors.brand) : AppColors.surface,
            border: Border.all(color: selected ? (small ? AppColors.brand : Colors.transparent) : AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: selected ? (small ? AppColors.brand : Colors.white) : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈에서 눌러 들어온 업무를 잠시 강조한다.
class _Highlight extends StatelessWidget {
  const _Highlight({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: on ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: on ? AppColors.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: on ? AppColors.brand : Colors.transparent, width: 1.5),
      ),
      child: child,
    );
  }
}
