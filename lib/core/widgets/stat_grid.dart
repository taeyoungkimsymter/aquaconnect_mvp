import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_providers.dart';
import '../theme/app_colors.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/models/red_tide.dart';

class StatGridTile extends StatelessWidget {
  const StatGridTile({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      decoration: BoxDecoration(color: AppColors.neutralCard, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// 적조 status in one or two words, with its color: 주의보 (a 주의보/경보 in
/// force), 출현 (a 속보 in the last few days), 없음.
(String, Color) redTideStatusLabel(RedTideInfo info) {
  if (info.hasAdvisory) return ('주의보', AppColors.danger);
  if (info.isActive) return ('출현', AppColors.warningDark);
  return ('없음', AppColors.good);
}

/// The 수온·적조 tiles repeated on Home / AllReport / ReportDetail. Both
/// are current data: the realtime NIFS water temperature and the newest
/// NIFS 적조 속보.
class OceanStatGrid extends ConsumerWidget {
  const OceanStatGrid({super.key, required this.snapshot});

  final OceanSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerLabel = oceanLayerDisplayLabel(snapshot.layer);
    final redTide = ref.watch(redTideProvider);
    final (tideValue, tideColor) = redTide.when(
      data: redTideStatusLabel,
      loading: () => ('…', AppColors.textMuted),
      error: (_, _) => ('정보 없음', AppColors.textMuted),
    );
    return Row(
      children: [
        Expanded(
          child: StatGridTile(
            label: layerLabel == null ? '수온' : '수온 · $layerLabel',
            value: '${snapshot.waterTemp.toStringAsFixed(1)}℃',
            valueColor: AppColors.danger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: StatGridTile(label: '적조 속보', value: tideValue, valueColor: tideColor)),
      ],
    );
  }
}
