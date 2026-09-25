import 'risk_level.dart';
import '../repositories/share_link_repository.dart';

enum OverallLevel {
  good,
  watch,
  urgent;

  static OverallLevel fromRisk(RiskLevel level) => switch (level) {
        RiskLevel.danger => OverallLevel.urgent,
        RiskLevel.warning => OverallLevel.watch,
        RiskLevel.good => OverallLevel.good,
      };

  String get label => switch (this) {
        OverallLevel.good => '양호',
        OverallLevel.watch => '관찰 필요',
        OverallLevel.urgent => '긴급',
      };
}

class ReportMetric {
  const ReportMetric({required this.label, required this.value, required this.unit, required this.note});

  final String label;
  final String value;
  final String unit;
  final String note;
}

class FlaggedPhoto {
  const FlaggedPhoto({required this.url, required this.label, required this.needsAttention});

  /// Empty string renders a placeholder tile.
  final String url;
  final String label;
  final bool needsAttention;
}

class ReportAction {
  const ReportAction({required this.id, required this.title, required this.sub, required this.done});

  final String id;
  final String title;
  final String sub;
  final bool done;

  ReportAction copyWith({bool? done}) => ReportAction(id: id, title: title, sub: sub, done: done ?? this.done);
}

/// Read-only shape rendered by the farm-side shared report page
/// (`/r/:token`). Mirrors the `report` prop in the design spec.
class SharedReportView {
  const SharedReportView({
    required this.farmName,
    required this.species,
    required this.orgName,
    required this.sharedAt,
    required this.level,
    required this.summary,
    required this.metrics,
    required this.flaggedPhotos,
    required this.diagnosis,
    required this.actions,
    required this.contactPhone,
    this.videoUrl,
    this.videoDuration,
  });

  final String farmName;
  final String species;
  final String orgName;
  final DateTime sharedAt;
  final OverallLevel level;
  final String summary;
  final List<ReportMetric> metrics;
  final List<FlaggedPhoto> flaggedPhotos;
  final String diagnosis;
  final List<ReportAction> actions;
  final String? videoUrl;
  final String? videoDuration;
  final String? contactPhone;

  /// Parses the `shared` object of `GET /api/public/reports/:token`.
  factory SharedReportView.fromJson(Map<String, dynamic> json) {
    final status = json['overallStatus'] as Map<String, dynamic>;
    return SharedReportView(
      farmName: json['farmName'] as String,
      species: json['species'] as String? ?? '',
      orgName: json['orgName'] as String? ?? '',
      sharedAt: DateTime.parse(json['sharedAt'] as String).toLocal(),
      level: OverallLevel.values.byName(status['level'] as String),
      summary: status['summary'] as String,
      metrics: [
        for (final m in json['metrics'] as List<dynamic>)
          ReportMetric(
            label: (m as Map<String, dynamic>)['label'] as String,
            value: m['value'] as String,
            unit: m['unit'] as String,
            note: m['note'] as String,
          ),
      ],
      flaggedPhotos: [
        for (final p in json['flaggedPhotos'] as List<dynamic>)
          FlaggedPhoto(
            url: (p as Map<String, dynamic>)['url'] as String? ?? '',
            label: p['label'] as String,
            needsAttention: p['needsAttention'] as bool? ?? false,
          ),
      ],
      diagnosis: json['diagnosis'] as String,
      actions: [
        for (final a in json['actions'] as List<dynamic>)
          ReportAction(
            id: (a as Map<String, dynamic>)['id'] as String,
            title: a['title'] as String,
            sub: a['sub'] as String? ?? '',
            done: a['done'] as bool,
          ),
      ],
      videoUrl: json['videoUrl'] as String?,
      videoDuration: json['videoDuration'] as String?,
      contactPhone: json['contactPhone'] as String?,
    );
  }

  /// Fallback for sources that don't provide `shared` (e.g. the mock
  /// repository): derives what it can from the report and fills the rest
  /// with clearly-marked example values.
  static const _placeholderOrgName = '해강 수산질병관리원';
  static const _placeholderOrgPhone = '061-000-0000';

  factory SharedReportView.fromBundle(SharedReportBundle bundle, {bool withExamples = false}) {
    final farm = bundle.farm;
    final report = bundle.report;
    return SharedReportView(
      farmName: farm.name,
      species: '',
      orgName: _placeholderOrgName,
      sharedAt: bundle.link.createdAt,
      level: OverallLevel.fromRisk(report.riskLevel),
      summary: report.headline,
      metrics: [
        ReportMetric(label: '주간 폐사', value: '${report.weeklyMortality}', unit: '마리', note: '최근 7일 누적'),
        ReportMetric(label: '평균 수온', value: report.avgTemp.toStringAsFixed(1), unit: '℃', note: report.periodLabel),
        ReportMetric(label: '최근 방문', value: '${report.lastVisitDays}', unit: '일 전', note: farm.assignedMemberName ?? '담당 관리사'),
        ReportMetric(label: '현재 수온', value: farm.waterTemp.toStringAsFixed(1), unit: '℃', note: farm.nearestStationName),
      ],
      flaggedPhotos: withExamples
          ? const [
              FlaggedPhoto(url: '', label: '아가미 색 변화', needsAttention: true),
              FlaggedPhoto(url: '', label: '표피 상태', needsAttention: false),
            ]
          : const [],
      diagnosis: [report.summary, ...report.findings.map((f) => '• $f')].join('\n'),
      actions: [
        for (var i = 0; i < report.followUps.length; i++)
          ReportAction(id: 'followup-$i', title: report.followUps[i], sub: '', done: false),
      ],
      videoUrl: withExamples ? 'https://example.com/videos/demo-field.mp4' : null,
      videoDuration: withExamples ? '3분 42초' : null,
      contactPhone: _placeholderOrgPhone,
    );
  }
}
