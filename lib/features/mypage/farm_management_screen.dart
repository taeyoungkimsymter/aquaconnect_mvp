import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/korean_search.dart';
import '../../core/widgets/farm_search_field.dart';
import '../../data/models/farm.dart';
import 'farm_form_sheet.dart';

/// "등록 양식장 관리" — list/create/edit/delete for the institute's farms,
/// opened from MyPage.
class FarmManagementScreen extends ConsumerStatefulWidget {
  const FarmManagementScreen({super.key});

  @override
  ConsumerState<FarmManagementScreen> createState() => _FarmManagementScreenState();
}

class _FarmManagementScreenState extends ConsumerState<FarmManagementScreen> {
  String _query = '';

  void _openForm(BuildContext context, {Farm? existing}) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FarmFormSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Farm farm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('양식장 삭제'),
        content: Text('${farm.name}을(를) 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(farmRepositoryProvider).deleteFarm(farm.id);
    ref.invalidate(farmsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(farmsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.brandDark,
        title: const Text('등록 양식장 관리', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.brand,
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: farmsAsync.when(
        data: (farms) {
          if (farms.isEmpty) {
            return const Center(
              child: Text('등록된 양식장이 없습니다.\n오른쪽 아래 + 버튼으로 등록해주세요.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            );
          }
          final shown = searchFarms(farms, _query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: FarmSearchField(onChanged: (q) => setState(() => _query = q)),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('맞는 양식장이 없어요', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _FarmManagementCard(
                          farm: shown[i],
                          onEdit: () => _openForm(context, existing: shown[i]),
                          onDelete: () => _confirmDelete(context, ref, shown[i]),
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('양식장 목록을 불러오지 못했습니다.\n$e', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ),
      ),
    );
  }
}

class _FarmManagementCard extends StatelessWidget {
  const _FarmManagementCard({required this.farm, required this.onEdit, required this.onDelete});

  final Farm farm;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(farm.name,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                tooltip: '수정',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                tooltip: '삭제',
              ),
            ],
          ),
          const SizedBox(height: 2),
          _InfoRow(icon: Icons.place_outlined, text: farm.address),
          const SizedBox(height: 4),
          _InfoRow(icon: Icons.call_outlined, text: farm.ownerContact ?? '전화번호 미등록'),
          if (farm.nearestStationName.isNotEmpty) ...[
            const SizedBox(height: 4),
            _InfoRow(icon: Icons.water_outlined, text: '인근 관측소 · ${farm.nearestStationName}'),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary))),
      ],
    );
  }
}
