import '../../logic/report_generator.dart';
import '../../models/ocean_reading.dart';
import '../../models/report.dart';
import '../../services/ocean_service.dart';
import '../farm_repository.dart';
import '../memo_repository.dart';
import '../report_repository.dart';

class MockReportRepository implements ReportRepository {
  MockReportRepository({
    required this._farmRepository,
    required this._memoRepository,
    required this._oceanService,
  });

  final FarmRepository _farmRepository;
  final MemoRepository _memoRepository;
  final OceanService _oceanService;

  final Map<String, Report> _latestByFarm = {};
  final Map<String, List<Report>> _historyByFarm = {};

  @override
  Future<Report?> getLatestReport(String farmId) async {
    return _latestByFarm[farmId] ?? generateReport(farmId);
  }

  @override
  Future<Report> generateReport(String farmId) async {
    final farm = await _farmRepository.getFarm(farmId);
    if (farm == null) {
      throw Exception('양식장을 찾을 수 없습니다: $farmId');
    }

    final memos = await _memoRepository.watchMemos(farmId: farmId).first;

    OceanSnapshot? oceanSnapshot;
    try {
      oceanSnapshot = await _oceanService.fetchSnapshot(
        stationCode: farm.nearestStationCode,
        stationName: farm.nearestStationName,
        region: farm.region,
      );
    } catch (_) {
      oceanSnapshot = null;
    }

    final report = ReportGenerator.generate(
      farm: farm,
      farmMemos: memos,
      ocean: oceanSnapshot,
      now: DateTime.now(),
    );
    _latestByFarm[farmId] = report;
    _historyByFarm.putIfAbsent(farmId, () => []).insert(0, report);
    return report;
  }

  @override
  Future<List<Report>> listReports(String farmId) async {
    await getLatestReport(farmId); // 한 번도 안 만들어졌다면 첫 리포트를 만든다
    return List.unmodifiable(_historyByFarm[farmId] ?? const <Report>[]);
  }

  @override
  Future<List<Report>> listLatestReports({required List<String> farmIds}) async {
    final reports = <Report>[];
    for (final id in farmIds) {
      final report = await getLatestReport(id);
      if (report != null) reports.add(report);
    }
    return reports;
  }
}
