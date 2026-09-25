import 'dart:math';

import '../../models/share_link.dart';
import '../../models/shared_report_view.dart';
import '../farm_repository.dart';
import '../report_repository.dart';
import '../share_link_repository.dart';

class MockShareLinkRepository implements ShareLinkRepository {
  MockShareLinkRepository({
    required FarmRepository farmRepository,
    required ReportRepository reportRepository,
  })  : _farmRepository = farmRepository,
        _reportRepository = reportRepository;

  final FarmRepository _farmRepository;
  final ReportRepository _reportRepository;

  // A fixed, never-expiring demo link so `/r/demo` always works in mock
  // mode without first walking through the create-link flow — handy for
  // trying the public SharedReportWeb page on its own.
  final List<ShareLink> _links = [
    ShareLink(id: 'link-demo', farmId: 'farm-sinil-1', token: 'demo', createdAt: DateTime.now()),
  ];

  static const _tokenChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final _random = Random();

  String _newToken() => List.generate(6, (_) => _tokenChars[_random.nextInt(_tokenChars.length)]).join();

  @override
  Future<ShareLink> createShareLink({required String farmId, required ShareLinkExpiry expiry}) async {
    final now = DateTime.now();
    final link = ShareLink(
      id: 'link-${now.microsecondsSinceEpoch}',
      farmId: farmId,
      token: _newToken(),
      createdAt: now,
      expiresAt: expiry.expiresAtFrom(now),
    );
    _links.insert(0, link);
    return link;
  }

  @override
  Future<List<ShareLink>> listShareLinks({String? farmId}) async {
    return _links.where((l) => farmId == null || l.farmId == farmId).toList();
  }

  @override
  Future<SharedReportBundle?> resolveToken(String token) async {
    ShareLink? link;
    for (final l in _links) {
      if (l.token == token) {
        link = l;
        break;
      }
    }
    if (link == null || !link.isActive) return null;

    final farm = await _farmRepository.getFarm(link.farmId);
    if (farm == null) return null;

    final report = await _reportRepository.getLatestReport(link.farmId);
    if (report == null) return null;

    final bundle = SharedReportBundle(farm: farm, report: report, link: link);
    return SharedReportBundle(
      farm: farm,
      report: report,
      link: link,
      view: SharedReportView.fromBundle(bundle, withExamples: true),
    );
  }

  @override
  Future<void> setActionDone({required String token, required String actionId, required bool done}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<void> sendInquiry({required String token, required String message}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
