import '../../models/report.dart';
import '../../services/api_client.dart';
import '../report_repository.dart';

class RemoteReportRepository implements ReportRepository {
  RemoteReportRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<Report?> getLatestReport(String farmId) async {
    try {
      final json = await _api.get('/api/reports/$farmId') as Map<String, dynamic>;
      return Report.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Report>> listReports(String farmId) async {
    final json = await _api.get('/api/reports/$farmId/history') as List<dynamic>;
    return json.map((e) => Report.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Report> generateReport(String farmId) async {
    final json = await _api.post('/api/reports/$farmId/generate') as Map<String, dynamic>;
    return Report.fromJson(json);
  }

  @override
  Future<List<Report>> listLatestReports({required List<String> farmIds}) async {
    if (farmIds.isEmpty) return [];
    final json = await _api.get('/api/reports', query: {'farmIds': farmIds.join(',')}) as List<dynamic>;
    return json.map((e) => Report.fromJson(e as Map<String, dynamic>)).toList();
  }
}
