import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/shared_report_view.dart';
import 'inquiry_sheet.dart';
import 'shared_report_tokens.dart';

/// Public, unauthenticated `/r/:token` page — what a farm owner opens on
/// their own phone after the institute sends the share link. Read-only,
/// except for the action checklist and the inquiry sheet.
class SharedReportWebScreen extends ConsumerStatefulWidget {
  const SharedReportWebScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<SharedReportWebScreen> createState() => _SharedReportWebScreenState();
}

class _SharedReportWebScreenState extends ConsumerState<SharedReportWebScreen> {
  late final Future<SharedReportView?> _future = _load();
  List<ReportAction>? _actions;

  Future<SharedReportView?> _load() async {
    final bundle = await ref.read(shareLinkRepositoryProvider).resolveToken(widget.token);
    return bundle == null ? null : bundle.view ?? SharedReportView.fromBundle(bundle);
  }

  /// Optimistic toggle: flip locally, PATCH, roll back on failure.
  Future<void> _toggleAction(String id) async {
    final current = _actions!;
    final index = current.indexWhere((a) => a.id == id);
    final next = !current[index].done;
    setState(() => _actions = [...current]..[index] = current[index].copyWith(done: next));
    try {
      await ref.read(shareLinkRepositoryProvider).setActionDone(token: widget.token, actionId: id, done: next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actions = [..._actions!]..[index] = _actions![index].copyWith(done: !next));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장에 실패했습니다. 다시 시도해 주세요.')));
    }
  }

  Future<void> _sendInquiry(String message) =>
      ref.read(shareLinkRepositoryProvider).sendInquiry(token: widget.token, message: message);

  void _openInquiry(SharedReportView report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: SharedTokens.scrim,
      constraints: const BoxConstraints(maxWidth: SharedTokens.maxWidth),
      builder: (_) => InquirySheet(orgName: report.orgName, phone: report.contactPhone, onSend: _sendInquiry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(textTheme: GoogleFonts.notoSansKrTextTheme(Theme.of(context).textTheme)),
      child: Scaffold(
        backgroundColor: SharedTokens.outerBg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SharedTokens.maxWidth),
            child: ColoredBox(
              color: SharedTokens.bg,
              child: FutureBuilder<SharedReportView?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: SharedTokens.primary));
                  }
                  final report = snapshot.data;
                  if (report == null) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('링크가 만료되었거나 존재하지 않습니다.', style: TextStyle(color: SharedTokens.textSub)),
                      ),
                    );
                  }
                  _actions ??= report.actions;
                  return _ReportBody(
                    report: report,
                    actions: _actions!,
                    onToggle: _toggleAction,
                    onInquire: () => _openInquiry(report),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.actions, required this.onToggle, required this.onInquire});

  final SharedReportView report;
  final List<ReportAction> actions;
  final void Function(String id) onToggle;
  final VoidCallback onInquire;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _Header(farmName: report.farmName),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _SharedMeta(orgName: report.orgName, sharedAt: report.sharedAt),
                const SizedBox(height: 14),
                _OverallCard(level: report.level, summary: report.summary),
                const SizedBox(height: 18),
                const _SectionTitle('주요 관찰 지표'),
                _MetricGrid(metrics: report.metrics),
                if (report.flaggedPhotos.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _SectionTitle('이상 소견 사진'),
                  _PhotoStrip(photos: report.flaggedPhotos),
                ],
                const SizedBox(height: 18),
                const _SectionTitle('진단 소견 상세'),
                _CardShell(child: Text(report.diagnosis, style: const TextStyle(fontSize: 13.5, height: 1.65, color: SharedTokens.text))),
                const SizedBox(height: 18),
                _ActionChecklist(actions: actions, onToggle: onToggle),
                if (report.videoUrl != null) ...[
                  const SizedBox(height: 14),
                  _VideoCard(url: report.videoUrl!, duration: report.videoDuration),
                ],
                const SizedBox(height: 18),
                _Footnote(orgName: report.orgName, phone: report.contactPhone),
              ],
            ),
          ),
          _InquiryCta(orgName: report.orgName, onTap: onInquire),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.farmName});

  final String farmName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: const BoxDecoration(color: SharedTokens.card, border: Border(bottom: BorderSide(color: SharedTokens.line))),
      child: Row(
        children: [
          IconButton(
            tooltip: '뒤로가기',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: SharedTokens.text),
            onPressed: () {
              if (context.canPop()) context.pop();
            },
          ),
          Expanded(
            child: Column(
              children: [
                const Text('양식장 관리 리포트', style: TextStyle(fontSize: 11, color: SharedTokens.textSub, fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(farmName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: SharedTokens.text)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'PDF 저장',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 22, color: SharedTokens.primary),
            // TODO: wire to a server-rendered PDF once the endpoint exists.
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF 저장은 준비 중입니다.'))),
          ),
        ],
      ),
    );
  }
}

