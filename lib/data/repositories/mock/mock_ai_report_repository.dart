import '../../models/ai_report.dart';
import '../ai_report_repository.dart';

/// Mock mode has no AI model behind it. Per the symterAI rule, an
/// unconnected AI is shown as 미연결 — never answered with a fake draft.
class MockAiReportRepository implements AiReportRepository {
  static const _notConnected = '목업 모드에서는 AI가 연결되어 있지 않습니다.';

  @override
  Future<AiModelStatus> status() async => const AiModelStatus(configured: false, model: '', note: _notConnected);

  @override
  Future<List<AiReport>> listForFarm(String farmId) async => const [];

  @override
  Future<AiReport> getReport(String id) => throw Exception('AI 리포트를 찾을 수 없습니다.');

  @override
  Future<AiReport> generate({
    required String farmId,
    required String from,
    required String to,
    List<String>? memoIds,
    bool includeComments = true,
    String? model,
  }) =>
      throw Exception(_notConnected);

  @override
  Future<AiReport> updateBody(String id, String body) => throw Exception(_notConnected);

  @override
  Future<AiReport> setConfirmed(String id, {required bool confirmed}) => throw Exception(_notConnected);

  @override
  Future<void> delete(String id) async {}
}
