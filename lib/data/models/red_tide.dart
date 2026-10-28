/// One organism found in one sea area in a NIFS 적조 속보.
class RedTideOccurrence {
  const RedTideOccurrence({
    required this.organism,
    required this.area,
    this.minDensity,
    this.maxDensity,
    this.minTemp,
    this.maxTemp,
  });

  /// Scientific name as NIFS reports it, e.g. "Cochlodinium polykrikoides".
  final String organism;
  final String area;

  /// 개체/mL.
  final double? minDensity;
  final double? maxDensity;
  final double? minTemp;
  final double? maxTemp;

  /// Korean common name for the usual 적조 organisms, else the scientific one.
  String get organismLabel {
    for (final e in _koreanNames.entries) {
      if (organism.startsWith(e.key)) return e.value;
    }
    return organism;
  }

  static const _koreanNames = {
    'Cochlodinium': '코클로디니움',
    'Margalefidinium': '코클로디니움',
    'Karenia': '카레니아',
    'Mesodinium': '메소디니움',
    'Akashiwo': '아카시오',
    'Scrippsiella': '스크립시엘라',
    'Chaetoceros': '키토세로스',
    'Skeletonema': '스켈레토네마',
    'Ceratium': '세라티움',
    'Heterosigma': '헤테로시그마',
    'Noctiluca': '야광충',
    'Prorocentrum': '프로로센트룸',
    'Alexandrium': '알렉산드리움',
  };

  factory RedTideOccurrence.fromJson(Map<String, dynamic> json) => RedTideOccurrence(
        organism: json['organism'] as String? ?? '',
        area: json['area'] as String? ?? '',
        minDensity: (json['minDensity'] as num?)?.toDouble(),
        maxDensity: (json['maxDensity'] as num?)?.toDouble(),
        minTemp: (json['minTemp'] as num?)?.toDouble(),
        maxTemp: (json['maxTemp'] as num?)?.toDouble(),
      );
}

/// One NIFS 적조 속보. The detail texts are only filled in for the newest
/// report ([RedTideInfo.latest]); each is newline-separated bullets.
class RedTideReport {
  const RedTideReport({
    required this.code,
    required this.reportDate,
    required this.occurrences,
    this.progress = '',
    this.breaking = '',
    this.outlook = '',
    this.request = '',
    this.reference = '',
  });

  final String code;

  /// 조사일 (a calendar day, local).
  final DateTime reportDate;
  final List<RedTideOccurrence> occurrences;

  /// 진행상황 / 특보상황 / 금후전망 / 당부사항 / 기타.
  final String progress;
  final String breaking;
  final String outlook;
  final String request;
  final String reference;

  factory RedTideReport.fromJson(Map<String, dynamic> json) {
    final d = (json['reportDate'] as String).split('-').map(int.parse).toList();
    return RedTideReport(
      code: json['code'] as String,
      reportDate: DateTime(d[0], d[1], d[2]),
      occurrences: (json['occurrences'] as List<dynamic>? ?? const [])
          .map((e) => RedTideOccurrence.fromJson(e as Map<String, dynamic>))
          .toList(),
      progress: json['progress'] as String? ?? '',
      breaking: json['breaking'] as String? ?? '',
      outlook: json['outlook'] as String? ?? '',
      request: json['request'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
    );
  }
}

/// `GET /api/ocean/redtide`: the newest 속보 plus the recent ones.
class RedTideInfo {
  const RedTideInfo({required this.latest, required this.recent, required this.fetchedAt});

  /// Null when NIFS has published nothing in the past year.
  final RedTideReport? latest;
  final List<RedTideReport> recent;
  final DateTime fetchedAt;

  /// NIFS issues a 속보 every day while a red tide is under way, so a report
  /// from the last few days means one is still going on.
  static const activeWithinDays = 3;

  int? get daysSinceLatest {
    final latest = this.latest;
    if (latest == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).difference(latest.reportDate).inDays;
  }

  bool get isActive => (daysSinceLatest ?? 999) <= activeWithinDays;

  /// A 주의보/경보 is in force per the newest 특보 text (and the report is current).
  bool get hasAdvisory {
    if (!isActive) return false;
    final text = latest!.breaking;
    if (text.contains('전면 해제')) return false;
    return text.contains('주의보') || text.contains('경보');
  }

  factory RedTideInfo.fromJson(Map<String, dynamic> json) => RedTideInfo(
        latest: json['latest'] == null ? null : RedTideReport.fromJson(json['latest'] as Map<String, dynamic>),
        recent: (json['recent'] as List<dynamic>? ?? const [])
            .map((e) => RedTideReport.fromJson(e as Map<String, dynamic>))
            .toList(),
        fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}
