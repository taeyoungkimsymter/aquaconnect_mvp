import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../core/providers/data_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/farm.dart';
import '../../data/models/share_link.dart';

void showShareLinkSheet(BuildContext context, {required Farm farm}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _ShareLinkSheet(farm: farm),
  );
}

class _ShareLinkSheet extends ConsumerStatefulWidget {
  const _ShareLinkSheet({required this.farm});
  final Farm farm;

  @override
  ConsumerState<_ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends ConsumerState<_ShareLinkSheet> {
  ShareLinkExpiry _expiry = ShareLinkExpiry.thirtyDays;
  ShareLink? _link;
  bool _loading = true;
  String? _error;

  /// [_link] was made in this sheet and hasn't been copied or shared yet —
  /// replacing it (by picking another 만료 기한) can safely revoke it.
  bool _unsentNewLink = false;

  @override
  void initState() {
    super.initState();
    _openExistingOrCreate();
  }

  /// Opening the sheet reuses the farm's newest still-valid link instead of
  /// minting a new one every time.
  Future<void> _openExistingOrCreate() async {
    try {
      final links = await ref.read(shareLinkRepositoryProvider).listShareLinks(farmId: widget.farm.id);
      final active = links.where((l) => l.isActive).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (active.isEmpty) return _createLink(_expiry);
      if (!mounted) return;
      setState(() {
        _link = active.first;
        _expiry = _expiryOf(active.first);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  static ShareLinkExpiry _expiryOf(ShareLink link) {
    final expiresAt = link.expiresAt;
    if (expiresAt == null) return ShareLinkExpiry.unlimited;
    return expiresAt.difference(link.createdAt).inDays <= 7 ? ShareLinkExpiry.sevenDays : ShareLinkExpiry.thirtyDays;
  }

  Future<void> _createLink(ShareLinkExpiry expiry) async {
    final repo = ref.read(shareLinkRepositoryProvider);
    final replaced = _unsentNewLink ? _link : null;
    setState(() {
      _expiry = expiry;
      _loading = true;
      _error = null;
    });
    try {
      final link = await repo.createShareLink(farmId: widget.farm.id, expiry: expiry);
      if (replaced != null) await repo.revokeShareLink(replaced.id);
      if (!mounted) return;
      setState(() {
        _link = link;
        _unsentNewLink = true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      ref.invalidate(shareLinksProvider);
    }
  }

  void _markSent() => _unsentNewLink = false;

  // The app uses go_router's default hash URL strategy, so the public
  // page lives at <origin>/#/r/<token> on whatever host serves this build.
  String get _url => '${Uri.base.origin}/#${_link?.urlPath() ?? ''}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFDCE3EC), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('리포트 링크 공유', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('${widget.farm.name} · 어가가 설치 없이 웹으로 열람', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.background, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 15, color: AppColors.neutralIcon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loading ? '링크 준비 중...' : (_error != null || _link == null ? '링크를 만들지 못했어요' : _url),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading || _link == null
                        ? null
                        : () async {
                            _markSent();
                            await Clipboard.setData(ClipboardData(text: _url));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 복사했습니다.')));
                            }
                          },
                    child: const Text('복사', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => _createLink(_expiry),
                    child: const Text('다시 시도', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
            if (_link?.expiresAt != null && !_loading) ...[
              const SizedBox(height: 6),
              Text('${_link!.expiresAt!.month}월 ${_link!.expiresAt!.day}일까지 열람할 수 있어요',
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ],
            const SizedBox(height: 16),
            const Text('만료 기한', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: ShareLinkExpiry.values.map((e) {
                final selected = e == _expiry;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    // A different 기한 needs a new link (a link's expiry is fixed).
                    onTap: _loading || e == _expiry ? null : () => _createLink(e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.brandTint : AppColors.background,
                        border: Border.all(color: selected ? AppColors.brand : AppColors.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(e.label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? AppColors.brand : AppColors.textTertiary)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(10)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 13, color: AppColors.warningDark),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '어가의 영업 정보를 담고 있는 링크입니다. 발급 이력은 마이페이지 > 공유 링크 관리에서 확인·회수할 수 있습니다.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.warningTintInk, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading || _link == null
                    ? null
                    : () {
                        _markSent();
                        Share.share(_url, subject: '${widget.farm.name} 리포트 링크');
                      },
                // Generic system share (문자·카카오톡·메일 …), so not Kakao-branded.
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('문자·카카오톡으로 보내기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
