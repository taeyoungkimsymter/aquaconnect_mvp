import '../../models/ai_report.dart';
import '../../services/api_client.dart';
import '../ai_report_repository.dart';

class RemoteAiReportRepository implements AiReportRepository {
  RemoteAiReportRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<AiModelStatus> status() async {
    final json = await _api.get('/api/ai-reports/status') as Map<String, dynamic>;
    return AiModelStatus.fromJson(json);
  }

  @override
  Future<List<AiReport>> listForFarm(String farmId) async {
    final json = await _api.get('/api/ai-reports/farm/$farmId') as List<dynamic>;
    return json.map((e) => AiReport.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<AiReport> getReport(String id) async {
    final json = await _api.get('/api/ai-reports/$id') as Map<String, dynamic>;
    return AiReport.fromJson(json);
  }

  @override
  Future<AiReport> generate({
    required String farmId,
    required String from,
    required String to,
    List<String>? memoIds,
    bool includeComments = true,
    String? model,
  }) async {
    final json = await _api.post('/api/ai-reports/farm/$farmId', body: {
      'from': from,
      'to': to,
      'memoIds': ?memoIds,
      'includeComments': includeComments,
      'model': ?model,
    }) as Map<String, dynamic>;
    return AiReport.fromJson(json);
  }

  @override
  Future<AiReport> updateBody(String id, String body) async {
    final json = await _api.put('/api/ai-reports/$id', body: {'body': body}) as Map<String, dynamic>;
    return AiReport.fromJson(json);
  }

  @override
  Future<AiReport> setConfirmed(String id, {required bool confirmed}) async {
    final json = await _api.post('/api/ai-reports/$id/${confirmed ? 'confirm' : 'unconfirm'}') as Map<String, dynamic>;
    return AiReport.fromJson(json);
  }

  @override
  Future<void> delete(String id) async {
    await _api.delete('/api/ai-reports/$id');
  }
}
