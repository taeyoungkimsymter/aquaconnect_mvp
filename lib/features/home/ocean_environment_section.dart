import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ocean_data_times_dialog.dart';
import '../../core/widgets/red_tide_card.dart';
import '../../core/widgets/stat_grid.dart';
import '../../data/models/ocean_reading.dart';

/// 해양환경 데이터 (실시간 수온 + 적조 정보) for one station, shown on Home under 전체
/// 리포트 보기. It always opens on the MyPage 바다 위치 (and follows it when
/// that changes); picking another station from the chip only browses it —
/// '내 위치로' goes back, and the MyPage setting is left alone.
class OceanEnvironmentSection extends ConsumerStatefulWidget {
  const OceanEnvironmentSection({super.key});

  @override
  ConsumerState<OceanEnvironmentSection> createState() => _OceanEnvironmentSectionState();
}

class _OceanEnvironmentSectionState extends ConsumerState<OceanEnvironmentSection> {
  String? _stationCode;
  String? _stationName;
  bool _initializedFromPreference = false;

  Future<OceanSnapshot>? _future;
  String? _futureStationCode;

  /// The last snapshot loaded for the current station, kept for the ⓘ
  /// button while a refresh is in flight.
  OceanSnapshot? _latest;

  void _selectStation(OceanStation station) {
    setState(() {
      _stationCode = station.code;
      _stationName = station.name;
    });
  }

  /// Created once per station (and on refresh) instead of on every build,
  /// so rebuilds don't refetch.
  Future<OceanSnapshot>? _snapshotFuture() {
    if (_stationCode == null || _stationName == null) return null;
    if (_future == null || _futureStationCode != _stationCode) {
      _latest = null;
      _load(refresh: false);
    }
    return _future;
  }

  void _load({required bool refresh}) {
    final code = _stationCode!;
    final name = _stationName!;
    _futureStationCode = code;
    _future = ref
        .read(oceanServiceProvider)
        .fetchSnapshot(stationCode: code, stationName: name, region: name, refresh: refresh)
        .then((snapshot) {
      if (mounted && _futureStationCode == code) setState(() => _latest = snapshot);
      return snapshot;
    });
  }

  void _refresh() {
    setState(() => _load(refresh: true));
    ref.read(oceanServiceProvider).fetchRedTide(refresh: true).whenComplete(() => ref.invalidate(redTideProvider));
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(oceanStationsProvider);
    final stations = stationsAsync.valueOrNull;
    // Wait for the saved 바다 위치 too: starting before it loads is what used
    // to drop Home onto the alphabetically-first station.
    final preferenceAsync = ref.watch(selectedOceanStationProvider);
    final preferred = preferenceAsync.valueOrNull;
    // A new MyPage 바다 위치 moves Home along with it.
    ref.listen(selectedOceanStationProvider, (previous, next) {
      final selection = next.valueOrNull;
      if (selection != null && selection.code != previous?.valueOrNull?.code) {
        final match = ref.read(oceanStationsProvider).valueOrNull?.where((s) => s.code == selection.code).firstOrNull;
        if (match != null) _selectStation(match);
      }
    });
    if (stations != null && stations.isNotEmpty && !_initializedFromPreference && !preferenceAsync.isLoading) {
      final initial = stations.where((s) => s.code == preferred?.code).firstOrNull ?? stations.first;
      _stationCode = initial.code;
      _stationName = initial.name;
      _initializedFromPreference = true;
    }
    final myStation = preferred == null ? null : stations?.where((s) => s.code == preferred.code).firstOrNull;
    final browsingOther = myStation != null && _stationCode != myStation.code;

    return stationsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
        child: Text('관측소 목록을 불러오지 못했습니다.\n$e', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
      data: (stations) {
        if (!_initializedFromPreference) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final future = _snapshotFuture();
        if (stations.isEmpty || future == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
            child: const Text('선택 가능한 관측소가 없습니다.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('해양환경 데이터',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                _HeaderIconButton(icon: Icons.refresh, tooltip: '새로고침', onPressed: _refresh),
                _HeaderIconButton(
                  icon: Icons.info_outline,
                  tooltip: '최근 관측 시각',
                  onPressed: _latest == null
                      ? null
                      : () => showOceanDataTimesDialog(context, _latest!, redTide: ref.read(redTideProvider).valueOrNull),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: _stationCode,
                  tooltip: '다른 지역 보기',
                  constraints: const BoxConstraints(maxHeight: 420),
                  onSelected: (code) => _selectStation(stations.firstWhere((s) => s.code == code)),
                  itemBuilder: (context) => [
                    if (myStation != null) ...[
                      PopupMenuItem(
                        value: myStation.code,
                        child: Row(
                          children: [
                            const Icon(Icons.home_outlined, size: 16, color: AppColors.brand),
                            const SizedBox(width: 6),
                            Text(myStation.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
                            const SizedBox(width: 6),
                            const Text('내 바다 위치', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    for (final s in stations)
                      if (s.code != myStation?.code)
                        PopupMenuItem(
                          value: s.code,
                          child: Text(s.sea == null ? s.name : '${s.name}  ·  ${s.sea}'),
                        ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_stationName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
                        const Icon(Icons.expand_more, size: 14, color: AppColors.brand),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    myStation == null
                        ? '마이페이지 > 바다 위치를 정하면 여기에 기본으로 보여요 · 오른쪽 칩을 눌러 다른 지역도 볼 수 있어요'
                        : browsingOther
                            ? '다른 지역을 보는 중이에요 (내 바다 위치: ${myStation.name})'
                            : '내 바다 위치(마이페이지 설정) 기준 · 오른쪽 칩을 눌러 다른 지역도 볼 수 있어요',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ),
                if (browsingOther)
                  TextButton.icon(
                    onPressed: () => _selectStation(myStation),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.my_location, size: 14),
                    label: const Text('내 위치로', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<OceanSnapshot>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
                    child: Text('해양환경 데이터를 불러오지 못했습니다.\n${snapshot.error ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  );
                }
                final ocean = snapshot.data!;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OceanStatGrid(snapshot: ocean),
                      const SizedBox(height: 10),
                      Text('출처 · ${ocean.source}', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA0B5))),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            const RedTideCard(),
          ],
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: AppColors.textTertiary,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }
}
