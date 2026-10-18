import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/info/info_screen.dart';
import '../../features/memo/memo_detail_screen.dart';
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
      if (!loggedIn && !isPublic) return '/login';
      // Covers finishing signup too: the new account is signed in, so Home.
      if (loggedIn && isAuthPage) return '/';
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
        path: '/memos/:memoId',
        builder: (context, state) => MemoDetailScreen(memoId: state.pathParameters['memoId']!),
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
          StatefulShellBranch(routes: [GoRoute(path: '/memo', builder: (context, state) => const MemoScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/info', builder: (context, state) => const InfoScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/mypage', builder: (context, state) => const MyPageScreen())]),
        ],
      ),
    ],
  );
});
