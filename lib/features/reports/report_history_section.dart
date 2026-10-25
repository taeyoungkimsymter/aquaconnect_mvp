import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/risk_badge.dart';
import '../../data/models/report.dart';

/// 양식장 상세의 '이전 리포트' — 지금 화면의 최신 리포트를 뺀, 앞서 발행된 리포트 목록.
/// 눌러서 그때 만들어진 내용을 그대로 본다.
class ReportHistorySection extends ConsumerWidget {
  const ReportHistorySection({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(reportHistoryProvider(farmId));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이전 리포트', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('이전 리포트를 불러오지 못했어요.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            data: (reports) {
              final previous = reports.skip(1).toList(); // [0]은 위에 보이는 최신 리포트
              if (previous.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('이전에 발행된 리포트가 없어요.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                );
              }
              return Column(
                children: [for (final r in previous) _HistoryRow(report: r)],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy.M.d HH:mm').format(report.generatedAt.toLocal());
    return InkWell(
      onTap: () => _showReport(context, report),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(report.headline,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RiskBadge(level: report.riskLevel, dense: true),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.neutralArrow),
            ],
          ),
        ),
      ),
    );
  }
}

void _showReport(BuildContext context, Report r) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          children: [
            Text('${DateFormat('yyyy.M.d HH:mm').format(r.generatedAt.toLocal())} 발행 리포트',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Row(
              children: [
                RiskBadge(level: r.riskLevel),
                const SizedBox(width: 10),
                Expanded(child: Text(r.headline, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              ],
            ),
            const SizedBox(height: 10),
            Text(r.summary, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 12),
            Text(
              '주간 폐사 ${r.weeklyMortality}마리 · 평균 수온 ${r.avgTemp == null ? '-' : '${r.avgTemp!.toStringAsFixed(1)}℃'} · '
              '최근 방문 ${r.lastVisitDays == null ? '기록 없음' : 'D-${r.lastVisitDays}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            if (r.findings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('AI 정리 소견', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              for (final f in r.findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $f', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
                ),
            ],
            if (r.followUps.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('후속 조치 제안', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              for (final f in r.followUps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $f', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
