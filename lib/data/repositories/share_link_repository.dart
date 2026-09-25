import '../models/farm.dart';
import '../models/report.dart';
import '../models/share_link.dart';
import '../models/shared_report_view.dart';

class SharedReportBundle {
  const SharedReportBundle({required this.farm, required this.report, required this.link, this.view});

  final Farm farm;
  final Report report;
  final ShareLink link;

  /// Farm-side page content. Null when the source does not provide it;
  /// [SharedReportView.fromBundle] is the fallback.
  final SharedReportView? view;
}

abstract class ShareLinkRepository {
  Future<ShareLink> createShareLink({required String farmId, required ShareLinkExpiry expiry});

  Future<List<ShareLink>> listShareLinks({String? farmId});

  /// Public lookup used by the unauthenticated `/r/:token` page. Returns
  /// null if the token is unknown, revoked, or expired.
  Future<SharedReportBundle?> resolveToken(String token);

  /// Persists a checklist toggle made by the farm on the shared page.
  Future<void> setActionDone({required String token, required String actionId, required bool done});

  /// Sends the farm's inquiry memo to the institute.
  Future<void> sendInquiry({required String token, required String message});
}
