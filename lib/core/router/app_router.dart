import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/memo/memo_screen.dart';
import '../../features/mypage/change_history_screen.dart';
import '../../features/mypage/daily_summary_settings_screen.dart';
import '../../features/mypage/farm_group_screen.dart';
import '../../features/mypage/farm_management_screen.dart';
import '../../features/mypage/invite_accept_screen.dart';
import '../../features/mypage/member_management_screen.dart';
import '../../features/mypage/mypage_screen.dart';
import '../../features/mypage/organization_info_screen.dart';
import '../../features/mypage/share_link_management_screen.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/reports/ai_report_list_screen.dart';
import '../../features/reports/ai_report_screen.dart';
import '../../features/reports/all_report_screen.dart';
import '../../features/reports/report_detail_screen.dart';
import '../../features/reports/shared_report_web_screen.dart';
import '../providers/repository_providers.dart';
import '../widgets/app_shell.dart';

/// Re-runs GoRouter's redirect logic whenever the auth stream emits, without
/// rebuilding the router itself (which would otherwise drop navigation state).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Bottom-tab (StatefulShellRoute branch) locations.
const _tabPaths = {'/', '/memo', '/calendar', '/mypage'};

/// Opens an in-app link from a notification. Tab locations are `go`ne to:
/// `push`ing one from a full-screen page (the 알림함) lands it inside the
/// shell *underneath* that page, so nothing would seem to happen.
void openAppLink(GoRouter router, String link) {
  if (_tabPaths.contains(Uri.parse(link).path)) {
    router.go(link);
  } else {
    router.push(link);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final refreshStream = GoRouterRefreshStream(authRepository.authStateChanges());
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final loggedIn = authRepository.currentSession != null;
      final path = state.matchedLocation;

      final isAuthPage = path == '/login' || path == '/signup';
      // /invite/<code> stays reachable when signed in, to say so on the page.
      final isPublic = isAuthPage || path.startsWith('/r/') || path.startsWith('/invite/');
      // Keep where we were headed (e.g. a push notification's link opened
      // while the app was closed — the session is still being restored) so
      // signing in lands there instead of on Home.
      if (!loggedIn && !isPublic) {
        final target = state.uri.toString();
        return target == '/' ? '/login' : '/login?from=${Uri.encodeComponent(target)}';
      }
      // Covers finishing signup too: the new account is signed in, so Home.
      if (loggedIn && isAuthPage) {
        final from = state.uri.queryParameters['from'];
        final safe = from != null && from.startsWith('/') && !from.startsWith('//') && !from.startsWith('/login');
        return safe ? from : '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
        path: '/r/:token',
        builder: (context, state) => SharedReportWebScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const AllReportScreen(),
      ),
      GoRoute(
        path: '/reports/:farmId/farm-report',
        builder: (context, state) => SharedReportWebScreen.preview(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/reports/:farmId/ai',
        builder: (context, state) => AiReportListScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/reports/:farmId/ai/new',
        builder: (context, state) => AiReportCreateScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/ai-reports/:id',
        builder: (context, state) => AiReportScreen(reportId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reports/:farmId',
        builder: (context, state) => ReportDetailScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/mypage/farms',
        builder: (context, state) => const FarmManagementScreen(),
      ),
      GoRoute(
        path: '/mypage/farm-groups',
        builder: (context, state) => const FarmGroupScreen(),
      ),
      GoRoute(
        path: '/mypage/members',
        builder: (context, state) => const MemberManagementScreen(),
      ),
      GoRoute(
        path: '/mypage/history',
        builder: (context, state) => const ChangeHistoryScreen(),
      ),
      GoRoute(
        path: '/mypage/organization',
        builder: (context, state) => const OrganizationInfoScreen(),
      ),
      GoRoute(
        path: '/mypage/share-links',
        builder: (context, state) => const ShareLinkManagementScreen(),
      ),
      GoRoute(
        path: '/mypage/daily-summary',
        builder: (context, state) => const DailySummarySettingsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/mypage/notifications',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/invite/:code',
        builder: (context, state) => InviteAcceptScreen(code: state.pathParameters['code']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/memo',
            // ?memo=<id>[&comments=1]: opened from a memo/comment notification;
            // ?view=today: from the 오늘의 업무 notification.
            builder: (context, state) => MemoScreen(
              focusMemoId: state.uri.queryParameters['memo'],
              openComments: state.uri.queryParameters['comments'] == '1',
              view: state.uri.queryParameters['view'],
            ),
          )]),
          // The 정보 tab (features/info) gave way to 캘린더; it's kept for a
          // later 정보/AquaInfo tab.
          StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (context, state) => const CalendarScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/mypage', builder: (context, state) => const MyPageScreen())]),
        ],
      ),
    ],
  );
});
