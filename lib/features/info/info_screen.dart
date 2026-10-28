import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/disease_info.dart';

class InfoScreen extends ConsumerStatefulWidget {
  const InfoScreen({super.key});

  @override
  ConsumerState<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends ConsumerState<InfoScreen> {
  final Set<DiseaseInfoScope> _scopeFilter = {};
  String? _speciesFilter;

  @override
  Widget build(BuildContext context) {
    final diseaseAsync = ref.watch(diseaseInfoProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              width: double.infinity,
              color: AppColors.background,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('정보', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const Text('수산질병 정보', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _FilterToggle(
                        label: '전체',
                        selected: _scopeFilter.isEmpty && _speciesFilter == null,
                        onTap: () => setState(() {
                          _scopeFilter.clear();
                          _speciesFilter = null;
                        }),
                      ),
                      _FilterToggle(
                        label: '국내',
                        selected: _scopeFilter.contains(DiseaseInfoScope.domestic),
                        onTap: () => setState(() => _toggleScope(DiseaseInfoScope.domestic)),
                      ),
                      _FilterToggle(
                        label: '해외',
                        selected: _scopeFilter.contains(DiseaseInfoScope.overseas),
                        onTap: () => setState(() => _toggleScope(DiseaseInfoScope.overseas)),
                      ),
                      _FilterToggle(
                        label: '넙치',
                        selected: _speciesFilter == '넙치',
                        onTap: () => setState(() => _speciesFilter = _speciesFilter == '넙치' ? null : '넙치'),
                      ),
                      _FilterToggle(
                        label: '새우',
                        selected: _speciesFilter == '새우',
                        onTap: () => setState(() => _speciesFilter = _speciesFilter == '새우' ? null : '새우'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('여러 항목을 함께 선택할 수 있어요 (예: 국내 + 넙치) · 전체를 누르면 초기화',
                      style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  diseaseAsync.when(
                    data: (items) {
                      final filtered = items.where((d) {
                        final scopeOk = _scopeFilter.isEmpty || _scopeFilter.contains(d.scope);
                        final speciesOk = _speciesFilter == null || d.species == _speciesFilter;
                        return scopeOk && speciesOk;
                      }).toList();
                      if (filtered.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('조건에 맞는 정보가 없습니다.', style: TextStyle(color: AppColors.textMuted)),
                        );
                      }
                      return Column(
                        children: [
                          for (final d in filtered) ...[
                            _DiseaseInfoCard(info: d),
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('불러오기 실패: $e'),
                  ),
                ],
              ),
            ),
            const MemoComposerBar(confirmOnSave: true),
          ],
        ),
      ),
    );
  }

  void _toggleScope(DiseaseInfoScope scope) {
    if (_scopeFilter.contains(scope)) {
      _scopeFilter.remove(scope);
    } else {
      _scopeFilter.add(scope);
    }
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(selected ? 10 : 12, 5, 12, 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : AppColors.surface,
          border: selected ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check, size: 10, color: Colors.white),
            ),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _DiseaseInfoCard extends StatelessWidget {
  const _DiseaseInfoCard({required this.info});

  final DiseaseInfo info;

  @override
  Widget build(BuildContext context) {
    final isDomestic = info.scope == DiseaseInfoScope.domestic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDomestic ? AppColors.goodTint : AppColors.neutralChip,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              info.scope.label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: isDomestic ? AppColors.good : AppColors.neutralIcon),
            ),
          ),
          const SizedBox(height: 4),
          Text(info.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text('${DateFormat('M/d').format(info.publishedAt)} · ${info.source}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
