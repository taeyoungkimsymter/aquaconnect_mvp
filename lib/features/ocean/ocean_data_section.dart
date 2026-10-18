import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ocean_data_times_dialog.dart';
import '../../core/widgets/stat_grid.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/services/ocean_station_preference_store.dart';

/// 해양환경 데이터 — 해역(관측소) 선택, 새로고침, 최근 관측 시각 안내, 수온·수질 카드.
/// 홈 화면에 놓이며, 관측소 목록·조회·오류 처리를 전부 이 위젯 안에서 해서
/// 여기서 실패해도 같은 화면의 리포트·양식장 목록에는 영향이 없습니다.
///
/// 선택한 해역은 마이페이지의 해역 설정([selectedOceanStationProvider])과 같은 값을 씁니다.
///
/// 조회가 실패해도 실패 문구를 띄우지 않고 마지막으로 성공한 데이터를 그대로 보여 줍니다.
class OceanDataSection extends ConsumerStatefulWidget {
  const OceanDataSection({super.key});

  @override
  ConsumerState<OceanDataSection> createState() => _OceanDataSectionState();
}

class _OceanDataSectionState extends ConsumerState<OceanDataSection> {
  /// 지금 선택된 해역.
  String? _stationCode;
  String? _stationName;
  bool _initializedFromPreference = false;

  /// 화면에 보여 주는 마지막 성공 조회 결과와 그 해역. 조회가 실패해도 이 값은 그대로 남습니다 —
  /// 실패 문구를 띄우지 않고 기존 데이터를 계속 보여 주기 위해서입니다.
  OceanSnapshot? _shown;
  String? _shownCode;
  String? _shownName;

  bool _loading = false;

  /// 해역을 빠르게 바꾸거나 새로고침을 누를 때 늦게 도착한 이전 응답을 버리기 위한 번호.
  int _generation = 0;

  void _selectStation(OceanStation station) {
    setState(() {
      _stationCode = station.code;
      _stationName = station.name;
    });
    ref.read(selectedOceanStationProvider.notifier).select(
          OceanStationSelection(code: station.code, name: station.name),
        );
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final code = _stationCode;
    final name = _stationName;
    if (code == null || name == null) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      var snapshot = await ref
          .read(oceanServiceProvider)
          .fetchSnapshot(stationCode: code, stationName: name, region: name, refresh: refresh);
      // 수질 상세만 일시적으로 못 가져온 경우, 같은 해역의 직전 수질 값을 유지합니다.
      final previous = _shown;
      if (previous != null &&
          _shownCode == code &&
          snapshot.waterQuality == null &&
          snapshot.waterQualityStatus == WaterQualityStatus.unavailable &&
          previous.waterQuality != null) {
        snapshot = OceanSnapshot(
          region: snapshot.region,
          stationName: snapshot.stationName,
          waterTemp: snapshot.waterTemp,
          source: snapshot.source,
          salinity: snapshot.salinity,
          dissolvedOxygen: snapshot.dissolvedOxygen,
          waterQualityStatus: previous.waterQualityStatus,
          layer: snapshot.layer,
          observedAt: snapshot.observedAt,
          waterQuality: previous.waterQuality,
          fetchedAt: snapshot.fetchedAt,
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _shown = snapshot;
        _shownCode = code;
        _shownName = name;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // 조회 실패: 실패 문구 없이 기존 데이터를 그대로 둡니다. 다른 해역으로 바꾸다 실패했다면
      // 데이터와 해역 이름이 어긋나지 않도록 직전 해역으로 조용히 되돌립니다.
      final revertCode = _shown != null && _shownCode != code ? _shownCode : null;
      final revertName = _shownName;
      setState(() {
        _loading = false;
        if (revertCode != null) {
          _stationCode = revertCode;
          _stationName = revertName;
        }
      });
      if (revertCode != null && revertName != null) {
        ref.read(selectedOceanStationProvider.notifier).select(
              OceanStationSelection(code: revertCode, name: revertName),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(oceanStationsProvider);

    // 마이페이지에서 해역을 바꾸면 여기에도 반영합니다(여기서 고른 경우는 이미 같은 값이라 무시).
    ref.listen(selectedOceanStationProvider, (_, next) {
      final selected = next.valueOrNull;
      if (selected != null && selected.code != _stationCode && mounted) {
        setState(() {
          _stationCode = selected.code;
          _stationName = selected.name;
        });
        _load();
      }
    });

    final stations = stationsAsync.valueOrNull;
    if (stations != null && stations.isNotEmpty && !_initializedFromPreference) {
      final preferred = ref.read(selectedOceanStationProvider).valueOrNull;
      var initial = stations.first;
      if (preferred != null) {
        for (final s in stations) {
          if (s.code == preferred.code) {
            initial = s;
            break;
          }
        }
      }
      _stationCode = initial.code;
      _stationName = initial.name;
      _initializedFromPreference = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return stationsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      // 실패 문구 대신 차분한 안내만 — 조회 실패를 화면에 드러내지 않습니다.
      // 새로고침으로 관측소 목록부터 다시 불러올 수 있게 제목과 버튼은 남겨 둡니다.
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('해양환경 데이터',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              _HeaderIconButton(
                icon: Icons.refresh,
                tooltip: '새로고침',
                onPressed: () => ref.invalidate(oceanStationsProvider),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const _MessageCard('해양환경 데이터를 준비하고 있어요.'),
        ],
      ),
      data: (stations) {
        if (stations.isEmpty || _stationCode == null || _stationName == null) {
          return const _MessageCard('선택 가능한 관측소가 없습니다.');
        }
        final shown = _shown;
        final showingSelected = shown != null && _shownCode == _stationCode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('해양환경 데이터',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                _loading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : _HeaderIconButton(icon: Icons.refresh, tooltip: '새로고침', onPressed: () => _load(refresh: true)),
                _HeaderIconButton(
                  icon: Icons.info_outline,
                  tooltip: '최근 관측 시각',
                  onPressed: shown == null ? null : () => showOceanDataTimesDialog(context, shown),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: _stationCode,
                  onSelected: (code) => _selectStation(stations.firstWhere((s) => s.code == code)),
                  itemBuilder: (context) =>
                      stations.map((s) => PopupMenuItem(value: s.code, child: Text(s.name))).toList(),
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
            const Text('여러 해역의 중층·저층 수온을 확인할 수 있어요 — 위 칩을 눌러 전환 (마이페이지에서도 선택 가능)',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            if (showingSelected)
              _DataCard(ocean: shown)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              const _MessageCard('해양환경 데이터를 준비하고 있어요.'),
          ],
        );
      },
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.ocean});

  final OceanSnapshot ocean;

  @override
  Widget build(BuildContext context) {
    final quality = ocean.waterQuality;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OceanStatGrid(snapshot: ocean),
          if (quality != null) ...[
            const SizedBox(height: 12),
            Text('수질 상세 · ${quality.pointName} (${DateFormat('yyyy.M.d').format(quality.observedAt)} 조사)',
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            const SizedBox(height: 6),
            WaterQualityGrid(quality: quality),
            const SizedBox(height: 4),
            const Text('저층 기준 · 염도 psu, 용존산소·COD·질소·인·부유물질 mg/L, 클로로필a µg/L',
                style: TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 10),
          Text('출처 · ${ocean.source}', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA0B5))),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