class _SharedMeta extends StatelessWidget {
  const _SharedMeta({required this.orgName, required this.sharedAt});

  final String orgName;
  final DateTime sharedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: SharedTokens.accent, borderRadius: BorderRadius.circular(20)),
          child: const Text('공유됨', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$orgName · ${DateFormat('yyyy.MM.dd HH:mm').format(sharedAt)} 공유',
              style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: SharedTokens.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0F0F1E19), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: SharedTokens.text)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.level, required this.summary});

  final OverallLevel level;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      OverallLevel.good => SharedTokens.primary,
      OverallLevel.watch => SharedTokens.amber,
      OverallLevel.urgent => SharedTokens.urgent,
    };
    final icon = level == OverallLevel.good ? Icons.check_circle_outline : Icons.warning_amber_rounded;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: SharedTokens.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0F0F1E19), blurRadius: 3, offset: Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Text('종합 소견 · ${level.label}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(summary,
                          style: GoogleFonts.notoSerifKr(fontSize: 16, fontWeight: FontWeight.w700, height: 1.45, color: SharedTokens.text)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<ReportMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final m in metrics)
            SizedBox(
              width: width,
              child: _CardShell(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.label, style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: m.value, style: GoogleFonts.notoSerifKr(fontSize: 24, fontWeight: FontWeight.w800, color: SharedTokens.text)),
                      TextSpan(text: ' ${m.unit}', style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
                    ])),
                    const SizedBox(height: 4),
                    Text(m.note, style: const TextStyle(fontSize: 11.5, color: SharedTokens.secondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});

  final List<FlaggedPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = photos[i];
          final placeholder = Container(
            color: const Color(0xFFD9E6E0),
            alignment: Alignment.center,
            child: const Icon(Icons.image_outlined, size: 32, color: SharedTokens.textSub),
          );
          return SizedBox(
            width: 128,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: p.needsAttention ? Border.all(color: SharedTokens.amber, width: 2) : null,
                    ),
                    child: p.url.isEmpty
                        ? placeholder
                        : Image.network(p.url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => placeholder),
                  ),
                ),
                const SizedBox(height: 6),
                Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionChecklist extends StatelessWidget {
  const _ActionChecklist({required this.actions, required this.onToggle});

  final List<ReportAction> actions;
  final void Function(String id) onToggle;

  @override
  Widget build(BuildContext context) {
    final doneCount = actions.where((a) => a.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          '권장 조치사항',
          trailing: Text('$doneCount/${actions.length} 완료',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: SharedTokens.primary)),
        ),
        _CardShell(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: SharedTokens.line),
                _ActionTile(action: actions[i], onTap: () => onToggle(actions[i].id)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final ReportAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = action.done;
    return Semantics(
      button: true,
      checked: done,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? SharedTokens.primary : Colors.transparent,
                    border: Border.all(color: done ? SharedTokens.primary : const Color(0xFFB7C6BF), width: 1.6),
                  ),
                  child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                            color: done ? SharedTokens.textSub : SharedTokens.text,
                            decoration: done ? TextDecoration.lineThrough : null,
                          )),
                      if (action.sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(action.sub, style: const TextStyle(fontSize: 12, height: 1.45, color: SharedTokens.textSub)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.url, this.duration});

  final String url;
  final String? duration;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SharedTokens.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => launchExternal(url),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: SharedTokens.primary, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('현장 영상 전체보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SharedTokens.text)),
                    if (duration != null) Text(duration!, style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SharedTokens.textSub),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.orgName, required this.phone});

  final String orgName;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    return Text(
      '이 리포트는 $orgName에서 해당 양식장에만 공유한 자료입니다. 링크를 다른 사람에게 전달하지 마세요.'
      '${phone == null ? '' : '\n문의: $phone'}',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11.5, height: 1.6, color: SharedTokens.textSub),
    );
  }
}

class _InquiryCta extends StatelessWidget {
  const _InquiryCta({required this.orgName, required this.onTap});

  final String orgName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(color: SharedTokens.card, border: Border(top: BorderSide(color: SharedTokens.line))),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: SharedTokens.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text('$orgName에 문의하기', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
