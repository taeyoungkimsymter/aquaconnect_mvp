import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The 양식장 검색 box used on Home, the memo tab's farm picker and 등록 양식장
/// 관리. Matching itself is [searchFarms] (초성·띄어쓰기 무시).
class FarmSearchField extends StatefulWidget {
  const FarmSearchField({
    super.key,
    required this.onChanged,
    this.hintText = '양식장 이름·주소·담당자 검색 (초성 가능)',
    this.autofocus = false,
    this.fillColor = AppColors.surface,
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final Color fillColor;

  @override
  State<FarmSearchField> createState() => _FarmSearchFieldState();
}

class _FarmSearchFieldState extends State<FarmSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.cancel, size: 17, color: AppColors.textMuted),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
        filled: true,
        fillColor: widget.fillColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
    );
  }
}
