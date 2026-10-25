import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/risk_badge.dart';
import '../../data/models/farm.dart';
import '../../data/models/farm_group.dart';

const _noRegion = '지역 미등록';

/// 시·군·구 of the farm's 주소; farms without one are grouped as 지역 미등록.
String _regionName(Farm f) {
  final r = regionOf(f);
  return r == '지역 미확인' ? _noRegion : r;
}

/// 읍·면·동 of the farm's 주소, or '' when the address has none.
String _townOf(Farm f) {
  for (final w in f.address.trim().split(RegExp(r'\s+'))) {
    if (w.length > 1 && RegExp(r'[읍면동]$').hasMatch(w)) return w;
  }
  return '';
}

String _normalize(String s) => s.replaceAll(RegExp(r'[\s\-]'), '').toLowerCase();

const _choseong = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';

String _initials(String s) => String.fromCharCodes(s.runes.map((c) {
      final n = c - 0xAC00;
      return n >= 0 && n < 11172 ? _choseong.codeUnitAt(n ~/ 588) : c;
    }));

bool _matches(Farm f, String q) {
  if (q.isEmpty) return true;
  final nameAddr = _normalize('${f.name}${f.address}');
  final text = nameAddr + _normalize(f.ownerContact ?? '');
  if (text.contains(q)) return true;
  return q.runes.every(_choseong.runes.contains) && _initials(nameAddr).contains(q);
}

String _visitLabel(Farm f) {
  final d = f.lastVisitDays;
  if (d == null) return '메모 기록 없음';
  return d == 0 ? '오늘 메모' : '최근 메모 $d일 전';
}

/// Home's 관리 양식장: every farm of the institute, folded by 시·군·구.
class FarmRegionList extends StatefulWidget {
  const FarmRegionList({super.key, required this.farmsAsync, required this.onRetry});

  final AsyncValue<List<Farm>> farmsAsync;
  final VoidCallback onRetry;

  @override
  State<FarmRegionList> createState() => _FarmRegionListState();
}

