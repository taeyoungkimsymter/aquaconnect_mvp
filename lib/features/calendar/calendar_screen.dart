import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/data_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/memo_card.dart';
import '../../data/models/memo.dart';

/// The day a memo sits on in the calendar: the day it was 완료 if it's done,
/// otherwise the day it was registered.
DateTime calendarDayOf(Memo memo) => _dayOf((memo.doneAt ?? memo.createdAt).toLocal());

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Sunday-first, like Google Calendar in Korean.
DateTime _weekStart(DateTime d) => _dayOf(d).subtract(Duration(days: d.weekday % 7));

const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

Color _weekdayColor(int index) => index == 0
    ? AppColors.danger
    : index == 6
    ? AppColors.brand
    : AppColors.textSecondary;

enum _CalView {
  month('월'),
  week('주'),
  agenda('일정');

  const _CalView(this.label);
  final String label;
}

enum _StatusFilter {
  all('전체'),
  open('진행 중'),
  done('완료');

  const _StatusFilter(this.label);
  final String label;

  bool accepts(Memo m) => switch (this) {
    _StatusFilter.all => true,
    _StatusFilter.open => !m.isDone && (m.isTask || m.mentionedMe),
    _StatusFilter.done => m.isDone,
  };
}

/// How a memo's chip looks: 완료 green, 문의 orange, 할일/호출 blue, other
/// memos a light blue.
({Color bg, Color fg, String prefix}) _styleOf(Memo m) {
  if (m.isDone) return (bg: AppColors.goodTint, fg: AppColors.goodDark, prefix: '✓ ');
  if (m.authorType == MemoAuthorType.farm || m.tags.contains('문의')) {
    return (bg: AppColors.warning, fg: Colors.white, prefix: '');
  }
  if (m.isTask || m.mentionedMe) return (bg: AppColors.brand, fg: Colors.white, prefix: '');
  return (bg: AppColors.brandTint, fg: AppColors.brandInk, prefix: '');
}

/// The first line without a leading '할일:' — the chip color already says so.
String _shortLine(String text) => _firstLine(text).replaceFirst(RegExp(r'^할일\s*:\s*'), '');

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.isEmpty ? '(내용 없음)' : line;
}

