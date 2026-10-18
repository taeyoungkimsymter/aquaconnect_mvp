import '../models/news_item.dart';

abstract class NewsRepository {
  /// 최신순(원문 게시일) 목록의 [page]쪽(1부터). [category]가 null이면 전체.
  Future<NewsPage> listNews({NewsCategory? category, int page = 1});

  /// 소식 한 건. 삭제됐거나 게시가 중단(숨김)됐으면 null, 네트워크 오류는 예외.
  Future<NewsItem?> getNews(String id);
}
