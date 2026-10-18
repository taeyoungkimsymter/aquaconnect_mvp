import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/farm_group_provider.dart';
import '../../core/providers/notification_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/farm_card.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/farm.dart';
import '../../data/models/farm_group.dart';
import '../../data/models/risk_level.dart';
import '../../data/services/farm_group_store.dart';
import '../notifications/notification_permission_sheet.dart';
import '../ocean/ocean_data_section.dart';
import 'onboarding_checklist_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  RiskLevel? _riskFilter;
  bool _mineOnly = true;

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(farmsProvider);
    final session = ref.watch(authStateProvider).valueOrNull;
    final orgName = session?.organization.name ?? 'AquaConnect';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: _buildScroll(context, farmsAsync, orgName)),
            const MemoComposerBar(confirmOnSave: true),
          ],
        ),
      ),
    );
  }

  Widget _buildScroll(BuildContext context, AsyncValue<List<Farm>> farmsAsync, String orgName) {
    final prefs = ref.watch(farmListPrefsProvider).valueOrNull ?? const FarmListPrefs();
    final sort = prefs.sort;
    final myId = ref.watch(authStateProvider).valueOrNull?.member.id;
    bool isMine(Farm f) => myId != null && f.assignedMemberId == myId;
    return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE3EFFA), AppColors.background],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _NotificationBell(onTap: () => openNotifications(context, ref)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'AquaConnect',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.brandDark),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        orgName,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => context.push('/memo'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            farmsAsync.when(
                              data: (farms) => Row(
                                children: [
                                  Text('${farms.length}',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brand)),
                                  const SizedBox(width: 6),
                                  const Text('담당 어가 · 메모 보러가기',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                                ],
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.chevron_right, size: 14, color: AppColors.brand),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const OnboardingChecklistCard(),
                  _ReportStatusCard(),
                  const SizedBox(height: 20),
                  const OceanDataSection(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
                      const Text('담당 양식장들', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      _SortMenu(
                        sort: sort,
                        onSelected: (s) => ref.read(farmListPrefsProvider.notifier).setSort(s),
                        onManageGroups: () => context.push('/mypage/farm-groups'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  farmsAsync.when(
                    data: (farms) => _FarmFilterRow(
                      farms: _mineOnly ? farms.where(isMine).toList() : farms,
                      mineCount: farms.where(isMine).length,
                      allCount: farms.length,
                      mineOnly: _mineOnly,
                      riskFilter: _riskFilter,
                      onMineOnly: () => setState(() {
                        _mineOnly = true;
                        _riskFilter = null;
                      }),
                      onAll: () => setState(() {
                        _mineOnly = false;
                        _riskFilter = null;
                      }),
                      onRisk: (r) => setState(() => _riskFilter = r),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 10),
                  farmsAsync.when(
                    data: (farms) {
                      final filtered = farms
                          .where((f) => !_mineOnly || isMine(f))
                          .where((f) => _riskFilter == null || f.riskLevel == _riskFilter)
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_mineOnly && farms.isNotEmpty && !farms.any(isMine))
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                "내가 담당하는 양식장이 없어요.\n'전체'를 누르거나, 마이페이지 > 등록 양식장 관리에서 담당자를 지정해 주세요.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5),
                              ),
                            ),
                          for (final section in _sections(filtered, sort, prefs.groups)) ...[
                            if (section.title != null) _SectionHeader(title: section.title!, count: section.farms.length),
                            for (final farm in section.farms) ...[
                              FarmCard(farm: farm, onTap: () => context.push('/reports/${farm.id}')),
                              const SizedBox(height: 10),
                            ],
                          ],
                          if (sort == FarmSort.group && prefs.groups.isEmpty)
                            _GroupEmptyHint(onTap: () => context.push('/mypage/farm-groups')),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('불러오기 실패: $e'),
                  ),
                ]),
              ),
            ),
          ],
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return Semantics(
      button: true,
      label: unread > 0 ? '알림 $unread개' : '알림',
      // The circle stays put and the icon stays centered whatever the count;
      // the count pill sits on the circle's top-right edge. (Material's
      // Badge re-laid the icon out to the top-left once a label appeared.)
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      unread > 0 ? Icons.notifications : Icons.notifications_none,
                      size: 19,
                      color: AppColors.neutralIconStrong,
                    ),
                  ),
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                top: -3,
                right: -5,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FarmFilterRow extends StatelessWidget {
  const _FarmFilterRow({
    required this.farms,
    required this.mineCount,
    required this.allCount,
    required this.mineOnly,
    required this.riskFilter,
    required this.onMineOnly,
    required this.onAll,
    required this.onRisk,
  });

  /// The farms in the current scope (내 담당 or 전체) — the risk counts.
  final List<Farm> farms;
  final int mineCount;
  final int allCount;
  final bool mineOnly;
  final RiskLevel? riskFilter;
  final VoidCallback onMineOnly;
  final VoidCallback onAll;
  final void Function(RiskLevel?) onRisk;

  int _count(RiskLevel level) => farms.where((f) => f.riskLevel == level).length;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterPillChip(label: '내 담당 $mineCount', selected: mineOnly, onTap: onMineOnly),
          const SizedBox(width: 6),
          FilterPillChip(label: '전체 $allCount', selected: !mineOnly, onTap: onAll),
          const SizedBox(width: 6),
          FilterPillChip(
            label: '위험 ${_count(RiskLevel.danger)}',
            selected: riskFilter == RiskLevel.danger,
            onTap: () => onRisk(riskFilter == RiskLevel.danger ? null : RiskLevel.danger),
            selectedColor: AppColors.dangerTint,
            selectedTextColor: AppColors.danger,
          ),
          const SizedBox(width: 6),
          FilterPillChip(
            label: '주의 ${_count(RiskLevel.warning)}',
            selected: riskFilter == RiskLevel.warning,
            onTap: () => onRisk(riskFilter == RiskLevel.warning ? null : RiskLevel.warning),
            selectedColor: AppColors.warningTint,
            selectedTextColor: AppColors.warningDark,
          ),
          const SizedBox(width: 6),
          FilterPillChip(
            label: '양호 ${_count(RiskLevel.good)}',
            selected: riskFilter == RiskLevel.good,
            onTap: () => onRisk(riskFilter == RiskLevel.good ? null : RiskLevel.good),
            selectedColor: AppColors.goodTint,
            selectedTextColor: AppColors.good,
          ),
        ],
      ),
    );
  }
}

