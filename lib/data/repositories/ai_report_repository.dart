import '../models/ai_report.dart';

abstract class AiReportRepository {
  /// Whether the server has an AI model configured (never exposes the key).
  Future<AiModelStatus> status();

  /// The farm's AI reports, newest first (summaries — no body).
  Future<List<AiReport>> listForFarm(String farmId);

  Future<AiReport> getReport(String id);

  /// Asks the AI for a new draft from the farm's memos between [from] and
  /// [to] (KST dates, inclusive). [memoIds] null means every memo in range;
  /// [model] null uses the server's default model.
  Future<AiReport> generate({
    required String farmId,
    required String from,
    required String to,
    List<String>? memoIds,
    bool includeComments = true,
    String? model,
  });

  Future<AiReport> updateBody(String id, String body);

  Future<AiReport> setConfirmed(String id, {required bool confirmed});

  Future<void> delete(String id);
}
