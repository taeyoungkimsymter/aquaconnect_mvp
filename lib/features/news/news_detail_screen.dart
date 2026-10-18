import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/news_item.dart';
import 'news_section.dart';

/// 수산 뉴스 상세 — 제목·출처·게시일·분류·짧은 소개와 "공식 원문 보기". 기사 전문은 싣지 않고
/// 정확한 원문 주소로 연결합니다. 삭제되었거나 게시가 중단된 소식, 불러오기 실패에는 각각 안내와 버튼이 나옵니다.
class NewsDetailScreen extends ConsumerWidget {
  const NewsDetailScreen({super.key, required this.newsId});

  final String newsId;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/info');
    }
  }

  Future<void> _openOriginal(BuildContext context, NewsItem item) async {
    final uri = Uri.tryParse(item.url);
    final ok = uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    if (ok && await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('원문을 열지 못했어요. 잠시 뒤 다시 시도해 주세요.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(newsItemProvider(newsId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        leading: BackButton(onPressed: () => _back(context)),
        title: const Text('수산 뉴스', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Notice(
          icon: Icons.wifi_off_rounded,
          message: '소식을 불러오지 못했어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(newsItemProvider(newsId)),
          secondaryLabel: '돌아가기',
          onSecondary: () => _back(context),
        ),
        data: (item) => item == null
            ? _Notice(
                icon: Icons.article_outlined,
                message: '삭제되었거나 게시가 중단된 소식이에요.',
                actionLabel: '돌아가기',
                onAction: () => _back(context),
              )
            : _Detail(item: item, onOpenOriginal: () => _openOriginal(context, item)),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item, required this.onOpenOriginal});

  final NewsItem item;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final date = formatNewsDate(item.publishedAt);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NewsCategoryPill(item.category),
              const SizedBox(height: 10),
              Text(item.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.4)),
              const SizedBox(height: 8),
              Text(
                [item.sourceName, date.isNotEmpty ? '$date 게시' : '게시일 확인 불가'].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              if (item.summary != null) ...[
                const SizedBox(height: 14),
                Text(item.summary!, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.6)),
              ],
              if (item.regions.isNotEmpty || item.species.isNotEmpty) ...[
                const SizedBox(height: 14),
                if (item.regions.isNotEmpty) _FactRow(label: '관련 지역', value: item.regions.join(', ')),
                if (item.species.isNotEmpty) _FactRow(label: '관련 어종', value: item.species.join(', ')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onOpenOriginal,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('공식 원문 보기'),
        ),
        const SizedBox(height: 14),
        const Text(
          '이 화면은 공식 기관이 게시한 소식의 제목·소개와 원문 링크만 보여줍니다. 게시일 기준의 과거 소식이며 '
          '현재 발효 중인 경보·주의보와 다를 수 있어요. 최신 상황은 원문과 기관 공지를 확인해 주세요.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
        ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null) TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}
