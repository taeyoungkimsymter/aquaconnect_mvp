import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/notification_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/app_notification.dart';
import 'push_status_card.dart';

/// 알림함 — notifications received by the signed-in member, newest first.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (!n.isRead) {
      try {
        await ref.read(notificationRepositoryProvider).markRead(n.id);
      } catch (_) {}
      ref.invalidate(notificationFeedProvider);
    }
    final link = n.link;
    if (link != null && link != '/notifications' && context.mounted) openAppLink(GoRouter.of(context), link);
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(notificationFeedProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('처리하지 못했어요: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final unread = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('알림', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
        actions: [
          IconButton(
            tooltip: '알림 설정',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => context.push('/mypage/notifications'),
          ),
          if (unread > 0)
            TextButton(
              onPressed: () => _markAllRead(context, ref),
              child: const Text('모두 읽음', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
            ),
        ],
      ),
      body: Column(
        children: [
          const PushStatusCard(),
          Expanded(
            child: feedAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('알림을 불러오지 못했어요.\n$e', textAlign: TextAlign.center)),
              data: (feed) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationFeedProvider),
                child: feed.items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.notifications_none, size: 40, color: AppColors.textFaint),
                          SizedBox(height: 12),
                          Center(
                            child: Text('아직 도착한 알림이 없어요',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                        itemCount: feed.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _NotificationTile(
                          notification: feed.items[i],
                          onTap: () => _open(context, ref, feed.items[i]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  static String _timeLabel(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return DateFormat('M/d HH:mm').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final (icon, color) = switch (n.type) {
      'risk' => (Icons.warning_amber_rounded, AppColors.danger),
      'memo' => (Icons.edit_note, AppColors.brand),
      'inquiry' => (Icons.chat_bubble_outline, AppColors.good),
      'comment' => (Icons.mode_comment_outlined, AppColors.brand),
      'mention' => (Icons.alternate_email, AppColors.warning),
      'digest' => (Icons.summarize_outlined, AppColors.brand),
      _ => (Icons.notifications_outlined, AppColors.textSecondary),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: n.isRead ? AppColors.surface : AppColors.brandTintStrong,
          border: Border.all(color: n.isRead ? AppColors.border : AppColors.brandTintBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(_timeLabel(n.createdAt), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(n.body, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.45)),
                ],
              ),
            ),
            if (!n.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
