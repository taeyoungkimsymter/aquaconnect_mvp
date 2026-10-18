import '../../models/news_item.dart';
import '../../services/api_client.dart';
import '../news_repository.dart';

class RemoteNewsRepository implements NewsRepository {
  RemoteNewsRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  static const pageSize = 20;

  @override
  Future<NewsPage> listNews({NewsCategory? category, int page = 1}) async {
    final json = await _api.get('/api/news', query: {
      if (category != null) 'category': category.key,
      'page': '$page',
      'pageSize': '$pageSize',
    }) as Map<String, dynamic>;
    return NewsPage.fromJson(json);
  }

  @override
  Future<NewsItem?> getNews(String id) async {
    try {
      final json = await _api.get('/api/news/${Uri.encodeComponent(id)}') as Map<String, dynamic>;
      return NewsItem.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
