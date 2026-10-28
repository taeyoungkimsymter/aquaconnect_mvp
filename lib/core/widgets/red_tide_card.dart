import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/data_providers.dart';
import '../theme/app_colors.dart';
import '../../data/models/red_tide.dart';
import 'stat_grid.dart';

/// 적조 정보: the newest NIFS 적조 속보 — status, 특보 상황 and where which
/// organism was found — with 진행상황·전망·당부사항 and the recent 속보
/// behind 자세히 보기.
class RedTideCard extends ConsumerStatefulWidget {
  const RedTideCard({super.key});

  @override
  ConsumerState<RedTideCard> createState() => _RedTideCardState();
}

class _RedTideCardState extends ConsumerState<RedTideCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(redTideProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (e, _) => Text('적조 정보를 불러오지 못했습니다.\n$e', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        data: _buildInfo,
      ),
    );
  }

  Widget _buildInfo(RedTideInfo info) {
    final latest = info.latest;
    final (status, color) = redTideStatusLabel(info);
    final days = info.daysSinceLatest;
    final dateFmt = DateFormat('M월 d일 (E)', 'ko_KR');

    final header = Row(
      children: [
        const Icon(Icons.waves, size: 17, color: AppColors.danger),
        const SizedBox(width: 6),
        const Text('적조 정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(
            info.hasAdvisory ? '적조 주의보 발령 중' : info.isActive ? '적조 출현 중' : '현재 적조 속보 없음',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
    );

    if (latest == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          const Text('최근 1년간 발표된 적조 속보가 없어요.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      );
    }

    final when = days == 0 ? '오늘' : days == 1 ? '어제' : '$days일 전';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 6),
        Text(
          info.isActive
              ? '${dateFmt.format(latest.reportDate)} 속보 ($when)'
              : '마지막 속보 · ${dateFmt.format(latest.reportDate)} ($when) — 그 뒤로 발표된 적조 속보가 없어요',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
        ),
        if (status != '없음' && latest.breaking.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TextBlock(title: '특보 상황', text: latest.breaking, tint: AppColors.dangerTint, ink: AppColors.dangerDark),
        ],
        if (latest.occurrences.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(info.isActive ? '출현 해역' : '마지막 속보의 출현 해역',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          for (final o in latest.occurrences) _OccurrenceRow(occurrence: o),
        ],
        if (_expanded) ...[
          if (status == '없음' && latest.breaking.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextBlock(title: '특보 상황', text: latest.breaking),
          ],
          if (latest.progress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextBlock(title: '진행 상황', text: latest.progress),
          ],
          if (latest.outlook.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextBlock(title: '금후 전망', text: latest.outlook),
          ],
          if (latest.request.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextBlock(title: '당부 사항', text: latest.request, tint: AppColors.warningTint, ink: AppColors.warningTintInk),
          ],
          if (info.recent.length > 1) ...[
            const SizedBox(height: 12),
            const Text('최근 속보',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            for (final r in info.recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(DateFormat('M/d').format(r.reportDate),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      child: Text(
                        r.occurrences.isEmpty
                            ? '-'
                            : r.occurrences.map((o) => '${o.area} ${o.organismLabel}${_densityText(o)}').join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text('출처 · 국립수산과학원 적조정보 · 조회 ${DateFormat('HH:mm').format(info.fetchedAt)}',
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA0B5))),
            ),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
              ),
              child: Text(_expanded ? '접기' : '자세히 보기',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
            ),
          ],
        ),
      ],
    );
  }
}

String _number(double v) => v == v.roundToDouble() ? NumberFormat('#,###').format(v) : NumberFormat('#,##0.##').format(v);

/// " 0.2~120개체/mL", or "" when NIFS gave no density.
String _densityText(RedTideOccurrence o) {
  final min = o.minDensity;
  final max = o.maxDensity;
  if (min == null && max == null) return '';
  if (max == 0 && (min ?? 0) == 0) return ' 미출현';
  final range = min == null || min == max ? _number(max ?? min!) : '${_number(min)}~${_number(max ?? min)}';
  return ' $range개체/mL';
}

class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({required this.occurrence});

  final RedTideOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final temp = o.minTemp == null && o.maxTemp == null
        ? ''
        : o.minTemp == o.maxTemp || o.maxTemp == null || o.minTemp == null
            ? ' · 수온 ${(o.maxTemp ?? o.minTemp)!.toStringAsFixed(1)}℃'
            : ' · 수온 ${o.minTemp!.toStringAsFixed(1)}~${o.maxTemp!.toStringAsFixed(1)}℃';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 6, color: AppColors.danger),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: o.area, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                TextSpan(text: '  ${o.organismLabel}${_densityText(o)}$temp'),
              ]),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.text, this.tint = AppColors.neutralCard, this.ink = AppColors.textSecondary});

  final String title;
  final String text;
  final Color tint;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 3),
          Text(text, style: TextStyle(fontSize: 12, color: ink, height: 1.5)),
        ],
      ),
    );
  }
}
