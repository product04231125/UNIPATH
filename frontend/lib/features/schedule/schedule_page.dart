import 'package:flutter/material.dart';

import '../../shared/widgets/equal_height_row.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/pending_ui_action.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/page_header.dart';
import '../planning/planning_dates.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.repository,
    this.initialDay,
    this.addRequest,
  });

  final PlanningRepository repository;
  final DateTime? initialDay;
  final PendingUiAction? addRequest;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _month;
  late DateTime _selectedDay;
  bool _autoAddScheduled = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(widget.initialDay ?? DateTime.now());
    _month = DateTime(_selectedDay.year, _selectedDay.month);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      if (widget.repository.isLoading || widget.repository.loadFailed) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              PlanningStorageState(repository: widget.repository),
            ],
          ),
        );
      }
      final selectedEvents = _eventsForDay(_selectedDay);
      final request = widget.addRequest;
      if (!_autoAddScheduled && request?.isPending == true) {
        _autoAddScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _autoAddScheduled = false;
          if (!mounted ||
              !identical(widget.addRequest, request) ||
              widget.repository.isLoading ||
              widget.repository.loadFailed) {
            return;
          }
          if (request!.consume()) _editEvent();
        });
      }
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: constraints.maxHeight < 620 ? 28 : 8,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(
                    actions: [
                      FilledButton.icon(
                        onPressed: () => _editEvent(),
                        icon: const Icon(Icons.add),
                        label: const Text('일정 추가'),
                      ),
                    ],
                  ),
                  if (constraints.maxWidth >= 820)
                    EqualHeightRow(
                      children: [
                        Expanded(flex: 3, child: _calendar()),
                        const SizedBox(width: 18),
                        Expanded(flex: 2, child: _dayList(selectedEvents)),
                      ],
                    )
                  else ...[
                    _calendar(),
                    const SizedBox(height: 18),
                    _dayList(selectedEvents),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _header({List<Widget> actions = const []}) => PageHeader(
    title: '일정',
    description: '개인 계획을 이 기기에 저장합니다. 학교 공식 일정·알림·반복 일정은 아직 연결되지 않았습니다.',
    actions: actions,
  );

  Widget _calendar() => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '이전 달',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${_month.year}년 ${_month.month}월',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '다음 달',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final day in planningWeek(
                DateTime.now(),
                widget.repository.profile.weekStartsOn,
              ))
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayLabel(day.weekday),
                      style: TextStyle(color: Color(0xff607386)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent:
                  MediaQuery.textScalerOf(context).scale(14) * 3 + 24,
            ),
            itemBuilder: (context, index) {
              final first = DateTime(_month.year, _month.month);
              final day = first.add(
                Duration(
                  days:
                      index -
                      (first.weekday -
                              widget.repository.profile.weekStartsOn.weekday +
                              7) %
                          7,
                ),
              );
              return _dayCell(day);
            },
          ),
        ],
      ),
    ),
  );

  Widget _dayCell(DateTime day) {
    final events = _eventsForDay(day);
    final selected = _sameDay(day, _selectedDay);
    final today = _sameDay(day, DateTime.now());
    final inMonth = day.month == _month.month;
    return Semantics(
      button: true,
      label: '${day.month}월 ${day.day}일, 일정 ${events.length}개',
      child: InkWell(
        onTap: () => setState(() => _selectedDay = _dateOnly(day)),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xffdcecf2) : null,
            border: today ? Border.all(color: const Color(0xff315a77)) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: selected || today
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: inMonth ? null : const Color(0xff9aaab6),
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 2,
                children: [
                  for (final event in events.take(3))
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _categoryColor(event.category),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 6, height: 6),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayList(List<PlanningEvent> events) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selectedDay.month}월 ${_selectedDay.day}일 일정',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Text(
              '등록된 개인 일정이 없습니다.',
              style: TextStyle(color: Color(0xff607386)),
            )
          else
            for (final event in events) _eventTile(event),
        ],
      ),
    ),
  );

  Widget _eventTile(PlanningEvent event, {bool showDate = false}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 4,
      height: 42,
      decoration: BoxDecoration(
        color: _categoryColor(event.category),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    title: Text(event.title),
    subtitle: Text(
      '${showDate ? '${event.start.month}.${event.start.day} · ' : ''}${_time(event.start)}–${_time(event.end)} · ${event.category.label}${event.memo.isEmpty ? '' : '\n${event.memo}'}',
    ),
    trailing: IconButton(
      tooltip: '${event.title} 수정',
      icon: const Icon(Icons.edit_outlined),
      onPressed: () => _editEvent(event),
    ),
  );

  List<PlanningEvent> _eventsForDay(DateTime day) =>
      eventsOnDay(widget.repository.events, day);

  Future<void> _editEvent([PlanningEvent? existing]) async {
    await showInputDialog<void>(
      context: context,
      builder: (context) => _EventEditor(
        event: existing,
        initialDay: _selectedDay,
        repository: widget.repository,
      ),
    );
  }
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({
    this.event,
    required this.initialDay,
    required this.repository,
  });
  final PlanningEvent? event;
  final DateTime initialDay;
  final PlanningRepository repository;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title;
  late final TextEditingController _memo;
  late DateTime _start;
  late DateTime _end;
  late PlanningEventCategory _category;
  late DateTime _defaultStart, _defaultEnd;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?.title);
    _memo = TextEditingController(text: event?.memo);
    _start =
        event?.start ??
        DateTime(
          widget.initialDay.year,
          widget.initialDay.month,
          widget.initialDay.day,
          9,
        );
    _end = event?.end ?? _start.add(const Duration(hours: 1));
    _category = event?.category ?? PlanningEventCategory.academic;
    _defaultStart = _start;
    _defaultEnd = _end;
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    changes: Listenable.merge([_title, _memo]),
    editing: widget.event != null,
    saving: _saving,
    hasContent: () =>
        _title.text.trim().isNotEmpty ||
        _memo.text.trim().isNotEmpty ||
        _category != PlanningEventCategory.academic ||
        _start != _defaultStart ||
        _end != _defaultEnd,
    title: Text(widget.event == null ? '일정 추가' : '일정 수정'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            enabled: !_saving,
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '제목',
              hintText: '예: 자료구조 과제 제출',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '제목을 입력해 주세요.' : null,
          ),
          const SizedBox(height: 12),
          _dateTimeField(
            '시작 일시',
            _start,
            (value) => setState(() {
              _start = value;
              if (_end.isBefore(_start)) {
                _end = _start.add(const Duration(hours: 1));
              }
            }),
          ),
          const SizedBox(height: 8),
          _dateTimeField(
            '종료 일시',
            _end,
            (value) => setState(() => _end = value),
          ),
          const SizedBox(height: 12),
          AnchoredSelectField<PlanningEventCategory>(
            value: _category,
            label: '분류',
            options: [
              for (final category in PlanningEventCategory.values)
                SelectOption(category, category.label),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            enabled: !_saving,
            controller: _memo,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '메모 (선택)'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.event != null)
        TextButton.icon(
          onPressed: _saving ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('삭제'),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '저장 중…' : '저장'),
      ),
    ],
  );

  Widget _dateTimeField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) => OutlinedButton(
    onPressed: _saving
        ? null
        : () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date == null || !mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (time == null || !mounted) return;
            onChanged(
              DateTime(date.year, date.month, date.day, time.hour, time.minute),
            );
          },
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$label  ${value.year}.${value.month}.${value.day} ${_time(value)}',
      ),
    ),
  );

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개인 일정 삭제'),
        content: Text('${widget.event!.title} 일정을 이 기기에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _persist(() => widget.repository.deleteEvent(widget.event!.id));
    }
  }

  Future<void> _persist(Future<void> Function() write) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await write();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '기기에 저장하지 못했습니다. 입력과 기존 일정을 유지했으니 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종료 일시는 시작 일시보다 뒤여야 합니다.')));
      return;
    }
    final event = PlanningEvent(
      id: widget.event?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      start: _start,
      end: _end,
      category: _category,
      memo: _memo.text.trim(),
    );
    await _persist(() => widget.repository.saveEvent(event));
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
Color _categoryColor(PlanningEventCategory category) => switch (category) {
  PlanningEventCategory.academic => const Color(0xff315a77),
  PlanningEventCategory.personal => const Color(0xff6c7a37),
  PlanningEventCategory.activity => const Color(0xff8f5a3c),
  PlanningEventCategory.deadline => const Color(0xffa4414d),
};
