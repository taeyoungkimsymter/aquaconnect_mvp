import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/disease_info.dart';
import '../../data/models/news_item.dart';
import '../../data/models/farm.dart';
import '../../data/models/memo.dart';
import '../../data/models/ocean_reading.dart';
import '../../data/models/org_member.dart';
import '../../data/models/report.dart';
import '../../data/models/share_link.dart';
import '../../data/services/ocean_service.dart';
import 'repository_providers.dart';

/// Org roster, used by the memo composer's '/' assignee menu.
final orgMembersProvider = FutureProvider<List<OrgMember>>((ref) {
  return ref.watch(orgRepositoryProvider).listMembers();
});

final farmsProvider = FutureProvider<List<Farm>>((ref) {
  return ref.watch(farmRepositoryProvider).listFarms();
});

final farmByIdProvider = FutureProvider.family<Farm?, String>((ref, farmId) {
  return ref.watch(farmRepositoryProvider).getFarm(farmId);
});

final memosProvider = StreamProvider.family<List<Memo>, String?>((ref, farmId) {
  return ref.watch(memoRepositoryProvider).watchMemos(farmId: farmId);
});

/// A single memo by id (null = deleted / not accessible). autoDispose so each
/// open re-fetches and picks up deletions.
final memoByIdProvider = FutureProvider.autoDispose.family<Memo?, String>((ref, id) {
  return ref.watch(memoRepositoryProvider).getMemo(id);
});

/// Bytes of one 댓글 attachment (photo or file). Kept, like memo photos, so
/// reopening the thread doesn't re-download them.
typedef CommentAttachmentKey = ({String memoId, String commentId, String attachmentId});

final commentAttachmentProvider = FutureProvider.family<Uint8List, CommentAttachmentKey>((ref, key) {
  return ref.watch(memoRepositoryProvider).loadCommentAttachment(
        memoId: key.memoId,
        commentId: key.commentId,
        attachmentId: key.attachmentId,
      );
});

/// Bytes for one memo photo. Kept (not autoDispose) so scrolling back to a
/// memo doesn't re-download its thumbnails.
final memoPhotoProvider = FutureProvider.family<Uint8List, String>((ref, photoId) {
  return ref.watch(memoRepositoryProvider).loadPhoto(photoId);
});

/// 수산 뉴스 한 건(null = 삭제되었거나 게시 중단). 열 때마다 새로 조회합니다.
final newsItemProvider = FutureProvider.autoDispose.family<NewsItem?, String>((ref, id) {
  return ref.watch(newsRepositoryProvider).getNews(id);
});

final diseaseInfoProvider = FutureProvider<List<DiseaseInfo>>((ref) {
  return ref.watch(diseaseInfoRepositoryProvider).listDiseaseInfo();
});

final reportProvider = FutureProvider.family<Report?, String>((ref, farmId) {
  return ref.watch(reportRepositoryProvider).getLatestReport(farmId);
});

final allReportsProvider = FutureProvider<List<Report>>((ref) async {
  final farms = await ref.watch(farmsProvider.future);
  return ref.watch(reportRepositoryProvider).listLatestReports(farmIds: farms.map((f) => f.id).toList());
});

/// Every share link issued by the org (active or not), newest first.
final shareLinksProvider = FutureProvider<List<ShareLink>>((ref) {
  return ref.watch(shareLinkRepositoryProvider).listShareLinks();
});

/// Every station selectable as a "바다 위치" from MyPage / Info, surface-only
/// ('표층') stations included, with official coordinates where recorded.
final oceanStationsProvider = FutureProvider<List<OceanStation>>((ref) {
  return ref.watch(oceanServiceProvider).fetchStations();
});

/// All current readings (표층 → 중층 → 저층) for the MyPage-selected "바다
/// 위치" station. Empty when no station is selected yet.
final selectedStationReadingsProvider = FutureProvider<List<OceanObservation>>((ref) async {
  final selection = await ref.watch(selectedOceanStationProvider.future);
  if (selection == null) return const [];
  final observations = await ref.watch(oceanServiceProvider).fetchRealtime(station: selection.code);
  final withTemp = observations.where((o) => o.waterTempC != null && o.stationCode == selection.code);
  final order = sortLayersTopDown(withTemp.map((o) => o.layer).toSet());
  return [for (final layer in order) withTemp.firstWhere((o) => o.layer == layer)];
});

/// 염도·용존산소 averaged over the nearest 어장환경 survey of every station
/// the org's farms are linked to, for the AllReport stat grid. The status is
/// noneNearby only when every station lacks a survey point within 50km.
final fleetWaterQualityProvider =
    FutureProvider<({double? salinity, double? dissolvedOxygen, WaterQualityStatus status})>((ref) async {
  final farms = await ref.watch(farmsProvider.future);
  final service = ref.watch(oceanServiceProvider);
  final codes = {for (final f in farms) if (f.nearestStationCode.isNotEmpty) f.nearestStationCode};
  final results = await Future.wait(codes.map((code) => resolveWaterQuality(service.fetchWaterQuality(code))));

  double? average(String key) {
    final values = [for (final (q, _) in results) ?q?.value(key)];
    return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  }

  final status = results.any((r) => r.$2 == WaterQualityStatus.available)
      ? WaterQualityStatus.available
      : results.isNotEmpty && results.every((r) => r.$2 == WaterQualityStatus.noneNearby)
          ? WaterQualityStatus.noneNearby
          : WaterQualityStatus.unavailable;
  return (salinity: average('salinity'), dissolvedOxygen: average('dissolvedOxygen'), status: status);
});
