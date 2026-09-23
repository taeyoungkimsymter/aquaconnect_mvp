import 'package:flutter/material.dart';

import '../../data/models/farm.dart';
import '../theme/app_colors.dart';

/// Shared memo input used by both Home (compact, single line) and Memo
/// (full, with expression chips + photo). Typing `/` opens a farm-tag
/// autocomplete popover, matching every `.dc.html` design's "'/' 로 양식장
/// 지정" pattern.
class MemoComposer extends StatefulWidget {
  const MemoComposer({
    super.key,
    required this.farms,
    required this.onSubmit,
    this.compact = false,
    this.showExpressionChips = false,
    this.hintText = "지금 본 것 적어두기 ('/' 로 양식장 지정)",
  });

  final List<Farm> farms;
  final void Function({required String content, Farm? farm, List<String> tags}) onSubmit;
  final bool compact;
  final bool showExpressionChips;
  final String hintText;

  @override
  State<MemoComposer> createState() => _MemoComposerState();
}

class _MemoComposerState extends State<MemoComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Farm? _selectedFarm;
  final Set<String> _selectedExpressions = {};

  static const _expressions = ['배달완료', '폐사', '투약', '방문', '할일'];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? get _slashQuery {
    final text = _controller.text;
    final slashIndex = text.lastIndexOf('/');
    if (slashIndex == -1) return null;
    final after = text.substring(slashIndex + 1);
    if (after.contains(' ') || after.contains('\n')) return null;
    return after;
  }

  List<Farm> get _suggestions {
    final query = _slashQuery;
    if (query == null) return const [];
    if (query.isEmpty) return widget.farms;
    return widget.farms.where((f) => f.name.contains(query)).toList();
  }

  void _pickFarm(Farm farm) {
    final text = _controller.text;
    final slashIndex = text.lastIndexOf('/');
    setState(() {
      _selectedFarm = farm;
      if (slashIndex != -1) {
        _controller.text = text.substring(0, slashIndex);
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      }
    });
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    widget.onSubmit(content: content, farm: _selectedFarm, tags: _selectedExpressions.toList());
    setState(() {
      _controller.clear();
      _selectedFarm = null;
      _selectedExpressions.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedFarm != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(_selectedFarm!.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                backgroundColor: AppColors.brandTint,
                labelStyle: const TextStyle(color: AppColors.brandDark),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _selectedFarm = null),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 7, 12, 4),
                  child: Text(
                    "'/' 입력 시 표시 · 등록된 양식장",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                  ),
                ),
                ...suggestions.map(
                  (f) => InkWell(
                    onTap: () => _pickFarm(f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(f.name, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (widget.showExpressionChips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _expressions
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(e, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          selected: _selectedExpressions.contains(e),
                          onSelected: (v) => setState(() {
                            v ? _selectedExpressions.add(e) : _selectedExpressions.remove(e);
                          }),
                          selectedColor: AppColors.brandTint,
                          labelStyle: TextStyle(
                            color: _selectedExpressions.contains(e) ? AppColors.brand : AppColors.textSecondary,
                          ),
                          backgroundColor: AppColors.brandTint,
                          side: BorderSide.none,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: widget.compact ? 1 : 4,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(widget.compact ? 30 : 22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(icon: Icons.photo_camera_outlined, onTap: () {}, filled: false),
            const SizedBox(width: 8),
            _RoundIconButton(icon: Icons.arrow_forward, onTap: _submit, filled: true),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, required this.filled});

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? AppColors.brand : AppColors.background,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: filled ? Colors.white : AppColors.neutralIcon),
      ),
    );
  }
}
