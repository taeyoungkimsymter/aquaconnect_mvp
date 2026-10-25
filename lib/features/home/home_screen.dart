import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/notification_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../../data/models/farm.dart';
import '../../data/models/risk_level.dart';
import '../notifications/notification_permission_sheet.dart';
import '../ocean/ocean_data_section.dart';
import 'farm_region_section.dart';
import 'onboarding_checklist_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
                  const FarmRegionSection(),
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

