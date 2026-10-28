import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/ai_report_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/disease_info_repository.dart';
import '../../data/repositories/farm_repository.dart';
import '../../data/repositories/memo_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/org_repository.dart';
import '../../data/repositories/mock/mock_ai_report_repository.dart';
import '../../data/repositories/mock/mock_auth_repository.dart';
import '../../data/repositories/mock/mock_disease_info_repository.dart';
import '../../data/repositories/mock/mock_farm_repository.dart';
import '../../data/repositories/mock/mock_memo_repository.dart';
import '../../data/repositories/mock/mock_notification_repository.dart';
import '../../data/repositories/mock/mock_org_repository.dart';
import '../../data/repositories/mock/mock_report_repository.dart';
import '../../data/repositories/mock/mock_share_link_repository.dart';
import '../../data/repositories/remote/remote_ai_report_repository.dart';
import '../../data/repositories/remote/remote_auth_repository.dart';
import '../../data/repositories/remote/remote_disease_info_repository.dart';
import '../../data/repositories/remote/remote_farm_repository.dart';
import '../../data/repositories/remote/remote_memo_repository.dart';
import '../../data/repositories/remote/remote_notification_repository.dart';
import '../../data/repositories/remote/remote_org_repository.dart';
import '../../data/repositories/remote/remote_report_repository.dart';
import '../../data/repositories/remote/remote_share_link_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/share_link_repository.dart';
import '../../data/services/api_client.dart';
import '../../data/services/auth_token_store.dart';
import '../../data/services/location_service.dart';
import '../../data/services/digest_settings_store.dart';
import '../../data/services/mock_ocean_service.dart';
import '../../data/services/ocean_service.dart';
import '../../data/services/ocean_station_preference_store.dart';
import '../../data/services/railway_ocean_service.dart';
import '../../data/services/web_push_service.dart';
import '../config/env.dart';

// `Env.useMock` (default true) picks between the in-memory mock_*
// repositories — fully clickable with zero backend — and the remote_*
// ones backed by the `server/` API. Both implement the same interfaces
// (lib/data/repositories/*.dart) so nothing above this layer cares which
// is active.

final authTokenStoreProvider = Provider<AuthTokenStore>((ref) => AuthTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStore: ref.watch(authTokenStoreProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Env.useMock) return MockAuthRepository();
  return RemoteAuthRepository(apiClient: ref.watch(apiClientProvider), tokenStore: ref.watch(authTokenStoreProvider));
});

final farmRepositoryProvider = Provider<FarmRepository>((ref) {
  if (Env.useMock) return MockFarmRepository();
  return RemoteFarmRepository(apiClient: ref.watch(apiClientProvider));
});

final memoRepositoryProvider = Provider<MemoRepository>((ref) {
  if (Env.useMock) return MockMemoRepository();
  return RemoteMemoRepository(apiClient: ref.watch(apiClientProvider));
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  if (Env.useMock) return MockNotificationRepository();
  return RemoteNotificationRepository(apiClient: ref.watch(apiClientProvider));
});

final orgRepositoryProvider = Provider<OrgRepository>((ref) {
  if (Env.useMock) return MockOrgRepository(authRepository: ref.watch(authRepositoryProvider));
  return RemoteOrgRepository(apiClient: ref.watch(apiClientProvider));
});

final webPushServiceProvider = Provider<WebPushService>((ref) => WebPushService());

final diseaseInfoRepositoryProvider = Provider<DiseaseInfoRepository>((ref) {
  if (Env.useMock) return MockDiseaseInfoRepository();
  return RemoteDiseaseInfoRepository(apiClient: ref.watch(apiClientProvider));
});

final oceanServiceProvider = Provider<OceanService>((ref) {
  if (Env.useMock) return MockOceanService();
  return RailwayOceanService(baseUrl: Env.apiBaseUrl);
});