/// 캘린더 tab: every memo laid out by day (Google Calendar style), in a month
/// grid, a week of columns, or an 일정 list. Pinch, ctrl+wheel or the −/+
/// buttons zoom so a busy day stays readable at any screen size.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _minZoom = 0.6;
  static const _maxZoom = 2.4;

  _CalView _view = _CalView.month;
  _StatusFilter _filter = _StatusFilter.all;
  DateTime _anchor = _dayOf(DateTime.now());
  double _zoom = 1.0;

  // Two-finger pinch, tracked with a Listener so it never fights the
  // scroll views for the gesture arena.
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartZoom = 1.0;

  void _setZoom(double zoom) {
    final next = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((next - _zoom).abs() > 0.001) setState(() => _zoom = next);
  }

  double? get _pointerDistance {
    if (_pointers.length != 2) return null;
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _pointerDistance;
      _pinchStartZoom = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStartDistance;
    final now = _pointerDistance;
    if (start != null && now != null && start > 0) _setZoom(_pinchStartZoom * now / start);
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScaleEvent) {
      _setZoom(_zoom * e.scale);
    } else if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        _setZoom(_zoom * (e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1));
      });
    }
  }

  void _shift(int direction) {
    setState(() {
      _anchor = switch (_view) {
        _CalView.week => _anchor.add(Duration(days: 7 * direction)),
        _ => DateTime(_anchor.year, _anchor.month + direction, 1),
      };
    });
  }

  String get _title {
    if (_view == _CalView.week) {
      final start = _weekStart(_anchor);
      final end = start.add(const Duration(days: 6));
      return start.month == end.month
          ? '${start.year}년 ${start.month}월'
          : '${start.year}년 ${start.month}월 – ${end.month}월';
    }
    return '${_anchor.year}년 ${_anchor.month}월';
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initial: _anchor),
    );
    if (picked != null) setState(() => _anchor = picked);
  }

  void _openDay(DateTime day, List<Memo> memos) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => _DaySheet(day: day, memos: memos),
    );
  }

  void _openMemo(Memo memo) => MemoCard(memo: memo).showDetail(context);

  @override
  Widget build(BuildContext context) {
    final memosAsync = ref.watch(memosProvider(null));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: memosAsync.when(
                data: (memos) {
                  final byDay = <DateTime, List<Memo>>{};
                  for (final m in memos.where(_filter.accepts)) {
                    byDay.putIfAbsent(calendarDayOf(m), () => []).add(m);
                  }
                  for (final list in byDay.values) {
                    list.sort((a, b) => (a.doneAt ?? a.createdAt).compareTo(b.doneAt ?? b.createdAt));
                  }
                  return Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerEnd,
                    onPointerCancel: _onPointerEnd,
                    onPointerSignal: _onPointerSignal,
                    onPointerPanZoomStart: (_) => _pinchStartZoom = _zoom,
                    onPointerPanZoomUpdate: (e) => _setZoom(_pinchStartZoom * e.scale),
                    child: GestureDetector(
                      // Swipe sideways for the previous / next month or week.
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() > 350) _shift(v < 0 ? 1 : -1);
                      },
                      child: switch (_view) {
                        _CalView.month => _MonthView(
                          anchor: _anchor,
                          byDay: byDay,
                          zoom: _zoom,
                          onDay: _openDay,
                          onMemo: _openMemo,
                        ),
                        _CalView.week => _WeekView(
                          anchor: _anchor,
                          byDay: byDay,
                          zoom: _zoom,
                          onDay: _openDay,
                          onMemo: _openMemo,
                        ),
                        _CalView.agenda => _AgendaView(anchor: _anchor, byDay: byDay, zoom: _zoom, onMemo: _openMemo),
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('메모를 불러오지 못했어요: $e', textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isCurrent = _view == _CalView.week
        ? _sameDay(_weekStart(_anchor), _weekStart(DateTime.now()))
        : _anchor.year == DateTime.now().year && _anchor.month == DateTime.now().month;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: AppColors.brandDark,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: AppColors.brandDark),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: _view == _CalView.week ? '이전 주' : '이전 달',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              IconButton(
                tooltip: _view == _CalView.week ? '다음 주' : '다음 달',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
              OutlinedButton(
                onPressed: isCurrent && _sameDay(_anchor, DateTime.now())
                    ? null
                    : () => setState(() => _anchor = _dayOf(DateTime.now())),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: AppColors.borderStrong),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('오늘', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              _ViewMenu(view: _view, onSelected: (v) => setState(() => _view = v)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _StatusFilter.values) ...[
                        FilterPillChip(
                          label: f.label,
                          selected: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              _ZoomControl(
                zoom: _zoom,
                onZoomOut: _zoom > _minZoom ? () => _setZoom(_zoom - 0.2) : null,
                onZoomIn: _zoom < _maxZoom ? () => _setZoom(_zoom + 0.2) : null,
                onReset: () => _setZoom(1.0),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const _Legend(),
        ],
      ),
    );
  }
}

class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.view, required this.onSelected});

  final _CalView view;
  final ValueChanged<_CalView> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CalView>(
      tooltip: '보기 방식',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in _CalView.values)
          CheckedPopupMenuItem(
            value: v,
            checked: v == view,
            child: Text(v.label, style: const TextStyle(fontSize: 13.5)),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              view.label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.brand),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({required this.zoom, required this.onZoomOut, required this.onZoomIn, required this.onReset});

  final double zoom;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.remove, tooltip: '축소', onTap: onZoomOut),
          Tooltip(
            message: '100%로 되돌리기',
            child: InkWell(
              onTap: onReset,
              child: SizedBox(
                width: 42,
                child: Text(
                  '${(zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
          _ZoomButton(icon: Icons.add, tooltip: '확대', onTap: onZoomIn),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: onTap == null ? AppColors.textFaint : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary)),
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        children: [
          item(AppColors.brand, '할일·호출'),
          item(AppColors.goodTint, '완료 (완료한 날)'),
          item(AppColors.warning, '문의'),
          item(AppColors.brandTint, '일반 메모 (등록한 날)'),
        ],
      ),
    );
  }
}

/// A memo as a one-line calendar chip (month grid).
class _EventChip extends StatelessWidget {
  const _EventChip({
    required this.memo,
    required this.height,
    required this.fontSize,
    required this.showFarm,
    required this.onTap,
  });

  final Memo memo;
  final double height;
  final double fontSize;

  /// Narrow (phone) cells have room for the memo text only.
  final bool showFarm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleOf(memo);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(4)),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: style.prefix),
              if (showFarm && memo.farmName != null)
                TextSpan(
                  text: '${memo.farmName} ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              TextSpan(text: showFarm ? _firstLine(memo.content) : _shortLine(memo.content)),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.15,
            fontWeight: FontWeight.w600,
            color: style.fg,
            decoration: memo.isDone ? TextDecoration.lineThrough : null,
            decorationColor: style.fg,
          ),
        ),
      ),
    );
  }
}

