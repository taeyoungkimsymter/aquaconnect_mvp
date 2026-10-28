import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';

String formatKoreanTime(TimeOfDay time) {
  final isPm = time.period == DayPeriod.pm;
  final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${isPm ? '오후' : '오전'} $hour12:$minute';
}

/// "마이페이지 > 오늘의 업무 알림" — on/off + time of the daily 오늘의 업무
/// notification (my open 할일 / 담당 / 호출 + 위험 양식장), which replaced the
/// old 하루 요약 / 주간 요약. The weekly flag is still stored server-side but
/// no longer sends anything, so it has no toggle here.
class DailySummarySettingsScreen extends ConsumerWidget {
  const DailySummarySettingsScreen({super.key});

  Future<void> _save(BuildContext context, Future<void> saving) async {
    try {
      await saving;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('설정을 저장하지 못했어요: $e')));
      }
    }
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, TimeOfDay current) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked != null) {
      if (context.mounted) await _save(context, ref.read(digestSettingsProvider.notifier).setDailyTime(picked));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(digestSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('오늘의 업무 알림', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Container(
              decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  _ToggleRow(
                    icon: Icons.checklist_rtl,
                    label: '오늘의 업무 알림 받기',
                    value: settings.dailyEnabled,
                    onChanged: (v) => _save(context, ref.read(digestSettingsProvider.notifier).setDailyEnabled(v)),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _TimeRow(
                    time: settings.dailyTime,
                    enabled: settings.dailyEnabled,
                    onTap: () => _pickTime(context, ref, settings.dailyTime),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('매일 정한 시각에 오늘 내가 할 일 — 남은 할일·담당 메모, 나를 호출한 메모 수와 위험·주의 양식장을 알려 드려요. '
                  '알림을 누르면 메모 탭의 오늘의 업무로 바로 이동해요. 아침 출근 시간으로 맞춰 두면 하루를 시작하기 좋아요.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5)),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('설정을 불러오지 못했습니다.\n$e', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.icon, required this.label, required this.value, required this.onChanged});

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.brand),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.time, required this.enabled, required this.onTap});

  final TimeOfDay time;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('알림 시각', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Text(formatKoreanTime(time), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 13, color: AppColors.neutralArrow),
            ],
          ),
        ),
      ),
    );
  }
}