class _FarmRegionListState extends State<FarmRegionList> {
  final _controller = TextEditingController();
  String? _selected; // null = 지역 전체
  String? _openRegion;
  String? _openFarmId;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Regions with their total farm counts, biggest first, 지역 미등록 last.
  List<MapEntry<String, int>> _regionCounts(List<Farm> farms) {
    final counts = <String, int>{};
    for (final f in farms) {
      counts.update(_regionName(f), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts.entries.toList()
      ..sort((a, b) {
        if (a.key == _noRegion) return 1;
        if (b.key == _noRegion) return -1;
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
  }

  void _onQuery(String raw, List<Farm> farms) {
    final q = _normalize(raw);
    final regions = {
      for (final f in farms)
        if ((_selected == null || _regionName(f) == _selected) && _matches(f, q)) _regionName(f)
    };
    setState(() {
      _query = q;
      _openFarmId = null;
      _openRegion = q.isNotEmpty && regions.length == 1 ? regions.first : _selected;
    });
  }

  void _select(String? region) {
    setState(() {
      _selected = region;
      _openRegion = region;
      _openFarmId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final farmsAsync = widget.farmsAsync;
    final farms = farmsAsync.valueOrNull ?? const <Farm>[];
    final counts = _regionCounts(farms);
    // A region that no longer exists (farm moved / deleted) falls back to all.
    final selected = counts.any((e) => e.key == _selected) ? _selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('관리 양식장',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            _RegionMenu(
              counts: counts,
              total: farms.length,
              selected: selected,
              onSelected: _select,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _SearchBox(controller: _controller, onChanged: (v) => _onQuery(v, farms)),
        const SizedBox(height: 12),
        farmsAsync.when(
          loading: () => farms.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
              : _body(farms, selected),
          error: (e, _) => farms.isNotEmpty
              ? _body(farms, selected)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const Text('양식장을 불러오지 못했어요.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      TextButton(onPressed: widget.onRetry, child: const Text('다시 시도')),
                    ],
                  ),
                ),
          data: (_) => _body(farms, selected),
        ),
      ],
    );
  }

  Widget _body(List<Farm> farms, String? selected) {
    if (farms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text('등록된 양식장이 없어요.\n마이페이지 > 등록 양식장 관리에서 추가해 주세요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5)),
      );
    }
    final matched = [
      for (final f in farms)
        if ((selected == null || _regionName(f) == selected) && _matches(f, _query)) f
    ];
    final byRegion = <String, List<Farm>>{};
    for (final f in matched) {
      byRegion.putIfAbsent(_regionName(f), () => []).add(f);
    }
    final order = [for (final e in _regionCounts(matched)) e.key];
    final searching = _query.isNotEmpty;
    final label = searching ? '검색 결과' : (selected ?? '전체');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$label '),
                      TextSpan(text: '${matched.length}', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                      const TextSpan(text: '곳 · '),
                      TextSpan(text: '${order.length}', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                      const TextSpan(text: '개 지역'),
                    ]),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ),
              const Text('지역별 보기', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        if (matched.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('검색 결과가 없어요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          )
        else
          for (final region in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RegionGroup(
                name: region,
                farms: byRegion[region]!,
                open: _openRegion == region,
                openFarmId: _openFarmId,
                onToggle: () => setState(() {
                  _openRegion = _openRegion == region ? null : region;
                  _openFarmId = null;
                }),
                onToggleFarm: (id) => setState(() => _openFarmId = _openFarmId == id ? null : id),
              ),
            ),
      ],
    );
  }
}

class _RegionMenu extends StatelessWidget {
  const _RegionMenu({required this.counts, required this.total, required this.selected, required this.onSelected});

  final List<MapEntry<String, int>> counts;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelected;

  PopupMenuEntry<String> _item(String value, String label, int n, bool on) => PopupMenuItem<String>(
        value: value,
        height: 44,
        child: Row(
          children: [
            SizedBox(width: 20, child: on ? const Icon(Icons.check, size: 16, color: AppColors.brand) : null),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? AppColors.brand : AppColors.textPrimary)),
            ),
            Text('$n곳', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '지역 선택',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      onSelected: (v) => onSelected(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        _item('', '지역 전체', total, selected == null),
        const PopupMenuDivider(height: 1),
        for (final e in counts) _item(e.key, e.key, e.value, e.key == selected),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected ?? '지역 전체', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '양식장 이름 · 주소 · 연락처 검색',
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '검색어 지우기',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.brand)),
      ),
    );
  }
}

class _RegionGroup extends StatelessWidget {
  const _RegionGroup({
    required this.name,
    required this.farms,
    required this.open,
    required this.openFarmId,
    required this.onToggle,
    required this.onToggleFarm,
  });

  final String name;
  final List<Farm> farms;
  final bool open;
  final String? openFarmId;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleFarm;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '$name ${farms.length}곳',
            excludeSemantics: true,
            onTap: onToggle,
            child: InkWell(
              onTap: onToggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                color: open ? AppColors.brandTint : null,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.place_outlined, size: 17, color: AppColors.brand),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    Text('${farms.length}곳', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(width: 4),
                    Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            for (final f in farms)
              _FarmRow(farm: f, open: openFarmId == f.id, onToggle: () => onToggleFarm(f.id)),
        ],
      ),
    );
  }
}

class _FarmRow extends StatelessWidget {
  const _FarmRow({required this.farm, required this.open, required this.onToggle});

  final Farm farm;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final town = _townOf(farm);
    final sub = [if (town.isNotEmpty) town, _visitLabel(farm)].join(' · ');
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '${farm.name}, ${farm.riskLevel.label}, $sub',
            excludeSemantics: true,
            onTap: onToggle,
            child: InkWell(
              onTap: onToggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(farm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 3),
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RiskBadge(level: farm.riskLevel, dense: true),
                  ],
                ),
              ),
            ),
          ),
          if (open) _FarmDetail(farm: farm),
        ],
      ),
    );
  }
}

class _FarmDetail extends StatelessWidget {
  const _FarmDetail({required this.farm});

  final Farm farm;

  @override
  Widget build(BuildContext context) {
    final d = farm.lastVisitDays;
    final record = d == null ? '' : (d == 0 ? '오늘' : '$d일 전');
    final contact = (farm.ownerContact ?? '').trim();
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, child: Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.35))),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('주소', farm.address.isEmpty ? '미등록' : farm.address),
          row('최근 메모', record.isEmpty ? '기록 없음' : record),
          row('연락처', contact.isEmpty ? '미등록' : contact),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/reports/${farm.id}'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              child: const Text('상세 보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