/// The date number in a day cell / column header; today gets the filled
/// blue circle.
class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.size, this.faded = false, this.weekdayIndex});

  final DateTime day;
  final double size;
  final bool faded;
  final int? weekdayIndex;

  @override
  Widget build(BuildContext context) {
    final today = _sameDay(day, DateTime.now());
    final color = today
        ? Colors.white
        : faded
        ? AppColors.textFaint
        : (weekdayIndex == null ? AppColors.textPrimary : _weekdayColor(weekdayIndex!));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: today ? const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle) : null,
      child: Text(
        '${day.day}',
        style: TextStyle(fontSize: size * 0.5, fontWeight: today ? FontWeight.w800 : FontWeight.w600, color: color),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                _weekdays[i],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _weekdayColor(i)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.anchor,
    required this.byDay,
    required this.zoom,
    required this.onDay,
    required this.onMemo,
  });

  final DateTime anchor;
  final Map<DateTime, List<Memo>> byDay;
  final double zoom;
  final void Function(DateTime day, List<Memo> memos) onDay;
  final ValueChanged<Memo> onMemo;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(anchor.year, anchor.month, 1);
    final start = _weekStart(first);
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final rows = ((first.weekday % 7) + daysInMonth + 6) ~/ 7;

    return Column(
      children: [
        const _WeekdayHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // At 100% the month fills the screen; zooming in makes the rows
              // taller (scroll to see them all) and the chips larger, zooming
              // out shrinks the chips so more of a busy day fits.
              final fit = constraints.maxHeight / rows;
              final rowHeight = math.max(fit, 76.0) * math.max(1.0, zoom);
              final chipHeight = (15.0 * zoom).clamp(11.0, 32.0);
              final fontSize = (10.0 * zoom).clamp(8.0, 19.0);
              final numberSize = (22.0 * math.sqrt(zoom)).clamp(18.0, 34.0);
              final showFarm = constraints.maxWidth / 7 >= 120;
              return SingleChildScrollView(
                child: Column(
                  children: [
                    for (var r = 0; r < rows; r++)
                      SizedBox(
                        height: rowHeight - 0.01,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var c = 0; c < 7; c++)
                              Expanded(
                                child: _MonthCell(
                                  day: start.add(Duration(days: r * 7 + c)),
                                  inMonth: start.add(Duration(days: r * 7 + c)).month == anchor.month,
                                  weekdayIndex: c,
                                  memos: byDay[start.add(Duration(days: r * 7 + c))] ?? const [],
                                  height: rowHeight,
                                  chipHeight: chipHeight,
                                  fontSize: fontSize,
                                  numberSize: numberSize,
                                  showFarm: showFarm,
                                  onDay: onDay,
                                  onMemo: onMemo,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.weekdayIndex,
    required this.memos,
    required this.height,
    required this.chipHeight,
    required this.fontSize,
    required this.numberSize,
    required this.showFarm,
    required this.onDay,
    required this.onMemo,
  });

  final DateTime day;
  final bool inMonth;
  final int weekdayIndex;
  final List<Memo> memos;
  final double height;
  final double chipHeight;
  final double fontSize;
  final double numberSize;
  final bool showFarm;
  final void Function(DateTime day, List<Memo> memos) onDay;
  final ValueChanged<Memo> onMemo;

  @override
  Widget build(BuildContext context) {
    final available = height - numberSize - 8;
    final capacity = math.max(0, (available / (chipHeight + 2)).floor());
    final overflow = memos.length > capacity;
    final shown = overflow ? math.max(0, capacity - 1) : memos.length;

    return InkWell(
      onTap: () => onDay(day, memos),
      child: Container(
        decoration: BoxDecoration(
          color: inMonth ? AppColors.surface : AppColors.neutralCard,
          border: const Border(
            right: BorderSide(color: AppColors.border, width: 0.6),
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _DayNumber(day: day, size: numberSize, faded: !inMonth, weekdayIndex: weekdayIndex),
            ),
            const SizedBox(height: 2),
            for (var i = 0; i < shown; i++)
              _EventChip(
                memo: memos[i],
                height: chipHeight,
                fontSize: fontSize,
                showFarm: showFarm,
                onTap: () => onMemo(memos[i]),
              ),
            if (overflow)
              SizedBox(
                height: chipHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    capacity == 0 ? '${memos.length}건' : '+${memos.length - shown}건 더보기',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.anchor,
    required this.byDay,
    required this.zoom,
    required this.onDay,
    required this.onMemo,
  });

  final DateTime anchor;
  final Map<DateTime, List<Memo>> byDay;
  final double zoom;
  final void Function(DateTime day, List<Memo> memos) onDay;
  final ValueChanged<Memo> onMemo;

  @override
  Widget build(BuildContext context) {
    final start = _weekStart(anchor);
    final days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    final fontSize = (10.5 * zoom).clamp(8.5, 20.0);
    final maxLines = (3 * zoom).round().clamp(1, 8);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onDay(days[i], byDay[days[i]] ?? const []),
                    child: Column(
                      children: [
                        Text(
                          _weekdays[i],
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _weekdayColor(i)),
                        ),
                        const SizedBox(height: 2),
                        _DayNumber(day: days[i], size: 28, weekdayIndex: i),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 400),
                        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                        decoration: BoxDecoration(
                          color: _sameDay(days[i], DateTime.now()) ? AppColors.brandTint.withValues(alpha: 0.5) : null,
                          border: const Border(right: BorderSide(color: AppColors.border, width: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final m in byDay[days[i]] ?? const <Memo>[])
                              _WeekEvent(memo: m, fontSize: fontSize, maxLines: maxLines, onTap: () => onMemo(m)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A memo in the week view: time on top, then a few lines of the text.
class _WeekEvent extends StatelessWidget {
  const _WeekEvent({required this.memo, required this.fontSize, required this.maxLines, required this.onTap});

  final Memo memo;
  final double fontSize;
  final int maxLines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleOf(memo);
    final at = (memo.doneAt ?? memo.createdAt).toLocal();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${style.prefix}${DateFormat('HH:mm').format(at)}',
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(fontSize: fontSize * 0.9, fontWeight: FontWeight.w800, color: style.fg),
            ),
            Text(
              [if (memo.farmName != null) memo.farmName!, _firstLine(memo.content)].join(' · '),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, height: 1.25, fontWeight: FontWeight.w600, color: style.fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google's 일정 view: the month's days that have memos, one block per day.
class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.anchor, required this.byDay, required this.zoom, required this.onMemo});

  final DateTime anchor;
  final Map<DateTime, List<Memo>> byDay;
  final double zoom;
  final ValueChanged<Memo> onMemo;

  @override
  Widget build(BuildContext context) {
    final days = byDay.keys.where((d) => d.year == anchor.year && d.month == anchor.month).toList()..sort();
    if (days.isEmpty) {
      return Center(
        child: Text('${anchor.month}월에 기록된 메모가 없어요.', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      );
    }
    final scale = zoom.clamp(0.8, 1.8).toDouble();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final weekdayIndex = day.weekday % 7;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48 * scale,
                child: Column(
                  children: [
                    Text(
                      _weekdays[weekdayIndex],
                      style: TextStyle(
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.w700,
                        color: _weekdayColor(weekdayIndex),
                      ),
                    ),
                    _DayNumber(day: day, size: 34 * scale, weekdayIndex: weekdayIndex),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final m in byDay[day]!) _AgendaItem(memo: m, scale: scale, onTap: () => onMemo(m))],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({required this.memo, required this.scale, required this.onTap});

  final Memo memo;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleOf(memo);
    final at = (memo.doneAt ?? memo.createdAt).toLocal();
    final status = memo.isDone
        ? '완료${memo.doneByName == null || memo.doneByName!.isEmpty ? '' : ' · ${memo.doneByName}'}'
        : (memo.isTask || memo.mentionedMe ? '진행 중' : '등록');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: style.bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${style.prefix}${DateFormat('HH:mm').format(at)} · $status · ${memo.farmLabel}',
                  style: TextStyle(
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w700,
                    color: style.fg.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  memo.content,
                  maxLines: (2 * scale).round(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: style.fg,
                    decoration: memo.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: style.fg,
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

/// A tapped day's memos as full cards (each opens 메모 상세).
class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day, required this.memos});

  final DateTime day;
  final List<Memo> memos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-read the live list so a 완료 / 수정 from inside shows up here.
    final live = ref.watch(memosProvider(null)).valueOrNull;
    final ids = memos.map((m) => m.id).toSet();
    final shown = live == null ? memos : live.where((m) => ids.contains(m.id)).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${DateFormat('M월 d일 (E)', 'ko_KR').format(day)} · ${shown.length}건',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Text('이 날 기록된 메모가 없어요.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => MemoCard(memo: shown[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year--)),
                  Expanded(
                    child: Text(
                      '$_year년',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year++)),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var m = 1; m <= 12; m++)
                    _MonthTile(
                      label: '$m월',
                      selected: _year == widget.initial.year && m == widget.initial.month,
                      current: _year == now.year && m == now.month,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_year == now.year && m == now.month ? _dayOf(now) : DateTime(_year, m, 1)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.label, required this.selected, required this.current, required this.onTap});

  final String label;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand : (current ? AppColors.brandTint : AppColors.background),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
