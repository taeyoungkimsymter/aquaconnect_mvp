import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ai_insight_card.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/farm_card.dart';
import '../../core/widgets/memo_card.dart';
import '../../core/widgets/stat_grid.dart';
import '../../data/models/farm.dart';
import '../../data/models/memo.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/models/report.dart';
import '../../data/models/risk_level.dart';

class AllReportScreen extends ConsumerWidget {
  const AllReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farmsAsync = ref.watch(farmsProvider);
    final reportsAsync = ref.watch(allReportsProvider);
    final memosAsync = ref.watch(memosProvider(null));
    final session = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
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
                        const Text('전체 리포트', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        farmsAsync.when(
                          data: (farms) => Text('${session?.organization.name ?? ''} · 담당 어가 ${farms.length}곳',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: farmsAsync.when(
                data: (farms) => reportsAsync.when(
                  data: (reports) => memosAsync.when(
                    data: (memos) => _Body(farms: farms, reports: reports, memos: memos),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('$e')),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.farms, required this.reports, required this.memos});

  final List<Farm> farms;
  final List<Report> reports;
  final List<Memo> memos;

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final level in RiskLevel.values) level: farms.where((f) => f.riskLevel == level).length,
    };
    final newMemoCount = memos.where((m) => m.createdAt.isAfter(DateTime.now().subtract(const Duration(hours: 24)))).length;
    final riskyFarms = [...farms]..sort((a, b) => a.riskLevel.index.compareTo(b.riskLevel.index));
    final temps = [for (final f in farms) if (f.waterTemp != null) f.waterTemp!];
    final avgTemp = temps.isEmpty ? null : temps.reduce((a, b) => a + b) / temps.length;
    final mortalityTrend = _weeklyMortalityTrend(memos);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            _SummaryTile(count: counts[RiskLevel.danger]!, label: '위험', bg: AppColors.dangerTint, fg: AppColors.danger),
            const SizedBox(width: 6),
            _SummaryTile(count: counts[RiskLevel.warning]!, label: '주의', bg: AppColors.warningTint, fg: AppColors.warningDark),
            const SizedBox(width: 6),
            _SummaryTile(count: counts[RiskLevel.good]!, label: '양호', bg: AppColors.goodTint, fg: AppColors.good),
            const SizedBox(width: 6),
            _SummaryTile(count: newMemoCount, label: '신규 메모', bg: AppColors.brandTintStrong, fg: AppColors.brand),
          ],
        ),
        const SizedBox(height: 16),
        AiInsightCard(
          title: 'AI 종합 소견 · 관리원 전체',
          bullets: [
            if (counts[RiskLevel.danger]! > 0)
              '고수온 영향 위험 양식장 ${counts[RiskLevel.danger]}곳 확인 — 우선 확인 권장',
            '관리원 전체 주간 폐사 ${mortalityTrend.fold<int>(0, (s, v) => s + v.round())}마리',
            if (newMemoCount > 0) '최근 24시간 신규 메모 $newMemoCount건',
          ],
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
                  Text('해양환경 데이터', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text('담당 해역 평균', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              if (avgTemp == null)
                const Text('수온 정보가 있는 양식장이 없습니다.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                OceanStatGrid(
                  snapshot: OceanSnapshot(region: '담당 해역', stationName: '평균', waterTemp: avgTemp, source: ''),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('주의 필요 양식장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text('위험도순', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand)),
          ],
        ),
        const SizedBox(height: 10),
        for (final farm in riskyFarms) ...[
          FarmCard(farm: farm, onTap: () => context.push('/reports/${farm.id}')),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('전체 폐사 추이', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Text('일별 폐사 (마리) · ${farms.length}개 양식장 합산', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              const SizedBox(height: 6),
              MortalityBarChart(values: mortalityTrend),
              const SizedBox(height: 4),
              ChartDayLabels(labels: _lastSevenDayLabels()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('최근 메모 하이라이트', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        for (final memo in memos.take(3)) ...[
          MemoCard(memo: memo),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  List<double> _weeklyMortalityTrend(List<Memo> memos) {
    final now = DateTime.now();
    final buckets = List<double>.filled(7, 0);
    final pattern = RegExp(r'폐사\s*(\d+)\s*마리');
    for (final memo in memos) {
      final match = pattern.firstMatch(memo.tags.join(' ')) ?? pattern.firstMatch(memo.content);
      if (match == null) continue;
      final count = int.tryParse(match.group(1) ?? '') ?? 0;
      final dayIndex = 6 - now.difference(memo.createdAt).inDays;
      if (dayIndex >= 0 && dayIndex < 7) buckets[dayIndex] += count;
    }
    return buckets;
  }

  List<String> _lastSevenDayLabels() {
    final now = DateTime.now();
    return List.generate(7, (i) => DateFormat('M/d').format(now.subtract(Duration(days: 6 - i))));
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.count, required this.label, required this.bg, required this.fg});

  final int count;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
