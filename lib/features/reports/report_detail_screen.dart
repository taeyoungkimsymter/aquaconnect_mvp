import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ai_insight_card.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/stat_grid.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/risk_badge.dart';
import '../../data/models/farm.dart';
import '../../data/models/memo.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/models/report.dart';
import 'ai_report_list_screen.dart';
import 'report_history_section.dart';
import 'share_link_sheet.dart';

class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farmAsync = ref.watch(farmByIdProvider(farmId));
    final reportAsync = ref.watch(reportProvider(farmId));
    final memosAsync = ref.watch(memosProvider(farmId));
    final oceanService = ref.watch(oceanServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: farmAsync.when(
          data: (farm) {
            if (farm == null) return const Center(child: Text('양식장을 찾을 수 없습니다.'));
            return Column(
              children: [
                _Header(farm: farm),
                Expanded(
                  child: reportAsync.when(
                    data: (report) => memosAsync.when(
                      data: (memos) => FutureBuilder<OceanSnapshot>(
                        future: oceanService.fetchSnapshot(
                          stationCode: farm.nearestStationCode,
                          stationName: farm.nearestStationName,
                          region: farm.region,
                        ),
                        builder: (context, oceanSnapshot) => _Body(
                          farm: farm,
                          report: report,
                          memos: memos,
                          ocean: oceanSnapshot.data,
                        ),
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('$e')),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('$e')),
                  ),
                ),
                _BottomActions(farm: farm),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.farm});
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(farm.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text('${farm.address} · 종합 리포트', style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.farm, required this.report, required this.memos, required this.ocean});

  final Farm farm;
  final Report? report;
  final List<Memo> memos;
  final OceanSnapshot? ocean;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (r != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: const Color(0xFFF0DCCF)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RiskBadge(level: r.riskLevel),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.headline, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(r.summary, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _StatTile(value: '${r.weeklyMortality}마리', label: '주간 폐사')),
                    const SizedBox(width: 8),
                    Expanded(child: _StatTile(value: r.avgTemp == null ? '-' : '${r.avgTemp!.toStringAsFixed(1)}℃', label: '평균 수온')),
                    const SizedBox(width: 8),
                    Expanded(child: _StatTile(value: r.lastVisitDays == null ? '기록 없음' : 'D-${r.lastVisitDays}', label: '최근 방문')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('해양환경 데이터', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(20)),
                    child: Text('${farm.nearestStationName} 관측소',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brand)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('이 양식장에서 가장 가까운 관측소 기준 (바다누리·NIFS)', style: TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              if (ocean != null)
                OceanStatGrid(snapshot: ocean!)
              else
                const Text('해양환경 데이터를 불러오지 못했습니다.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (r != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('현장 기록 데이터', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    Text('AquaConnect 자체기록', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('일별 폐사 (마리) · 최근 7일', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                const SizedBox(height: 6),
                MortalityBarChart(values: r.mortalityTrend),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('메모 타임라인', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text('수산질병관리원 · 어가 기록', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              if (memos.isEmpty)
                const Text('아직 기록된 메모가 없습니다.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                for (final memo in memos.take(4)) ...[
                  MemoCard(memo: memo, showFarmTag: false),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (r != null)
          AiInsightCard(
            title: 'AI 정리 소견',
            bullets: r.findings,
          ),
        const SizedBox(height: 16),
        _AiReportEntry(farmId: farm.id),
        if (r != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('후속 조치 제안', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                for (final action in r.followUps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: AppColors.good),
                        const SizedBox(width: 8),
                        Expanded(child: Text(action, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        ReportHistorySection(farmId: farm.id),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () async {
              await ref.read(reportRepositoryProvider).generateReport(farm.id);
              ref.invalidate(reportProvider(farm.id));
              ref.invalidate(reportHistoryProvider(farm.id));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리포트를 새로 생성했습니다.')));
              }
            },
            child: const Text('리포트 새로고침', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
          ),
        ),
        if (r != null)
          Center(
            child: Text('생성 ${DateFormat('M/d HH:mm').format(r.generatedAt)}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
          ),
      ],
    );
  }
}

/// Entry to the AI 관리 리포트 (symterAI port): latest draft's status at a
/// glance, tap through to the list / create flow.
class _AiReportEntry extends ConsumerWidget {
  const _AiReportEntry({required this.farmId});
  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(aiReportsProvider(farmId)).valueOrNull?.firstOrNull;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/reports/$farmId/ai'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: AppColors.brandTintBorder), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI 관리 리포트', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      latest == null
                          ? '기간·메모를 골라 AI가 근거 있는 리포트 초안을 써요'
                          : '최근: ${aiReportPeriodLabel(latest)} · ${latest.isConfirmed ? '확정' : '초안'} · 메모 ${latest.memoCount}건',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.neutralArrow),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.neutralCard, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.farm});
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => context.push('/reports/${farm.id}/farm-report'),
                icon: const Icon(Icons.visibility_outlined, size: 14, color: AppColors.brand),
                label: const Text('어가 화면 미리보기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
              ),
              TextButton.icon(
                onPressed: () => showShareLinkSheet(context, farm: farm),
                icon: const Icon(Icons.link, size: 14, color: AppColors.brand),
                label: const Text('어가에 리포트 링크 공유', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlineButton(label: '방문 예약', onPressed: () {}),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(label: '메모 남기기', onPressed: () => context.push('/memo')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