final oceanStationPreferenceStoreProvider = Provider<OceanStationPreferenceStore>((ref) {
  return OceanStationPreferenceStore();
});

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// The MyPage-selected "바다 위치" (sea location), loaded from local storage
/// on first watch. Null means the user hasn't picked one yet.
final selectedOceanStationProvider =
    AsyncNotifierProvider<SelectedOceanStationNotifier, OceanStationSelection?>(SelectedOceanStationNotifier.new);

class SelectedOceanStationNotifier extends AsyncNotifier<OceanStationSelection?> {
  @override
  Future<OceanStationSelection?> build() {
    return ref.watch(oceanStationPreferenceStoreProvider).read();
  }

  Future<void> select(OceanStationSelection selection) async {
    await ref.read(oceanStationPreferenceStoreProvider).write(selection);
    state = AsyncValue.data(selection);
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  if (Env.useMock) {
    return MockReportRepository(
      farmRepository: ref.watch(farmRepositoryProvider),
      memoRepository: ref.watch(memoRepositoryProvider),
      oceanService: ref.watch(oceanServiceProvider),
    );
  }
  return RemoteReportRepository(apiClient: ref.watch(apiClientProvider));
});

final aiReportRepositoryProvider = Provider<AiReportRepository>((ref) {
  if (Env.useMock) return MockAiReportRepository();
  return RemoteAiReportRepository(apiClient: ref.watch(apiClientProvider));
});

final shareLinkRepositoryProvider = Provider<ShareLinkRepository>((ref) {
  if (Env.useMock) {
    return MockShareLinkRepository(
      farmRepository: ref.watch(farmRepositoryProvider),
      reportRepository: ref.watch(reportRepositoryProvider),
    );
  }
  return RemoteShareLinkRepository(apiClient: ref.watch(apiClientProvider));
});

final authStateProvider = StreamProvider<AuthSession?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});

final digestSettingsStoreProvider = Provider<DigestSettingsStore>((ref) {
  if (Env.useMock) return LocalDigestSettingsStore();
  return RemoteDigestSettingsStore(apiClient: ref.watch(apiClientProvider));
});

/// The signed-in member's "오늘의 업무 알림" (digest notification prefs). Read by
/// both the settings screen and the MyPage list row (for its "오후 4:00"
/// trailing value) so they always agree.
final digestSettingsProvider = AsyncNotifierProvider<DigestSettingsNotifier, DigestSettings>(DigestSettingsNotifier.new);

class DigestSettingsNotifier extends AsyncNotifier<DigestSettings> {
  // Chains every _update onto the previous one so two calls fired back to
  // back (e.g. two toggles tapped in quick succession) can't both read the
  // same stale `state.valueOrNull` and have the slower one clobber the
  // other's field change — each update now fully completes, including the
  // `state =` assignment, before the next one reads `current`.
  Future<void> _writeQueue = Future.value();

  @override
  Future<DigestSettings> build() {
    // Settings belong to the member, so reload when someone else signs in.
    ref.watch(authStateProvider.select((s) => s.valueOrNull?.member.id));
    return ref.watch(digestSettingsStoreProvider).read();
  }

  /// Throws if saving fails (the previous settings stay shown).
  Future<void> _update(DigestSettings Function(DigestSettings) transform) {
    final result = _writeQueue.then((_) async {
      final current = state.valueOrNull ?? await ref.read(digestSettingsStoreProvider).read();
      final saved = await ref.read(digestSettingsStoreProvider).write(transform(current));
      state = AsyncValue.data(saved);
    });
    // A failed save must not block every later one.
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> setDailyEnabled(bool enabled) => _update((s) => s.copyWith(dailyEnabled: enabled));

  Future<void> setDailyTime(TimeOfDay time) => _update((s) => s.copyWith(dailyTime: time));

  Future<void> setWeeklyEnabled(bool enabled) => _update((s) => s.copyWith(weeklyEnabled: enabled));
}
