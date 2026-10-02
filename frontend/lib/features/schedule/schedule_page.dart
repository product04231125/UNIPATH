import 'package:flutter/material.dart';

import '../planning/planning_repository.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.repository});

  final PlanningRepository repository;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(DateTime.now());
    _month = DateTime(_selectedDay.year, _selectedDay.month);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      if (widget.repository.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final selectedEvents = _eventsForDay(_selectedDay);
      final weekEvents = _eventsForWeek(DateTime.now());
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: constraints.maxHeight < 620 ? 28 : 8,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '일정',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '개인 계획을 이 기기에 저장합니다. 학교 공식 일정·알림·반복 일정은 아직 연결되지 않았습니다.',
                            style: TextStyle(color: Color(0xff607386)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _editEvent(),
                      icon: const Icon(Icons.add),
                      label: const Text('일정 추가'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (constraints.maxWidth >= 820)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 18),
                _weekList(weekEvents),
              ],
            ),
          ),
        ),
      );
    },
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
              for (final day in ['월', '화', '수', '목', '금', '토', '일'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.12,
            ),
            itemBuilder: (context, index) {
              final first = DateTime(_month.year, _month.month);
              final day = first.add(
                Duration(days: index - (first.weekday - 1)),
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

  Widget _weekList(List<PlanningEvent> events) {
    final start = _startOfWeek(DateTime.now());
    final end = start.add(const Duration(days: 6));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이번 주', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${start.month}.${start.day}–${end.month}.${end.day}',
              style: const TextStyle(color: Color(0xff607386)),
            ),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const Text(
                '이번 주에 등록한 개인 일정이 없습니다.',
                style: TextStyle(color: Color(0xff607386)),
              )
            else
              for (final event in events) _eventTile(event, showDate: true),
          ],
        ),
      ),
    );
  }

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

  List<PlanningEvent> _eventsForDay(DateTime day) => widget.repository.events
      .where(
        (event) =>
            !event.end.isBefore(_dateOnly(day)) &&
            !event.start.isAfter(_dateOnly(day).add(const Duration(days: 1))),
      )
      .toList();

  List<PlanningEvent> _eventsForWeek(DateTime date) {
    final start = _startOfWeek(date);
    final end = start.add(const Duration(days: 7));
    return widget.repository.events
        .where((event) => event.start.isBefore(end) && event.end.isAfter(start))
        .toList();
  }

  Future<void> _editEvent([PlanningEvent? existing]) async {
    final result = await showDialog<_EventChange>(
      context: context,
      builder: (context) =>
          _EventEditor(event: existing, initialDay: _selectedDay),
    );
    if (result == null) return;
    if (result.delete) {
      await widget.repository.deleteEvent(existing!.id);
    } else {
      await widget.repository.saveEvent(result.event!);
    }
  }
}

class _EventChange {
  const _EventChange.save(this.event) : delete = false;
  const _EventChange.delete() : event = null, delete = true;
  final PlanningEvent? event;
  final bool delete;
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({this.event, required this.initialDay});
  final PlanningEvent? event;
  final DateTime initialDay;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title;
  late final TextEditingController _memo;
  late DateTime _start;
  late DateTime _end;
  late PlanningEventCategory _category;
  final _formKey = GlobalKey<FormState>();

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
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.event == null ? '일정 추가' : '일정 수정'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '제목',
                  hintText: '예: 자료구조 과제 제출',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '제목을 입력해 주세요.'
                    : null,
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
              DropdownButtonFormField<PlanningEventCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '분류'),
                items: [
                  for (final category in PlanningEventCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memo,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.event != null)
        TextButton.icon(
          onPressed: () => Navigator.pop(context, const _EventChange.delete()),
          icon: const Icon(Icons.delete_outline),
          label: const Text('삭제'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(onPressed: _save, child: const Text('저장')),
    ],
  );

  Widget _dateTimeField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) => OutlinedButton(
    onPressed: () async {
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
      if (time == null) return;
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

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종료 일시는 시작 일시보다 뒤여야 합니다.')));
      return;
    }
    Navigator.pop(
      context,
      _EventChange.save(
        PlanningEvent(
          id:
              widget.event?.id ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          title: _title.text.trim(),
          start: _start,
          end: _end,
          category: _category,
          memo: _memo.text.trim(),
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
DateTime _startOfWeek(DateTime value) =>
    _dateOnly(value).subtract(Duration(days: value.weekday - 1));
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
