import 'package:flutter/material.dart';

import '../app_style.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// A real calendar day written as `YYYY-MM-DD`, or null.
DateTime? parseDay(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final day = DateTime.tryParse(text);
  return day != null && formatDay(day) == text ? day : null;
}

/// `YYYY-MM-DD`, the form records keep.
String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// `2026.11.25 (수)`, as the schedule shows dates.
String displayDay(DateTime day) =>
    '${day.year}.${day.month}.${day.day} (${_weekdays[day.weekday - 1]})';

/// A date chosen from a calendar instead of typed. The value is `YYYY-MM-DD` text (empty
/// when unset), kept in [controller] or, without one, started from [initialValue] and
/// reported through [onChanged], so forms keep reading and saving text as before.
/// Looks like the other inputs: label, `2026.11.25 (수)`, a calendar icon, and a clear
/// button when [clearable].
class DatePickerFormField extends StatefulWidget {
  const DatePickerFormField({
    super.key,
    this.controller,
    this.initialValue = '',
    required this.label,
    this.validator,
    this.enabled = true,
    this.clearable = true,
    this.firstDate,
    this.lastDate,
    this.initialDate,
    this.onChanged,
    this.errorText,
    this.helperText,
    this.showLabel = true,
  });

  final TextEditingController? controller;
  final String initialValue;
  final String label;
  final String? Function(String value)? validator;
  final bool enabled, clearable;
  final DateTime? firstDate, lastDate;

  /// Where the calendar opens when nothing is chosen yet (e.g. the start of a period).
  final DateTime? Function()? initialDate;
  final ValueChanged<String>? onChanged;

  /// An error from elsewhere (e.g. the server), shown when the validator has none.
  final String? errorText, helperText;

  /// False when a [FieldLabel] above already names the field: the box then shows
  /// `날짜 선택` until a day is chosen.
  final bool showLabel;

  @override
  State<DatePickerFormField> createState() => _DatePickerFormFieldState();
}

class _DatePickerFormFieldState extends State<DatePickerFormField> {
  TextEditingController? _own;
  TextEditingController get _controller =>
      widget.controller ??
      (_own ??= TextEditingController(text: widget.initialValue));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _set(FormFieldState<String> state, String value) {
    _controller.text = value;
    state.didChange(value);
    widget.onChanged?.call(value);
  }

  Future<void> _pick(FormFieldState<String> state) async {
    final now = DateTime.now();
    final first = widget.firstDate ?? DateTime(1950);
    final last = widget.lastDate ?? DateTime(now.year + 20, 12, 31);
    var initial =
        parseDay(_controller.text) ?? widget.initialDate?.call() ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: widget.label,
    );
    if (picked != null && mounted) _set(state, formatDay(picked));
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    validator: widget.validator == null
        ? null
        : (_) => widget.validator!(_controller.text),
    builder: (state) => ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final text = _controller.text.trim();
        final day = parseDay(text);
        // A value that is not a real day (older records) stays visible to be replaced.
        final shown = day == null ? text : displayDay(day);
        final enabled = widget.enabled;
        return Semantics(
          button: true,
          enabled: enabled,
          label: '${widget.label} ${shown.isEmpty ? '날짜 선택' : shown}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(appCornerRadius),
            onTap: enabled ? () => _pick(state) : null,
            child: InputDecorator(
              isEmpty: shown.isEmpty,
              decoration: InputDecoration(
                labelText: widget.showLabel ? widget.label : null,
                hintText: widget.showLabel ? null : '날짜 선택',
                enabled: enabled,
                errorText: state.errorText ?? widget.errorText,
                helperText: widget.helperText,
                helperMaxLines: 3,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.clearable && text.isNotEmpty)
                      IconButton(
                        tooltip: '${widget.label} 지우기',
                        onPressed: enabled ? () => _set(state, '') : null,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 12),
                      child: Icon(Icons.event_outlined),
                    ),
                  ],
                ),
              ),
              child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      },
    ),
  );
}

/// Two related inputs (start and end) on one line when both fit, as in 일정; stacked
/// otherwise.
class FieldPair extends StatelessWidget {
  const FieldPair({
    super.key,
    required this.first,
    required this.second,
    this.minWidth = 440,
    this.gap = 12,
  });
  final Widget first, second;
  final double minWidth, gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(minWidth)
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              SizedBox(width: gap),
              Expanded(child: second),
            ],
          )
        : Column(
            children: [
              first,
              SizedBox(height: gap),
              second,
            ],
          ),
  );
}
