import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_providers.dart';
import 'farm_region_list.dart';

/// Home's 관리 양식장 — [FarmRegionList] fed with the institute's farms.
class FarmRegionSection extends ConsumerWidget {
  const FarmRegionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FarmRegionList(farmsAsync: ref.watch(farmsProvider), onRetry: () => ref.invalidate(farmsProvider));
}