class _ReportStatusCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farmsAsync = ref.watch(farmsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('리포트 현황', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [
              SourceBadgeChip(
                icon: Icons.water,
                label: '해양환경 데이터',
                bg: AppColors.brandTint,
                fg: AppColors.brand,
              ),
              SourceBadgeChip(
                icon: Icons.description_outlined,
                label: '현장 메모',
                bg: AppColors.goodTint,
                fg: AppColors.good,
              ),
            ],
          ),
          const SizedBox(height: 12),
          farmsAsync.when(
            data: (farms) {
              final risky = farms.where((f) => f.riskLevel == RiskLevel.danger).toList();
              if (risky.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppColors.dangerTint, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: AppColors.dangerTintStrong, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.dangerDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('고수온 영향 위험 양식장 ${risky.length}곳 확인',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dangerDark)),
                          const SizedBox(height: 2),
                          const Text('아래 목록에서 확인하세요',
                              style: TextStyle(fontSize: 12, color: AppColors.dangerInk)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => GoRouter.of(context).push('/reports'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.chevron_right, size: 16),
              label: const Text('전체 리포트 보기', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One block of the farm list; [title] is null when there is no section header
/// (위험도순).
class _FarmSection {
  const _FarmSection(this.title, this.farms);

  final String? title;
  final List<Farm> farms;
}

List<Farm> _byRisk(Iterable<Farm> farms) => farms.toList()..sort((a, b) => a.riskLevel.index.compareTo(b.riskLevel.index));

/// Lays [farms] out for the chosen [sort]. Inside every section the farms stay
/// in risk order (위험 → 주의 → 양호).
List<_FarmSection> _sections(List<Farm> farms, FarmSort sort, List<FarmGroup> groups) {
  switch (sort) {
    case FarmSort.risk:
      return [_FarmSection(null, _byRisk(farms))];
    case FarmSort.region:
      final byRegion = <String, List<Farm>>{};
      for (final f in farms) {
        byRegion.putIfAbsent(regionOf(f), () => []).add(f);
      }
      final names = byRegion.keys.toList()..sort();
      return [for (final n in names) _FarmSection(n, _byRisk(byRegion[n]!))];
    case FarmSort.group:
      final byId = {for (final f in farms) f.id: f};
      final used = <String>{};
      final result = <_FarmSection>[];
      for (final g in groups) {
        final members = [for (final id in g.farmIds) ?byId[id]];
        used.addAll(members.map((f) => f.id));
        if (members.isNotEmpty) result.add(_FarmSection(g.name, _byRisk(members)));
      }
      final rest = farms.where((f) => !used.contains(f.id)).toList();
      if (rest.isNotEmpty) result.add(_FarmSection('그룹 미지정', _byRisk(rest)));
      return result;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
        ],
      ),
    );
  }
}

class _GroupEmptyHint extends StatelessWidget {
  const _GroupEmptyHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.folder_copy_outlined, size: 18, color: AppColors.brand),
            SizedBox(width: 10),
            Expanded(
              child: Text('아직 만든 그룹이 없어요. 탭해서 그룹을 만들어 보세요.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "위험도순 ▾" — switches how the list is ordered, plus a shortcut to the
/// group builder.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onSelected, required this.onManageGroups});

  final FarmSort sort;
  final ValueChanged<FarmSort> onSelected;
  final VoidCallback onManageGroups;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: '정렬 방식',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) => v is FarmSort ? onSelected(v) : onManageGroups(),
      itemBuilder: (_) => [
        for (final s in FarmSort.values)
          CheckedPopupMenuItem<Object>(value: s, checked: s == sort, child: Text(s.label, style: const TextStyle(fontSize: 13.5))),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: 'manage', child: Text('그룹 만들기·관리', style: TextStyle(fontSize: 13.5))),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sort.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand)),
          const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.brand),
        ],
      ),
    );
  }
}
