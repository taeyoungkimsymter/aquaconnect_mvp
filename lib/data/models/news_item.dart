/// 수산 뉴스 분류. [key]는 서버(`news_items.category`)와 같은 값입니다.
enum NewsCategory {
  disease('disease', '질병·방역'),
  environment('environment', '해양환경'),
  support('support', '지원사업'),
  policy('policy', '양식·정책');

  const NewsCategory(this.key, this.label);

  final String key;
  final String label;

  static NewsCategory? fromKey(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// 공식 기관(해양수산부·국립수산과학원) 소식 한 건. 원문 전체가 아니라 제목·출처·게시일·원문 링크와
/// 짧은 소개만 담습니다.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.sourceName,
    required this.title,
    required this.url,
    required this.category,
    this.publishedAt,
    this.summary,
    this.regions = const [],
    this.species = const [],
  });

  final String id;

  /// 출처 기관 이름 ("해양수산부" 등).
  final String sourceName;
  final String title;

  /// 공식 원문 주소.
  final String url;
  final NewsCategory category;

  /// 원문 게시일. 출처에서 확인되지 않으면 null — 임의로 오늘 날짜를 넣지 않습니다.
  final DateTime? publishedAt;

  /// 짧은 소개 — 있는 경우에만.
  final String? summary;
  final List<String> regions;
  final List<String> species;

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        id: json['id'] as String,
        sourceName: json['sourceName'] as String? ?? '',
        title: json['title'] as String,
        url: json['url'] as String,
        category: NewsCategory.fromKey(json['category'] as String?) ?? NewsCategory.policy,
        publishedAt: json['publishedAt'] == null ? null : DateTime.parse(json['publishedAt'] as String).toLocal(),
        summary: (json['summary'] as String?)?.trim().isEmpty ?? true ? null : (json['summary'] as String).trim(),
        regions: (json['regions'] as List<dynamic>? ?? const []).cast<String>(),
        species: (json['species'] as List<dynamic>? ?? const []).cast<String>(),
      );
}

/// 목록 한 쪽.
class NewsPage {
  const NewsPage({required this.items, required this.hasMore});

  static const empty = NewsPage(items: [], hasMore: false);

  final List<NewsItem> items;
  final bool hasMore;

  factory NewsPage.fromJson(Map<String, dynamic> json) => NewsPage(
        items: (json['items'] as List<dynamic>).map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}
