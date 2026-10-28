import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/farm_group_provider.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/notification_providers.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import 'daily_summary_settings_screen.dart';
import 'ocean_station_picker_sheet.dart';

class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authStateProvider).valueOrNull;
    final farmsAsync = ref.watch(farmsProvider);
    final selectedStation = ref.watch(selectedOceanStationProvider).valueOrNull;
    final readingsAsync = ref.watch(selectedStationReadingsProvider);
    final digestSettings = ref.watch(digestSettingsProvider).valueOrNull;
    final shareLinksAsync = ref.watch(shareLinksProvider);
    final pushStatus = ref.watch(pushStatusProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
              child: const Text('마이페이지', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  InkWell(
                    onTap: () => context.push('/mypage/organization'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
                          child: const Icon(Icons.person_outline, size: 26, color: AppColors.brand),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(session?.member.name ?? '-',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                  const SizedBox(width: 6),
                                  if (session?.member.isOwner == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(20)),
                                      child: const Text('소유자', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(session?.organization.name ?? '-',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 14, color: AppColors.neutralArrow),
                      ],
                    ),
                  ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('관리원 관리'),
                  const SizedBox(height: 8),
                  _MenuGroup(items: [
                    _MenuItem(
                      icon: Icons.groups_outlined,
                      label: '구성원 관리',
                      onTap: () => context.push('/mypage/members'),
                    ),
                    _MenuItem(
                      icon: Icons.home_work_outlined,
                      label: '등록 양식장 관리',
                      trailing: farmsAsync.maybeWhen(data: (f) => '${f.length}곳', orElse: () => ''),
                      onTap: () => context.push('/mypage/farms'),
                    ),
                    _MenuItem(
                      icon: Icons.folder_copy_outlined,
                      label: '양식장 그룹 관리',
                      trailing: ref.watch(farmListPrefsProvider).maybeWhen(
                            data: (p) => p.groups.isEmpty ? '' : '${p.groups.length}개',
                            orElse: () => '',
                          ),
                      onTap: () => context.push('/mypage/farm-groups'),
                    ),
                    _MenuItem(
                      icon: Icons.history,
                      label: '변경 이력',
                      trailing: '최근 3개월',
                      onTap: () => context.push('/mypage/history'),
                    ),
                    _MenuItem(
                      icon: Icons.link,
                      label: '공유 링크 관리',
                      trailing: shareLinksAsync.maybeWhen(
                        data: (links) => '열람 가능 ${links.where((l) => l.isActive).length}건',
                        orElse: () => '',
                      ),
                      onTap: () => context.push('/mypage/share-links'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _SectionLabel('개인 설정'),
                  const SizedBox(height: 8),
                  _MenuGroup(items: [
                    _MenuItem(
                      icon: Icons.water_outlined,
                      label: '바다 위치 (수온 관측소)',
                      trailing: selectedStation?.name ?? '미설정',
                      subtitle: selectedStation == null
                          ? null
                          : readingsAsync.when(
                              data: (readings) => readings.isEmpty
                                  ? '수온 정보 없음'
                                  : readings.map((o) => '${o.layer} ${o.waterTempC!.toStringAsFixed(1)}℃').join(' · '),
                              loading: () => '수온 불러오는 중…',
                              error: (_, _) => '수온을 불러오지 못했어요',
                            ),
                      onTap: () => showOceanStationPickerSheet(context),
                    ),
                    _MenuItem(
                      icon: Icons.checklist_rtl,
                      label: '오늘의 업무 알림',
                      trailing: digestSettings == null
                          ? ''
                          : (digestSettings.dailyEnabled ? formatKoreanTime(digestSettings.dailyTime) : '꺼짐'),
                      onTap: () => context.push('/mypage/daily-summary'),
                    ),
                    _MenuItem(
                      icon: Icons.notifications_none,
                      label: '알림 설정',
                      trailing: pushStatus == null ? '' : (pushStatus.enabled ? '켜짐' : '꺼짐'),
                      onTap: () => context.push('/mypage/notifications'),
                    ),
                    const _MenuItem(icon: Icons.file_download_outlined, label: '데이터 내보내기'),
                    _MenuItem(
                      icon: Icons.help_outline,
                      label: '사용 가이드 다시 보기',
                      onTap: () async {
                        await ref.read(onboardingProvider.notifier).reset();
                        if (context.mounted) context.go('/');
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        await ref.read(pushControllerProvider).detachBeforeSignOut();
                        await ref.read(authRepositoryProvider).signOut();
                      },
                      child: const Text('로그아웃', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.icon, required this.label, this.trailing, this.subtitle, this.onTap});
  final IconData icon;
  final String label;
  final String? trailing;
  final String? subtitle;
  final VoidCallback? onTap;
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: items[i].onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Icon(items[i].icon, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(items[i].label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          if (items[i].subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(items[i].subtitle!, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                          ],
                        ],
                      ),
                    ),
                    if (items[i].trailing != null) ...[
                      Text(items[i].trailing!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      const SizedBox(width: 6),
                    ],
                    const Icon(Icons.chevron_right, size: 13, color: AppColors.neutralArrow),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
