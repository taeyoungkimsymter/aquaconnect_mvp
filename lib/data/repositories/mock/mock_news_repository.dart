import '../../models/news_item.dart';
import '../news_repository.dart';

/// 모의 모드에는 수집 서버가 없으므로 뉴스가 없습니다 — 가짜 뉴스를 만들어 넣지 않고 빈 목록을 돌려줍니다.
class MockNewsRepository implements NewsRepository {
  @override
  Future<NewsPage> listNews({NewsCategory? category, int page = 1}) async => NewsPage.empty;

  @override
  Future<NewsItem?> getNews(String id) async => null;
}
