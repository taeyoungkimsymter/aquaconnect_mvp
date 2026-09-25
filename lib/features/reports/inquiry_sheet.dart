import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'shared_report_tokens.dart';

enum _Step { options, input, done }

/// Bottom sheet for the "문의하기" CTA: options → memo input → confirmation.
/// State lives in the sheet, so closing at any step resets it. Backdrop tap
/// and Esc dismissal come from the modal route.
class InquirySheet extends StatefulWidget {
  const InquirySheet({super.key, required this.orgName, required this.phone, required this.onSend});

  final String orgName;
  final String? phone;
  final Future<void> Function(String message) onSend;

  @override
  State<InquirySheet> createState() => _InquirySheetState();
}

class _InquirySheetState extends State<InquirySheet> {
  final _controller = TextEditingController();
  _Step _step = _Step.options;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSend(message);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _step = _Step.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '전송에 실패했습니다. 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: '문의하기',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          decoration: const BoxDecoration(
            color: SharedTokens.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      switch (_step) {
                        _Step.options => '${widget.orgName}에 문의하기',
                        _Step.input => '메모 남기기',
                        _Step.done => '',
                      },
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SharedTokens.text),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.close, color: SharedTokens.textSub),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                FocusScope(
                  autofocus: true,
                  child: switch (_step) {
                    _Step.options => _options(),
                    _Step.input => _input(),
                    _Step.done => _done(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _options() {
    final phone = widget.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionTile(
          autofocus: true,
          icon: Icons.call,
          title: '전화 걸기',
          subtitle: phone ?? '전화번호가 등록되지 않았습니다',
          onTap: phone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: phone)),
        ),
        const SizedBox(height: 10),
        _OptionTile(
          icon: Icons.edit_note,
          title: '메모 남기기',
          subtitle: '남기신 내용은 담당자가 확인 후 연락드립니다',
          onTap: () => setState(() => _step = _Step.input),
        ),
      ],
    );
  }

  Widget _input() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 6,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '예) 오늘 오전부터 우럭 폐사가 늘었습니다. 방문 가능한 시간이 언제인가요?',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AAAA3)),
            filled: true,
            fillColor: SharedTokens.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: SharedTokens.primary, width: 1.5),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: SharedTokens.urgent)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _sending ? null : () => setState(() => _step = _Step.options),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SharedTokens.text,
                    side: const BorderSide(color: SharedTokens.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('이전', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _controller.text.trim().isEmpty || _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: SharedTokens.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('보내기', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _done() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: SharedTokens.primary, shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 14),
        const Text('문의가 접수되었습니다',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SharedTokens.text)),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: SharedTokens.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.autofocus = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SharedTokens.bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: onTap == null ? SharedTokens.textSub : SharedTokens.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: SharedTokens.text)),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: SharedTokens.textSub)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: SharedTokens.textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
