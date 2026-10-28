import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/models/red_tide.dart';

/// Shows when each part of the 해양환경 data was measured: the realtime water
/// temperature of [snapshot] and the newest 적조 속보 in [redTide].
Future<void> showOceanDataTimesDialog(BuildContext context, OceanSnapshot snapshot, {RedTideInfo? redTide}) {
  final format = DateFormat('yyyy.MM.dd HH:mm');
  final latestTide = redTide?.latest;
  final layerLabel = oceanLayerDisplayLabel(snapshot.layer);

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('최근 관측 시각', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Entry(
            title: '수온 · 실시간',
            time: snapshot.observedAt == null ? '정보 없음' : format.format(snapshot.observedAt!),
            detail: '${snapshot.stationName} 관측소${layerLabel == null ? '' : ' · $layerLabel'}',
          ),
          const SizedBox(height: 14),
          _Entry(
            title: '적조 속보',
            time: latestTide == null ? '정보 없음' : DateFormat('yyyy.MM.dd').format(latestTide.reportDate),
            detail: latestTide == null
                ? '최근 1년간 발표된 속보가 없습니다'
                : '국립수산과학원 적조정보 · 적조가 있는 동안 매일 발표돼요',
          ),
          if (snapshot.fetchedAt != null) ...[
            const SizedBox(height: 8),
            Text('마지막 조회 · ${DateFormat('HH:mm:ss').format(snapshot.fetchedAt!)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
      ],
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.title, required this.time, required this.detail});

  final String title;
  final String time;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(time, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        Text(detail, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
      ],
    );
  }
}
