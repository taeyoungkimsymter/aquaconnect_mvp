import '../../models/farm.dart';
import '../../models/report.dart';
import '../../models/share_link.dart';
import '../../models/shared_report_view.dart';
import '../../services/api_client.dart';
import '../share_link_repository.dart';

class RemoteShareLinkRepository implements ShareLinkRepository {
  RemoteShareLinkRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  static const _expiryKey = {
    ShareLinkExpiry.sevenDays: '7d',
    ShareLinkExpiry.thirtyDays: '30d',
    ShareLinkExpiry.unlimited: 'unlimited',
  };

  @override
  Future<ShareLink> createShareLink({required String farmId, required ShareLinkExpiry expiry}) async {
    final json = await _api.post(
      '/api/share-links',
      body: {'farmId': farmId, 'expiry': _expiryKey[expiry]},
    ) as Map<String, dynamic>;
    return ShareLink.fromJson(json);
  }

  @override
  Future<List<ShareLink>> listShareLinks({String? farmId}) async {
    final json = await _api.get('/api/share-links', query: farmId == null ? null : {'farmId': farmId}) as List<dynamic>;
    return json.map((e) => ShareLink.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<SharedReportBundle?> resolveToken(String token) async {
    try {
      final json = await _api.get('/api/public/reports/$token') as Map<String, dynamic>;
      return SharedReportBundle(
        farm: Farm.fromJson(json['farm'] as Map<String, dynamic>),
        report: Report.fromJson(json['report'] as Map<String, dynamic>),
        link: ShareLink.fromJson(json['link'] as Map<String, dynamic>),
        view: json['shared'] == null ? null : SharedReportView.fromJson(json['shared'] as Map<String, dynamic>),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> setActionDone({required String token, required String actionId, required bool done}) async {
    await _api.patch('/api/public/reports/$token/actions/$actionId', body: {'done': done});
  }

  @override
  Future<void> sendInquiry({required String token, required String message}) async {
    await _api.post('/api/public/reports/$token/inquiries', body: {'message': message});
  }
}
