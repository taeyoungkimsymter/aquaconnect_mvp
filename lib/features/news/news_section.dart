import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../data/models/news_item.dart';

/// 정보 탭의 "수산 뉴스" — 서버가 공식 기관(해양수산부·국립수산과학원)에서 미리 모아 둔 소식을
/// 최신순으로 보여줍니다. 분류 필터와 쪽 단위 불러오기를 가지고, 상태는 이 위젯이 들고 있어서
/// 상세 화면을 보고 돌아와도 필터·불러온 목록·스크롤 위치가 그대로입니다(정보 탭은 탭 전환 시에도 유지됨).
class NewsSection extends ConsumerStatefulWidget {
  const NewsSection({super.key});

  @override
  ConsumerState<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends ConsumerState<NewsSection> {
  NewsCategory? _category; // null = 전체
  final List<NewsItem> _items = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true; // 첫 쪽(또는 필터를 바꾼 뒤)
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;

  /// 필터를 빠르게 바꿀 때 늦게 도착한 이전 응답을 버리기 위한 번호.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _moreError = null;
      _items.clear();
      _page = 0;
      _hasMore = false;
    });
    try {
      final page = await ref.read(newsRepositoryProvider).listNews(category: _category, page: 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await ref.read(newsRepositoryProvider).listNews(category: _category, page: _page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page += 1;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _moreError = e;
        _loadingMore = false;
      });
    }
  }

  void _select(NewsCategory? category) {
    if (_category == category) return;
    _category = category;
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('수산 뉴스', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterPillChip(label: '전체', selected: _category == null, onTap: () => _select(null)),
            for (final c in NewsCategory.values)
              FilterPillChip(label: c.label, selected: _category == c, onTap: () => _select(c)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '해양수산부·국립수산과학원의 공식 보도자료를 하루 세 번(오전 8시·오후 2시·오후 8시) 모아 보여드려요. '
          '게시일 기준의 소식이며, 현재 발효 중인 경보와는 다를 수 있어요.',
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, height: 1.45),
        ),
        const SizedBox(height: 10),
        _body(),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _Notice(
        icon: Icons.wifi_off_rounded,
        message: '뉴스를 불러오지 못했어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
        actionLabel: '다시 시도',
        onAction: _loadFirstPage,
      );
    }
    if (_items.isEmpty) {
      return _Notice(
        icon: Icons.newspaper_outlined,
        message: _category == null ? '아직 모인 소식이 없어요.' : "'${_category!.label}' 분류의 최근 소식이 없어요.",
      );
    }
    return Column(
      children: [
        for (final item in _items) ...[
          _NewsCard(item: item),
          const SizedBox(height: 8),
        ],
        if (_moreError != null)
          _Notice(
            icon: Icons.error_outline,
            message: '다음 소식을 불러오지 못했어요.',
            actionLabel: '다시 시도',
            onAction: _loadMore,
            compact: true,
          )
        else if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: _loadingMore
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('소식 더 보기'),
            ),
          ),
      ],
    );
  }
}

String formatNewsDate(DateTime? date) => date == null ? '' : DateFormat('yyyy.MM.dd').format(date);

/// 분류 표시. 위험 경보처럼 보이지 않도록 붉은색은 쓰지 않고 앱의 파란 톤만 씁니다.
class NewsCategoryPill extends StatelessWidget {
  const NewsCategoryPill(this.category, {super.key});

  final NewsCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(20)),
      child: Text(category.label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final date = formatNewsDate(item.publishedAt);
    final tags = [
      if (item.regions.isNotEmpty) '지역 ${item.regions.join(', ')}',
      if (item.species.isNotEmpty) '어종 ${item.species.join(', ')}',
    ];
    return InkWell(
      onTap: () => context.push('/news/${item.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NewsCategoryPill(item.category),
            const SizedBox(height: 6),
            Text(item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.4)),
            if (item.summary != null) ...[
              const SizedBox(height: 4),
              Text(item.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45)),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tags.join(' · '), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
            const SizedBox(height: 6),
            Text(
              [item.sourceName, if (date.isNotEmpty) '$date 게시'].join(' · '),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.actionLabel, this.onAction, this.compact = false});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 28),
      child: Column(
        children: [
          Icon(icon, size: compact ? 20 : 32, color: AppColors.textFaint),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5)),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
