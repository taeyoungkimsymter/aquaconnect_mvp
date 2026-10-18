import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/memo_composer_bar.dart';
import '../news/news_section.dart';

/// 정보 탭 — 수산 뉴스. (해양환경 데이터는 홈 화면의 리포트 현황 아래로 옮겼습니다.)
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              width: double.infinity,
              color: AppColors.background,
              child: const Text('정보', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.brandDark)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: const [NewsSection()],
              ),
            ),
            const MemoComposerBar(confirmOnSave: true),
          ],
        ),
      ),
    );
  }
}
