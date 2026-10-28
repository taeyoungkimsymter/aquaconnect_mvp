import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/data_providers.dart';
import '../providers/onboarding_provider.dart';
import '../theme/app_colors.dart';
import 'responsive_mobile_frame.dart';
import 'tutorial_overlay.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _memoTab = 1;
  static const _calendarTab = 2;

  static const _tabs = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: '홈'),
    (icon: Icons.edit_note_outlined, activeIcon: Icons.edit_note, label: '메모'),
    (icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, label: '캘린더'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: '마이페이지'),
  ];

  /// One-time intro shown the first time each tab is opened (after the
  /// welcome card). Same order as [_tabs].
  static const _intros = [
    (id: 'home', title: '홈', body: '맨 위 오늘의 업무에서 오늘 할 일을 먼저 확인하고, 담당 양식장과 바다 수온·적조 정보도 여기서 바로 봐요. 아래 입력창에서 메모를 남기고, 오른쪽 위 종 모양에서 알림을 확인해요.'),
    (id: 'memo', title: '메모', body: '맨 위 오늘의 업무에서 내가 할 일을 확인하고, 끝난 일은 메모 왼쪽 동그라미(✓)를 눌러 완료해요. 양식장은 오른쪽 위 선택 버튼으로 골라 봐요.'),
    (id: 'calendar', title: '캘린더', body: '메모가 날짜별로 모여 있어요. 완료한 일은 완료한 날, 아직인 일은 등록한 날에 보여요. 두 손가락으로 벌리거나 −/+ 버튼으로 확대·축소해요.'),
    (id: 'mypage', title: '마이페이지', body: '양식장·구성원 관리, 바다 위치, 알림·오늘의 업무 알림 설정은 여기에서 해요.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider).valueOrNull;
    final notifier = ref.read(onboardingProvider.notifier);
    final intro = _intros[navigationShell.currentIndex];
    // 메모 tab badge: what's left of my 오늘의 업무.
    final openTasks = ref.watch(myTodayTasksProvider)?.open.length ?? 0;

    Widget? overlay;
    if (onboarding != null && !onboarding.welcomeSeen) {
      overlay = TutorialOverlay(
        icon: Icons.waves,
        title: 'AquaConnect에 오신 걸 환영해요',
        body: '담당 양식장의 수온·질병 위험을 한눈에 확인하고, 리포트를 어가에 바로 공유해 보세요.',
        primaryLabel: '시작하기',
        onPrimary: notifier.markWelcomeSeen,
        onSkip: () async {
          for (final i in _intros) {
            await notifier.markCoachmarkSeen(i.id);
          }
          await notifier.markWelcomeSeen();
        },
      );
    } else if (onboarding != null && !onboarding.coachmarksSeen.contains(intro.id)) {
      overlay = TutorialOverlay(
        icon: _tabs[navigationShell.currentIndex].activeIcon,
        title: intro.title,
        body: intro.body,
        primaryLabel: '확인',
        onPrimary: () => notifier.markCoachmarkSeen(intro.id),
        pointsDown: true,
        // Tab i's center as an Alignment x. The card has a 24px side
        // margin, so the tab centers are pulled in a little to compensate.
        arrowX: (-1 + (2 * navigationShell.currentIndex + 1) / _tabs.length) * 1.12,
      );
    }

    // The calendar tab may use a wide window; the other tabs keep the
    // mobile-width column.
    return ResponsiveMobileFrame(
      maxWidth: navigationShell.currentIndex == _calendarTab ? 1280 : 480,
      child: Scaffold(
        body: Stack(children: [navigationShell, ?overlay]),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 9, bottom: 4),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  final selected = i == navigationShell.currentIndex;
                  final color = selected ? AppColors.brand : AppColors.textMuted;
                  return Expanded(
                    child: InkWell(
                      onTap: () => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TabIcon(
                            icon: selected ? tab.activeIcon : tab.icon,
                            color: color,
                            badge: i == _memoTab ? openTasks : 0,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab icon with an optional count pill on its top-right corner.
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, required this.color, this.badge = 0});

  final IconData icon;
  final Color color;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 21, color: color);
    if (badge <= 0) return iconWidget;
    return Semantics(
      label: '남은 업무 $badge건',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            top: -4,
            right: -10,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(fontSize: 9.5, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
